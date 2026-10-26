import Foundation
import XCTest
@testable import ConsigliereCore

/// Jobs must reproduce fixtures/jobs.json: reading jobs, binding starters, the day's timeline of when he comes
/// out and how boldly, the ledger, and carrying unfinished jobs into the next day.
final class JobsTests: XCTestCase {

    private struct ParseFixture: Decodable {
        let text: String
        let bindings: [String: String]
        let drafts: [JobDraft]
    }

    private struct DayKeyFixture: Decodable {
        let wall: Int
        let key: String
    }

    /// One step of the timeline. `result` is a list of job ids for "add", a nudge (or nothing) for "nudge".
    private struct StepFixture: Decodable {
        let op: String
        let text: String?
        let at: Int?
        let id: String?
        let quiet: Bool?
        let idle: Int?
        let ids: [String]?
        let nudge: Nudge?

        private enum CodingKeys: String, CodingKey { case op, text, at, id, quiet, idle, result }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            op = try c.decode(String.self, forKey: .op)
            text = try c.decodeIfPresent(String.self, forKey: .text)
            at = try c.decodeIfPresent(Int.self, forKey: .at)
            id = try c.decodeIfPresent(String.self, forKey: .id)
            quiet = try c.decodeIfPresent(Bool.self, forKey: .quiet)
            idle = try c.decodeIfPresent(Int.self, forKey: .idle)
            ids = op == "add" ? try c.decodeIfPresent([String].self, forKey: .result) : nil
            nudge = op == "nudge" ? try c.decodeIfPresent(Nudge.self, forKey: .result) : nil
        }
    }

    private struct OpenFixture: Decodable {
        let wall: Int
        let quiet: Bool
        let idle: Int
        let opened: Bool
        let open: Bool
    }

    private struct FileFixture: Decodable {
        let now: Int
        let catalog: [CatalogEntry]
        let parses: [ParseFixture]
        let dayKeys: [DayKeyFixture]
        let steps: [StepFixture]
        let finalDay: JobDay
        let ledger: String
        let described: [String]
        let rolled: JobDay
        let rolledLedger: String
        let opens: [OpenFixture]
    }

    private func load() throws -> FileFixture {
        return try Fixtures.load(FileFixture.self, "jobs.json")
    }

    func testReadingJobsAgreesWithTheReference() throws {
        let file = try load()
        XCTAssertGreaterThanOrEqual(file.parses.count, 10)
        for p in file.parses {
            XCTAssertEqual(Jobs.parse(p.text, nowWall: file.now, catalog: file.catalog, bindings: p.bindings), p.drafts, "\"\(p.text)\"")
        }
    }

    func testDayKeys() throws {
        for d in try load().dayKeys {
            XCTAssertEqual(Jobs.dayKey(d.wall), d.key, "\(d.wall)")
        }
        XCTAssertEqual(Jobs.clockMinutes("09:00"), 540)
        XCTAssertEqual(Jobs.clockMinutes("0:30"), 30)
        XCTAssertNil(Jobs.clockMinutes("24:00"))
        XCTAssertNil(Jobs.clockMinutes("nine"))
    }

    func testTheTimelineAgreesWithTheReference() throws {
        let file = try load()
        var day = JobDay(day: "2026-10-11")
        let settings = JobSettings()
        var last: Nudge? = nil
        var shown: Nudge? = nil
        for (index, step) in file.steps.enumerated() {
            let label = "step \(index): \(step.op)"
            switch step.op {
            case "add":
                let drafts = Jobs.parse(step.text ?? "", nowWall: step.at ?? 0, catalog: file.catalog)
                XCTAssertEqual(day.add(drafts, now: step.at ?? 0), step.ids, label)
            case "nudge":
                last = Jobs.nextNudge(day, now: step.at ?? 0, settings: settings, quiet: step.quiet ?? false, idleSeconds: step.idle ?? 0)
                XCTAssertEqual(last, step.nudge, label)
            case "appeared":
                shown = last
                if let nudge = shown { day.appeared(nudge, now: step.at ?? 0) }
            case "ignored":
                if let nudge = shown { day.ignored(nudge) }
            case "start": day.start(step.id ?? "", now: step.at ?? 0)
            case "finish": day.finish(step.id ?? "", now: step.at ?? 0)
            case "skip": day.skip(step.id ?? "")
            case "later": day.later(step.id ?? "", now: step.at ?? 0, settings: settings)
            case "sleepLater": day.sleepLater(now: step.at ?? 0, minutes: 10)
            case "closeBooks": day.closeBooks()
            default: XCTFail("unknown step \(step.op)")
            }
        }
        XCTAssertEqual(day, file.finalDay)
        XCTAssertEqual(Jobs.ledger(day), file.ledger)
        XCTAssertEqual(day.jobs.map(Jobs.describe), file.described)

        let rolled = Jobs.rollover(day, to: "2026-10-12")
        XCTAssertEqual(rolled, file.rolled)
        XCTAssertEqual(Jobs.rollover(rolled, to: "2026-10-12"), rolled, "the same day is left alone")
        XCTAssertEqual(Jobs.ledger(Jobs.rollover(rolled, to: "2026-10-13")), file.rolledLedger)
    }

    func testTheListOpensByItselfOnceADay() throws {
        let file = try load()
        XCTAssertGreaterThanOrEqual(file.opens.count, 8)
        for o in file.opens {
            var day = JobDay(day: "2026-10-11")
            if o.opened { day.markListOpened() }
            XCTAssertEqual(Jobs.shouldOpenList(day, now: o.wall, quiet: o.quiet, idleSeconds: o.idle), o.open, "\(o.wall) quiet=\(o.quiet) idle=\(o.idle)")
        }
    }

    func testUntickingAndDeleting() throws {
        let file = try load()
        var day = JobDay(day: "2026-10-11")
        day.add(Jobs.parse("read 30 min, call dad, gym", nowWall: file.now, catalog: file.catalog), now: file.now)
        day.finish("j1", now: file.now)
        day.reopen("j1")
        XCTAssertEqual(day.jobs[0].status, .open)
        XCTAssertNil(day.jobs[0].doneAt)
        XCTAssertTrue(day.remove("j2"))
        XCTAssertFalse(day.remove("j2"))
        XCTAssertEqual(day.jobs.map { $0.id }, ["j1", "j3"])
        day.add(Jobs.parse("stretch", nowWall: file.now, catalog: file.catalog), now: file.now)
        XCTAssertEqual(day.jobs[2].id, "j4", "ids are never reused")
        XCTAssertEqual(Jobs.ledger(day), "Jobs, 2026-10-11\nStill owed: read (30 min), gym, stretch")
    }

    func testFindingAJobByName() throws {
        let file = try load()
        var day = JobDay(day: "2026-10-11")
        day.add(Jobs.parse("read 30 min, call dad", nowWall: file.now, catalog: file.catalog), now: file.now)
        day.add(Jobs.parse("Read 45 min", nowWall: file.now, catalog: file.catalog), now: file.now)
        XCTAssertEqual(day.jobs.count, 2)
        XCTAssertEqual(day.jobs[0].minutes, 45)
        XCTAssertEqual(day.find("read")?.id, "j1")
        XCTAssertEqual(day.find("dad")?.id, "j2")
        XCTAssertNil(day.find("gym"))
        XCTAssertNil(day.find(""))
    }

    func testAJobDayRoundTripsThroughItsFile() throws {
        let file = try load()
        let data = try JSONFile.encoder().encode(file.finalDay)
        XCTAssertEqual(try JSONDecoder().decode(JobDay.self, from: data), file.finalDay)
        // An almost empty file still loads.
        let bare = try JSONDecoder().decode(JobDay.self, from: Data(#"{"day":"2026-10-11","jobs":[{"id":"j1","title":"read"}]}"#.utf8))
        XCTAssertEqual(bare.jobs.first?.status, .open)
        XCTAssertEqual(bare.nextID, 2)
    }
}
