import AVFoundation
import ConsigliereCore

/// The voice. English text read by an Italian system voice, which gives the accent for free.
/// If a recorded clip exists for a line (Resources, named "<line id>.m4a"), that is played instead.
@MainActor
final class Mouth: NSObject, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private var clipPlayer: AVAudioPlayer?
    private var voice: AVSpeechSynthesisVoice?
    private var settings = VoiceTheme()

    var isMuted = false

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func apply(_ settings: VoiceTheme) {
        self.settings = settings
        voice = Mouth.pickVoice(named: settings.voiceName)
    }

    /// The named voice if it is installed; otherwise the best Italian voice on this Mac; otherwise the default.
    static func pickVoice(named name: String) -> AVSpeechSynthesisVoice? {
        let all = AVSpeechSynthesisVoice.speechVoices()
        if !name.isEmpty, let exact = all.first(where: { $0.name == name }) { return exact }
        let italian = all.filter { $0.language.hasPrefix("it") }
        return italian.max { $0.quality.rawValue < $1.quality.rawValue }
    }

    /// Every Italian voice installed, for the settings window.
    static var italianVoiceNames: [String] {
        return AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("it") }.map { $0.name }
    }

    /// Says a line. If he is already talking, the new line is dropped: two lines never overlap.
    func say(_ pick: LinePick) {
        guard !isMuted, pick.speak else { return }
        say(text: pick.text, clipID: pick.id)
    }

    func say(text: String, clipID: String? = nil) {
        guard !isMuted else { return }
        if synthesizer.isSpeaking || clipPlayer?.isPlaying == true { return }

        if let clipID = clipID, let url = Bundle.main.url(forResource: clipID, withExtension: "m4a"),
           let player = try? AVAudioPlayer(contentsOf: url) {
            clipPlayer = player
            player.play()
            return
        }

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        // AVSpeech runs from 0 to 1 with 0.5 as normal. The config uses 1.0 as normal, like the prototype.
        utterance.rate = Float(max(0.1, min(1.0, Double(AVSpeechUtteranceDefaultSpeechRate) * settings.rate)))
        utterance.pitchMultiplier = Float(max(0.5, min(2.0, settings.pitch)))
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        clipPlayer?.stop()
    }
}
