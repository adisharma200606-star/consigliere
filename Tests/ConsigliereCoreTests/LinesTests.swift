import Foundation
import XCTest
@testable import ConsigliereCore

/// The line picker must reproduce fixtures/lines.json pick by pick.
final class LinesTests: XCTestCase {

    private struct PickedFixture: Decodable {
        let id: String
        let text: String
        let speak: Bool
    }

    private struct PickFixture: Decodable {
        let category: String
        let target: String?
        let frequency: Double
        let picked: PickedFixture?
        let rngUsed: Int
    }

    private struct FileFixture: Decodable {
        let bank: LineBank
        let rngValues: [Double]
        let picks: [PickFixture]
        let finalState: LineState
    }

    func testGoldenPicks() throws {
        let file = try Fixtures.load(FileFixture.self, "lines.json")
        let random = ScriptedRandom(file.rngValues)
        var state = LineState()

        for (index, expected) in file.picks.enumerated() {
            let pick = Lines.pick(bank: file.bank, state: &state, category: expected.category, target: expected.target,
                                  frequency: expected.frequency, rng: random.next)
            XCTAssertEqual(pick?.id, expected.picked?.id, "pick \(index) chose the wrong line")
            XCTAssertEqual(pick?.text, expected.picked?.text, "pick \(index) has the wrong text")
            XCTAssertEqual(pick?.speak, expected.picked?.speak, "pick \(index) got speak wrong")
            XCTAssertEqual(random.used, expected.rngUsed, "pick \(index) consumed the wrong amount of randomness")
        }
        XCTAssertEqual(state, file.finalState)
    }

    func testNeverRepeatsWithinTheLastFive() {
        let bank: LineBank = ["open_site": (1...8).map { Line(id: "os\($0)", text: "line \($0)") }]
        var state = LineState()
        var seen = [String]()
        for _ in 0..<40 {
            guard let pick = Lines.pick(bank: bank, state: &state, category: "open_site", target: nil, frequency: 1, rng: { 0 }) else {
                return XCTFail("expected a line")
            }
            XCTAssertFalse(seen.suffix(5).contains(pick.id), "repeated \(pick.id)")
            seen.append(pick.id)
        }
    }

    func testAPoolOfOneStillWorksAndUnknownCategoriesGiveNothing() {
        let bank: LineBank = ["saved": [Line(id: "sv1", text: "only one")]]
        var state = LineState()
        XCTAssertEqual(Lines.pick(bank: bank, state: &state, category: "saved", target: nil, frequency: 1, rng: { 0 })?.id, "sv1")
        XCTAssertEqual(Lines.pick(bank: bank, state: &state, category: "saved", target: nil, frequency: 1, rng: { 0 })?.id, "sv1")
        XCTAssertNil(Lines.pick(bank: bank, state: &state, category: "nope", target: nil, frequency: 1, rng: { 0 }))
    }

    func testFrequencyZeroNeverSpeaks() {
        var state = LineState()
        let pick = Lines.pick(bank: Lines.fallbackBank, state: &state, category: "saved", target: nil, frequency: 0, rng: { 0.2 })
        XCTAssertEqual(pick?.speak, false)
        XCTAssertEqual(pick?.text, "I'll hold onto this.")
    }
}
