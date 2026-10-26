import Foundation

/// One saved thing. Times are milliseconds since 1970, to match the JS reference and the phone Shortcut.
public struct StashItem: Codable, Equatable {
    public var id: String
    /// "url", "text", "file" or "image".
    public var kind: String
    public var payload: String
    public var title: String?
    /// "drop", "hotkey" or "phone".
    public var source: String
    public var savedAt: Int
    public var servedAt: Int?
    public var openedAt: Int?
    public var skippedCount: Int

    public init(id: String, kind: String = "url", payload: String, title: String? = nil, source: String = "drop",
                savedAt: Int, servedAt: Int? = nil, openedAt: Int? = nil, skippedCount: Int = 0) {
        self.id = id
        self.kind = kind
        self.payload = payload
        self.title = title
        self.source = source
        self.savedAt = savedAt
        self.servedAt = servedAt
        self.openedAt = openedAt
        self.skippedCount = skippedCount
    }
}

/// The stash is plain data so it can be saved as JSON as it is. Ported from `reference-js/core.js`.
///
/// Serving rules:
///  - an opened item is never served again
///  - items skipped `skipLimit` or more times only come back when nothing else is left
///  - serving alternates between a fresh bucket (saved under 14 days ago) and an old one, fresh first
public struct Stash: Codable, Equatable {
    public static let dayMs = 24 * 60 * 60 * 1000
    public static let freshDays = 14
    public static let skipLimit = 3

    public var items: [StashItem]
    /// "fresh", "old" or nil.
    public var lastBucket: String?
    public var currentID: String?

    public init(items: [StashItem] = [], lastBucket: String? = nil, currentID: String? = nil) {
        self.items = items
        self.lastBucket = lastBucket
        self.currentID = currentID
    }

    /// How many items are still waiting to be given back.
    public var remaining: Int {
        return items.filter { $0.openedAt == nil }.count
    }

    /// Save something. Saving the same thing twice refreshes it instead of duplicating it.
    /// Returns nil when there is nothing to save.
    @discardableResult
    public mutating func add(payload rawPayload: String, kind: String = "url", title: String? = nil,
                             source: String = "drop", id: String? = nil, now: Int) -> StashItem? {
        let payload = rawPayload.trimmingCharacters(in: .whitespacesAndNewlines)
        if payload.isEmpty { return nil }

        if let index = items.firstIndex(where: { $0.payload == payload && $0.kind == kind }) {
            items[index].savedAt = now
            items[index].openedAt = nil
            items[index].skippedCount = 0
            return items[index]
        }

        let created = StashItem(id: id ?? "s\(now)-\(items.count)", kind: kind, payload: payload, title: title,
                                source: source, savedAt: now)
        items.append(created)
        return created
    }

    /// Give one item back. Consumes exactly one `rng()` value when it serves something, none when it cannot.
    public mutating func serve(now: Int, rng: () -> Double, excluding excludeID: String? = nil) -> StashItem? {
        var pool = items.filter { $0.openedAt == nil }
        if let excludeID = excludeID, pool.count > 1 {
            pool = pool.filter { $0.id != excludeID }
        }
        if pool.isEmpty {
            currentID = nil
            return nil
        }

        let keen = pool.filter { $0.skippedCount < Stash.skipLimit }
        if !keen.isEmpty { pool = keen }

        let cutoff = Stash.freshDays * Stash.dayMs
        let fresh = pool.filter { now - $0.savedAt < cutoff }.sorted(by: Stash.byAgeThenID)
        let old = pool.filter { now - $0.savedAt >= cutoff }.sorted(by: Stash.byAgeThenID)

        var want = lastBucket == "fresh" ? "old" : "fresh"
        var bucket = want == "fresh" ? fresh : old
        if bucket.isEmpty {
            want = want == "fresh" ? "old" : "fresh"
            bucket = want == "fresh" ? fresh : old
        }

        let r = rng()
        let index = Swift.min(bucket.count - 1, Int((r * Double(bucket.count)).rounded(.down)))
        let chosenID = bucket[Swift.max(0, index)].id

        guard let position = items.firstIndex(where: { $0.id == chosenID }) else { return nil }
        items[position].servedAt = now
        items[position].openedAt = now
        lastBucket = want
        currentID = chosenID
        return items[position]
    }

    /// "Another": un-open the current item, count the skip, serve the next one.
    public mutating func another(now: Int, rng: () -> Double) -> StashItem? {
        var skippedID: String? = nil
        if let currentID = currentID, let position = items.firstIndex(where: { $0.id == currentID }) {
            items[position].openedAt = nil
            items[position].skippedCount += 1
            skippedID = currentID
        }
        return serve(now: now, rng: rng, excluding: skippedID)
    }

    private static func byAgeThenID(_ a: StashItem, _ b: StashItem) -> Bool {
        if a.savedAt != b.savedAt { return a.savedAt < b.savedAt }
        return a.id < b.id
    }
}
