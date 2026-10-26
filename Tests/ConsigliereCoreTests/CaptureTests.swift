import Foundation
import XCTest
@testable import ConsigliereCore

/// The reminder reader must reproduce fixtures/capture.json.
final class CaptureTests: XCTestCase {

    private struct CaseFixture: Decodable {
        let typed: String
        let now: Int
        let title: String
        let dueWall: Int?
        let said: String
    }

    private struct FileFixture: Decodable {
        let cases: [CaseFixture]
    }

    func testEveryGoldenCase() throws {
        let file = try Fixtures.load(FileFixture.self, "capture.json")
        XCTAssertGreaterThanOrEqual(file.cases.count, 35)
        for c in file.cases {
            let result = ReminderParser.parse(c.typed, nowWall: c.now)
            XCTAssertEqual(result.title, c.title, "title for \"\(c.typed)\"")
            XCTAssertEqual(result.dueWall, c.dueWall, "due for \"\(c.typed)\"")
            XCTAssertEqual(ReminderParser.describe(dueWall: result.dueWall, nowWall: c.now), c.said, "said for \"\(c.typed)\"")
        }
    }

    func testWallClockRoundTripsThroughARealTimeZone() throws {
        var india = Calendar(identifier: .gregorian)
        india.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Kolkata"))
        // 21 September 2026, 14:30 in Bengaluru is 09:00 UTC.
        let moment = Date(timeIntervalSince1970: 1_789_981_200)
        let wall = ReminderParser.wall(from: moment, calendar: india)
        XCTAssertEqual(ReminderParser.describe(dueWall: wall, nowWall: wall), "Today 14:30")
        XCTAssertEqual(ReminderParser.date(fromWall: wall, calendar: india), moment)

        let due = try XCTUnwrap(ReminderParser.parse("call mom tomorrow at 5", nowWall: wall).dueWall)
        let real = ReminderParser.date(fromWall: due, calendar: india)
        XCTAssertEqual(real.timeIntervalSince(moment), 26.5 * 3600, accuracy: 1, "tomorrow 17:00 is 26.5 hours after today 14:30")
    }
}
