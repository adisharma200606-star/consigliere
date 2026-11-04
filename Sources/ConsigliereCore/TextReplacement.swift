import Foundation

// Text replacement for apps that ignore macOS's own (Brave, and every Chromium browser).
// Port of reference-js/replace.js: it must reproduce fixtures/replace.json exactly.
//
// Why: Safari and Apple's apps run macOS's text system, which does the replacing. Brave handles typing in
// web pages itself and skips it, so the list kept in System Settings → Keyboard → Text Replacements does
// nothing there. The app watches keys typed in Brave and, when a shortcut is followed by a space or
// punctuation, deletes the shortcut and types the phrase. This file is only the deciding part: it keeps the
// last few characters typed, in memory, and nothing else.

/// One line of the list: type `shortcut`, get `phrase`.
public struct TextReplacement: Codable, Equatable, Sendable {
    public var shortcut: String
    public var phrase: String

    public init(shortcut: String, phrase: String) {
        self.shortcut = shortcut
        self.phrase = phrase
    }
}

/// What to do: press backspace `deleteCount` times, then type `insert`.
public struct Expansion: Codable, Equatable, Sendable {
    public let deleteCount: Int
    public let insert: String

    public init(deleteCount: Int, insert: String) {
        self.deleteCount = deleteCount
        self.insert = insert
    }
}

/// The last few characters typed, and the rules for when they become a phrase. See reference-js/replace.js.
public struct TypingBuffer: Equatable, Sendable {
    /// A shortcut is replaced when one of these is typed right after it. The delimiter is kept.
    public static let delimiters: Set<Character> = [" ", ".", ",", "!", "?", ";", ":", ")"]
    /// How many typed characters are remembered. Longer than any sensible shortcut.
    public static let memory = 64

    public private(set) var text: [Character] = []

    public init() {}

    /// Shortcuts that can never work are dropped: empty, containing spaces, or the same as their phrase.
    public static func usable(_ list: [TextReplacement]) -> [TextReplacement] {
        return list.filter { r in
            !r.shortcut.isEmpty && !r.phrase.isEmpty && !r.shortcut.contains(where: { $0.isWhitespace }) && r.shortcut != r.phrase
        }
    }

    /// One character typed. Returns what to replace, if this character finished a shortcut.
    public mutating func type(_ ch: Character, list: [TextReplacement]) -> Expansion? {
        if TypingBuffer.delimiters.contains(ch) {
            var best: TextReplacement?
            var bestLength = 0
            for r in TypingBuffer.usable(list) {
                let s = Array(r.shortcut)
                guard s.count <= text.count else { continue }
                // Compared character by character, ignoring case: "OMW" works for "omw".
                guard String(text.suffix(s.count)).lowercased() == String(s).lowercased() else { continue }
                // The shortcut must start a word, so "now" never fires inside "known".
                let before = text.count - s.count - 1
                if before >= 0 && TypingBuffer.isWordChar(text[before]) { continue }
                // The longest wins; on a tie, the first in the list.
                if best == nil || s.count > bestLength {
                    best = r
                    bestLength = s.count
                }
            }
            if let best = best {
                text = []
                return Expansion(deleteCount: bestLength + 1, insert: best.phrase + String(ch))
            }
        }
        text.append(ch)
        if text.count > TypingBuffer.memory { text.removeFirst(text.count - TypingBuffer.memory) }
        return nil
    }

    public mutating func backspace() {
        if !text.isEmpty { text.removeLast() }
    }

    /// A click, an arrow key, a shortcut with ⌘, or switching apps: what came before no longer counts.
    public mutating func reset() {
        text = []
    }

    private static func isWordChar(_ ch: Character) -> Bool {
        return ch.isLetter || ch.isNumber
    }
}

/// Reading the list Adi already keeps in System Settings → Keyboard → Text Replacements.
public enum MacTextReplacements {
    /// The `sqlite3 -json` output of the query in `query`, as macOS stores the list in
    /// ~/Library/KeyboardServices/TextReplacements.db.
    public static let query = "SELECT ZSHORTCUT AS shortcut, ZPHRASE AS phrase FROM ZTEXTREPLACEMENTENTRY WHERE ZWASDELETED = 0 OR ZWASDELETED IS NULL;"

    public static func parseSQLiteJSON(_ data: Data) -> [TextReplacement] {
        guard let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return rows.compactMap { row in
            guard let s = row["shortcut"] as? String, let p = row["phrase"] as? String else { return nil }
            return TextReplacement(shortcut: s, phrase: p)
        }
    }

    /// The older copy macOS keeps in the global preferences, `NSUserDictionaryReplacementItems`:
    /// a list of { "on": 1, "replace": "omw", "with": "On my way!" }.
    public static func parseDefaults(_ items: [[String: Any]]) -> [TextReplacement] {
        return items.compactMap { item in
            if let on = item["on"] as? Int, on == 0 { return nil }
            guard let s = item["replace"] as? String, let p = item["with"] as? String else { return nil }
            return TextReplacement(shortcut: s, phrase: p)
        }
    }

    /// One list from several, the first source winning when a shortcut appears twice.
    public static func merged(_ sources: [[TextReplacement]]) -> [TextReplacement] {
        var seen = Set<String>()
        var out: [TextReplacement] = []
        for source in sources {
            for r in source where !seen.contains(r.shortcut.lowercased()) {
                seen.insert(r.shortcut.lowercased())
                out.append(r)
            }
        }
        return out
    }
}
