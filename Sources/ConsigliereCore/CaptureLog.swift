import Foundation

/// A short memory of the notes and reminders made from the notch, so they can be glanced at later
/// instead of vanishing the moment the confirmation line fades.
///
/// It is a list, newest last, capped at `limit`. The actual note lives in Apple Notes and the actual reminder
/// in Apple Reminders; this only remembers what was typed and how to find it again (`externalID`).
public struct CaptureEntry: Codable, Equatable {
    public var id: String
    /// "note" or "reminder".
    public var kind: String
    public var text: String
    /// When a reminder is due, in real milliseconds since 1970. Nil for notes and to-dos.
    public var dueMs: Int?
    public var createdAt: Int
    /// Notes' own id for the note ("x-coredata://…"), or Reminders' identifier for the reminder.
    public var externalID: String?

    public init(id: String, kind: String, text: String, dueMs: Int? = nil, createdAt: Int, externalID: String? = nil) {
        self.id = id
        self.kind = kind
        self.text = text
        self.dueMs = dueMs
        self.createdAt = createdAt
        self.externalID = externalID
    }
}

public struct CaptureLog: Codable, Equatable {
    public static let limit = 50
    public var entries: [CaptureEntry]

    public init(entries: [CaptureEntry] = []) {
        self.entries = entries
    }

    /// Adds an entry and returns its id. The oldest entries fall off once there are more than `limit`.
    @discardableResult
    public mutating func add(kind: String, text: String, dueMs: Int? = nil, now: Int, externalID: String? = nil) -> String {
        let id = "c\(now)-\(entries.count)"
        entries.append(CaptureEntry(id: id, kind: kind, text: text, dueMs: dueMs, createdAt: now, externalID: externalID))
        if entries.count > CaptureLog.limit {
            entries.removeFirst(entries.count - CaptureLog.limit)
        }
        return id
    }

    /// Fills in the external id once Notes or Reminders has handed it back.
    public mutating func setExternalID(_ externalID: String, for id: String) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].externalID = externalID
    }

    /// The most recent entries of one kind, newest first.
    public func recent(_ kind: String, limit: Int) -> [CaptureEntry] {
        return Array(entries.filter { $0.kind == kind }.reversed().prefix(limit))
    }
}

/// The apps installed on this Mac, turned into things the box can open, so an app does not need an entry
/// before it can be typed. Scanning the disk happens in the app; this part only decides what to keep.
public enum InstalledApps {

    public struct Found: Equatable, Sendable {
        public let name: String
        public let bundleID: String?
        public let path: String

        public init(name: String, bundleID: String?, path: String) {
            self.name = name
            self.bundleID = bundleID
            self.path = path
        }
    }

    /// Turns found apps into catalog entries. Skips apps the catalog already opens (same bundle id, or an entry
    /// that answers to the same name), and duplicates found in more than one folder. The first one found wins.
    public static func entries(from found: [Found], excluding catalog: [CatalogEntry]) -> [CatalogEntry] {
        let takenIDs = Set(catalog.filter { $0.kind == .app }.map { $0.target.lowercased() })
        let takenNames = Set(catalog.flatMap { $0.keys }.map { TextTools.normalize($0) })
        var seenNames = Set<String>()
        var result = [CatalogEntry]()

        for app in found {
            let key = TextTools.normalize(app.name)
            if key.isEmpty || takenNames.contains(key) || seenNames.contains(key) { continue }
            if let id = app.bundleID, takenIDs.contains(id.lowercased()) { continue }
            seenNames.insert(key)
            result.append(CatalogEntry(name: app.name.lowercased(), display: app.name, aliases: [], kind: .app,
                                       target: app.bundleID ?? app.path))
        }
        return result
    }
}
