import Foundation

/// Where Consigliere keeps its files.
public enum ConsiglierePaths {
    public static var home: URL {
        return FileManager.default.homeDirectoryForCurrentUser
    }

    /// ~/.consigliere. Until `moveOldFolders` has run (or if it could not), the old ~/.brochacho is used
    /// instead, so a Mac that had the app under its old name never starts with an empty config.
    public static var configDirectory: URL {
        return preferred(home.appendingPathComponent(".consigliere", isDirectory: true),
                         over: home.appendingPathComponent(OldName.configFolder, isDirectory: true))
    }

    public static var configFile: URL {
        return configDirectory.appendingPathComponent("config.json")
    }

    public static var usageFile: URL {
        return configDirectory.appendingPathComponent("usage.json")
    }

    public static var captureLogFile: URL {
        return configDirectory.appendingPathComponent("captures.json")
    }

    public static var catalogMigrationFile: URL {
        return configDirectory.appendingPathComponent("catalog-migrations.json")
    }

    public static var jobsFile: URL {
        return configDirectory.appendingPathComponent("jobs.json")
    }

    public static var lineStateFile: URL {
        return configDirectory.appendingPathComponent("line-state.json")
    }

    /// The stash lives in iCloud Drive when it exists, so a phone Shortcut can append to the same file.
    /// Otherwise it lives next to the config.
    public static var stashFile: URL {
        let cloudDocs = home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: cloudDocs.path, isDirectory: &isDirectory), isDirectory.boolValue {
            let folder = preferred(cloudDocs.appendingPathComponent("Consigliere", isDirectory: true),
                                   over: cloudDocs.appendingPathComponent(OldName.cloudFolder, isDirectory: true))
            return folder.appendingPathComponent("stash.json")
        }
        return configDirectory.appendingPathComponent("stash.json")
    }

    /// The folder the iPhone shortcuts write to. It is the Shortcuts app's own iCloud Drive folder, because that is
    /// the one place a shortcut can always append to a file. (Path to be confirmed on the Mac: see BLIND_SPOTS.)
    public static var phoneFolder: URL {
        return home.appendingPathComponent("Library/Mobile Documents/iCloud~is~workflow~my~workflows/Documents/Consigliere", isDirectory: true)
    }

    /// Only the phone writes these two.
    public static var phoneInboxFile: URL { return phoneFolder.appendingPathComponent("phone-inbox.txt") }
    public static var phoneOpenedFile: URL { return phoneFolder.appendingPathComponent("phone-opened.txt") }
    /// Only the Mac writes this one.
    public static var forPhoneFile: URL { return phoneFolder.appendingPathComponent("for-phone.txt") }

    /// The app was called Brochacho until 26 October 2026. These are the folders it kept its files in then.
    enum OldName {
        static let configFolder = ".brochacho"
        static let cloudFolder = "Brochacho"
    }

    /// The new folder if it exists; otherwise the old one if that exists; otherwise the new one (a fresh Mac).
    static func preferred(_ new: URL, over old: URL) -> URL {
        let files = FileManager.default
        if files.fileExists(atPath: new.path) { return new }
        if files.fileExists(atPath: old.path) { return old }
        return new
    }

    /// Carries the files over from the app's old name, once, at launch, before anything is loaded:
    /// ~/.brochacho becomes ~/.consigliere (with a link left at the old path, so anything still pointing
    /// there, like a character folder written into config.json, keeps working), and the iCloud Drive
    /// stash folder "Brochacho" becomes "Consigliere". Nothing is ever deleted or overwritten: a folder is
    /// moved only when the new one does not exist yet, and if a move fails the old folder simply stays in
    /// use (see `preferred`). Returns one line per thing it did or could not do, for the log.
    @discardableResult
    public static func moveOldFolders(home: URL = home) -> [String] {
        var report: [String] = []
        let cloudDocs = home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
        let moves: [(old: URL, new: URL, leaveLink: Bool)] = [
            (home.appendingPathComponent(OldName.configFolder, isDirectory: true),
             home.appendingPathComponent(".consigliere", isDirectory: true), true),
            // No link here: iCloud Drive syncs links badly, and only this app reads that folder.
            (cloudDocs.appendingPathComponent(OldName.cloudFolder, isDirectory: true),
             cloudDocs.appendingPathComponent("Consigliere", isDirectory: true), false),
        ]
        let files = FileManager.default
        for move in moves {
            // fileExists follows links, so the link left by an earlier move counts as "already done".
            guard files.fileExists(atPath: move.old.path), !files.fileExists(atPath: move.new.path) else { continue }
            do {
                try files.moveItem(at: move.old, to: move.new)
                report.append("moved \(move.old.path) to \(move.new.path)")
            } catch {
                report.append("could not move \(move.old.path), still using it: \(error)")
                continue
            }
            if move.leaveLink {
                do {
                    try files.createSymbolicLink(at: move.old, withDestinationURL: move.new)
                } catch {
                    report.append("moved, but could not leave a link at \(move.old.path): \(error)")
                }
            }
        }
        return report
    }

    /// Turn "~/Downloads" into a real path.
    public static func expandTilde(_ path: String) -> String {
        if path == "~" { return home.path }
        if path.hasPrefix("~/") { return home.path + String(path.dropFirst(1)) }
        return path
    }
}

/// What went wrong while loading a file. Loading never throws and never crashes; it reports and carries on.
public enum LoadProblem: Equatable {
    /// The file was there but could not be read as JSON of the right shape. It was left alone.
    case malformed(path: String, detail: String)
    /// The broken file was moved aside to this path so nothing is lost, and a fresh one was started.
    case movedAside(from: String, to: String)
}

/// Reads and writes small JSON files safely. Writes are atomic, so a crash never leaves half a file.
public enum JSONFile {
    public static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return e
    }

    public static func read<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(type, from: data)
    }

    public static func write<T: Encodable>(_ value: T, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder().encode(value)
        try data.write(to: url, options: .atomic)
    }

    public static func exists(_ url: URL) -> Bool {
        return FileManager.default.fileExists(atPath: url.path)
    }
}

public enum ConfigStore {
    /// Loads the config. A missing file is created with defaults. A broken file is left untouched and
    /// defaults are used for this run, so a typo in the config never deletes his settings.
    public static func load(from url: URL = ConsiglierePaths.configFile) -> (config: Config, problem: LoadProblem?) {
        if !JSONFile.exists(url) {
            let fresh = Config()
            try? JSONFile.write(fresh, to: url)
            return (fresh, nil)
        }
        do {
            return (try JSONFile.read(Config.self, from: url), nil)
        } catch {
            return (Config(), .malformed(path: url.path, detail: String(describing: error)))
        }
    }

    public static func save(_ config: Config, to url: URL = ConsiglierePaths.configFile) throws {
        try JSONFile.write(config, to: url)
    }
}

public enum StashStore {
    /// Loads the stash. A missing file means an empty stash. A broken or half-synced file is moved aside,
    /// never deleted, and an empty stash is started.
    public static func load(from url: URL = ConsiglierePaths.stashFile, nowMs: Int = SystemClock.nowMs()) -> (stash: Stash, problem: LoadProblem?) {
        if !JSONFile.exists(url) { return (Stash(), nil) }
        do {
            return (try JSONFile.read(Stash.self, from: url), nil)
        } catch {
            let aside = url.deletingLastPathComponent().appendingPathComponent("stash.broken-\(nowMs).json")
            do {
                try FileManager.default.moveItem(at: url, to: aside)
                return (Stash(), .movedAside(from: url.path, to: aside.path))
            } catch {
                return (Stash(), .malformed(path: url.path, detail: String(describing: error)))
            }
        }
    }

    public static func save(_ stash: Stash, to url: URL = ConsiglierePaths.stashFile) throws {
        try JSONFile.write(stash, to: url)
    }
}

/// How often each thing has been opened. Used to break ties in the matcher.
public enum PhoneStore {
    /// Reads whatever the phone has written and folds it into the stash. Missing files simply mean "nothing yet".
    @discardableResult
    public static func pull(into stash: inout Stash, nowMs: Int = SystemClock.nowMs(),
                            inbox: URL = ConsiglierePaths.phoneInboxFile, opened: URL = ConsiglierePaths.phoneOpenedFile) -> PhoneSync.Counts {
        let inboxText = (try? String(contentsOf: inbox, encoding: .utf8)) ?? ""
        let openedText = (try? String(contentsOf: opened, encoding: .utf8)) ?? ""
        if inboxText.isEmpty && openedText.isEmpty { return PhoneSync.Counts() }
        return stash.ingestPhone(inbox: inboxText, opened: openedText, nowMs: nowMs)
    }

    /// Writes the list the phone's "bored" shortcut reads. Only does so when the phone folder already exists,
    /// so a Mac that has never seen the shortcuts does not create stray folders in iCloud.
    public static func push(_ stash: Stash, to url: URL = ConsiglierePaths.forPhoneFile) {
        let folder = url.deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: folder.path) else { return }
        try? Data(PhoneSync.exportForPhone(stash).utf8).write(to: url, options: .atomic)
    }
}

public enum UsageStore {
    public static func load(from url: URL = ConsiglierePaths.usageFile) -> [String: Int] {
        return (try? JSONFile.read([String: Int].self, from: url)) ?? [:]
    }

    public static func save(_ usage: [String: Int], to url: URL = ConsiglierePaths.usageFile) {
        try? JSONFile.write(usage, to: url)
    }
}

public enum CaptureLogStore {
    public static func load(from url: URL = ConsiglierePaths.captureLogFile) -> CaptureLog {
        return (try? JSONFile.read(CaptureLog.self, from: url)) ?? CaptureLog()
    }

    public static func save(_ log: CaptureLog, to url: URL = ConsiglierePaths.captureLogFile) {
        try? JSONFile.write(log, to: url)
    }
}

/// Today's jobs. A missing or unreadable file means an empty day; it is never deleted.
public enum JobsStore {
    public static func load(from url: URL = ConsiglierePaths.jobsFile) -> JobDay? {
        return try? JSONFile.read(JobDay.self, from: url)
    }

    public static func save(_ day: JobDay, to url: URL = ConsiglierePaths.jobsFile) {
        try? JSONFile.write(day, to: url)
    }
}

public enum LineStateStore {
    public static func load(from url: URL = ConsiglierePaths.lineStateFile) -> LineState {
        return (try? JSONFile.read(LineState.self, from: url)) ?? LineState()
    }

    public static func save(_ state: LineState, to url: URL = ConsiglierePaths.lineStateFile) {
        try? JSONFile.write(state, to: url)
    }
}

public enum LineBankStore {
    /// Loads a bank from a file, falling back to the tiny built-in one.
    public static func load(from url: URL?) -> LineBank {
        guard let url = url, let bank = try? JSONFile.read(LineBank.self, from: url), !bank.isEmpty else {
            return Lines.fallbackBank
        }
        return bank
    }
}

public enum SystemClock {
    /// Milliseconds since 1970.
    public static func nowMs() -> Int {
        return Int((Date().timeIntervalSince1970 * 1000).rounded())
    }
}
