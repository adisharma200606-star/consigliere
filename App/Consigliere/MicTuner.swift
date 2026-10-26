import AVFoundation
import ConsigliereCore

/// Feeds the microphone to the pitch detector while the tuner is open.
/// About twelve readings a second: each one is 4096 samples, which is what the low strings need.
final class MicTuner {
    private let engine = AVAudioEngine()
    private let queue = DispatchQueue(label: "consigliere.tuner", qos: .userInteractive)
    private var window = [Float]()
    private let windowSize = 4096
    private var isBusy = false
    private(set) var isRunning = false

    /// `onReading` is called on the main thread. Nil means "no clear pitch right now".
    func start(onReading: @escaping (PitchReading?) -> Void) {
        guard !isRunning else { return }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        let sampleRate = format.sampleRate
        guard sampleRate > 0 else { return }

        window.removeAll(keepingCapacity: true)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            guard let self = self, let channel = buffer.floatChannelData?[0] else { return }
            let samples = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
            self.queue.async {
                self.window.append(contentsOf: samples)
                guard self.window.count >= self.windowSize, !self.isBusy else {
                    // Never let the backlog grow if detection falls behind.
                    if self.window.count > self.windowSize * 3 { self.window.removeFirst(self.window.count - self.windowSize) }
                    return
                }
                self.isBusy = true
                let slice = Array(self.window.suffix(self.windowSize))
                self.window.removeAll(keepingCapacity: true)
                let reading = PitchDetector.detect(samples: slice, sampleRate: sampleRate)
                self.isBusy = false
                DispatchQueue.main.async { onReading(reading) }
            }
        }

        engine.prepare()
        do {
            try engine.start()
            isRunning = true
        } catch {
            NSLog("Consigliere: the microphone would not start for the tuner: \(error)")
            input.removeTap(onBus: 0)
        }
    }

    func stop() {
        guard isRunning else { return }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        isRunning = false
    }
}
