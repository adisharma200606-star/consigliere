import Foundation
import XCTest
@testable import ConsigliereCore

/// The timer and the living bookmarks must reproduce fixtures/extras.json.
final class ExtrasTests: XCTestCase {

    private struct DurationFixture: Decodable {
        let text: String
        let seconds: Int?
    }

    private struct FormatFixture: Decodable {
        let ms: Int
        let text: String
    }

    private struct BookmarkFixture: Decodable {
        let url: String
        let result: String
        let names: [String]
    }

    private struct PhoneLineFixture: Decodable {
        let payload: String
        let at: Int
        let dated: Bool
    }

    private struct CountsFixture: Decodable {
        let added: Int
        let refreshed: Int
        let opened: Int
    }

    private struct PhoneFixture: Decodable {
        let inbox: String
        let opened: String
        let now: Int
        let initial: Stash
        let counts: CountsFixture
        let finalStash: Stash
        let forPhone: String
        let lines: [PhoneLineFixture]

        private enum CodingKeys: String, CodingKey {
            case inbox, opened, now, initial, counts, forPhone, lines
            case finalStash = "final"
        }
    }

    private struct StopFixture: Decodable {
        let text: String
        let stop: Bool
    }

    private struct AddedFixture: Decodable {
        let seconds: Int
        let start: Int
        let add: Int
        let now: Int
        let startedAt: Int
        let durationMs: Int
    }

    private struct FileFixture: Decodable {
        let stops: [StopFixture]
        let added: [AddedFixture]
        let phone: PhoneFixture
        let durations: [DurationFixture]
        let formats: [FormatFixture]
        let catalog: [CatalogEntry]
        let bookmarks: [BookmarkFixture]
    }

    func testDurationsAgreeWithTheReference() throws {
        let file = try Fixtures.load(FileFixture.self, "extras.json")
        XCTAssertGreaterThanOrEqual(file.durations.count, 35)
        for d in file.durations {
            XCTAssertEqual(DurationParser.parse(d.text), d.seconds, "\"\(d.text)\"")
        }
    }

    func testCountdown() throws {
        let file = try Fixtures.load(FileFixture.self, "extras.json")
        for f in file.formats {
            XCTAssertEqual(CountdownTimer.format(remainingMs: f.ms), f.text, "\(f.ms) ms")
        }
        let timer = CountdownTimer(seconds: 600, nowMs: 1_000)
        XCTAssertEqual(timer.status(nowMs: 1_000), TimerStatus(remainingMs: 600_000, fraction: 1, done: false, text: "10:00"))
        XCTAssertEqual(timer.status(nowMs: 301_000), TimerStatus(remainingMs: 300_000, fraction: 0.5, done: false, text: "5:00"))
        XCTAssertEqual(timer.status(nowMs: 601_000), TimerStatus(remainingMs: 0, fraction: 0, done: true, text: "0:00"))
        XCTAssertTrue(timer.status(nowMs: 999_999).done)
    }

    func testBookmarksAgreeWithTheReference() throws {
        let file = try Fixtures.load(FileFixture.self, "extras.json")
        for b in file.bookmarks {
            let names: [String]
            let result: String
            switch LivingBookmarks.find(for: b.url, in: file.catalog) {
            case .update(let entry):
                result = "update"
                names = [entry.name]
            case .ambiguous(let entries):
                result = "ambiguous"
                names = entries.map { $0.name }
            case .noMatch:
                result = "none"
                names = []
            }
            XCTAssertEqual(result, b.result, b.url)
            XCTAssertEqual(names, b.names, b.url)
        }
    }

    func testStoppingAndAddingTimeAgreeWithTheReference() throws {
        let file = try Fixtures.load(FileFixture.self, "extras.json")
        for s in file.stops {
            XCTAssertEqual(CountdownTimer.isStopWord(s.text), s.stop, "\"\(s.text)\"")
        }
        for a in file.added {
            let timer = CountdownTimer(seconds: a.seconds, nowMs: a.start).adding(seconds: a.add, nowMs: a.now)
            XCTAssertEqual(timer.startedAt, a.startedAt)
            XCTAssertEqual(timer.durationMs, a.durationMs)
        }
    }

    func testPhoneFilesAgreeWithTheReference() throws {
        let phone = try Fixtures.load(FileFixture.self, "extras.json").phone

        let lines = PhoneSync.parseLines(phone.inbox, nowMs: phone.now)
        XCTAssertEqual(lines.map { $0.payload }, phone.lines.map { $0.payload })
        XCTAssertEqual(lines.map { $0.at }, phone.lines.map { $0.at })
        XCTAssertEqual(lines.map { $0.dated }, phone.lines.map { $0.dated })

        var stash = phone.initial
        let counts = stash.ingestPhone(inbox: phone.inbox, opened: phone.opened, nowMs: phone.now)
        XCTAssertEqual(counts, PhoneSync.Counts(added: phone.counts.added, refreshed: phone.counts.refreshed, opened: phone.counts.opened))
        XCTAssertEqual(stash, phone.finalStash)
        XCTAssertEqual(PhoneSync.exportForPhone(stash), phone.forPhone)

        let again = stash.ingestPhone(inbox: phone.inbox, opened: phone.opened, nowMs: phone.now + 60_000)
        XCTAssertEqual(again, PhoneSync.Counts(), "running it twice changes nothing")
        XCTAssertEqual(stash, phone.finalStash)
    }

    func testPhoneDates() {
        XCTAssertEqual(PhoneSync.parseDate("2026-09-18T08:00:00Z"), 1_789_718_400_000)
        XCTAssertEqual(PhoneSync.parseDate("2026-09-19T21:40:00+05:30"), 1_789_834_200_000)
        XCTAssertEqual(PhoneSync.parseDate("2026-09-10"), 1_788_998_400_000)
        XCTAssertNil(PhoneSync.parseDate("2026"))
        XCTAssertNil(PhoneSync.parseDate("https://x.example"))
        XCTAssertEqual(PhoneSync.parseLines("2026 plans for the band", nowMs: 7), [PhoneSync.PhoneLine(payload: "2026 plans for the band", at: 7, dated: false)])
    }

    func testMovingAnEntryKeepsEverythingElse() throws {
        let file = try Fixtures.load(FileFixture.self, "extras.json")
        let moved = LivingBookmarks.move("bat", to: "https://reader.example/manga/absolute-batman/chapter-14", in: file.catalog)
        let bat = try XCTUnwrap(moved.first { $0.name == "bat" })
        XCTAssertEqual(bat.target, "https://reader.example/manga/absolute-batman/chapter-14")
        XCTAssertTrue(bat.living)
        XCTAssertEqual(moved.first { $0.name == "berserk" }, file.catalog.first { $0.name == "berserk" })
    }

    func testURLParts() {
        XCTAssertEqual(LivingBookmarks.parts(of: "https://www.Example.com:8080/a/b/?q=1#frag"),
                       LivingBookmarks.URLParts(host: "example.com:8080", segments: ["a", "b"]))
        XCTAssertEqual(LivingBookmarks.parts(of: "https://user:pw@example.com/x"),
                       LivingBookmarks.URLParts(host: "example.com", segments: ["x"]))
        XCTAssertEqual(LivingBookmarks.parts(of: "example.com"), LivingBookmarks.URLParts(host: "example.com", segments: []))
    }

    func testLivingFlagIsOnlyWrittenWhenOn() throws {
        let plain = CatalogEntry(name: "youtube", kind: .site, target: "https://www.youtube.com")
        let living = CatalogEntry(name: "bat", kind: .site, target: "https://reader.example/x", living: true)
        let plainJSON = String(decoding: try JSONFile.encoder().encode(plain), as: UTF8.self)
        let livingJSON = String(decoding: try JSONFile.encoder().encode(living), as: UTF8.self)
        XCTAssertFalse(plainJSON.contains("living"))
        XCTAssertTrue(livingJSON.contains("\"living\" : true"))
        XCTAssertEqual(try JSONDecoder().decode(CatalogEntry.self, from: Data(livingJSON.utf8)), living)
    }
}
