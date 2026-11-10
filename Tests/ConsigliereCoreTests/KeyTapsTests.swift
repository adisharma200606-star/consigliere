import Foundation
import XCTest
@testable import ConsigliereCore

/// Key gestures must reproduce fixtures/taps.json (written by reference-js/taps.test.js) exactly.
final class KeyTapsTests: XCTestCase {

    private struct Step: Decodable {
        let `do`: String
        let key: String?
        let side: String?
        let t: Int
        let alone: Bool?
    }

    private struct EventFixture: Decodable, Equatable {
        let t: Int
        let event: String
    }

    private struct CaseFixture: Decodable {
        let name: String
        let steps: [Step]
        let events: [EventFixture]
    }

    private struct FileFixture: Decodable {
        let tapMax: Int
        let gapMax: Int
        let holdAfter: Int
        let cases: [CaseFixture]
    }

    func testEveryGoldenCase() throws {
        let file = try Fixtures.load(FileFixture.self, "taps.json")
        XCTAssertEqual(TapDetector.tapMax, file.tapMax)
        XCTAssertEqual(TapDetector.gapMax, file.gapMax)
        XCTAssertEqual(TapDetector.holdAfter, file.holdAfter)
        XCTAssertGreaterThanOrEqual(file.cases.count, 16)

        for c in file.cases {
            var detector = TapDetector()
            var got: [EventFixture] = []
            for step in c.steps {
                var event: TapEvent?
                let key = ModifierKey(rawValue: step.key ?? "") ?? .option
                switch step.do {
                case "down":
                    event = detector.down(key, side: KeySide(rawValue: step.side ?? "left") ?? .left, at: step.t, alone: step.alone ?? true)
                case "up":
                    event = detector.up(key, at: step.t)
                case "other":
                    detector.other()
                default:
                    event = detector.tick(at: step.t)
                }
                if let event = event { got.append(EventFixture(t: step.t, event: event.name)) }
            }
            XCTAssertEqual(got, c.events, c.name)
        }
    }

    func testGesturesAreOnByDefaultAndOldConfigsGetThem() throws {
        let old = try JSONDecoder().decode(Config.self, from: Data(#"{"hotkeys":{"open":"opt+space"}}"#.utf8))
        XCTAssertTrue(old.hotkeys.gestures)
        XCTAssertEqual(old.hotkeys.openBox, "opt+space")
    }
}
