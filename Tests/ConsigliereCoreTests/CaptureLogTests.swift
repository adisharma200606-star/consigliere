import Foundation
import XCTest
@testable import ConsigliereCore

final class CaptureLogTests: XCTestCase {

    func testRecentIsNewestFirstAndPerKind() {
        var log = CaptureLog()
        log.add(kind: "note", text: "one", now: 1)
        log.add(kind: "reminder", text: "call mom", dueMs: 99, now: 2)
        log.add(kind: "note", text: "two", now: 3)
        log.add(kind: "note", text: "three", now: 4)
        XCTAssertEqual(log.recent("note", limit: 2).map { $0.text }, ["three", "two"])
        XCTAssertEqual(log.recent("reminder", limit: 5).map { $0.text }, ["call mom"])
        XCTAssertEqual(log.recent("reminder", limit: 5).first?.dueMs, 99)
    }

    func testTheOldestFallOff() {
        var log = CaptureLog()
        for i in 0..<(CaptureLog.limit + 7) {
            log.add(kind: "note", text: "n\(i)", now: i)
        }
        XCTAssertEqual(log.entries.count, CaptureLog.limit)
        XCTAssertEqual(log.entries.first?.text, "n7")
    }

    func testExternalIDIsFilledInLater() throws {
        var log = CaptureLog()
        let id = log.add(kind: "note", text: "strings", now: 10)
        log.setExternalID("x-coredata://abc/ICNote/p1", for: id)
        XCTAssertEqual(log.entries.first?.externalID, "x-coredata://abc/ICNote/p1")
        let data = try JSONEncoder().encode(log)
        XCTAssertEqual(try JSONDecoder().decode(CaptureLog.self, from: data), log)
    }

    func testInstalledAppsSkipWhatTheCatalogAlreadyOpens() {
        let catalog = [
            CatalogEntry(name: "steam", kind: .app, target: "com.valvesoftware.steam"),
            CatalogEntry(name: "whatsapp", aliases: ["wa"], kind: .app, target: "net.whatsapp.WhatsApp")
        ]
        let found = [
            InstalledApps.Found(name: "Steam", bundleID: "com.valvesoftware.steam", path: "/Applications/Steam.app"),
            InstalledApps.Found(name: "WhatsApp", bundleID: "desktop.WhatsApp", path: "/Applications/WhatsApp.app"),
            InstalledApps.Found(name: "Prime Video", bundleID: "com.amazon.aiv.AIVApp", path: "/Applications/Prime Video.app"),
            InstalledApps.Found(name: "Prime Video", bundleID: "com.amazon.aiv.AIVApp", path: "/Users/adi/Applications/Prime Video.app"),
            InstalledApps.Found(name: "Old Thing", bundleID: nil, path: "/Applications/Old Thing.app")
        ]
        let entries = InstalledApps.entries(from: found, excluding: catalog)
        XCTAssertEqual(entries.map { $0.name }, ["prime video", "old thing"])
        XCTAssertEqual(entries.first?.display, "Prime Video")
        XCTAssertEqual(entries.first?.target, "com.amazon.aiv.AIVApp")
        XCTAssertEqual(entries.last?.target, "/Applications/Old Thing.app", "no bundle id: open it by path")
        XCTAssertEqual(Matcher.match("prime", catalog: catalog + entries).results.first?.entry.name, "prime video")
    }

    func testTimerStopWords() {
        XCTAssertTrue(CountdownTimer.isStopWord("stop"))
        XCTAssertTrue(CountdownTimer.isStopWord("cancel the timer"))
        XCTAssertFalse(CountdownTimer.isStopWord("stop 10"))
        XCTAssertFalse(CountdownTimer.isStopWord("10"))
    }
}
