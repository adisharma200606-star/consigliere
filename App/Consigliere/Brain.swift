import AppKit
import ConsigliereCore
import SwiftUI

/// The Brain connects everything. It is the only class that knows about all the others.
///
///   hotkeys, the notch sensor  ->  Brain  ->  ConsigliereCore decides  ->  Brain acts  ->  notch, voice, sounds
///
/// Two rules shape almost every method here:
///   1. The action happens first. The line, the sound and the voice come after and never hold it up.
///   2. He never speaks first. Everything below starts from something the person did.
@MainActor
final class Brain {
    // State that lives in files (see docs/GUIDE.md, "Where your files live").
    private(set) var config: Config
    private var usage: [String: Int]
    private var stash: Stash
    private var lineState: LineState
    private var lineBank: LineBank
    private var captureLog: CaptureLog
    /// Today's jobs (~/.consigliere/jobs.json). Rolled over to a new day at 04:00, unfinished jobs carried along.
    private var jobDay: JobDay
    /// Every installed app, as catalog entries. Filled in shortly after launch.
    private var installedApps: [CatalogEntry] = []

    // The parts.
    private let model: NotchModel
    private let controller: NotchController
    private let sensor = NotchSensor()
    private let hotkeys = HotkeyCenter()
    private let mouth = Mouth()
    private let sounds = SoundPlayer()
    private let ears = Ears()
    private let micTuner = MicTuner()
    private let settingsWindow = SettingsWindow()
    private let tutorialWindow = TutorialWindow()
    private let roamer = Roamer()
    private let jobCard = JobCard()

    // What is going on right now.
    private var decision: Decision?
    private var closeTask: Task<Void, Never>?
    private var tunerSession = TunerSession()
    private var tuning: ResolvedTuning?
    private var tuningIndex = 0
    private var wasInTune = false
    private var countdown: CountdownTimer?
    private var countdownTicker: Timer?
    private var pendingBookmarkURL: String?
    private var pendingBookmarkChoices: [CatalogEntry] = []
    private var askTask: Task<Void, Never>?
    private var glanceKind = ""
    private var glanceNotes: [CaptureEntry] = []
    private var glanceReminders: [CaptureWriter.Upcoming] = []
    /// What he is out of the notch about, while he is.
    private var outNudge: Nudge?
    private var jobTicker: Timer?
    /// The job the running timer belongs to, so its end can ask "done?".
    private var countdownJobID: String?
    /// A job that has nothing to open yet. Whatever he opens next from the box becomes its starter.
    private var pendingBindJobID: String?
    /// When set, a row picked on the chooser screen goes here instead of to the living bookmarks.
    private var chooserAction: ((Int) -> Void)?

    init() {
        let loaded = ConfigStore.load()
        config = loaded.config
        if let problem = loaded.problem { NSLog("Consigliere: config problem, using defaults for now: \(problem)") }
        usage = UsageStore.load()
        lineState = LineStateStore.load()
        let stashLoaded = StashStore.load()
        stash = stashLoaded.stash
        if let problem = stashLoaded.problem { NSLog("Consigliere: stash problem: \(problem)") }
        lineBank = LineBankStore.load(from: Bundle.main.url(forResource: "lines", withExtension: "json"))
        captureLog = CaptureLogStore.load()
        jobDay = Jobs.rollover(JobsStore.load(), to: Jobs.dayKey(ReminderParser.wall(from: Date())))
        JobsStore.save(jobDay)

        // Bring an existing config up to date with any built-in command added since it was first written
        // (config.json otherwise keeps whatever catalog it had on day one, forever — see CatalogMigration).
        let migrationState = CatalogMigrationStore.load()
        let migrated = CatalogMigration.merge(existing: config.catalog, defaults: DefaultCatalog.entries,
                                              alreadyOffered: Set(migrationState.offered))
        if migrated.catalog != config.catalog || migrated.offered != migrationState.offered.sorted() {
            // A local copy: a closure may not touch `self` (and so `config`) until init has set every property.
            let before = Set(config.catalog.map(\.name))
            let added = migrated.catalog.map(\.name).filter { !before.contains($0) }
            config.catalog = migrated.catalog
            CatalogMigrationStore.save(CatalogMigrationState(offered: migrated.offered))
            do {
                try ConfigStore.save(config)
                NSLog("Consigliere: added built-in commands to config.json: \(added)")
            } catch {
                NSLog("Consigliere: could not save config.json after adding built-ins: \(error)")
            }
        }

        model = NotchModel(theme: NotchTheme(config.theme))
        controller = NotchController(model: model)
    }

    // MARK: - Starting and stopping

    func start() {
        wireModel()
        applyConfig()
        sounds.preload()
        ears.requestPermissions()
        sensor.onClick = { [weak self] in self?.pull() }
        sensor.onDrop = { [weak self] things in self?.handleDrop(things) }
        sensor.menuProvider = { [weak self] in self?.contextMenu() }
        sensor.start()
        controller.onDismiss = { [weak self] in
            self?.sounds.play(.close)
            self?.close()
        }
        controller.onEnter = { [weak self] in
            guard let self = self else { return }
            if self.model.screen == .jobs { self.addDraftJobs() } else { self.submit(choosing: nil) }
        }
        startJobs()
        refreshInstalledApps()
        if !TutorialWindow.hasBeenSeen {
            // A moment after launch, so it does not fight the permission prompts.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.showTutorial() }
        }
    }

    /// Scans for installed apps off the main thread, then keeps only the ones the catalog does not already open.
    func refreshInstalledApps() {
        guard config.includeInstalledApps else {
            installedApps = []
            return
        }
        let catalog = config.catalog
        DispatchQueue.global(qos: .utility).async {
            let found = AppIndex.scan()
            let entries = InstalledApps.entries(from: found, excluding: catalog)
            DispatchQueue.main.async { [weak self] in self?.installedApps = entries }
        }
    }

    /// What the box matches against: his own entries first, then every installed app.
    private var searchable: [CatalogEntry] {
        return config.includeInstalledApps ? config.catalog + installedApps : config.catalog
    }

    func showTutorial() {
        tutorialWindow.show(hotkeys: config.hotkeys, theme: model.theme)
    }

    func shutDown() {
        micTuner.stop()
        mouth.stop()
        persistStash()
        JobsStore.save(jobDay)
    }

    /// Called by the settings window. Saves, then re-applies everything that depends on the config.
    func update(_ newConfig: Config) {
        config = newConfig
        do {
            try ConfigStore.save(config)
        } catch {
            NSLog("Consigliere: could not save the config: \(error)")
        }
        applyConfig()
        refreshInstalledApps()
    }

    private func applyConfig() {
        model.theme = NotchTheme(config.theme)
        controller.apply(model.theme)
        mouth.apply(config.theme.voice)
        sounds.apply(config.feedback)
        ears.setLocale(config.speechLocale)
        tunerSession.options.toleranceCents = config.tuner.toleranceCents
        model.character = CharacterFrames.load(folder: config.character.folder, facesLeft: config.character.facesLeft)

        hotkeys.removeAll()
        let ok = [
            hotkeys.register(config.hotkeys.openBox, onDown: { [weak self] in self?.toggleBox() }),
            hotkeys.register(config.hotkeys.talk, onDown: { [weak self] in self?.startTalking() }, onUp: { [weak self] in self?.stopTalking() }),
            hotkeys.register(config.hotkeys.saveTab, onDown: { [weak self] in self?.saveFrontTab() }),
            hotkeys.register(config.hotkeys.markPlace, onDown: { [weak self] in self?.markMyPlace() })
        ]
        if ok.contains(false) { NSLog("Consigliere: a hotkey in the config could not be understood: \(config.hotkeys)") }
    }

    private func wireModel() {
        model.onTextChange = { [weak self] text in self?.textChanged(text) }
        model.onSubmit = { [weak self] index in self?.submit(choosing: index) }
        model.onAnother = { [weak self] in self?.pull(another: true) }
        model.onChoose = { [weak self] index in self?.choose(index) }
        model.onTuningStep = { [weak self] step in self?.stepTuning(step) }
        model.onCopyCommand = { [weak self] in self?.copyCommand() }
        model.onTimerTap = { [weak self] in self?.showTimer() }
        model.onStopTimer = { [weak self] in self?.stopTimer() }
        model.onAddTime = { [weak self] seconds in self?.addTime(seconds) }
        model.onGlanceOpen = { [weak self] index in self?.openGlanceItem(index) }
        model.onGlanceTick = { [weak self] index in self?.tickGlanceItem(index) }
        model.onGlanceButton = { [weak self] index in self?.glanceButton(index) }
        model.onJobWaitingTap = { [weak self] in self?.showJobs() }
        model.onJobToggle = { [weak self] id in self?.toggleJob(id) }
        model.onJobStart = { [weak self] id in self?.startJob(id) }
        model.onJobDelete = { [weak self] id in self?.deleteJob(id) }
        model.onJobDraftChange = { [weak self] in self?.cancelAutoClose() }
        model.onCharacterTap = { [weak self] in self?.pet() }
    }

    // MARK: - The box

    private func toggleBox() {
        if controller.isOpen && model.screen == .input {
            sounds.play(.close)
            close()
        } else {
            openBox()
        }
    }

    private func openBox(listening: Bool = false) {
        cancelAutoClose()
        stopTuner()
        model.text = ""
        model.isListening = listening
        model.screen = .input
        textChanged("")
        controller.open(takeKeyboard: true)
        sounds.play(.open)
    }

    private func textChanged(_ text: String) {
        let decision = Matcher.match(text, catalog: searchable, usage: usage)
        self.decision = decision
        model.selected = 0
        model.isUnknown = decision.mode == .nothing

        if decision.mode == .ask {
            model.rows = [NotchModel.Row(id: 0, title: "Ask: \(decision.query ?? "")", detail: "Claude")]
            return
        }
        model.rows = decision.results.enumerated().map { index, hit in
            var title = hit.entry.shownName
            if decision.mode == .search, let query = decision.query, !query.isEmpty { title += "  ›  \(query)" }
            return NotchModel.Row(id: index, title: title, detail: Brain.whereItOpens(hit.entry, searching: decision.mode == .search))
        }
    }

    /// The small grey text on the right of a row: where this thing will open.
    private static func whereItOpens(_ entry: CatalogEntry, searching: Bool) -> String {
        switch entry.kind {
        case .site: return searching ? "search" : "Brave, \(entry.profile ?? "personal")"
        case .app: return "app"
        case .path: return "Finder"
        case .tool:
            switch entry.target {
            case "note": return searching ? "Apple Notes" : "your notes"
            case "reminder": return searching ? "Apple Reminders" : "coming up"
            case "flip": return "the screen"
            case "help": return "the guide"
            case "pull": return "your stash"
            case "settings": return "settings"
            case "jobs": return searching ? "the books" : "today's jobs"
            case "done": return "the books"
            case "diary": return "apple notes"
            case "quiet": return "until tomorrow"
            case "music": return searching ? "music" : "play"
            case "playpause", "next": return "music"
            case "louder", "quieter", "volume": return "volume"
            case "pet": return "your dragon"
            case "home": return "back in the notch"
            default: return "in the notch"
            }
        }
    }

    /// Enter, or a click on a row. `index` nil means "whichever row is highlighted".
    private func submit(choosing index: Int?) {
        let decision = self.decision ?? Matcher.match(model.text, catalog: searchable, usage: usage)
        let chosen = index ?? model.selected

        switch decision.mode {
        case .empty where index == nil && model.rows.isEmpty:
            return
        case .nothing:
            sounds.play(.unknown)
            showLine(category: "unknown", target: nil)
            return
        default:
            break
        }

        let plan = decision.mode == .ask ? ActionPlan.make(from: decision) : ActionPlan.make(from: decision, choosing: chosen)
        guard let plan = plan else { return }
        run(plan)
    }

    // MARK: - Doing things

    private func run(_ plan: ActionPlan) {
        switch plan {
        case .openURL, .openApp, .openPath:
            // Rule 1: the thing opens first.
            Opener.run(plan, config: config)
            count(plan.entryName)
            if let jobID = pendingBindJobID { bindStarter(jobID, to: plan.entryName) }
            showLine(category: plan.lineCategory, target: plan.entryName)

        case .openTool(let tool, let argument, let entry):
            count(entry)
            switch tool {
            case "tuner": openTuner(entry: entry)
            case "timer": startTimer(argument, entry: entry)
            case "note": capture(note: argument, entry: entry)
            case "reminder": capture(reminder: argument, entry: entry)
            case "pull": pull(fromBox: true)
            case "flip": flipScreen(entry: entry)
            case "help":
                close()
                showTutorial()
            case "settings":
                close()
                settingsWindow.show(brain: self)
            case "jobs": jobsCommand(argument)
            case "done": doneCommand(argument)
            case "diary": diary(argument)
            case "quiet": quietForToday()
            case "music": playMusic(argument)
            case "playpause", "next", "louder", "quieter", "volume": musicControl(tool, argument)
            case "pet": pet()
            case "home": sendHome()
            default:
                sounds.play(.unknown)
                showLine(category: "unknown", target: nil)
            }

        case .ask(let question):
            ask(question)
        }
    }

    private func count(_ entryName: String) {
        guard !entryName.isEmpty else { return }
        usage[entryName, default: 0] += 1
        UsageStore.save(usage)
    }

    // MARK: - Lines

    /// Shows a line in the notch and, some of the time, says it. `text` replaces what is shown (used for
    /// confirmations like "call mom · Tomorrow 17:00") while the voice still says a proper line.
    private func showLine(category: String, target: String?, text: String? = nil, alwaysSpeak: Bool = false, hold: Double? = nil) {
        let frequency = alwaysSpeak ? 1.0 : config.theme.voice.frequency
        let pick = Lines.pick(bank: lineBank, state: &lineState, category: category, target: target,
                              frequency: frequency, rng: { Double.random(in: 0..<1) })
        LineStateStore.save(lineState)

        model.isListening = false
        model.lineText = text ?? pick?.text ?? ""
        model.screen = .line
        if !controller.isOpen { controller.open(takeKeyboard: false) }
        if let pick = pick, config.speak { mouth.say(pick) }

        let shown = model.lineText
        closeAfter(hold ?? (1.3 + Double(shown.count) * 0.045))
    }

    private func closeAfter(_ seconds: Double) {
        cancelAutoClose()
        closeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.close()
        }
    }

    private func cancelAutoClose() {
        closeTask?.cancel()
        closeTask = nil
    }

    private func close() {
        cancelAutoClose()
        askTask?.cancel()
        askTask = nil
        stopTuner()
        if ears.isListening { ears.stop { _ in } }
        model.isListening = false
        model.inputHint = nil
        pendingBindJobID = nil
        chooserAction = nil
        controller.close()
    }

    // MARK: - The stash

    private func persistStash() {
        do {
            try StashStore.save(stash)
        } catch {
            NSLog("Consigliere: could not save the stash: \(error)")
        }
        PhoneStore.push(stash)
    }

    /// A click on the notch, or "another".
    private func pull(another: Bool = false, fromBox: Bool = false) {
        if controller.isOpen && !another && !fromBox { return }   // a click while something is showing does nothing
        cancelAutoClose()
        PhoneStore.pull(into: &stash)
        let now = SystemClock.nowMs()
        let rng: () -> Double = { Double.random(in: 0..<1) }
        let item = another ? stash.another(now: now, rng: rng) : stash.serve(now: now, rng: rng)
        persistStash()

        guard let item = item else {
            showLine(category: "empty_stash", target: nil)
            return
        }

        Opener.open(item, config: config)                // first
        sounds.play(another ? .another : .pulled)

        let days = max(0, (now - item.savedAt) / Stash.dayMs)
        model.pullTitle = item.title?.isEmpty == false ? (item.title ?? item.payload) : item.payload
        model.pullDetail = days == 0 ? "saved today" : (days == 1 ? "saved yesterday" : "saved \(days) days ago")
        model.screen = .pull
        if !controller.isOpen { controller.open(takeKeyboard: false) }

        let pick = Lines.pick(bank: lineBank, state: &lineState, category: another ? "another" : "pulled", target: nil,
                              frequency: config.theme.voice.frequency, rng: { Double.random(in: 0..<1) })
        if let pick = pick, config.speak { mouth.say(pick) }
        closeAfter(6)
    }

    private func save(payload: String, kind: String, title: String?, source: String) {
        stash.add(payload: payload, kind: kind, title: title, source: source, now: SystemClock.nowMs())
        persistStash()
        sounds.play(.saved)
        showLine(category: "saved", target: nil)
    }

    private func saveFrontTab() {
        guard let tab = TabGrabber.frontTab() else {
            sounds.play(.unknown)
            showLine(category: "unknown", target: nil, text: "No page in front to save.")
            return
        }
        save(payload: tab.url, kind: "url", title: tab.title, source: "hotkey")
    }

    private func handleDrop(_ things: [DroppedThing]) {
        for thing in things {
            switch thing {
            case .link(let url):
                stash.add(payload: url.absoluteString, kind: "url", source: "drop", now: SystemClock.nowMs())
            case .text(let text):
                stash.add(payload: text, kind: "text", source: "drop", now: SystemClock.nowMs())
            case .file(let url):
                stash.add(payload: url.path, kind: "file", title: url.lastPathComponent, source: "drop", now: SystemClock.nowMs())
            case .image(let image):
                if let path = Brain.keep(image) {
                    stash.add(payload: path, kind: "image", title: "An image you saved", source: "drop", now: SystemClock.nowMs())
                }
            }
        }
        persistStash()
        sounds.play(.saved)
        showLine(category: "saved", target: nil)
    }

    /// A dropped image has no file of its own, so it is written into ~/.consigliere/images.
    private static func keep(_ image: NSImage) -> String? {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return nil }
        let folder = ConsiglierePaths.configDirectory.appendingPathComponent("images", isDirectory: true)
        let file = folder.appendingPathComponent("\(UUID().uuidString).png")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try png.write(to: file)
            return file.path
        } catch {
            return nil
        }
    }

    // MARK: - Bookmarks that remember where he stopped

    private func markMyPlace() {
        guard let tab = TabGrabber.frontTab() else {
            sounds.play(.unknown)
            showLine(category: "unknown", target: nil, text: "No page in front to mark.")
            return
        }
        switch LivingBookmarks.find(for: tab.url, in: config.catalog) {
        case .update(let entry):
            moveBookmark(entry.name, to: tab.url)
        case .ambiguous(let entries):
            pendingBookmarkURL = tab.url
            pendingBookmarkChoices = entries
            model.chooserTitle = "Which one are you reading?"
            model.chooserOptions = entries.map { $0.shownName }
            model.screen = .chooser
            cancelAutoClose()
            controller.open(takeKeyboard: false)
        case .noMatch:
            sounds.play(.unknown)
            showLine(category: "unknown", target: nil, text: "Nothing here remembers its place yet.", hold: 2.6)
        }
    }

    /// A row on the chooser screen. Jobs use it to ask "done?"; otherwise it is the living bookmarks.
    private func choose(_ index: Int) {
        if let action = chooserAction {
            chooserAction = nil
            action(index)
        } else {
            chooseBookmark(index)
        }
    }

    private func chooseBookmark(_ index: Int) {
        guard pendingBookmarkChoices.indices.contains(index), let url = pendingBookmarkURL else { return }
        moveBookmark(pendingBookmarkChoices[index].name, to: url)
        pendingBookmarkURL = nil
        pendingBookmarkChoices = []
    }

    private func moveBookmark(_ name: String, to url: String) {
        var updated = config
        updated.catalog = LivingBookmarks.move(name, to: url, in: config.catalog)
        update(updated)
        sounds.play(.bookmarkMoved)
        showLine(category: "bookmark_moved", target: nil)
    }

    // MARK: - Talking

    private func startTalking() {
        guard !ears.isListening else { return }
        mouth.stop()
        openBox(listening: true)
        let hints = searchable.flatMap { $0.keys }
        ears.start(hints: hints) { [weak self] heard in
            guard let self = self, self.model.isListening else { return }
            self.model.text = heard
        }
    }

    private func stopTalking() {
        guard ears.isListening else { return }
        ears.stop { [weak self] heard in
            guard let self = self else { return }
            self.model.isListening = false
            let text = heard.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty {
                self.close()
                return
            }
            self.model.text = text
            self.textChanged(text)
            // Opening the wrong thing is worse than opening nothing: only act by itself when sure.
            if self.decision?.confident == true {
                self.submit(choosing: nil)
            }
        }
    }

    // MARK: - The tuner

    private var tunings: [Tuning] {
        return config.tuner.allTunings + [Tuning(id: "chromatic", instrument: "", name: "Chromatic", strings: [])]
    }

    private func openTuner(entry: String) {
        cancelAutoClose()
        tuningIndex = tunings.firstIndex { $0.id == config.tuner.lastTuningID } ?? 0
        setTuning()
        model.screen = .tuner
        if !controller.isOpen { controller.open(takeKeyboard: true) }

        let pick = Lines.pick(bank: lineBank, state: &lineState, category: "open_tool", target: entry,
                              frequency: config.theme.voice.frequency, rng: { Double.random(in: 0..<1) })
        if let pick = pick, config.speak { mouth.say(pick) }

        micTuner.start { [weak self] reading in self?.heard(reading) }
    }

    private func setTuning() {
        let chosen = tunings[tuningIndex]
        tuning = chosen.strings.isEmpty ? nil : ResolvedTuning(chosen, a4: config.tuner.a4)
        tunerSession = TunerSession()
        tunerSession.options.toleranceCents = config.tuner.toleranceCents
        wasInTune = false
        model.tuningName = chosen.instrument.isEmpty ? chosen.name : "\(chosen.instrument.capitalized), \(chosen.name.lowercased())"
        model.tuningStrings = chosen.strings
        model.lockedStrings = []
        model.tuner = .idle
    }

    private func stepTuning(_ step: Int) {
        tuningIndex = (tuningIndex + step + tunings.count) % tunings.count
        setTuning()
        var updated = config
        updated.tuner.lastTuningID = tunings[tuningIndex].id
        config = updated
        try? ConfigStore.save(config)
    }

    private func heard(_ reading: PitchReading?) {
        guard model.screen == .tuner else { return }
        let shown = tunerSession.feed(reading, nowMs: SystemClock.nowMs(), tuning: tuning, a4: config.tuner.a4)
        model.tuner = shown
        model.lockedStrings = tunerSession.lockedStringIndexes

        if shown.allInTuneNow {
            sounds.play(.allInTune)
            let pick = Lines.pick(bank: lineBank, state: &lineState, category: "all_in_tune", target: nil,
                                  frequency: 1, rng: { Double.random(in: 0..<1) })
            if let pick = pick, config.speak { mouth.say(pick) }
        } else if shown.inTune && !wasInTune {
            sounds.play(.tunerLock)
        }
        wasInTune = shown.inTune
    }

    private func stopTuner() {
        micTuner.stop()
    }

    // MARK: - The timer

    private func startTimer(_ argument: String?, entry: String) {
        let words = (argument ?? "").trimmingCharacters(in: .whitespaces)

        if words.isEmpty {
            if countdown != nil {
                showTimer()
            } else {
                showLine(category: "open_tool", target: nil, text: "Say how long: timer 10, timer 90s, timer 1:30", hold: 3)
            }
            return
        }
        if CountdownTimer.isStopWord(words) {
            if countdown != nil {
                stopTimer()
            } else {
                showLine(category: "open_tool", target: nil, text: "No timer running.", hold: 2)
            }
            return
        }
        guard let seconds = DurationParser.parse(words) else {
            sounds.play(.unknown)
            showLine(category: "unknown", target: nil, text: "I could not read “\(words)” as a time.", hold: 2.6)
            return
        }

        beginCountdown(seconds: seconds)
        showLine(category: "open_tool", target: entry)
    }

    /// Starts the one timer. `job` is the job it belongs to, if any: its end then asks whether the job is done.
    private func beginCountdown(seconds: Int, job: String? = nil) {
        cancelTimer()
        countdown = CountdownTimer(seconds: seconds, nowMs: SystemClock.nowMs())
        countdownJobID = job
        refreshTimer()
        countdownTicker = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshTimer() }
        }
    }

    private func refreshTimer() {
        guard let countdown = countdown else { return }
        let status = countdown.status(nowMs: SystemClock.nowMs())
        model.timerText = status.text
        model.timerFraction = status.fraction
        if status.done {
            let jobID = countdownJobID
            cancelTimer()
            sounds.play(.timerDone)
            if let id = jobID, let job = jobDay.job(id), job.status == .started {
                askIfDone(job)
            } else {
                showLine(category: "timer_done", target: nil, alwaysSpeak: true, hold: 3)
            }
        }
    }

    /// The timer's own screen, with Stop and more time.
    private func showTimer() {
        guard countdown != nil else { return }
        cancelAutoClose()
        refreshTimer()
        model.screen = .timer
        controller.open(takeKeyboard: false)
        closeAfter(8)
    }

    private func stopTimer() {
        guard countdown != nil else { return }
        cancelTimer()
        sounds.play(.close)
        showLine(category: "timer_stopped", target: nil, hold: 1.8)
    }

    private func addTime(_ seconds: Int) {
        guard let timer = countdown else { return }
        countdown = timer.adding(seconds: seconds, nowMs: SystemClock.nowMs())
        refreshTimer()
        closeAfter(8)
        let pick = Lines.pick(bank: lineBank, state: &lineState, category: "timer_extended", target: nil,
                              frequency: config.theme.voice.frequency, rng: { Double.random(in: 0..<1) })
        if let pick = pick, config.speak { mouth.say(pick) }
    }

    private func cancelTimer() {
        countdownTicker?.invalidate()
        countdownTicker = nil
        countdown = nil
        countdownJobID = nil
        model.timerText = nil
        model.timerFraction = 0
    }

    // MARK: - Notes and reminders

    private func capture(note argument: String?, entry: String) {
        let text = (argument ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            showNotesGlance()
            return
        }
        let noteID = CaptureWriter.makeNote(text)
        let ok = noteID != nil
        if ok {
            captureLog.add(kind: "note", text: text, now: SystemClock.nowMs(), externalID: noteID)
            CaptureLogStore.save(captureLog)
        }
        sounds.play(ok ? .captured : .unknown)
        showLine(category: "open_tool", target: entry, text: ok ? "Note: \(text)" : "Notes would not take it. Check Privacy, Automation.", hold: 3)
    }

    private func capture(reminder argument: String?, entry: String) {
        let text = (argument ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            showRemindersGlance()
            return
        }
        let nowWall = ReminderParser.wall(from: Date())
        let parsed = ReminderParser.parse(text, nowWall: nowWall)
        let due = parsed.dueWall.map { ReminderParser.date(fromWall: $0) }
        let said = ReminderParser.describe(dueWall: parsed.dueWall, nowWall: nowWall)

        // Show what was understood straight away; the save itself takes a moment.
        sounds.play(.captured)
        showLine(category: "open_tool", target: entry, text: "\(parsed.title)  ·  \(said)", hold: 3.2)
        let logID = captureLog.add(kind: "reminder", text: parsed.title,
                                   dueMs: due.map { Int(($0.timeIntervalSince1970 * 1000).rounded()) }, now: SystemClock.nowMs())
        CaptureLogStore.save(captureLog)
        CaptureWriter.makeReminder(title: parsed.title, due: due) { [weak self] identifier in
            guard let self = self else { return }
            guard let identifier = identifier else {
                self.sounds.play(.unknown)
                self.showLine(category: "unknown", target: nil, text: "Reminders would not take it. Check Privacy, Reminders.", hold: 3.5)
                return
            }
            self.captureLog.setExternalID(identifier, for: logID)
            CaptureLogStore.save(self.captureLog)
        }
    }

    // MARK: - The glance: recent notes and upcoming reminders

    private static let shortDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.doesRelativeDateFormatting = true
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    private func openGlance(title: String, empty: String, buttons: [String]) {
        cancelAutoClose()
        model.glanceTitle = title
        model.glanceEmpty = empty
        model.glanceButtons = buttons
        model.glanceItems = []
        model.screen = .glance
        if !controller.isOpen { controller.open(takeKeyboard: false) }
        closeAfter(10)
    }

    private func showNotesGlance() {
        glanceKind = "note"
        glanceNotes = captureLog.recent("note", limit: 6)
        openGlance(title: "Notes you made here", empty: "Nothing yet. Type note, then what to remember.", buttons: ["New note", "Open Notes"])
        let now = Date()
        model.glanceItems = glanceNotes.enumerated().map { index, note in
            let made = Date(timeIntervalSince1970: Double(note.createdAt) / 1000)
            let detail = Calendar.current.isDate(made, inSameDayAs: now) ? "today" : Brain.shortDate.string(from: made)
            return NotchModel.GlanceItem(id: index, title: note.text, detail: detail, done: nil)
        }
    }

    private func showRemindersGlance() {
        glanceKind = "reminder"
        glanceReminders = []
        openGlance(title: "Coming up", empty: "Looking…", buttons: ["Open Reminders"])
        CaptureWriter.upcomingReminders(limit: 6) { [weak self] items in
            guard let self = self, self.model.screen == .glance, self.glanceKind == "reminder" else { return }
            guard let items = items else {
                self.model.glanceEmpty = "I am not allowed to read Reminders. System Settings, Privacy, Reminders."
                return
            }
            self.glanceReminders = items
            self.model.glanceEmpty = "Nothing coming up. Type remind me to…"
            self.model.glanceItems = items.enumerated().map { index, item in
                let detail = item.due.map { Brain.shortDate.string(from: $0) } ?? "no time"
                return NotchModel.GlanceItem(id: index, title: item.title, detail: detail, done: false)
            }
        }
    }

    private func openGlanceItem(_ index: Int) {
        if glanceKind == "note", glanceNotes.indices.contains(index) {
            close()
            CaptureWriter.showNote(id: glanceNotes[index].externalID)
        } else if glanceKind == "reminder" {
            close()
            CaptureWriter.openReminders()
        }
    }

    private func tickGlanceItem(_ index: Int) {
        guard glanceKind == "reminder", glanceReminders.indices.contains(index),
              model.glanceItems.indices.contains(index) else { return }
        let done = !(model.glanceItems[index].done ?? false)
        closeAfter(10)
        CaptureWriter.setDone(glanceReminders[index].identifier, done: done) { [weak self] ok in
            guard let self = self, ok, self.model.glanceItems.indices.contains(index) else { return }
            self.model.glanceItems[index].done = done
            if done {
                self.sounds.play(.saved)
                let pick = Lines.pick(bank: self.lineBank, state: &self.lineState, category: "ticked", target: nil,
                                      frequency: self.config.theme.voice.frequency, rng: { Double.random(in: 0..<1) })
                if let pick = pick, self.config.speak { self.mouth.say(pick) }
            }
        }
    }

    private func glanceButton(_ index: Int) {
        close()
        if glanceKind == "note" {
            if index == 0 { _ = CaptureWriter.openFreshNote() } else { CaptureWriter.showNote(id: nil) }
        } else {
            CaptureWriter.openReminders()
        }
    }

    // MARK: - Flipping the screen

    private func flipScreen(entry: String) {
        close()
        // Let the notch get out of the way before the whole screen turns. ScreenRotator then checks that
        // the screen really moved, trying other ways of asking if it did not (which can take a couple of
        // seconds with an HDMI screen plugged in), so the line is only said once it has actually turned.
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            let outcome = await ScreenRotator.toggleOneEighty()
            guard let self = self else { return }
            switch outcome {
            case .rotated:
                let pick = Lines.pick(bank: self.lineBank, state: &self.lineState, category: "open_tool", target: entry,
                                      frequency: self.config.theme.voice.frequency, rng: { Double.random(in: 0..<1) })
                if let pick = pick, self.config.speak { self.mouth.say(pick) }
            case .busy:
                break
            case .failed(let problem):
                self.sounds.play(.unknown)
                self.showLine(category: "unknown", target: nil, text: problem, hold: 6)
            }
        }
    }

    // MARK: - Ask

    private func ask(_ question: String) {
        cancelAutoClose()
        askTask?.cancel()
        model.question = question
        model.answerText = ""
        model.answerCommand = nil
        model.didCopy = false
        model.isThinking = true
        model.screen = .answer
        if !controller.isOpen { controller.open(takeKeyboard: true) }

        // The clipboard is only read, and only sent, when the question points at it ("explain this").
        let clip = Ask.wantsClipboard(question) ? NSPasteboard.general.string(forType: .string) : nil
        let settings = config.ask

        askTask = Task { @MainActor [weak self] in
            let text: String
            var command: String? = nil
            do {
                let answer = try await AskClient.ask(question: question, clip: clip, config: settings)
                text = answer.text
                command = answer.command
            } catch {
                text = AskClient.explain(error)
            }
            guard let self = self, !Task.isCancelled, self.model.screen == .answer else { return }
            self.model.isThinking = false
            self.model.answerText = text
            self.model.answerCommand = command
            self.sounds.play(.answer)
            let pick = Lines.pick(bank: self.lineBank, state: &self.lineState, category: "explained", target: nil,
                                  frequency: self.config.theme.voice.frequency, rng: { Double.random(in: 0..<1) })
            if let pick = pick, self.config.speak { self.mouth.say(pick) }
        }
    }

    private func copyCommand() {
        guard let command = model.answerCommand else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        model.didCopy = true
    }

    // MARK: - Jobs
    //
    // The day's list, Sopranos style. Each job has a "starter", the thing "start it" opens, because the
    // incentive is taking away the first step, not guilt. When a job is due he flies out of the notch and
    // roams the screen without a word; the voice only comes once he is clicked.

    private var nowWall: Int {
        return ReminderParser.wall(from: Date())
    }

    private func saveJobs() {
        JobsStore.save(jobDay)
    }

    /// Past 04:00, a new job day starts and whatever was not finished comes along, owed one more day.
    private func rollJobs() {
        let key = Jobs.dayKey(nowWall)
        guard jobDay.day != key else { return }
        jobDay = Jobs.rollover(jobDay, to: key)
        saveJobs()
    }

    private func startJobs() {
        roamer.onClick = { [weak self] in self?.roamerClicked() }
        roamer.onGaveUp = { [weak self] in self?.roamerGaveUp() }
        roamer.menuProvider = { [weak self] in self?.roamerMenu() }
        roamer.onPetted = { [weak self] in self?.dragonSays("petted", always: false) }
        roamer.onThrown = { [weak self] in self?.dragonSays("thrown", always: true) }
        roamer.onFetched = { [weak self] in self?.dragonSays("fetched", always: true) }
        jobCard.onButton = { [weak self] index in self?.cardButton(index) }
        jobCard.onDismiss = { [weak self] in self?.cardDismissed() }
        jobTicker = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkJobs() }
        }
    }

    /// "jobs read 30 min, swift course, duolingo by 10pm", or "jobs" on its own for the list.
    private func jobsCommand(_ argument: String?) {
        rollJobs()
        let words = (argument ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if words.isEmpty {
            showJobs()
            return
        }
        let drafts = Jobs.parse(words, nowWall: nowWall, catalog: searchable, bindings: config.jobs.bindings)
        guard !drafts.isEmpty else {
            sounds.play(.unknown)
            showLine(category: "unknown", target: nil, text: "I could not find a job in that.", hold: 2.6)
            return
        }
        jobDay.add(drafts, now: nowWall)
        saveJobs()
        sounds.play(.captured)
        // Say back what was understood, so a misread never goes unnoticed: "read · duolingo by 22:00".
        let said = drafts.map { draft in draft.title + (draft.dueWall.map { " by \(Jobs.clockText($0))" } ?? "") }
        showLine(category: "job_added", target: nil, text: "on the books: " + said.joined(separator: " · "), hold: 3.4)
    }

    /// The checklist. It stays open while you work in it. `byItself` is the once-a-day opening: then it does not
    /// take the keyboard (you may be typing somewhere else) and closes after a minute if you never touch it.
    private func showJobs(byItself: Bool = false) {
        rollJobs()
        cancelAutoClose()
        model.jobDraft = ""
        refreshJobRows()
        model.screen = .jobs
        controller.open(takeKeyboard: !byItself)
        if byItself { closeAfter(60) }
    }

    private static let jobsDateFormat: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE d MMMM"
        return formatter
    }()

    private func refreshJobRows() {
        model.jobsDate = Brain.jobsDateFormat.string(from: Date())
        let done = jobDay.jobs.filter { $0.status == .done }.count
        model.jobsCount = jobDay.jobs.isEmpty ? "" : "\(done) of \(jobDay.jobs.count) done"
        model.jobRows = jobDay.jobs.map { job in
            let canStart = job.starter.map { name in searchable.contains { $0.name == name } } ?? false
            return NotchModel.JobRow(id: job.id, title: job.title, detail: describe(job), done: job.status == .done,
                                     canStart: canStart)
        }
    }

    /// Enter on the checklist: whatever is in the field goes on the books, and the field is ready for more.
    private func addDraftJobs() {
        rollJobs()
        cancelAutoClose()
        let text = model.jobDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let drafts = Jobs.parse(text, nowWall: nowWall, catalog: searchable, bindings: config.jobs.bindings)
        guard !drafts.isEmpty else {
            sounds.play(.unknown)
            return
        }
        jobDay.add(drafts, now: nowWall)
        saveJobs()
        sounds.play(.captured)
        model.jobDraft = ""
        refreshJobRows()
    }

    /// A box on the checklist: done (with the explosion), or, if it was done, back on the list.
    private func toggleJob(_ id: String) {
        guard let job = jobDay.job(id) else { return }
        cancelAutoClose()
        if job.status == .done {
            jobDay.reopen(id)
        } else {
            jobDay.finish(id, now: nowWall)
            if countdownJobID == id { cancelTimer() }
            model.boom = NotchModel.Boom(rowID: id, serial: (model.boom?.serial ?? 0) + 1)
            sounds.play(.allInTune)
            // He answers the tick, but the list stays where it is: no line screen in the way.
            let pick = Lines.pick(bank: lineBank, state: &lineState, category: "job_done", target: nil,
                                  frequency: config.theme.voice.frequency, rng: { Double.random(in: 0..<1) })
            LineStateStore.save(lineState)
            if let pick = pick, config.speak { mouth.say(pick) }
        }
        saveJobs()
        refreshJobRows()
    }

    private func deleteJob(_ id: String) {
        cancelAutoClose()
        if countdownJobID == id { cancelTimer() }
        jobDay.remove(id)
        saveJobs()
        refreshJobRows()
    }

    /// "by 22:00 · 30 min · opens books".
    private func describe(_ job: Job) -> String {
        var parts = [Jobs.describe(job)].filter { !$0.isEmpty }
        if let starter = job.starter, job.status == .open || job.status == .started {
            let shown = searchable.first { $0.name == starter }?.shownName ?? starter
            parts.append("opens \(shown)")
        }
        return parts.joined(separator: " · ")
    }

    /// "done read". On its own: the one job that was started, if there is only one.
    private func doneCommand(_ argument: String?) {
        rollJobs()
        let words = (argument ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let started = jobDay.jobs.filter { $0.status == .started }
        let job = words.isEmpty ? (started.count == 1 ? started.first : nil) : jobDay.find(words)
        guard let found = job else {
            if words.isEmpty {
                showJobs()
            } else {
                sounds.play(.unknown)
                showLine(category: "unknown", target: nil, text: "No job called that on the books.", hold: 2.6)
            }
            return
        }
        finishJob(found.id)
    }

    /// "start it": the starter opens first (rule 1), then the timer for the job's length, then the line.
    private func startJob(_ id: String) {
        rollJobs()
        guard let job = jobDay.job(id) else { return }
        let entry = job.starter.flatMap { name in searchable.first { $0.name == name } }
        let plan = entry.flatMap { entry in
            ActionPlan.make(from: Decision(mode: .open, results: [Hit(entry: entry, band: .exact, quality: 1, usage: 0)],
                                           query: nil, confident: true))
        }
        if let plan = plan {
            Opener.run(plan, config: config)
            count(plan.entryName)
        }
        jobDay.start(id, now: nowWall)
        saveJobs()
        if let minutes = job.minutes { beginCountdown(seconds: minutes * 60, job: id) }

        if plan == nil {
            // Nothing opens this job yet. Open the box and ask: whatever he opens next becomes its starter,
            // and the first word of the job is remembered, so "read" opens it every day after.
            openBox()
            model.inputHint = "what opens “\(job.title)”?"
            pendingBindJobID = id
            return
        }
        sounds.play(.saved)
        let text = job.minutes.map { "\(job.title) · \($0) min on the clock" }
        showLine(category: "job_started", target: nil, text: text, hold: 2.6)
    }

    /// Remembers what opens a job, for this job and every later one that starts with the same word.
    private func bindStarter(_ jobID: String, to entryName: String) {
        pendingBindJobID = nil
        model.inputHint = nil
        guard !entryName.isEmpty, let index = jobDay.jobs.firstIndex(where: { $0.id == jobID }),
              let entry = searchable.first(where: { $0.name == entryName }), entry.kind != .tool else { return }
        jobDay.jobs[index].starter = entryName
        saveJobs()
        if let word = TextTools.words(jobDay.jobs[index].title).first {
            var updated = config
            updated.jobs.bindings[word] = entryName
            update(updated)
        }
    }

    private func finishJob(_ id: String) {
        jobDay.finish(id, now: nowWall)
        saveJobs()
        if countdownJobID == id { cancelTimer() }
        sounds.play(.allInTune)
        showLine(category: "job_done", target: nil, hold: 2.4)
    }

    private func laterJob(_ id: String) {
        jobDay.later(id, now: nowWall, settings: config.jobs.settings)
        saveJobs()
        showLine(category: "job_later", target: nil, hold: 2.2)
    }

    private func skipJob(_ id: String) {
        jobDay.skip(id)
        saveJobs()
        if countdownJobID == id { cancelTimer() }
        showLine(category: "job_skipped", target: nil, hold: 2.2)
    }

    /// The timer for a job ran out. He asked to be told, so this one is spoken.
    private func askIfDone(_ job: Job) {
        cancelAutoClose()
        let pick = Lines.pick(bank: lineBank, state: &lineState, category: "timer_done", target: nil,
                              frequency: 1, rng: { Double.random(in: 0..<1) })
        if let pick = pick, config.speak { mouth.say(pick) }
        let id = job.id
        model.chooserTitle = "\(job.title): time's up. done?"
        model.chooserOptions = ["done", "not yet", "skip it"]
        chooserAction = { [weak self] index in
            switch index {
            case 0: self?.finishJob(id)
            case 1: self?.laterJob(id)
            default: self?.skipJob(id)
            }
        }
        model.screen = .chooser
        controller.open(takeKeyboard: false)
        closeAfter(30)
    }

    /// "quiet": he stays in the notch until the job day ends.
    private func quietForToday() {
        let now = nowWall
        let shifted = now - Jobs.rolloverHour * 3_600_000
        let dayStart = shifted - ((shifted % 86_400_000) + 86_400_000) % 86_400_000 + Jobs.rolloverHour * 3_600_000
        jobDay.quietUntil = dayStart + 86_400_000
        saveJobs()
        jobCard.close()
        outNudge = nil
        roamer.goHome()
        showLine(category: "quiet_on", target: nil, hold: 2.2)
    }

    // MARK: Coming out of the notch

    /// Every 30 seconds: is there a job he should come out about?
    private func checkJobs() {
        rollJobs()
        let now = nowWall
        let held = FocusQuiet.isOn || !config.character.roam || (jobDay.quietUntil.map { now < $0 } ?? false)

        // His head beside the notch says a job is waiting. That head is the reminder Adi relies on, so it shows
        // whenever a job is waiting and he is not already out on the screen, whatever the fly-out setting says.
        // (It used to show only while he was held in. A config saved by the 24 Oct version had the fly-out
        // switch on, so on that Mac he was never held in and the head never appeared.)
        let waiting = jobDay.jobs.contains { job in
            job.status == .open && (job.snoozedUntil.map { now >= $0 } ?? true) && (job.dueWall.map { $0 <= now } ?? true)
        }
        let showHead = waiting && !roamer.isOut
        if model.jobWaiting != showHead {
            model.jobWaiting = showHead
            controller.refreshClosed()
        }

        guard !roamer.isOut, !jobCard.isOpen, !controller.isOpen else { return }
        // Seconds since the last key press or mouse movement. Only how long, never what: no screen is read.
        let anyInput = CGEventType(rawValue: ~0) ?? .mouseMoved
        let idle = Int(CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput))

        // Once a day, from jobs.openListAt (10:00), the list opens by itself so the day can be planned. Silent.
        if !config.jobs.openListAt.isEmpty,
           Jobs.shouldOpenList(jobDay, now: now, settings: config.jobs.settings, quiet: FocusQuiet.isOn, idleSeconds: idle) {
            jobDay.markListOpened()
            saveJobs()
            showJobs(byItself: true)
            return
        }

        guard !held else { return }
        guard let nudge = Jobs.nextNudge(jobDay, now: now, settings: config.jobs.settings, quiet: false, idleSeconds: idle) else { return }

        outNudge = nudge
        jobDay.appeared(nudge, now: now)
        saveJobs()
        // Out he flies. No sound, no voice: rule 4.
        roamer.flyOut(level: nudge.level, size: CGFloat(config.character.size), frames: model.character,
                      roamSeconds: config.jobs.roamMinutes * 60)
    }

    /// Someone clicked him: he stops, and his card opens beside him.
    private func roamerClicked() {
        guard let nudge = outNudge else {
            roamer.goHome()
            return
        }
        roamer.hold()
        let shown: (String) -> String = { [weak self] category in
            guard let self = self else { return "" }
            return Lines.pick(bank: self.lineBank, state: &self.lineState, category: category, target: nil,
                              frequency: 0, rng: { Double.random(in: 0..<1) })?.text ?? ""
        }
        switch nudge.kind {
        case .sleep:
            jobCard.show(line: shown("bedtime"), title: "bed", detail: "the books close when you go",
                         buttons: ["going", "10 more"], theme: model.theme, beside: roamer.frame)
        case .job, .check:
            guard let id = nudge.jobID, let job = jobDay.job(id) else {
                outNudge = nil
                roamer.goHome()
                return
            }
            let category = nudge.kind == .check ? "job_check" : (job.owedDays > 0 ? "job_owed" : "job_card")
            let buttons = nudge.kind == .check ? ["done", "not yet", "skip it"] : ["start it", "later", "skip today"]
            jobCard.show(line: shown(category), title: job.title, detail: describe(job), buttons: buttons,
                         theme: model.theme, beside: roamer.frame)
        }
        LineStateStore.save(lineState)
    }

    private func cardButton(_ index: Int) {
        guard let nudge = outNudge else { return }
        outNudge = nil
        // The action first, then he flies home.
        switch nudge.kind {
        case .sleep:
            if index == 0 {
                goToSleep()
            } else {
                jobDay.sleepLater(now: nowWall, minutes: 10)
                saveJobs()
                showLine(category: "job_later", target: nil, text: "ten more minutes. i'm counting.", hold: 2.4)
            }
        case .job, .check:
            guard let id = nudge.jobID else { break }
            switch (nudge.kind, index) {
            case (.job, 0): startJob(id)
            case (.check, 0): finishJob(id)
            case (_, 1): laterJob(id)
            default: skipJob(id)
            }
        }
        roamer.goHome()
    }

    /// A click somewhere else while his card was open: not now. He was noticed, so this is not "ignored".
    private func cardDismissed() {
        outNudge = nil
        roamer.goHome()
    }

    /// Nobody clicked him. Next time he comes out bolder.
    private func roamerGaveUp() {
        guard let nudge = outNudge else { return }
        outNudge = nil
        jobDay.ignored(nudge)
        saveJobs()
    }

    private func roamerMenu() -> NSMenu {
        let menu = NSMenu()
        if roamer.isPlaying {
            menu.addItem(MenuAction("Follow me") { [weak self] in
                self?.roamer.startFollowing()
                self?.dragonSays("follow_on", always: true)
            })
            menu.addItem(MenuAction("Fetch") { [weak self] in self?.roamer.startFetch() })
            menu.addItem(.separator())
            menu.addItem(MenuAction("Go home") { [weak self] in
                self?.dragonSays("pet_bye", always: true)
                self?.roamer.goHome()
            })
            return menu
        }
        if let nudge = outNudge, nudge.kind != .sleep, let id = nudge.jobID {
            menu.addItem(MenuAction("Done") { [weak self] in
                self?.outNudge = nil
                self?.finishJob(id)
                self?.roamer.goHome()
            })
            menu.addItem(MenuAction("Not today") { [weak self] in
                self?.outNudge = nil
                self?.skipJob(id)
                self?.roamer.goHome()
            })
        }
        menu.addItem(MenuAction("Leave me alone today") { [weak self] in self?.quietForToday() })
        return menu
    }

    /// "going": the day's record goes into the diary, the books close, and he stops asking.
    private func goToSleep() {
        jobDay.closeBooks()
        if let id = CaptureWriter.appendToDiary(noteID: jobDay.diaryNoteID, title: diaryTitle, lines: Jobs.ledger(jobDay)) {
            jobDay.diaryNoteID = id
        }
        saveJobs()
        showLine(category: "sleep_going", target: nil, alwaysSpeak: true, hold: 2.6)
    }

    // MARK: - The dragon, out to play

    /// "pet": he flies out of the notch to be played with. Already out playing: he comes to the cursor.
    /// Out about a job: he is already here; click him for the job.
    private func pet() {
        close()
        if roamer.isOut && !roamer.isPlaying { return }
        let wasOut = roamer.isOut
        roamer.comeOutToPlay(size: CGFloat(config.character.size), frames: model.character)
        if !wasOut { dragonSays("pet_hello", always: true) }
    }

    /// "go home", "go back", "scram": wherever he is, back into the notch. Out about a job, it counts as
    /// "not now" (like closing his card), not as ignoring him.
    private func sendHome() {
        close()
        guard roamer.isOut else {
            showLine(category: "unknown", target: nil, text: "He's already home.", hold: 1.8)
            return
        }
        if roamer.isPlaying {
            dragonSays("pet_bye", always: true)
        } else {
            jobCard.close()
            outNudge = nil
        }
        roamer.goHome()
    }

    /// A line from him while he is out: always in his speech bubble, spoken like any other line.
    /// `always` for answers to something you just did to him; petting uses the usual frequency dial.
    private func dragonSays(_ category: String, always: Bool) {
        let pick = Lines.pick(bank: lineBank, state: &lineState, category: category, target: nil,
                              frequency: always ? 1 : config.theme.voice.frequency, rng: { Double.random(in: 0..<1) })
        LineStateStore.save(lineState)
        guard let pick = pick else { return }
        roamer.say(pick.text)
        if config.speak { mouth.say(pick) }
    }

    // MARK: - The diary

    /// "Consigliere diary · 11 Oct 2026": one note per job day.
    private var diaryTitle: String {
        let parse = DateFormatter()
        parse.dateFormat = "yyyy-MM-dd"
        parse.locale = Locale(identifier: "en_US_POSIX")
        let show = DateFormatter()
        show.dateFormat = "d MMM yyyy"
        let date = parse.date(from: jobDay.day).map { show.string(from: $0) } ?? jobDay.day
        return "Consigliere diary · \(date)"
    }

    /// "diary long day, good one" adds a line to today's diary note. "diary" on its own opens it.
    private func diary(_ argument: String?) {
        rollJobs()
        let text = (argument ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            close()
            CaptureWriter.showNote(id: jobDay.diaryNoteID)
            return
        }
        guard let id = CaptureWriter.appendToDiary(noteID: jobDay.diaryNoteID, title: diaryTitle,
                                                   lines: "\(Jobs.clockText(nowWall))  \(text)") else {
            sounds.play(.unknown)
            showLine(category: "unknown", target: nil, text: "Notes would not take it. Check Privacy, Automation.", hold: 3)
            return
        }
        jobDay.diaryNoteID = id
        saveJobs()
        sounds.play(.captured)
        showLine(category: "diary_saved", target: nil, hold: 2.2)
    }

    // MARK: - Music

    /// "play beabadoobee". Spotify's search takes a moment over the internet; the line waits for it.
    private func playMusic(_ argument: String?) {
        let words = argument ?? ""
        let player = config.music.player
        Task { @MainActor [weak self] in
            let outcome = await MusicPlayer.play(words, player: player)
            guard let self = self else { return }
            switch outcome {
            case .playing(let name):
                self.showLine(category: "music_play", target: nil, text: name.isEmpty ? nil : "playing \(name)", hold: 2.4)
            case .searching(let query):
                self.showLine(category: "music_play", target: nil, text: "searching spotify for \(query)", hold: 2.4)
            case .failed(let problem):
                self.sounds.play(.unknown)
                self.showLine(category: "unknown", target: nil, text: problem, hold: 3)
            }
        }
    }

    /// Pause, next, louder, quieter, volume 30. No line: the music answering is the feedback.
    private func musicControl(_ tool: String, _ argument: String?) {
        let player = config.music.player
        var ok = true
        switch tool {
        case "playpause": ok = MusicPlayer.playPause(player: player)
        case "next": ok = MusicPlayer.next(player: player)
        case "louder": ok = MusicPlayer.nudgeVolume(by: 10)
        case "quieter": ok = MusicPlayer.nudgeVolume(by: -10)
        default: ok = MusicPlayer.setVolume(argument ?? "") != nil
        }
        if ok {
            close()
        } else {
            sounds.play(.unknown)
            let problem = tool == "volume" ? "Volume from 0 to 100: volume 30." : "Nothing is playing."
            showLine(category: "unknown", target: nil, text: problem, hold: 2.4)
        }
    }

    // MARK: - The right-click menu, and a test line for the settings window

    private func contextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(MenuAction("Settings…") { [weak self] in
            guard let self = self else { return }
            self.settingsWindow.show(brain: self)
        })
        menu.addItem(MenuAction(mouth.isMuted ? "Let him talk" : "Mute him") { [weak self] in
            guard let self = self else { return }
            self.mouth.isMuted.toggle()
            if self.mouth.isMuted { self.mouth.stop() }
            self.showLine(category: self.mouth.isMuted ? "muted_on" : "muted_off", target: nil, alwaysSpeak: !self.mouth.isMuted)
        })
        if countdown != nil {
            menu.addItem(MenuAction("Cancel the timer") { [weak self] in self?.cancelTimer() })
        }
        menu.addItem(.separator())
        menu.addItem(MenuAction("Quit Consigliere") { NSApp.terminate(nil) })
        return menu
    }

    func sayTestLine(with voice: VoiceTheme) {
        mouth.apply(voice)
        mouth.say(text: "Opening YouTube. Mamma mia.")
    }
}

/// A menu item that runs a closure, so the menu needs no target-action plumbing.
final class MenuAction: NSMenuItem {
    private let run: () -> Void

    init(_ title: String, run: @escaping () -> Void) {
        self.run = run
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) {
        fatalError("not used")
    }

    @objc private func fire() {
        run()
    }
}
