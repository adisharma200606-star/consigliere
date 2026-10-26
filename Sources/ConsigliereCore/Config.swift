import Foundation

// Everything the user can change lives in one file: ~/.consigliere/config.json
// Every field has a default, so a config that leaves things out (or an older config) still loads.

public struct Hotkeys: Codable, Equatable {
    /// Opens the box in the notch. Config key "open".
    public var openBox: String
    /// Held down to talk, released to run. Config key "talk".
    /// It must include a normal key: macOS cannot register a modifier on its own as a global hotkey.
    public var talk: String
    /// Saves the front browser tab to the stash. No window appears. Config key "save".
    public var saveTab: String
    /// Moves a living bookmark to the page in front. Config key "mark".
    public var markPlace: String

    public init(openBox: String = "opt+space", talk: String = "ctrl+opt+space", saveTab: String = "ctrl+opt+s",
                markPlace: String = "ctrl+opt+m") {
        self.openBox = openBox
        self.talk = talk
        self.saveTab = saveTab
        self.markPlace = markPlace
    }

    private enum CodingKeys: String, CodingKey {
        case openBox = "open"
        case talk
        case saveTab = "save"
        case markPlace = "mark"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Hotkeys()
        openBox = try c.decodeIfPresent(String.self, forKey: .openBox) ?? d.openBox
        talk = try c.decodeIfPresent(String.self, forKey: .talk) ?? d.talk
        saveTab = try c.decodeIfPresent(String.self, forKey: .saveTab) ?? d.saveTab
        markPlace = try c.decodeIfPresent(String.self, forKey: .markPlace) ?? d.markPlace
    }
}

public struct BraveConfig: Codable, Equatable {
    /// The Brave binary. Launched directly, because `open -a` drops its arguments when Brave is already running.
    public var binaryPath: String
    /// Folder names inside Brave's user data directory. Found on day one; see DAY_ONE.md.
    public var personalProfileDir: String
    public var workProfileDir: String

    public init(binaryPath: String = "/Applications/Brave Browser.app/Contents/MacOS/Brave Browser",
                personalProfileDir: String = "Default", workProfileDir: String = "Profile 1") {
        self.binaryPath = binaryPath
        self.personalProfileDir = personalProfileDir
        self.workProfileDir = workProfileDir
    }

    private enum CodingKeys: String, CodingKey { case binaryPath, personalProfileDir, workProfileDir }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = BraveConfig()
        binaryPath = try c.decodeIfPresent(String.self, forKey: .binaryPath) ?? d.binaryPath
        personalProfileDir = try c.decodeIfPresent(String.self, forKey: .personalProfileDir) ?? d.personalProfileDir
        workProfileDir = try c.decodeIfPresent(String.self, forKey: .workProfileDir) ?? d.workProfileDir
    }

    /// The profile directory for a catalog entry's `profile` value.
    public func profileDirectory(for profile: String) -> String {
        return profile == "work" ? workProfileDir : personalProfileDir
    }
}

/// The spring that drives the notch. Same numbers as the phone prototype:
/// SwiftUI `interpolatingSpring(mass: 1, stiffness:, damping:)`.
public struct MotionTheme: Codable, Equatable {
    public var stiffness: Double
    public var damping: Double

    public init(stiffness: Double = 260, damping: Double = 24) {
        self.stiffness = stiffness
        self.damping = damping
    }

    private enum CodingKeys: String, CodingKey { case stiffness, damping }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = MotionTheme()
        stiffness = try c.decodeIfPresent(Double.self, forKey: .stiffness) ?? d.stiffness
        damping = try c.decodeIfPresent(Double.self, forKey: .damping) ?? d.damping
    }
}

/// The look. Version 2 is "Nocturne, liner notes": a black notch, thin Helvetica Neue, small monospaced
/// labels, one steel-blue accent, a rim of light along the notch's bottom edge and a little film grain.
public struct LookTheme: Codable, Equatable {
    /// The name of the palette ("nocturne"). Informational.
    public var palette: String
    /// The one accent colour, "#RRGGBB": the selected row's marker, the line he says, the tuner's needle.
    public var accent: String
    /// The three colours of the soft light around the open notch: inner, middle, outer.
    public var glowColors: [String]
    /// 0 turns that light off, 1 is full strength.
    public var glowStrength: Double
    /// How visible the film grain on the notch is, 0 to 1. Around 0.06 is barely there.
    public var grain: Double
    /// Base text size in points. The typed text and the tuner note scale from it.
    public var textSize: Double
    /// How long one pulse of the cursor takes, in milliseconds.
    public var caretBlinkMs: Double

    public static let nocturneAccent = "#A9BBD6"
    public static let nocturneGlow = ["#7890C8", "#16233C", "#0B1222"]
    /// Kept so an old config that names these colours still reads them.
    public static let auroraColors = ["#FF375F", "#0A84FF", "#BF5AF2"]

    public init(palette: String = "nocturne", accent: String = LookTheme.nocturneAccent,
                glowColors: [String] = LookTheme.nocturneGlow, glowStrength: Double = 0.35, grain: Double = 0.06,
                textSize: Double = 19, caretBlinkMs: Double = 600) {
        self.palette = palette
        self.accent = accent
        self.glowColors = glowColors
        self.glowStrength = glowStrength
        self.grain = grain
        self.textSize = textSize
        self.caretBlinkMs = caretBlinkMs
    }

    private enum CodingKeys: String, CodingKey { case palette, accent, glowColors, glowStrength, grain, textSize, caretBlinkMs }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = LookTheme()
        textSize = try c.decodeIfPresent(Double.self, forKey: .textSize) ?? d.textSize
        caretBlinkMs = try c.decodeIfPresent(Double.self, forKey: .caretBlinkMs) ?? d.caretBlinkMs
        // A config written before the Nocturne look has no "accent". Its colours were the old Aurora defaults,
        // not a choice, so it moves to the new look instead of keeping them.
        guard c.contains(.accent) else {
            palette = d.palette
            accent = d.accent
            glowColors = d.glowColors
            glowStrength = d.glowStrength
            grain = d.grain
            return
        }
        palette = try c.decodeIfPresent(String.self, forKey: .palette) ?? d.palette
        accent = try c.decodeIfPresent(String.self, forKey: .accent) ?? d.accent
        glowColors = try c.decodeIfPresent([String].self, forKey: .glowColors) ?? d.glowColors
        glowStrength = try c.decodeIfPresent(Double.self, forKey: .glowStrength) ?? d.glowStrength
        grain = try c.decodeIfPresent(Double.self, forKey: .grain) ?? d.grain
    }

    /// The accent as red, green, blue in 0...1, falling back to the Nocturne steel.
    public var accentRGB: (red: Double, green: Double, blue: Double) {
        return LookTheme.rgb(hex: accent) ?? LookTheme.rgb(hex: LookTheme.nocturneAccent) ?? (red: 1, green: 1, blue: 1)
    }

    /// The three glow colours as red, green, blue in 0...1. Always returns exactly three, falling back to
    /// the Nocturne colours for anything missing or unreadable.
    public var glowRGB: [(red: Double, green: Double, blue: Double)] {
        return (0..<3).map { index in
            let fallback = LookTheme.nocturneGlow[index]
            let hex = index < glowColors.count ? glowColors[index] : fallback
            return LookTheme.rgb(hex: hex) ?? LookTheme.rgb(hex: fallback) ?? (red: 1, green: 1, blue: 1)
        }
    }

    /// "#RRGGBB" or "RRGGBB" to red, green, blue in 0...1. Nil when it cannot be read.
    public static func rgb(hex raw: String) -> (red: Double, green: Double, blue: Double)? {
        var hex = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.utf8.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
        return (red: Double((value >> 16) & 0xFF) / 255.0,
                green: Double((value >> 8) & 0xFF) / 255.0,
                blue: Double(value & 0xFF) / 255.0)
    }
}

public struct VoiceTheme: Codable, Equatable {
    /// The name of the system voice to use. Empty means "the best Italian voice installed".
    public var voiceName: String
    /// 1.0 is the voice's normal speed.
    public var rate: Double
    public var pitch: Double
    /// Chance, 0 to 1, that a line is spoken as well as shown.
    public var frequency: Double

    public init(voiceName: String = "", rate: Double = 0.95, pitch: Double = 0.9, frequency: Double = 0.6) {
        self.voiceName = voiceName
        self.rate = rate
        self.pitch = pitch
        self.frequency = frequency
    }

    private enum CodingKeys: String, CodingKey { case voiceName, rate, pitch, frequency }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = VoiceTheme()
        voiceName = try c.decodeIfPresent(String.self, forKey: .voiceName) ?? d.voiceName
        rate = try c.decodeIfPresent(Double.self, forKey: .rate) ?? d.rate
        pitch = try c.decodeIfPresent(Double.self, forKey: .pitch) ?? d.pitch
        frequency = try c.decodeIfPresent(Double.self, forKey: .frequency) ?? d.frequency
    }
}

/// The block the phone prototype exports. Paste it over "theme" in config.json.
public struct Theme: Codable, Equatable {
    public var motion: MotionTheme
    public var look: LookTheme
    public var voice: VoiceTheme

    public init(motion: MotionTheme = MotionTheme(), look: LookTheme = LookTheme(), voice: VoiceTheme = VoiceTheme()) {
        self.motion = motion
        self.look = look
        self.voice = voice
    }

    private enum CodingKeys: String, CodingKey { case motion, look, voice }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        motion = try c.decodeIfPresent(MotionTheme.self, forKey: .motion) ?? MotionTheme()
        look = try c.decodeIfPresent(LookTheme.self, forKey: .look) ?? LookTheme()
        voice = try c.decodeIfPresent(VoiceTheme.self, forKey: .voice) ?? VoiceTheme()
    }
}

public struct TunerConfig: Codable, Equatable {
    /// Reference pitch for A4 in Hz. 440 unless he is playing along with something tuned differently.
    public var a4: Double
    /// How close, in cents, counts as in tune.
    public var toleranceCents: Double
    /// The tuning the tuner opens on. "chromatic" means any note.
    public var lastTuningID: String
    /// His own tunings, shown after the built-in ones.
    public var customTunings: [Tuning]

    public init(a4: Double = 440, toleranceCents: Double = 5, lastTuningID: String = "guitar-standard", customTunings: [Tuning] = []) {
        self.a4 = a4
        self.toleranceCents = toleranceCents
        self.lastTuningID = lastTuningID
        self.customTunings = customTunings
    }

    private enum CodingKeys: String, CodingKey { case a4, toleranceCents, lastTuningID, customTunings }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = TunerConfig()
        a4 = try c.decodeIfPresent(Double.self, forKey: .a4) ?? d.a4
        toleranceCents = try c.decodeIfPresent(Double.self, forKey: .toleranceCents) ?? d.toleranceCents
        lastTuningID = try c.decodeIfPresent(String.self, forKey: .lastTuningID) ?? d.lastTuningID
        customTunings = try c.decodeIfPresent([Tuning].self, forKey: .customTunings) ?? d.customTunings
    }

    /// Built-in tunings followed by his own.
    public var allTunings: [Tuning] {
        return DefaultTunings.all + customTunings
    }
}

/// Settings for "Ask". The key itself is never stored here: it lives in the Mac's Keychain.
public struct AskConfig: Codable, Equatable {
    /// Which Claude model answers. The small fast one is the right default.
    public var model: String
    /// The longest reply allowed, in tokens. Three sentences fit comfortably.
    public var maxTokens: Int
    /// A spending ceiling per calendar month, in US dollars. When it is reached he says so and stops asking.
    public var monthlyBudgetUSD: Double
    /// What the chosen model costs, in US dollars per million tokens. Only used to keep count against the
    /// budget. Change these if you change `model`.
    public var inputUSDPerMillionTokens: Double
    public var outputUSDPerMillionTokens: Double

    public init(model: String = "claude-haiku-4-5", maxTokens: Int = 300, monthlyBudgetUSD: Double = 2,
                inputUSDPerMillionTokens: Double = 1, outputUSDPerMillionTokens: Double = 5) {
        self.model = model
        self.maxTokens = maxTokens
        self.monthlyBudgetUSD = monthlyBudgetUSD
        self.inputUSDPerMillionTokens = inputUSDPerMillionTokens
        self.outputUSDPerMillionTokens = outputUSDPerMillionTokens
    }

    private enum CodingKeys: String, CodingKey {
        case model, maxTokens, monthlyBudgetUSD, inputUSDPerMillionTokens, outputUSDPerMillionTokens
    }

    /// What one reply cost, from the token counts the API reports.
    public func cost(inputTokens: Int, outputTokens: Int) -> Double {
        return Double(inputTokens) / 1_000_000 * inputUSDPerMillionTokens + Double(outputTokens) / 1_000_000 * outputUSDPerMillionTokens
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AskConfig()
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? d.model
        maxTokens = try c.decodeIfPresent(Int.self, forKey: .maxTokens) ?? d.maxTokens
        monthlyBudgetUSD = try c.decodeIfPresent(Double.self, forKey: .monthlyBudgetUSD) ?? d.monthlyBudgetUSD
        inputUSDPerMillionTokens = try c.decodeIfPresent(Double.self, forKey: .inputUSDPerMillionTokens) ?? d.inputUSDPerMillionTokens
        outputUSDPerMillionTokens = try c.decodeIfPresent(Double.self, forKey: .outputUSDPerMillionTokens) ?? d.outputUSDPerMillionTokens
    }
}

/// When he comes out of the notch about jobs. Times are "HH:MM" on the wall clock.
public struct JobsConfig: Codable, Equatable {
    /// He does not come out before this.
    public var dayStart: String
    /// After this the only job left is sleep. Times before 04:00 mean after midnight.
    public var bedtime: String
    /// Least minutes between two appearances about jobs with no time set.
    public var cooldownMinutes: Int
    /// What "later" puts a job off by.
    public var laterMinutes: Int
    /// How bold he gets when ignored, 0 to 3. 0 means he only ever bobs just under the notch.
    public var maxLevel: Int
    /// Minutes he roams before giving up and flying home.
    public var roamMinutes: Double
    /// The list opens by itself once a day, the first time you are at the Mac after this. Empty: never.
    public var openListAt: String
    /// Words he has learned start a particular thing: "read" to "books". Filled in when you pick one.
    public var bindings: [String: String]

    public init(dayStart: String = "09:00", bedtime: String = "00:30", cooldownMinutes: Int = 45, laterMinutes: Int = 30,
                maxLevel: Int = 3, roamMinutes: Double = 3, openListAt: String = "10:00", bindings: [String: String] = [:]) {
        self.dayStart = dayStart
        self.bedtime = bedtime
        self.cooldownMinutes = cooldownMinutes
        self.laterMinutes = laterMinutes
        self.maxLevel = maxLevel
        self.roamMinutes = roamMinutes
        self.openListAt = openListAt
        self.bindings = bindings
    }

    private enum CodingKeys: String, CodingKey { case dayStart, bedtime, cooldownMinutes, laterMinutes, maxLevel, roamMinutes, openListAt, bindings }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = JobsConfig()
        dayStart = try c.decodeIfPresent(String.self, forKey: .dayStart) ?? d.dayStart
        bedtime = try c.decodeIfPresent(String.self, forKey: .bedtime) ?? d.bedtime
        cooldownMinutes = try c.decodeIfPresent(Int.self, forKey: .cooldownMinutes) ?? d.cooldownMinutes
        laterMinutes = try c.decodeIfPresent(Int.self, forKey: .laterMinutes) ?? d.laterMinutes
        maxLevel = try c.decodeIfPresent(Int.self, forKey: .maxLevel) ?? d.maxLevel
        roamMinutes = try c.decodeIfPresent(Double.self, forKey: .roamMinutes) ?? d.roamMinutes
        openListAt = try c.decodeIfPresent(String.self, forKey: .openListAt) ?? d.openListAt
        bindings = try c.decodeIfPresent([String: String].self, forKey: .bindings) ?? d.bindings
    }

    /// The numbers the brain works with. A time it cannot read falls back to the default.
    public var settings: JobSettings {
        let d = JobSettings()
        return JobSettings(dayStartMin: Jobs.clockMinutes(dayStart) ?? d.dayStartMin,
                           bedtimeMin: Jobs.clockMinutes(bedtime) ?? d.bedtimeMin,
                           cooldownMin: max(1, cooldownMinutes), laterMin: max(1, laterMinutes),
                           maxLevel: min(3, max(0, maxLevel)),
                           openAtMin: Jobs.clockMinutes(openListAt) ?? d.openAtMin)
    }
}

/// The character who lives in the notch.
public struct CharacterConfig: Codable, Equatable {
    /// A folder of PNG frames: idle_0.png, idle_1.png… and fly_0.png, fly_1.png…, facing right.
    /// Empty or missing means the little dragon that ships with the app.
    public var folder: String
    /// How big he is on screen, in points, before he gets bolder.
    public var size: Double
    /// Off: he never leaves the notch; a due job only shows as his head beside it.
    public var roam: Bool
    /// True when the pictures in the folder face left (most game sprites face you, slightly left).
    public var facesLeft: Bool

    public init(folder: String = "~/.consigliere/character", size: Double = 64, roam: Bool = false, facesLeft: Bool = false) {
        self.folder = folder
        self.size = size
        self.roam = roam
        self.facesLeft = facesLeft
    }

    private enum CodingKeys: String, CodingKey { case folder, size, roam, facesLeft }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = CharacterConfig()
        folder = try c.decodeIfPresent(String.self, forKey: .folder) ?? d.folder
        size = try c.decodeIfPresent(Double.self, forKey: .size) ?? d.size
        roam = try c.decodeIfPresent(Bool.self, forKey: .roam) ?? d.roam
        facesLeft = try c.decodeIfPresent(Bool.self, forKey: .facesLeft) ?? d.facesLeft
    }
}

/// "play beabadoobee". The Spotify keys, when there are any, live in the Keychain, not here.
public struct MusicConfig: Codable, Equatable {
    /// "spotify" or "music" (Apple Music).
    public var player: String

    public init(player: String = "spotify") {
        self.player = player
    }

    private enum CodingKeys: String, CodingKey { case player }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        player = try c.decodeIfPresent(String.self, forKey: .player) ?? MusicConfig().player
    }
}

public struct Config: Codable, Equatable {
    public var hotkeys: Hotkeys
    public var brave: BraveConfig
    /// Master switch for the voice. The text line shows either way.
    public var speak: Bool
    /// The accent the Mac should expect when you talk to it. "en-IN" is English as spoken in India.
    public var speechLocale: String
    public var theme: Theme
    public var tuner: TunerConfig
    public var ask: AskConfig
    public var feedback: FeedbackConfig
    /// When on, every app installed on this Mac can be opened by typing its name, with no entry needed.
    public var includeInstalledApps: Bool
    public var jobs: JobsConfig
    public var character: CharacterConfig
    public var music: MusicConfig
    public var catalog: [CatalogEntry]

    public init(hotkeys: Hotkeys = Hotkeys(), brave: BraveConfig = BraveConfig(), speak: Bool = true, speechLocale: String = "en-IN",
                theme: Theme = Theme(), tuner: TunerConfig = TunerConfig(), ask: AskConfig = AskConfig(),
                feedback: FeedbackConfig = FeedbackConfig(), includeInstalledApps: Bool = true,
                jobs: JobsConfig = JobsConfig(), character: CharacterConfig = CharacterConfig(), music: MusicConfig = MusicConfig(),
                catalog: [CatalogEntry] = DefaultCatalog.entries) {
        self.hotkeys = hotkeys
        self.brave = brave
        self.speak = speak
        self.speechLocale = speechLocale
        self.theme = theme
        self.tuner = tuner
        self.ask = ask
        self.feedback = feedback
        self.includeInstalledApps = includeInstalledApps
        self.jobs = jobs
        self.character = character
        self.music = music
        self.catalog = catalog
    }

    private enum CodingKeys: String, CodingKey { case hotkeys, brave, speak, speechLocale, theme, tuner, ask, feedback, includeInstalledApps, jobs, character, music, catalog }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hotkeys = try c.decodeIfPresent(Hotkeys.self, forKey: .hotkeys) ?? Hotkeys()
        brave = try c.decodeIfPresent(BraveConfig.self, forKey: .brave) ?? BraveConfig()
        speak = try c.decodeIfPresent(Bool.self, forKey: .speak) ?? true
        speechLocale = try c.decodeIfPresent(String.self, forKey: .speechLocale) ?? "en-IN"
        theme = try c.decodeIfPresent(Theme.self, forKey: .theme) ?? Theme()
        tuner = try c.decodeIfPresent(TunerConfig.self, forKey: .tuner) ?? TunerConfig()
        ask = try c.decodeIfPresent(AskConfig.self, forKey: .ask) ?? AskConfig()
        feedback = try c.decodeIfPresent(FeedbackConfig.self, forKey: .feedback) ?? FeedbackConfig()
        includeInstalledApps = try c.decodeIfPresent(Bool.self, forKey: .includeInstalledApps) ?? true
        jobs = try c.decodeIfPresent(JobsConfig.self, forKey: .jobs) ?? JobsConfig()
        character = try c.decodeIfPresent(CharacterConfig.self, forKey: .character) ?? CharacterConfig()
        music = try c.decodeIfPresent(MusicConfig.self, forKey: .music) ?? MusicConfig()
        catalog = try c.decodeIfPresent([CatalogEntry].self, forKey: .catalog) ?? DefaultCatalog.entries
    }
}
