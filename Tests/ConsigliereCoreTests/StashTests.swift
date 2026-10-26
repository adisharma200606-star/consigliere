import Foundation
import XCTest
@testable import ConsigliereCore

/// The stash must reproduce fixtures/stash.json step by step.
final class StashTests: XCTestCase {

    private struct StepFixture: Decodable {
        let op: String
        let now: Int
        let served: String?
        let rngUsed: Int
    }

    private struct FileFixture: Decodable {
        let initial: Stash
        let rngValues: [Double]
        let steps: [StepFixture]
        let finalStash: Stash

        private enum CodingKeys: String, CodingKey {
            case initial, rngValues, steps
            case finalStash = "final"
        }
    }

    func testGoldenSession() throws {
        let file = try Fixtures.load(FileFixture.self, "stash.json")
        var stash = file.initial
        let random = ScriptedRandom(file.rngValues)

        for (index, step) in file.steps.enumerated() {
            let item: StashItem?
            if step.op == "another" {
                item = stash.another(now: step.now, rng: random.next)
            } else {
                item = stash.serve(now: step.now, rng: random.next)
            }
            XCTAssertEqual(item?.id, step.served, "step \(index) (\(step.op)) served the wrong item")
            XCTAssertEqual(random.used, step.rngUsed, "step \(index) (\(step.op)) consumed the wrong amount of randomness")
        }
        XCTAssertEqual(stash, file.finalStash)
    }

    func testAlternatesFreshAndOldAndNeverRepeats() {
        let now = 1_800_000_000_000
        var stash = Stash()
        stash.add(payload: "https://example.com/old1", id: "old1", now: now - 120 * Stash.dayMs)
        stash.add(payload: "https://example.com/old2", id: "old2", now: now - 40 * Stash.dayMs)
        stash.add(payload: "https://example.com/new1", id: "new1", now: now - 3 * Stash.dayMs)
        stash.add(payload: "https://example.com/new2", id: "new2", now: now - 1 * Stash.dayMs)

        let random = ScriptedRandom([0, 0, 0, 0])
        var order = [String]()
        for i in 0..<4 {
            order.append(stash.serve(now: now + i, rng: random.next)?.id ?? "nil")
        }
        XCTAssertEqual(order, ["new1", "old1", "new2", "old2"])
        XCTAssertNil(stash.serve(now: now + 10, rng: random.next))
        XCTAssertEqual(random.used, 4, "an empty serve must not consume randomness")
        XCTAssertEqual(stash.remaining, 0)
    }

    func testSavingTheSameThingTwiceRefreshesIt() {
        var stash = Stash()
        stash.add(payload: "https://example.com/a", id: "a", now: 1_000)
        _ = stash.serve(now: 2_000, rng: { 0 })
        stash.add(payload: "  https://example.com/a \n", now: 3_000)
        XCTAssertEqual(stash.items.count, 1)
        XCTAssertNil(stash.items[0].openedAt)
        XCTAssertEqual(stash.items[0].savedAt, 3_000)
        XCTAssertNil(stash.add(payload: "   ", now: 4_000))
    }

    func testABrokenFileIsMovedAsideNotDeleted() throws {
        let directory = try temporaryDirectory()
        let url = directory.appendingPathComponent("stash.json")
        try Data("{ this is not json".utf8).write(to: url)

        let loaded = StashStore.load(from: url, nowMs: 42)
        XCTAssertEqual(loaded.stash, Stash())
        let aside = directory.appendingPathComponent("stash.broken-42.json")
        XCTAssertEqual(loaded.problem, .movedAside(from: url.path, to: aside.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: aside.path))

        var stash = loaded.stash
        stash.add(payload: "https://example.com/x", now: 50)
        try StashStore.save(stash, to: url)
        XCTAssertEqual(StashStore.load(from: url).stash, stash)
    }
}
