import AVFoundation
import ConsigliereCore

/// Feeds the microphone to the pitch detector while the tuner is open.
///
/// Each reading looks at 4096 samples (what the low strings need), and a new reading starts every 2048, so they
/// overlap: about 23 readings a second on a Mac's 48 kHz microphone. More readings make the needle smooth and
/// let the tuner decide on a string sooner after a pluck. Every reading also carries how loud the room is, so the
/// screen can show that the microphone is hearing something even when there is no clear note.
final class MicTuner {
    private let engine = AVAudioEngine()
    private let queue = DispatchQueue(label: "consigliere.tuner", qos: .userInteractive)
    private var window = [Float]()
    private let windowSize = 4096
    private let hop = 2048
    private(set) var isRunning = false

    /// Both are called on the main thread. `onReading` gets nil for "no clear pitch right now", and the loudness
    /// (root mean square of the samples, 0 to about 1). `onProblem` gets a sentence for the screen.
    func start(onReading: @escaping (PitchReading?, Double) -> Void, onProblem: @escaping (String) -> Void) {
        guard !isRunning else { return }

        // Without permission the engine starts happily and delivers pure silence, which looks like a broken tuner.
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .denied, .restricted:
            onProblem("microphone is off for Consigliere: System Settings › Privacy › Microphone")
            return
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.start(onReading: onReading, onProblem: onProblem)
                    } else {
                        onProblem("microphone is off for Consigliere: System Settings › Privacy › Microphone")
                    }
                }
            }
            return
        default:
            break
        }

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        let sampleRate = format.sampleRate
        guard sampleRate > 0, format.channelCount > 0 else {
            onProblem("no microphone found")
            return
        }

        let windowSize = self.windowSize
        let hop = self.hop
        queue.async { self.window.removeAll(keepingCapacity: true) }
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            guard let self = self, let channel = buffer.floatChannelData?[0] else { return }
            let samples = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
            self.queue.async {
                self.window.append(contentsOf: samples)
                // Never let a backlog grow if detection falls behind: keep only the newest sound.
                if self.window.count > windowSize * 4 { self.window.removeFirst(self.window.count - windowSize) }
                while self.window.count >= windowSize {
                    let slice = Array(self.window.prefix(windowSize))
                    self.window.removeFirst(hop)
                    var energy: Float = 0
                    for sample in slice { energy += sample * sample }
                    let level = Double((energy / Float(windowSize)).squareRoot())
                    let reading = PitchDetector.detect(samples: slice, sampleRate: sampleRate)
                    DispatchQueue.main.async { onReading(reading, level) }
                }
            }
        }

        engine.prepare()
        do {
            try engine.start()
            isRunning = true
        } catch {
            NSLog("Consigliere: the microphone would not start for the tuner: \(error)")
            input.removeTap(onBus: 0)
            onProblem("the microphone would not start")
        }
    }

    func stop() {
        guard isRunning else { return }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        isRunning = false
    }
}
