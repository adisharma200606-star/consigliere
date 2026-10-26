import Foundation
import XCTest
@testable import ConsigliereCore

/// The app was renamed from Brochacho. These check that a Mac with the old folders keeps every file.
final class RenameTests: XCTestCase {

    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    func testOldFoldersAreMovedAndALinkIsLeftForTheConfig() throws {
        let home = try temporaryDirectory()
        let cloud = home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
        try write("{\"jobs\":1}", to: home.appendingPathComponent(".brochacho/jobs.json"))
        try write("{\"stash\":1}", to: cloud.appendingPathComponent("Brochacho/stash.json"))

        let report = ConsiglierePaths.moveOldFolders(home: home)
        XCTAssertEqual(report.count, 2, "\(report)")

        let files = FileManager.default
        XCTAssertEqual(try String(contentsOf: home.appendingPathComponent(".consigliere/jobs.json")), "{\"jobs\":1}")
        XCTAssertEqual(try String(contentsOf: cloud.appendingPathComponent("Consigliere/stash.json")), "{\"stash\":1}")
        // The old config path still works, through the link.
        XCTAssertEqual(try String(contentsOf: home.appendingPathComponent(".brochacho/jobs.json")), "{\"jobs\":1}")
        XCTAssertEqual(try files.destinationOfSymbolicLink(atPath: home.appendingPathComponent(".brochacho").path),
                       home.appendingPathComponent(".consigliere").path)
        XCTAssertFalse(files.fileExists(atPath: cloud.appendingPathComponent("Brochacho").path))
    }

    func testRunningTwiceDoesNothingTheSecondTime() throws {
        let home = try temporaryDirectory()
        try write("x", to: home.appendingPathComponent(".brochacho/config.json"))
        XCTAssertEqual(ConsiglierePaths.moveOldFolders(home: home).count, 1)
        XCTAssertEqual(ConsiglierePaths.moveOldFolders(home: home), [])
        XCTAssertEqual(try String(contentsOf: home.appendingPathComponent(".consigliere/config.json")), "x")
    }

    func testANewFolderIsNeverOverwritten() throws {
        let home = try temporaryDirectory()
        try write("old", to: home.appendingPathComponent(".brochacho/config.json"))
        try write("new", to: home.appendingPathComponent(".consigliere/config.json"))
        XCTAssertEqual(ConsiglierePaths.moveOldFolders(home: home), [])
        XCTAssertEqual(try String(contentsOf: home.appendingPathComponent(".consigliere/config.json")), "new")
        XCTAssertEqual(try String(contentsOf: home.appendingPathComponent(".brochacho/config.json")), "old")
    }

    func testAFreshMacMovesNothing() throws {
        XCTAssertEqual(ConsiglierePaths.moveOldFolders(home: try temporaryDirectory()), [])
    }

    func testTheOldFolderIsUsedUntilItHasBeenMoved() throws {
        let home = try temporaryDirectory()
        let old = home.appendingPathComponent(".brochacho", isDirectory: true)
        let new = home.appendingPathComponent(".consigliere", isDirectory: true)
        XCTAssertEqual(ConsiglierePaths.preferred(new, over: old), new, "a fresh Mac uses the new name")
        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
        XCTAssertEqual(ConsiglierePaths.preferred(new, over: old), old, "an unmoved old folder is still used")
        try FileManager.default.createDirectory(at: new, withIntermediateDirectories: true)
        XCTAssertEqual(ConsiglierePaths.preferred(new, over: old), new)
    }
}
