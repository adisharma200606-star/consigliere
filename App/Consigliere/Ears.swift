import AVFoundation
import Speech

/// Hold-to-talk. Starts listening when the talk key goes down, and hands back the words when it comes up.
///
/// Recognition happens on the Mac when the chosen language supports it. When it does not, macOS sends the
/// audio to Apple to be recognised; `isOnDevice` says which is in use, and the settings window shows it.
@MainActor
final class Ears {
    private var recognizer: SFSpeechRecognizer?
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var latest = ""
    private var finish: ((String) -> Void)?
    private(set) var isListening = false

    var isOnDevice: Bool { recognizer?.supportsOnDeviceRecognition ?? false }

    func setLocale(_ identifier: String) {
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: identifier)) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    }

    /// Asks for the two permissions up front, so the first real use is not interrupted by dialogs.
    func requestPermissions() {
        SFSpeechRecognizer.requestAuthorization { _ in }
        AVCaptureDevice.requestAccess(for: .audio) { _ in }
    }

    /// `hints` are the names of his things, so "yt" and "consigliere" are heard as words and not as noise.
    func start(hints: [String], onPartial: @escaping (String) -> Void) {
        guard !isListening, let recognizer = recognizer, recognizer.isAvailable,
              SFSpeechRecognizer.authorizationStatus() == .authorized else { return }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.contextualStrings = hints
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        self.request = request
        latest = ""

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            NSLog("Consigliere: the microphone would not start: \(error)")
            input.removeTap(onBus: 0)
            return
        }
        isListening = true

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let failed = error != nil
            Task { @MainActor in
                guard let self = self else { return }
                if let text = text {
                    self.latest = text
                    onPartial(text)
                }
                if isFinal || failed { self.deliver() }
            }
        }
    }

    /// Stops listening. `completion` gets the words, once, within about half a second.
    func stop(completion: @escaping (String) -> Void) {
        guard isListening else {
            completion("")
            return
        }
        isListening = false
        finish = completion
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()

        // The recogniser usually sends a final result almost at once. If it does not, use what we have.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            self.deliver()
        }
    }

    private func deliver() {
        guard let finish = finish else { return }
        self.finish = nil
        task?.cancel()
        task = nil
        request = nil
        finish(latest)
    }
}
