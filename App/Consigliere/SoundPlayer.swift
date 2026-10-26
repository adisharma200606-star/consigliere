import AppKit
import AVFoundation
import ConsigliereCore

/// Interface sounds and trackpad taps. Which sound goes with which event is decided in ConsigliereCore
/// (`Feedback.spec`); this file only plays them.
@MainActor
final class SoundPlayer {
    private var players = [String: AVAudioPlayer]()
    private var settings = FeedbackConfig()

    func apply(_ settings: FeedbackConfig) {
        self.settings = settings
    }

    /// Loads every sound once, so playing one later is instant.
    func preload() {
        for name in ["open", "close", "save", "pull", "nope", "answer", "lock", "done"] {
            // XcodeGen copies resources into the top of the bundle; look in a "sounds" folder too, in case
            // the project is ever set up to keep the folder.
            let url = Bundle.main.url(forResource: name, withExtension: "wav")
                ?? Bundle.main.url(forResource: name, withExtension: "wav", subdirectory: "sounds")
            guard let url = url, let player = try? AVAudioPlayer(contentsOf: url) else {
                NSLog("Consigliere: sound \(name).wav is missing from the app")
                continue
            }
            player.prepareToPlay()
            players[name] = player
        }
    }

    func play(_ event: FeedbackEvent) {
        let spec = Feedback.spec(for: event)

        if settings.sounds, let name = spec.sound, let player = players[name] {
            player.volume = Float(max(0, min(1, settings.volume)))
            player.currentTime = 0
            player.play()
        }

        if settings.haptics, let haptic = spec.haptic {
            let pattern: NSHapticFeedbackManager.FeedbackPattern
            switch haptic {
            case .alignment: pattern = .alignment
            case .levelChange: pattern = .levelChange
            case .generic: pattern = .generic
            }
            // Only felt while a finger is resting on the trackpad.
            NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
        }
    }
}
