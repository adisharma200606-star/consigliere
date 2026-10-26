import Foundation

/// The day's jobs, what starts each one, and when he comes out of the notch about one.
/// Ported from `reference-js/jobs.js`; `fixtures/jobs.json` keeps the two in step.
///
/// Every time here is in wall-clock milliseconds, the same idea as `ReminderParser`: what the clock on the wall
/// says, written as if it were UTC. The app converts with `ReminderParser.wall(from:)`.
///
/// The incentive is not guilt. It is removing the first step: every job gets a "starter", the thing that opens
/// when he presses "start it" (Books for "read", the saved course page for "swift course").

public enum JobStatus: String, Codable, Equatable, Sendable {
    case open, started, done, skipped
}

public struct Job: Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    /// The catalog entry that "start it" opens. Nil when nothing fits; starting then just marks it begun.
    public var starter: String?
    /// How long it takes, from "read 30 min". Starting it runs a timer this long.
    public var minutes: Int?
    /// When it is due, from "by 10pm". Nil means "some time today".
    public var dueWall: Int?
    public var status: JobStatus
    public var addedAt: Int
    public var startedAt: Int?
    public var doneAt: Int?
    /// "Later" puts it off until this time.
    public var snoozedUntil: Int?
    public var lastShownAt: Int?
    /// How many times in a row he came out about it and nobody clicked. Makes him bolder.
    public var ignored: Int
    /// How many days it has been carried over unfinished.
    public var owedDays: Int

    public init(id: String, title: String, starter: String? = nil, minutes: Int? = nil, dueWall: Int? = nil,
                status: JobStatus = .open, addedAt: Int, startedAt: Int? = nil, doneAt: Int? = nil,
                snoozedUntil: Int? = nil, lastShownAt: Int? = nil, ignored: Int = 0, owedDays: Int = 0) {
        self.id = id
        self.title = title
        self.starter = starter
        self.minutes = minutes
        self.dueWall = dueWall
        self.status = status
        self.addedAt = addedAt
        self.startedAt = startedAt
        self.doneAt = doneAt
        self.snoozedUntil = snoozedUntil
        self.lastShownAt = lastShownAt
        self.ignored = ignored
        self.owedDays = owedDays
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, starter, minutes, dueWall, status, addedAt, startedAt, doneAt, snoozedUntil, lastShownAt, ignored, owedDays
    }

    // Hand-written so an older or hand-edited jobs.json still loads.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        starter = try c.decodeIfPresent(String.self, forKey: .starter)
        minutes = try c.decodeIfPresent(Int.self, forKey: .minutes)
        dueWall = try c.decodeIfPresent(Int.self, forKey: .dueWall)
        status = try c.decodeIfPresent(JobStatus.self, forKey: .status) ?? .open
        addedAt = try c.decodeIfPresent(Int.self, forKey: .addedAt) ?? 0
        startedAt = try c.decodeIfPresent(Int.self, forKey: .startedAt)
        doneAt = try c.decodeIfPresent(Int.self, forKey: .doneAt)
        snoozedUntil = try c.decodeIfPresent(Int.self, forKey: .snoozedUntil)
        lastShownAt = try c.decodeIfPresent(Int.self, forKey: .lastShownAt)
        ignored = try c.decodeIfPresent(Int.self, forKey: .ignored) ?? 0
        owedDays = try c.decodeIfPresent(Int.self, forKey: .owedDays) ?? 0
    }

    var isLive: Bool { status == .open || status == .started }
    var number: Int { Int(id.dropFirst()) ?? 0 }
}

/// What he typed, read into a job but not yet added to the day.
public struct JobDraft: Codable, Equatable, Sendable {
    public var title: String
    public var minutes: Int?
    public var dueWall: Int?
    public var starter: String?

    public init(title: String, minutes: Int? = nil, dueWall: Int? = nil, starter: String? = nil) {
        self.title = title
        self.minutes = minutes
        self.dueWall = dueWall
        self.starter = starter
    }
}

/// When and how he comes out. Every number has a default; `JobsConfig` turns the config's "09:00" into these.
public struct JobSettings: Equatable, Sendable {
    /// He does not come out before this (minutes after midnight).
    public var dayStartMin: Int
    /// After this the only job left is sleep. 30 means 00:30, after midnight.
    public var bedtimeMin: Int
    /// Least time between two appearances about jobs with no time set.
    public var cooldownMin: Int
    /// Least time between two appearances about jobs that are due.
    public var dueGapMin: Int
    /// Least time between two bedtime appearances.
    public var sleepGapMin: Int
    /// What "later" puts a job off by.
    public var laterMin: Int
    /// How bold he gets when ignored: 0 bobs under the notch, 3 loops the middle of the screen.
    public var maxLevel: Int
    /// Nobody at the Mac for this long: stay home.
    public var idleLimitSec: Int
    /// The list opens by itself once a day, the first time he is at the Mac after this (minutes after midnight).
    public var openAtMin: Int
    /// ...and only if he touched the Mac this recently, so it is seen.
    public var activeWithinSec: Int

    public init(dayStartMin: Int = 540, bedtimeMin: Int = 30, cooldownMin: Int = 45, dueGapMin: Int = 10,
                sleepGapMin: Int = 10, laterMin: Int = 30, maxLevel: Int = 3, idleLimitSec: Int = 300,
                openAtMin: Int = 600, activeWithinSec: Int = 120) {
        self.dayStartMin = dayStartMin
        self.bedtimeMin = bedtimeMin
        self.cooldownMin = cooldownMin
        self.dueGapMin = dueGapMin
        self.sleepGapMin = sleepGapMin
        self.laterMin = laterMin
        self.maxLevel = maxLevel
        self.idleLimitSec = idleLimitSec
        self.openAtMin = openAtMin
        self.activeWithinSec = activeWithinSec
    }
}

public enum NudgeKind: String, Codable, Equatable, Sendable {
    /// A job to start.
    case job
    /// A job started a while ago: done yet?
    case check
    /// It is past bedtime.
    case sleep
}

/// "Come out of the notch about this, this boldly."
public struct Nudge: Codable, Equatable, Sendable {
    public let kind: NudgeKind
    public let jobID: String?
    public let level: Int

    public init(kind: NudgeKind, jobID: String?, level: Int) {
        self.kind = kind
        self.jobID = jobID
        self.level = level
    }
}

/// One job day, 04:00 to 04:00. Saved as ~/.consigliere/jobs.json.
public struct JobDay: Codable, Equatable, Sendable {
    /// "2026-10-11"
    public var day: String
    public var jobs: [Job]
    public var nextID: Int
    public var lastAppearance: Int?
    public var sleepSnoozedUntil: Int?
    public var sleepIgnored: Int
    /// The books are closed: the day's record went into the diary and he stops asking about bed.
    public var closed: Bool
    /// "quiet" in the box keeps him in the notch until this time.
    public var quietUntil: Int?
    /// The day's diary note in Apple Notes.
    public var diaryNoteID: String?
    /// The list has already opened by itself today.
    public var listOpened: Bool

    public init(day: String) {
        self.day = day
        jobs = []
        nextID = 1
        lastAppearance = nil
        sleepSnoozedUntil = nil
        sleepIgnored = 0
        closed = false
        quietUntil = nil
        diaryNoteID = nil
        listOpened = false
    }

    private enum CodingKeys: String, CodingKey {
        case day, jobs, nextID, lastAppearance, sleepSnoozedUntil, sleepIgnored, closed, quietUntil, diaryNoteID, listOpened
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        day = try c.decode(String.self, forKey: .day)
        jobs = try c.decodeIfPresent([Job].self, forKey: .jobs) ?? []
        nextID = try c.decodeIfPresent(Int.self, forKey: .nextID) ?? (jobs.count + 1)
        lastAppearance = try c.decodeIfPresent(Int.self, forKey: .lastAppearance)
        sleepSnoozedUntil = try c.decodeIfPresent(Int.self, forKey: .sleepSnoozedUntil)
        sleepIgnored = try c.decodeIfPresent(Int.self, forKey: .sleepIgnored) ?? 0
        closed = try c.decodeIfPresent(Bool.self, forKey: .closed) ?? false
        quietUntil = try c.decodeIfPresent(Int.self, forKey: .quietUntil)
        diaryNoteID = try c.decodeIfPresent(String.self, forKey: .diaryNoteID)
        listOpened = try c.decodeIfPresent(Bool.self, forKey: .listOpened) ?? false
    }

    public func job(_ id: String) -> Job? {
        return jobs.first { $0.id == id }
    }

    /// Jobs not yet done or skipped.
    public var liveJobs: [Job] {
        return jobs.filter { $0.isLive }
    }

    // MARK: adding

    /// Adds drafts. A draft with the same title as a job not yet finished updates it instead.
    /// Returns the ids of the jobs added or updated.
    @discardableResult
    public mutating func add(_ drafts: [JobDraft], now: Int) -> [String] {
        var ids = [String]()
        for draft in drafts {
            if let index = jobs.firstIndex(where: { $0.isLive && TextTools.normalize($0.title) == TextTools.normalize(draft.title) }) {
                if let minutes = draft.minutes { jobs[index].minutes = minutes }
                if let due = draft.dueWall { jobs[index].dueWall = due }
                if let starter = draft.starter { jobs[index].starter = starter }
                ids.append(jobs[index].id)
                continue
            }
            let job = Job(id: "j\(nextID)", title: draft.title, starter: draft.starter, minutes: draft.minutes,
                          dueWall: draft.dueWall, addedAt: now)
            nextID += 1
            jobs.append(job)
            ids.append(job.id)
        }
        return ids
    }

    /// "done read": the unfinished job whose title best fits. Exact, then start, then anywhere.
    public func find(_ text: String) -> Job? {
        let q = TextTools.normalize(text)
        if q.isEmpty { return nil }
        let live = liveJobs
        let tests: [(String) -> Bool] = [{ $0 == q }, { $0.hasPrefix(q) }, { $0.contains(q) }]
        for test in tests {
            if let hit = live.first(where: { test(TextTools.normalize($0.title)) }) { return hit }
        }
        return nil
    }

    // MARK: what he did with a job

    private mutating func change(_ id: String, _ body: (inout Job) -> Void) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[index].ignored = 0
        jobs[index].snoozedUntil = nil
        body(&jobs[index])
    }

    public mutating func start(_ id: String, now: Int) {
        change(id) { $0.status = .started; $0.startedAt = now }
    }

    public mutating func finish(_ id: String, now: Int) {
        change(id) { $0.status = .done; $0.doneAt = now }
    }

    public mutating func skip(_ id: String) {
        change(id) { $0.status = .skipped }
    }

    public mutating func later(_ id: String, now: Int, settings: JobSettings = JobSettings()) {
        change(id) { $0.snoozedUntil = now + settings.laterMin * Jobs.minute }
    }

    public mutating func sleepLater(now: Int, minutes: Int = 10) {
        sleepSnoozedUntil = now + minutes * Jobs.minute
        sleepIgnored = 0
    }

    public mutating func closeBooks() {
        closed = true
    }

    /// Ticked by mistake: back on the list.
    public mutating func reopen(_ id: String) {
        change(id) { $0.status = .open; $0.doneAt = nil; $0.startedAt = nil }
    }

    /// Gone from the list, not done and not skipped: it never goes into the ledger. True if it was there.
    @discardableResult
    public mutating func remove(_ id: String) -> Bool {
        let before = jobs.count
        jobs.removeAll { $0.id == id }
        return jobs.count < before
    }

    public mutating func markListOpened() {
        listOpened = true
    }

    // MARK: coming out of the notch

    /// He came out.
    public mutating func appeared(_ nudge: Nudge, now: Int) {
        lastAppearance = now
        if let id = nudge.jobID, let index = jobs.firstIndex(where: { $0.id == id }) {
            jobs[index].lastShownAt = now
        }
    }

    /// He went home without anyone clicking him. Next time he is one step bolder.
    public mutating func ignored(_ nudge: Nudge) {
        if nudge.kind == .sleep {
            sleepIgnored += 1
            return
        }
        if let id = nudge.jobID, let index = jobs.firstIndex(where: { $0.id == id }) {
            jobs[index].ignored += 1
        }
    }
}

public enum Jobs {
    static let minute = 60_000
    static let hour = 3_600_000
    static let day = 86_400_000
    /// A job day runs from 04:00 to 04:00, so a job typed at 1 a.m. still belongs to the evening before.
    public static let rolloverHour = 4

    private static let durationUnits: Set<String> = ["h", "hr", "hrs", "hour", "hours", "m", "min", "mins", "minute", "minutes"]
    /// Words people put in front of a job that are not part of it: "i need to call dad" is the job "call dad".
    private static let leadingPhrases: [[String]] = [["i", "need", "to"], ["i", "have", "to"], ["i", "gotta"], ["i", "must"],
                                                     ["i", "should"], ["need", "to"], ["have", "to"], ["gotta"], ["must"], ["to"]]

    // MARK: clock helpers

    /// "09:00" or "0:30" to minutes after midnight, or nil.
    public static func clockMinutes(_ text: String) -> Int? {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, (1...2).contains(parts[0].count), parts[1].count == 2,
              parts.allSatisfy({ $0.allSatisfy { $0.isASCII && $0.isNumber } }),
              let h = Int(parts[0]), let m = Int(parts[1]), h <= 23, m <= 59 else { return nil }
        return h * 60 + m
    }

    private static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? calendar.timeZone
        return calendar
    }

    /// "2026-10-11": which job day a wall time belongs to.
    public static func dayKey(_ wall: Int) -> String {
        let date = Date(timeIntervalSince1970: Double(wall - rolloverHour * hour) / 1000)
        let p = utc.dateComponents([.year, .month, .day], from: date)
        let two: (Int) -> String = { $0 < 10 ? "0\($0)" : "\($0)" }
        return "\(p.year ?? 1970)-\(two(p.month ?? 1))-\(two(p.day ?? 1))"
    }

    /// Minutes since midnight, but the small hours count as the end of the day before (1:00 is 1500).
    static func shifted(_ minutes: Int) -> Int {
        return minutes < rolloverHour * 60 ? minutes + 1440 : minutes
    }

    static func wallMinutes(_ wall: Int) -> Int {
        return (((wall % day) + day) % day) / minute
    }

    /// "22:00" from a wall time.
    public static func clockText(_ wall: Int) -> String {
        let ms = ((wall % day) + day) % day
        let two: (Int) -> String = { $0 < 10 ? "0\($0)" : "\($0)" }
        return "\(two(ms / hour)):\(two((ms % hour) / minute))"
    }

    // MARK: reading jobs

    /// Lowercase, with anything that is not a letter, digit, "." or ":" trimmed off both ends.
    private static func bare(_ token: String) -> String {
        let keep: (Character) -> Bool = { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == ":") }
        var chars = Array(token.lowercased())
        while let first = chars.first, !keep(first) { chars.removeFirst() }
        while let last = chars.last, !keep(last) { chars.removeLast() }
        return String(chars)
    }

    private static func isNumber(_ s: String) -> Bool {
        let pieces = s.split(separator: ".", omittingEmptySubsequences: false)
        guard pieces.count == 1 || pieces.count == 2 else { return false }
        return pieces.allSatisfy { !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber } }
    }

    /// "30min" to ("30", "min"); "1.5h" to ("1.5", "h").
    private static func splitGlued(_ s: String) -> (String, String)? {
        let number = s.prefix { ($0.isASCII && $0.isNumber) || $0 == "." }
        let letters = s.dropFirst(number.count)
        guard isNumber(String(number)), !letters.isEmpty, letters.allSatisfy({ $0.isASCII && $0.isLetter }) else { return nil }
        return (String(number), String(letters))
    }

    /// Finds "30 min", "for 1h", "an hour", "half an hour" (but not "in 30 min", which is a time).
    static func takeDuration(_ tokens: [String]) -> (minutes: Int?, rest: [String]) {
        let words = tokens.map { bare($0) }
        func word(_ i: Int) -> String? { i >= 0 && i < words.count ? words[i] : nil }
        for i in words.indices {
            if i > 0 && words[i - 1] == "in" { continue }
            var seconds: Int? = nil
            var count = 0
            if words[i] == "half", word(i + 1) == "an", word(i + 2) == "hour" {
                seconds = 1800
                count = 3
            } else if words[i] == "an" || words[i] == "a", word(i + 1) == "hour" {
                seconds = 3600
                count = 2
            } else if isNumber(words[i]), let unit = word(i + 1), durationUnits.contains(unit) {
                seconds = DurationParser.parse(words[i] + " " + unit)
                count = 2
            } else if let (_, unit) = splitGlued(words[i]), durationUnits.contains(unit) {
                seconds = DurationParser.parse(words[i])
                count = 1
            }
            guard let found = seconds else { continue }
            var from = i
            if i > 0 && words[i - 1] == "for" {
                from = i - 1
                count += 1
            }
            let rest = Array(tokens[0..<from]) + Array(tokens[(from + count)...])
            let minutes = Swift.max(1, Int((Double(found) / 60).rounded(.toNearestOrAwayFromZero)))
            return (minutes, rest)
        }
        return (nil, tokens)
    }

    private static func dropLeadingPhrase(_ tokens: [String]) -> [String] {
        let words = tokens.map { bare($0) }
        for phrase in leadingPhrases where words.count > phrase.count {
            if Array(words.prefix(phrase.count)) == phrase { return Array(tokens.dropFirst(phrase.count)) }
        }
        return tokens
    }

    /// Which catalog entry starts this job, or nil. In order:
    ///  1. a word he has bound before ("read" to "books")
    ///  2. the whole title matches confidently ("duolingo", "read a chapter" through "read")
    ///  3. the end of the title exactly names an entry ("finish the swift course" to "swift course")
    /// Tools never start a job: "timer" in a job title is not a reason to open the timer.
    public static func bindStarter(_ title: String, catalog: [CatalogEntry], bindings: [String: String] = [:]) -> String? {
        let tokens = title.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let hasEntry: (String) -> Bool = { name in catalog.contains { $0.name == name && $0.kind != .tool } }
        for token in tokens {
            if let bound = bindings[TextTools.normalize(token)], hasEntry(bound) { return bound }
        }
        let decision = Matcher.match(title, catalog: catalog, usage: [:])
        if decision.mode == .open, decision.confident, let first = decision.results.first, first.entry.kind != .tool {
            return first.entry.name
        }
        if tokens.count > 1 {
            for start in 1..<tokens.count {
                let ranked = Matcher.rank(TextTools.normalize(tokens[start...].joined()), catalog: catalog, usage: [:])
                if let first = ranked.first, first.band == .exact, first.entry.kind != .tool { return first.entry.name }
            }
        }
        return nil
    }

    /// "read 30 min, swift course, duolingo by 10pm" to three drafts.
    /// Commas, semicolons and new lines separate jobs. "and" does not, so "call mom and dad" stays one job.
    public static func parse(_ text: String, nowWall: Int, catalog: [CatalogEntry], bindings: [String: String] = [:]) -> [JobDraft] {
        var drafts = [JobDraft]()
        for piece in text.split(whereSeparator: { $0 == "," || $0 == ";" || $0 == "\n" }) {
            var tokens = piece.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            if tokens.isEmpty { continue }
            tokens = dropLeadingPhrase(tokens)
            let duration = takeDuration(tokens)
            if duration.rest.isEmpty { continue }
            let read = ReminderParser.parse(duration.rest.joined(separator: " "), nowWall: nowWall)
            let title = read.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if title.isEmpty { continue }
            drafts.append(JobDraft(title: title, minutes: duration.minutes, dueWall: read.dueWall,
                                   starter: bindStarter(title, catalog: catalog, bindings: bindings)))
        }
        return drafts
    }

    // MARK: days

    /// A new day. Whatever was not finished comes along, owed one more day. Done and skipped jobs stay behind.
    public static func rollover(_ day: JobDay?, to key: String) -> JobDay {
        if let day = day, day.day == key { return day }
        var fresh = JobDay(day: key)
        guard let day = day else { return fresh }
        for job in day.jobs where job.isLive {
            // A time from yesterday is no longer a time; the job becomes one for whenever.
            let carried = Job(id: "j\(fresh.nextID)", title: job.title, starter: job.starter, minutes: job.minutes,
                              dueWall: nil, addedAt: job.addedAt, owedDays: job.owedDays + 1)
            fresh.nextID += 1
            fresh.jobs.append(carried)
        }
        return fresh
    }

    // MARK: when he comes out

    /// Should he come out of the notch now, and about what? `quiet` is a Focus mode with his filter on.
    /// He never speaks when he comes out. The app only makes him fly; the voice waits for a click.
    public static func nextNudge(_ day: JobDay, now: Int, settings: JobSettings = JobSettings(), quiet: Bool, idleSeconds: Int) -> Nudge? {
        if quiet { return nil }
        if let until = day.quietUntil, now < until { return nil }
        if idleSeconds > settings.idleLimitSec { return nil }

        let nowShifted = shifted(wallMinutes(now))
        let gap = day.lastAppearance.map { now - $0 } ?? Int.max
        let snoozed: (Job) -> Bool = { job in job.snoozedUntil.map { now < $0 } ?? false }
        let level: (Job) -> Int = { Swift.min(settings.maxLevel, $0.ignored) }

        if nowShifted >= shifted(settings.bedtimeMin) {
            if day.closed { return nil }
            if let until = day.sleepSnoozedUntil, now < until { return nil }
            if gap < settings.sleepGapMin * minute { return nil }
            return Nudge(kind: .sleep, jobID: nil, level: Swift.min(settings.maxLevel, day.sleepIgnored))
        }
        if nowShifted < shifted(settings.dayStartMin) { return nil }

        let due = day.jobs
            .filter { $0.status == .open && !snoozed($0) && ($0.dueWall.map { $0 <= now } ?? false) }
            .sorted { a, b in a.dueWall != b.dueWall ? (a.dueWall ?? 0) < (b.dueWall ?? 0) : a.number < b.number }
        if let first = due.first, gap >= settings.dueGapMin * minute {
            return Nudge(kind: .job, jobID: first.id, level: level(first))
        }

        if gap < settings.cooldownMin * minute { return nil }

        let checks = day.jobs.filter { job in
            guard job.status == .started, !snoozed(job), let started = job.startedAt else { return false }
            return now - started >= Swift.max(job.minutes ?? 0, settings.cooldownMin) * minute
        }.sorted { $0.number < $1.number }
        if let first = checks.first {
            return Nudge(kind: .check, jobID: first.id, level: level(first))
        }

        let loose = day.jobs.filter { $0.status == .open && !snoozed($0) && $0.dueWall == nil }.sorted { a, b in
            if a.owedDays != b.owedDays { return a.owedDays > b.owedDays }
            let aShown = a.lastShownAt ?? -1
            let bShown = b.lastShownAt ?? -1
            if aShown != bShown { return aShown < bShown }
            return a.number < b.number
        }
        if let first = loose.first {
            return Nudge(kind: .job, jobID: first.id, level: level(first))
        }
        return nil
    }

    /// Should the list open by itself now, so he can plan the day? Once a day, the first time he is at the Mac
    /// after `openAtMin`, never during quiet, never after bedtime. Silent: the list opens, nothing is said.
    public static func shouldOpenList(_ day: JobDay, now: Int, settings: JobSettings = JobSettings(), quiet: Bool, idleSeconds: Int) -> Bool {
        if day.listOpened || quiet { return false }
        if let until = day.quietUntil, now < until { return false }
        if idleSeconds > settings.activeWithinSec { return false }
        let nowShifted = shifted(wallMinutes(now))
        return nowShifted >= shifted(settings.openAtMin) && nowShifted < shifted(settings.bedtimeMin)
    }

    // MARK: saying it back

    /// The small grey text beside a job in the list: "by 22:00 · 30 min · owed 2 days".
    public static func describe(_ job: Job) -> String {
        var parts = [String]()
        switch job.status {
        case .done: parts.append("done")
        case .skipped: parts.append("skipped")
        case .started: parts.append("on it")
        case .open: break
        }
        if let due = job.dueWall { parts.append("by \(clockText(due))") }
        if let minutes = job.minutes { parts.append("\(minutes) min") }
        if job.owedDays == 1 {
            parts.append("owed since yesterday")
        } else if job.owedDays > 1 {
            parts.append("owed \(job.owedDays) days")
        }
        return parts.joined(separator: " · ")
    }

    /// The day's record, written into the diary when he closes the books.
    public static func ledger(_ day: JobDay) -> String {
        let name: (Job) -> String = { $0.title + ($0.minutes.map { " (\($0) min)" } ?? "") }
        var lines = ["Jobs, \(day.day)"]
        let done = day.jobs.filter { $0.status == .done }
        let skipped = day.jobs.filter { $0.status == .skipped }
        let owed = day.liveJobs
        if day.jobs.isEmpty { lines.append("No jobs today.") }
        if !done.isEmpty { lines.append("Done: " + done.map(name).joined(separator: ", ")) }
        if !skipped.isEmpty { lines.append("Skipped: " + skipped.map(name).joined(separator: ", ")) }
        if !owed.isEmpty {
            lines.append("Still owed: " + owed.map { job in
                name(job) + (job.owedDays > 0 ? " (\(job.owedDays + 1) days now)" : "")
            }.joined(separator: ", "))
        }
        return lines.joined(separator: "\n")
    }
}
