import Foundation
import XCTest
@testable import ConsigliereCore

/// The migration must reproduce fixtures/migrate.json exactly.
final class CatalogMigrationTests: XCTestCase {

    private struct CaseFixture: Decodable {
        let existing: [CatalogEntry]
        let defaults: [CatalogEntry]
        let offered: [String]
        let result: ResultFixture
    }

    private struct ResultFixture: Decodable {
        let catalog: [CatalogEntry]
        let offered: [String]
    }

    private struct FileFixture: Decodable {
        let cases: [CaseFixture]
    }

    func testEveryGoldenCase() throws {
        let file = try Fixtures.load(FileFixture.self, "migrate.json")
        XCTAssertGreaterThanOrEqual(file.cases.count, 5)
        for (index, c) in file.cases.enumerated() {
            let result = CatalogMigration.merge(existing: c.existing, defaults: c.defaults, alreadyOffered: Set(c.offered))
            XCTAssertEqual(result.catalog, c.result.catalog, "case \(index)")
            XCTAssertEqual(result.offered, c.result.offered, "case \(index)")
        }
    }

    func testDeletingABuiltinOnPurposeIsRespectedForever() {
        let youtube = CatalogEntry(name: "youtube", kind: .site, target: "https://www.youtube.com")
        let help = CatalogEntry(name: "help", kind: .tool, target: "help")
        let first = CatalogMigration.merge(existing: [youtube], defaults: [youtube, help], alreadyOffered: [])
        XCTAssertEqual(first.catalog.map { $0.name }, ["youtube", "help"])

        let withoutHelp = first.catalog.filter { $0.name != "help" }
        let second = CatalogMigration.merge(existing: withoutHelp, defaults: [youtube, help], alreadyOffered: Set(first.offered))
        XCTAssertEqual(second.catalog.map { $0.name }, ["youtube"], "help was deleted on purpose and stays gone")
        XCTAssertTrue(second.offered.contains("help"), "still remembered, so it never sneaks back")
    }

    func testCustomEntriesAreUntouched() {
        let bat = CatalogEntry(name: "bat", aliases: ["batman"], kind: .site, target: "https://reader.example/x", living: true)
        let youtube = CatalogEntry(name: "youtube", kind: .site, target: "https://www.youtube.com")
        let result = CatalogMigration.merge(existing: [youtube, bat], defaults: [youtube], alreadyOffered: [])
        XCTAssertEqual(result.catalog, [youtube, bat])
        XCTAssertFalse(result.offered.contains("bat"))
    }

    func testStoreRoundTrips() throws {
        let url = try temporaryDirectory().appendingPathComponent("catalog-migrations.json")
        XCTAssertEqual(CatalogMigrationStore.load(from: url), CatalogMigrationState())
        let state = CatalogMigrationState(offered: ["youtube", "flip"])
        CatalogMigrationStore.save(state, to: url)
        XCTAssertEqual(CatalogMigrationStore.load(from: url), state)
    }
}
