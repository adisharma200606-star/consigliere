import Foundation

/// The Mac trackpad's three kinds of tap. Only felt while a finger is resting on the trackpad.
public enum HapticKind: String, Codable, Equatable {
    case alignment
    case levelChange
    case generic
}

/// Everything that can happen that deserves a sound or a tap.
public enum FeedbackEvent: String, CaseIterable, Equatable {
    case open
    case close
    case opened
    case saved
    case captured
    case bookmarkMoved
    case pulled
    case another
    case unknown
    case answer
    case tunerLock
    case allInTune
    case timerDone
}

public struct FeedbackSpec: Equatable {
    /// The name of a file in Resources/sounds, without ".wav". Nil for silence.
    public let sound: String?
    public let haptic: HapticKind?
}

/// What he hears and feels for each event. Ported from `reference-js/core.js`; fixtures/feedback.json keeps the two in step.
public enum Feedback {
    public static func spec(for event: FeedbackEvent) -> FeedbackSpec {
        switch event {
        case .open: return FeedbackSpec(sound: "open", haptic: .alignment)
        case .close: return FeedbackSpec(sound: "close", haptic: nil)
        case .opened: return FeedbackSpec(sound: nil, haptic: nil)   // the thing opening is its own feedback
        case .saved: return FeedbackSpec(sound: "save", haptic: .levelChange)
        case .captured: return FeedbackSpec(sound: "save", haptic: .levelChange)
        case .bookmarkMoved: return FeedbackSpec(sound: "save", haptic: .levelChange)
        case .pulled: return FeedbackSpec(sound: "pull", haptic: nil)
        case .another: return FeedbackSpec(sound: "pull", haptic: nil)
        case .unknown: return FeedbackSpec(sound: "nope", haptic: .generic)
        case .answer: return FeedbackSpec(sound: "answer", haptic: nil)
        case .tunerLock: return FeedbackSpec(sound: "lock", haptic: .alignment)
        case .allInTune: return FeedbackSpec(sound: "done", haptic: .generic)
        case .timerDone: return FeedbackSpec(sound: "done", haptic: .generic)
        }
    }
}

public struct FeedbackConfig: Codable, Equatable {
    public var sounds: Bool
    /// 0 to 1. The sounds are quiet to begin with; this scales them further.
    public var volume: Double
    public var haptics: Bool

    public init(sounds: Bool = true, volume: Double = 0.5, haptics: Bool = true) {
        self.sounds = sounds
        self.volume = volume
        self.haptics = haptics
    }

    private enum CodingKeys: String, CodingKey { case sounds, volume, haptics }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = FeedbackConfig()
        sounds = try c.decodeIfPresent(Bool.self, forKey: .sounds) ?? d.sounds
        volume = try c.decodeIfPresent(Double.self, forKey: .volume) ?? d.volume
        haptics = try c.decodeIfPresent(Bool.self, forKey: .haptics) ?? d.haptics
    }
}
