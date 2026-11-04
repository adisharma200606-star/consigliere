import Foundation
import XCTest
@testable import ConsigliereCore

/// Text replacement must reproduce fixtures/replace.json (written by reference-js/replace.test.js) exactly.
final class TextReplacementTests: XCTestCase {

    private struct Step: Decodable {
        let text: String?
        let key: String?
    }

    private struct ExpansionFixture: Decodable, Equatable {
        let step: Int
        let deleteCount: Int
        let insert: String
    }

    private struct CaseFixture: Decodable {
        let steps: [Step]
        let expansions: [ExpansionFixture]
        let remembered: String
    }

    private struct FileFixture: Decodable {
        let list: [TextReplacement]
        let usable: [String]
        let memory: Int
        let cases: [CaseFixture]
    }

    func testEveryGoldenCase() throws {
        let file = try Fixtures.load(FileFixture.self, "replace.json")
        XCTAssertEqual(TypingBuffer.usable(file.list).map { $0.shortcut }, file.usable)
        XCTAssertEqual(TypingBuffer.memory, file.memory)
        XCTAssertGreaterThanOrEqual(file.cases.count, 15)

        for (caseIndex, c) in file.cases.enumerated() {
            var buffer = TypingBuffer()
            var got: [ExpansionFixture] = []
            for (stepIndex, step) in c.steps.enumerated() {
                switch step.key {
                case "backspace": buffer.backspace()
                case "reset": buffer.reset()
                default:
                    for ch in step.text ?? "" {
                        if let e = buffer.type(ch, list: file.list) {
                            got.append(ExpansionFixture(step: stepIndex, deleteCount: e.deleteCount, insert: e.insert))
                        }
                    }
                }
            }
            XCTAssertEqual(got, c.expansions, "case \(caseIndex)")
            XCTAssertEqual(String(buffer.text), c.remembered, "case \(caseIndex)")
        }
    }

    func testReadingTheMacList() {
        let json = #"[{"shortcut":"omw","phrase":"On my way!"},{"shortcut":"brb","phrase":"be right back"},{"shortcut":null,"phrase":"x"}]"#
        XCTAssertEqual(MacTextReplacements.parseSQLiteJSON(Data(json.utf8)),
                       [TextReplacement(shortcut: "omw", phrase: "On my way!"), TextReplacement(shortcut: "brb", phrase: "be right back")])
        XCTAssertEqual(MacTextReplacements.parseSQLiteJSON(Data("not json".utf8)), [])

        let items: [[String: Any]] = [["on": 1, "replace": "omw", "with": "On my way!"], ["on": 0, "replace": "off", "with": "x"]]
        XCTAssertEqual(MacTextReplacements.parseDefaults(items), [TextReplacement(shortcut: "omw", phrase: "On my way!")])

        let merged = MacTextReplacements.merged([[TextReplacement(shortcut: "OMW", phrase: "mine")],
                                                 [TextReplacement(shortcut: "omw", phrase: "On my way!"),
                                                  TextReplacement(shortcut: "brb", phrase: "be right back")]])
        XCTAssertEqual(merged.map { $0.phrase }, ["mine", "be right back"], "the first source wins, ignoring case")
    }

    func testConfigDefaultsAndOldConfigs() throws {
        let old = try JSONDecoder().decode(Config.self, from: Data("{}".utf8))
        XCTAssertTrue(old.textReplacement.on)
        XCTAssertEqual(old.textReplacement.apps, ["com.brave.Browser"])
        XCTAssertEqual(old.textReplacement.extra, [])
    }
}
