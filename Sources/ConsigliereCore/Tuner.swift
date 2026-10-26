import Foundation

// The tuner's brain. Pure maths, no microphone. Ported from `reference-js/tuner.js`.
//   Notes          note names <-> MIDI numbers <-> frequencies
//   PitchDetector  YIN pitch detection on a buffer of samples
//   TunerSession   turns a jumpy stream of readings into a steady display

// MARK: - Notes

/// The nearest note to a frequency, and how many cents sharp (+) or flat (-) the frequency is.
public struct NoteReading: Equatable {
    public let midi: Int
    public let name: String
    public let octave: Int
    public let cents: Double
}

public enum Notes {
    public static let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    private static let ln2 = 0.6931471805599453

    /// "E2", "F#3", "Bb3" to a MIDI note number. Nil when it cannot be read.
    public static func parse(_ raw: String) -> Int? {
        let text = Array(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        guard let letter = text.first else { return nil }
        let base: Int
        switch String(letter).uppercased() {
        case "C": base = 0
        case "D": base = 2
        case "E": base = 4
        case "F": base = 5
        case "G": base = 7
        case "A": base = 9
        case "B": base = 11
        default: return nil
        }
        var index = 1
        var accidental = 0
        if index < text.count {
            if text[index] == "#" {
                accidental = 1
                index += 1
            } else if text[index] == "b" {
                accidental = -1
                index += 1
            }
        }
        guard index < text.count, let octave = Int(String(text[index...])) else { return nil }
        return (octave + 1) * 12 + base + accidental
    }

    public static func frequency(midi: Int, a4: Double = 440) -> Double {
        return a4 * pow(2.0, Double(midi - 69) / 12.0)
    }

    /// The (fractional) MIDI number of a frequency.
    public static func midi(frequency: Double, a4: Double = 440) -> Double {
        return 69.0 + 12.0 * (log(frequency / a4) / ln2)
    }

    /// How many cents `frequency` is above (+) or below (-) `target`.
    public static func cents(from frequency: Double, to target: Double) -> Double {
        return 1200.0 * (log(frequency / target) / ln2)
    }

    public static func describe(_ frequency: Double, a4: Double = 440) -> NoteReading {
        let exact = midi(frequency: frequency, a4: a4)
        let nearest = Int((exact + 0.5).rounded(.down))
        let pitchClass = ((nearest % 12) + 12) % 12
        let octave = Int((Double(nearest) / 12.0).rounded(.down)) - 1
        return NoteReading(midi: nearest, name: names[pitchClass], octave: octave, cents: (exact - Double(nearest)) * 100.0)
    }
}

// MARK: - Tunings

/// A tuning as written in config: note names from the lowest-numbered string position upwards.
public struct Tuning: Codable, Equatable {
    public var id: String
    /// "guitar", "ukulele", or anything he likes for a custom tuning.
    public var instrument: String
    public var name: String
    public var strings: [String]

    public init(id: String, instrument: String, name: String, strings: [String]) {
        self.id = id
        self.instrument = instrument
        self.name = name
        self.strings = strings
    }
}

public struct ResolvedString: Equatable {
    public let note: String
    public let midi: Int
    public let frequency: Double
}

public struct ResolvedTuning: Equatable {
    public let id: String
    public let instrument: String
    public let name: String
    public let strings: [ResolvedString]

    /// Expands note names into target frequencies. Nil when a note name cannot be read.
    public init?(_ tuning: Tuning, a4: Double = 440) {
        var resolved = [ResolvedString]()
        for note in tuning.strings {
            guard let midi = Notes.parse(note) else { return nil }
            resolved.append(ResolvedString(note: note, midi: midi, frequency: Notes.frequency(midi: midi, a4: a4)))
        }
        if resolved.isEmpty { return nil }
        self.id = tuning.id
        self.instrument = tuning.instrument
        self.name = tuning.name
        self.strings = resolved
    }

    /// The nearest string to a frequency and how far off it is. Deliberately simple: no octave folding,
    /// so a slack new string passing through 55 Hz never reads as "A2, in tune".
    public func match(_ frequency: Double) -> StringMatch {
        var bestIndex = 0
        var bestCents = Double.infinity
        for (index, string) in strings.enumerated() {
            let c = Notes.cents(from: frequency, to: string.frequency)
            if abs(c) < abs(bestCents) {
                bestCents = c
                bestIndex = index
            }
        }
        let string = strings[bestIndex]
        return StringMatch(index: bestIndex, note: string.note, targetFrequency: string.frequency, cents: bestCents)
    }
}

public struct StringMatch: Equatable {
    public let index: Int
    public let note: String
    public let targetFrequency: Double
    public let cents: Double
}

// MARK: - Pitch detection

public struct PitchReading: Equatable {
    public let frequency: Double
    /// 0...1. How confident the detector is that this is a real pitch.
    public let clarity: Double
    /// Loudness of the buffer, for a noise gate.
    public let rms: Double

    public init(frequency: Double, clarity: Double, rms: Double) {
        self.frequency = frequency
        self.clarity = clarity
        self.rms = rms
    }
}

/// YIN pitch detection (de Cheveigne and Kawahara, 2002).
/// 4096 samples at 44.1 or 48 kHz reaches down to about 45 Hz, which covers Drop A (55 Hz).
public enum PitchDetector {
    public struct Options: Equatable {
        public var minFrequency: Double = 45
        public var maxFrequency: Double = 1200
        public var threshold: Double = 0.12
        public var giveUpAbove: Double = 0.35
        public init() {}
    }

    /// Microphone buffers arrive as Float.
    public static func detect(samples: [Float], sampleRate: Double, options: Options = Options()) -> PitchReading? {
        return detect(samples: samples.map { Double($0) }, sampleRate: sampleRate, options: options)
    }

    public static func detect(samples: [Double], sampleRate: Double, options: Options = Options()) -> PitchReading? {
        let n = samples.count
        if n < 64 { return nil }

        let tauMax = Swift.min(Int(sampleRate / options.minFrequency), n / 2)
        let tauMin = Swift.max(2, Int(sampleRate / options.maxFrequency))
        if tauMax <= tauMin + 2 { return nil }
        let windowLength = n - tauMax

        // Remove any constant offset, and measure loudness.
        var mean = 0.0
        for value in samples { mean += value }
        mean /= Double(n)
        var x = [Double](repeating: 0, count: n)
        var energy = 0.0
        for i in 0..<n {
            x[i] = samples[i] - mean
            energy += x[i] * x[i]
        }
        let rms = (energy / Double(n)).squareRoot()
        if rms == 0 { return nil }

        // Steps 1 and 2: the difference function.
        var diff = [Double](repeating: 0, count: tauMax + 1)
        x.withUnsafeBufferPointer { buffer in
            for tau in 1...tauMax {
                var sum = 0.0
                for j in 0..<windowLength {
                    let delta = buffer[j] - buffer[j + tau]
                    sum += delta * delta
                }
                diff[tau] = sum
            }
        }

        // Step 3: cumulative mean normalised difference.
        var cmnd = [Double](repeating: 1, count: tauMax + 1)
        var running = 0.0
        for tau in 1...tauMax {
            running += diff[tau]
            cmnd[tau] = running == 0 ? 1 : diff[tau] * Double(tau) / running
        }

        // Step 4: the first dip under the threshold, followed down to its lowest point.
        var found = -1
        var tau = tauMin
        while tau <= tauMax {
            if cmnd[tau] < options.threshold {
                while tau + 1 <= tauMax && cmnd[tau + 1] < cmnd[tau] { tau += 1 }
                found = tau
                break
            }
            tau += 1
        }
        if found < 0 {
            // Nothing clearly periodic. Take the best dip if it is at least plausible.
            var best = tauMin
            var t = tauMin + 1
            while t <= tauMax {
                if cmnd[t] < cmnd[best] { best = t }
                t += 1
            }
            if cmnd[best] > options.giveUpAbove { return nil }
            found = best
        }

        // Step 5: parabolic interpolation on the raw difference function for a sub-sample period.
        var period = Double(found)
        if found > 1 && found < tauMax {
            let s0 = diff[found - 1]
            let s1 = diff[found]
            let s2 = diff[found + 1]
            let denominator = s0 + s2 - 2 * s1
            if denominator != 0 {
                let shift = (s0 - s2) / (2 * denominator)
                if shift > -1 && shift < 1 { period = Double(found) + shift }
            }
        }

        let clarity = Swift.max(0.0, Swift.min(1.0, 1.0 - cmnd[found]))
        return PitchReading(frequency: sampleRate / period, clarity: clarity, rms: rms)
    }
}

// MARK: - Session

public enum TunerState: String, Equatable {
    /// Nothing heard for a while. Show "pluck a string".
    case idle
    /// A fresh reading. `cents` is the smoothed value.
    case listening
    /// The note has just stopped ringing. The last display is kept briefly.
    case holding
}

/// What the notch should show right now.
public struct TunerDisplay: Equatable {
    public var state: TunerState
    /// The target string ("E2") in tuning mode, or the note name ("A") in chromatic mode.
    public var label: String?
    /// Chromatic mode only.
    public var octave: Int?
    /// Tuning mode only.
    public var stringIndex: Int?
    public var cents: Double
    /// True once the reading has stayed inside the tolerance for `lockAfterMs`.
    public var inTune: Bool
    public var frequency: Double?
    /// True exactly once per session: the moment every string of the tuning has locked at least once.
    public var allInTuneNow: Bool

    public static let idle = TunerDisplay(state: .idle, label: nil, octave: nil, stringIndex: nil, cents: 0,
                                          inTune: false, frequency: nil, allInTuneNow: false)
}

public struct TunerSession {
    public struct Options: Equatable {
        public var minClarity: Double = 0.85
        public var minRms: Double = 0.01
        public var toleranceCents: Double = 5
        public var lockAfterMs: Int = 350
        public var holdMs: Int = 1200
        public var windowMs: Int = 600
        public var keep: Int = 7
        /// A different string only takes over once this many readings in a row agree on it.
        public var switchAfter: Int = 2
        public init() {}
    }

    private struct Sample {
        let cents: Double
        let at: Int
    }

    public var options: Options
    private var key: String? = nil
    private var pendingKey: String? = nil
    private var pendingCount = 0
    private var readings = [Sample]()
    private var inTuneSince: Int? = nil
    private var lastValidAt: Int? = nil
    private var last: TunerDisplay? = nil
    private var lockedStrings = [Int]()
    private var celebrated = false

    public init(options: Options = Options()) {
        self.options = options
    }

    /// The strings that have been in tune at least once this session, for the screen to mark.
    public var lockedStringIndexes: [Int] {
        return lockedStrings
    }

    static func median(_ values: [Double]) -> Double {
        if values.isEmpty { return 0 }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count % 2 == 1 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2
    }

    /// Feed one detector reading (nil for "no pitch") and get back what to show.
    /// `tuning` nil means chromatic mode: the nearest note of any kind.
    public mutating func feed(_ reading: PitchReading?, nowMs: Int, tuning: ResolvedTuning?, a4: Double = 440) -> TunerDisplay {
        var valid = false
        if let r = reading {
            valid = r.clarity >= options.minClarity && r.rms >= options.minRms && r.frequency > 0
        }

        guard valid, let r = reading else {
            if var held = last, let lastValidAt = lastValidAt, nowMs - lastValidAt <= options.holdMs {
                held.state = .holding
                held.allInTuneNow = false
                return held
            }
            key = nil
            pendingKey = nil
            pendingCount = 0
            readings = []
            inTuneSince = nil
            last = nil
            return TunerDisplay.idle
        }

        let newKey: String
        let label: String
        var octave: Int? = nil
        var stringIndex: Int? = nil
        let cents: Double
        if let tuning = tuning {
            let m = tuning.match(r.frequency)
            newKey = "s\(m.index)"
            label = m.note
            stringIndex = m.index
            cents = m.cents
        } else {
            let d = Notes.describe(r.frequency, a4: a4)
            newKey = "m\(d.midi)"
            label = d.name
            octave = d.octave
            cents = d.cents
        }

        // One stray reading (an octave slip, a knock on the desk) changes nothing.
        if let current = key, newKey != current {
            if newKey == pendingKey {
                pendingCount += 1
            } else {
                pendingKey = newKey
                pendingCount = 1
            }
            if pendingCount < options.switchAfter {
                lastValidAt = nowMs
                var kept = last ?? TunerDisplay.idle
                kept.allInTuneNow = false
                return kept
            }
        }
        if newKey != key {
            key = newKey
            readings = []
            inTuneSince = nil
        }
        pendingKey = nil
        pendingCount = 0

        readings.append(Sample(cents: cents, at: nowMs))
        readings = readings.filter { nowMs - $0.at <= options.windowMs }
        if readings.count > options.keep {
            readings = Array(readings.suffix(options.keep))
        }

        let smoothed = TunerSession.median(readings.map { $0.cents })
        if abs(smoothed) <= options.toleranceCents {
            if inTuneSince == nil { inTuneSince = nowMs }
        } else {
            inTuneSince = nil
        }
        var locked = false
        if let since = inTuneSince {
            locked = nowMs - since >= options.lockAfterMs
        }

        var allInTuneNow = false
        if locked, let tuning = tuning, let index = stringIndex, !lockedStrings.contains(index) {
            lockedStrings.append(index)
            if !celebrated && lockedStrings.count == tuning.strings.count {
                celebrated = true
                allInTuneNow = true
            }
        }

        lastValidAt = nowMs
        let display = TunerDisplay(state: .listening, label: label, octave: octave, stringIndex: stringIndex,
                                   cents: smoothed, inTune: locked, frequency: r.frequency, allInTuneNow: false)
        last = display
        var shown = display
        shown.allInTuneNow = allInTuneNow
        return shown
    }
}
