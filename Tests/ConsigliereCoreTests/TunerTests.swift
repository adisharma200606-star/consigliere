import Foundation
import XCTest
@testable import ConsigliereCore

final class TunerTests: XCTestCase {

    // MARK: fixtures written by reference-js/tuner.test.js

    private struct NoteFixture: Decodable {
        let note: String
        let midi: Int
        let frequency: Double
    }

    private struct StringCaseFixture: Decodable {
        let frequency: Double
        let tuning: String
        let index: Int
        let note: String
        let cents: Double
    }

    private struct ReadingFixture: Decodable {
        let frequency: Double
        let clarity: Double
        let rms: Double
    }

    private struct DisplayFixture: Decodable {
        let state: String
        let label: String?
        let octave: Int?
        let stringIndex: Int?
        let cents: Double
        let inTune: Bool
        let frequency: Double?
        let allInTuneNow: Bool
    }

    private struct SessionStepFixture: Decodable {
        let reading: ReadingFixture?
        let at: Int
        let display: DisplayFixture
    }

    private struct FileFixture: Decodable {
        let tunings: [Tuning]
        let notes: [NoteFixture]
        let stringCases: [StringCaseFixture]
        let session: [SessionStepFixture]
    }

    /// A plucked-string-like test tone. Same generator as `synthString` in reference-js/tuner.js.
    private func synthString(_ frequency: Double, sampleRate: Double, length: Int, weakFundamental: Bool = false, noise: Double = 0) -> [Double] {
        let amps: [Double] = weakFundamental ? [0.08, 1.0, 0.7, 0.45, 0.3, 0.2] : [1.0, 0.6, 0.4, 0.25, 0.15, 0.1]
        var seed = 12345
        var out = [Double](repeating: 0, count: length)
        var peak = 0.0
        for i in 0..<length {
            let t = Double(i) / sampleRate
            var v = 0.0
            for (h, amp) in amps.enumerated() {
                let f = frequency * Double(h + 1)
                if f < sampleRate / 2 {
                    v += amp * sin(2 * Double.pi * f * t + Double(h) * 0.7) * exp(-t * (1.5 + Double(h)))
                }
            }
            if noise > 0 {
                seed = (seed * 48271) % 2147483647
                v += noise * (Double(seed) / 2147483647.0 * 2 - 1)
            }
            out[i] = v
            peak = Swift.max(peak, abs(v))
        }
        let scale = peak == 0 ? 1 : peak
        return out.map { $0 / scale * 0.5 }
    }

    func testDefaultTuningsMatchTheSharedJSON() throws {
        let file = try Fixtures.load(FileFixture.self, "tuner.json")
        XCTAssertEqual(DefaultTunings.all, file.tunings, "run scripts/gen_default_tunings.py")
        for tuning in DefaultTunings.all {
            let resolved = ResolvedTuning(tuning)
            XCTAssertNotNil(resolved, "\(tuning.id) has a note that cannot be read")
            XCTAssertEqual(resolved?.strings.count, tuning.instrument == "ukulele" ? 4 : 6, tuning.id)
        }
    }

    func testNotes() throws {
        XCTAssertEqual(Notes.parse("A4"), 69)
        XCTAssertEqual(Notes.parse("E2"), 40)
        XCTAssertEqual(Notes.parse("Eb2"), 39)
        XCTAssertEqual(Notes.parse("F#3"), 54)
        XCTAssertEqual(Notes.parse("a1"), 33)
        XCTAssertNil(Notes.parse("H2"))
        XCTAssertNil(Notes.parse(""))
        XCTAssertNil(Notes.parse("E"))
        XCTAssertEqual(Notes.frequency(midi: 69), 440, accuracy: 1e-9)
        XCTAssertEqual(Notes.frequency(midi: 33), 55, accuracy: 1e-9)
        XCTAssertEqual(Notes.frequency(midi: 69, a4: 432), 432, accuracy: 1e-9)

        let sharp = Notes.describe(446)
        XCTAssertEqual(sharp.name, "A")
        XCTAssertEqual(sharp.octave, 4)
        XCTAssertEqual(sharp.cents, 23.45, accuracy: 0.05)

        let file = try Fixtures.load(FileFixture.self, "tuner.json")
        for note in file.notes {
            XCTAssertEqual(Notes.parse(note.note), note.midi, note.note)
            XCTAssertEqual(Notes.frequency(midi: note.midi), note.frequency, accuracy: 1e-9, note.note)
        }
    }

    func testStringMatchingAgreesWithTheReference() throws {
        let file = try Fixtures.load(FileFixture.self, "tuner.json")
        for c in file.stringCases {
            guard let tuning = file.tunings.first(where: { $0.id == c.tuning }), let resolved = ResolvedTuning(tuning) else {
                return XCTFail("missing tuning \(c.tuning)")
            }
            let m = resolved.match(c.frequency)
            XCTAssertEqual(m.index, c.index, "\(c.frequency) Hz in \(c.tuning)")
            XCTAssertEqual(m.note, c.note, "\(c.frequency) Hz in \(c.tuning)")
            XCTAssertEqual(m.cents, c.cents, accuracy: 1e-6, "\(c.frequency) Hz in \(c.tuning)")
        }
    }

    func testASlackStringNeverReadsAsInTune() throws {
        let standard = try XCTUnwrap(ResolvedTuning(try XCTUnwrap(DefaultTunings.all.first { $0.id == "guitar-standard" })))
        let m = standard.match(55.0)
        XCTAssertEqual(m.note, "E2")
        XCTAssertEqual(m.cents, -700, accuracy: 1)
    }

    func testSessionAgreesWithTheReference() throws {
        let file = try Fixtures.load(FileFixture.self, "tuner.json")
        let tuning = try XCTUnwrap(file.tunings.first { $0.id == "guitar-standard" })
        let standard = try XCTUnwrap(ResolvedTuning(tuning))
        var session = TunerSession()

        for (index, step) in file.session.enumerated() {
            let reading = step.reading.map { PitchReading(frequency: $0.frequency, clarity: $0.clarity, rms: $0.rms) }
            let shown = session.feed(reading, nowMs: step.at, tuning: standard)
            let expected = step.display
            XCTAssertEqual(shown.state.rawValue, expected.state, "step \(index) state")
            XCTAssertEqual(shown.label, expected.label, "step \(index) label")
            XCTAssertEqual(shown.stringIndex, expected.stringIndex, "step \(index) string")
            XCTAssertEqual(shown.cents, expected.cents, accuracy: 1e-6, "step \(index) cents")
            XCTAssertEqual(shown.inTune, expected.inTune, "step \(index) inTune")
            XCTAssertEqual(shown.allInTuneNow, expected.allInTuneNow, "step \(index) allInTuneNow")
        }
    }

    func testEveryStringLockingIsAnnouncedExactlyOnce() throws {
        let tuning = try XCTUnwrap(DefaultTunings.all.first { $0.id == "ukulele-standard" })
        let ukulele = try XCTUnwrap(ResolvedTuning(tuning))
        var session = TunerSession()
        var now = 0
        var fired = 0

        func hold(_ stringIndex: Int) {
            for _ in 0..<6 {
                now += 100
                let reading = PitchReading(frequency: ukulele.strings[stringIndex].frequency, clarity: 0.97, rms: 0.2)
                if session.feed(reading, nowMs: now, tuning: ukulele).allInTuneNow { fired += 1 }
            }
        }

        hold(0); hold(1); hold(2)
        XCTAssertEqual(fired, 0)
        hold(3)
        XCTAssertEqual(fired, 1)
        hold(0); hold(3)
        XCTAssertEqual(fired, 1)
    }

    func testChromaticMode() {
        var session = TunerSession()
        let shown = session.feed(PitchReading(frequency: 446, clarity: 0.95, rms: 0.2), nowMs: 0, tuning: nil)
        XCTAssertEqual(shown.label, "A")
        XCTAssertEqual(shown.octave, 4)
        XCTAssertNil(shown.stringIndex)
        XCTAssertEqual(shown.cents, 23.45, accuracy: 0.05)
    }

    // MARK: detection on synthetic plucks

    private var distinctNotes: [Int] {
        let all = DefaultTunings.all.flatMap { $0.strings }.compactMap { Notes.parse($0) }
        return Array(Set(all)).sorted()
    }

    func testCleanPlucksLandWithinOneAndAHalfCents() {
        for midi in distinctNotes {
            for offset in [-20.0, 0.0, 20.0] {
                let truth = Notes.frequency(midi: midi) * pow(2.0, offset / 1200.0)
                let samples = synthString(truth, sampleRate: 44_100, length: 4096)
                guard let reading = PitchDetector.detect(samples: samples, sampleRate: 44_100) else {
                    XCTFail("midi \(midi) offset \(offset) not detected")
                    continue
                }
                XCTAssertLessThanOrEqual(abs(Notes.cents(from: reading.frequency, to: truth)), 1.5, "midi \(midi) offset \(offset) read \(reading.frequency)")
                XCTAssertGreaterThanOrEqual(reading.clarity, 0.85, "midi \(midi)")
            }
        }
    }

    func testLaptopMicPlucksAt48kLandWithinThreeCents() {
        for midi in distinctNotes {
            let truth = Notes.frequency(midi: midi) * pow(2.0, 7.0 / 1200.0)
            let samples = synthString(truth, sampleRate: 48_000, length: 4096, weakFundamental: true, noise: 0.02)
            guard let reading = PitchDetector.detect(samples: samples, sampleRate: 48_000) else {
                XCTFail("midi \(midi) not detected")
                continue
            }
            XCTAssertLessThanOrEqual(abs(Notes.cents(from: reading.frequency, to: truth)), 3, "midi \(midi) read \(reading.frequency) wanted \(truth)")
        }
    }

    func testSilenceAndShortBuffersGiveNothing() {
        XCTAssertNil(PitchDetector.detect(samples: [Double](repeating: 0, count: 4096), sampleRate: 44_100))
        XCTAssertNil(PitchDetector.detect(samples: [0.1, 0.2], sampleRate: 44_100))
        let floats = synthString(110, sampleRate: 44_100, length: 4096).map { Float($0) }
        let reading = PitchDetector.detect(samples: floats, sampleRate: 44_100)
        XCTAssertEqual(reading?.frequency ?? 0, 110, accuracy: 0.2, "Float buffers from the microphone work too")
    }
}
