import Foundation
import XCTest
@testable import ConsigliereCore

/// Smart jobs must reproduce fixtures/smart.json: who gets asked about, the exact words sent, and how replies
/// are checked so that only names that exist ever come through.
final class SmartTests: XCTestCase {

    private struct ReplyFixture: Decodable {
        let text: String
        let suggestions: [Smart.Suggestion]
    }

    private struct FileFixture: Decodable {
        let rules: String
        let groups: [String]
        let catalog: [CatalogEntry]
        let day: JobDay
        let askedIDs: [String]
        let noGroupsAskedIDs: [String]
        let candidates: [String]
        let prompt: Smart.Prompt
        let noGroupsPrompt: Smart.Prompt
        let replies: [ReplyFixture]
    }

    private func load() throws -> FileFixture {
        return try Fixtures.load(FileFixture.self, "smart.json")
    }

    func testTheWordsSentAgreeWithTheReference() throws {
        let file = try load()
        XCTAssertEqual(Smart.rules, file.rules)
        let all = file.day.jobs.map { $0.id }
        let asked = Smart.needingHelp(file.day, ids: all, groups: file.groups)
        XCTAssertEqual(asked.map { $0.id }, file.askedIDs)
        XCTAssertEqual(Smart.needingHelp(file.day, ids: all, groups: []).map { $0.id }, file.noGroupsAskedIDs)
        XCTAssertEqual(Smart.candidates(file.catalog), file.candidates)
        XCTAssertEqual(Smart.prompt(for: asked, catalog: file.catalog, groups: file.groups), file.prompt)
        XCTAssertEqual(Smart.prompt(for: asked, catalog: file.catalog, groups: []), file.noGroupsPrompt)
    }

    func testRepliesAgreeWithTheReference() throws {
        let file = try load()
        XCTAssertGreaterThanOrEqual(file.replies.count, 6)
        for reply in file.replies {
            XCTAssertEqual(Smart.readReply(reply.text, askedIDs: ["j2", "j3", "j4"], catalog: file.catalog, groups: file.groups),
                           reply.suggestions, reply.text)
        }
    }

    /// The schema sent must be the one the reference defines, so both describe the same reply.
    func testTheSchemaAgreesWithTheReference() throws {
        let fixture = try JSONSerialization.jsonObject(with: Data(contentsOf: Fixtures.directory.appendingPathComponent("smart.json"))) as? [String: Any]
        let reference = fixture?["schema"] as? NSDictionary
        let ours = try JSONSerialization.jsonObject(with: Data(Smart.schemaJSON.utf8)) as? NSDictionary
        XCTAssertNotNil(reference)
        XCTAssertEqual(ours, reference)
    }

    func testTheRequestBody() throws {
        let prompt = Smart.Prompt(system: Smart.rules, user: "Jobs:\nj1: email the landlord")
        let body = try JSONSerialization.jsonObject(with: Smart.requestBody(prompt: prompt, model: "claude-haiku-5-5", effort: "low")) as? [String: Any]
        XCTAssertEqual(body?["model"] as? String, "claude-haiku-5-5")
        XCTAssertEqual(body?["max_tokens"] as? Int, Smart.maxTokens)
        XCTAssertEqual(body?["system"] as? String, Smart.rules)
        let output = body?["output_config"] as? [String: Any]
        XCTAssertEqual(output?["effort"] as? String, "low")
        XCTAssertEqual((output?["format"] as? [String: Any])?["type"] as? String, "json_schema")
        XCTAssertNil(body?["temperature"], "newer models refuse sampling settings")

        let older = try JSONSerialization.jsonObject(with: Smart.requestBody(prompt: prompt, model: "claude-haiku-4-5", effort: "")) as? [String: Any]
        XCTAssertNil((older?["output_config"] as? [String: Any])?["effort"], "an empty effort is left out")
    }
}
