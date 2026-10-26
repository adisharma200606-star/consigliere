import Foundation

/// One thing the voice can say.
public struct Line: Codable, Equatable {
    public var id: String
    public var text: String

    public init(id: String, text: String) {
        self.id = id
        self.text = text
    }
}

/// Category name to lines. Categories are "open_site", "saved", ... and "target:<entry name>".
public typealias LineBank = [String: [Line]]

/// What has been said recently, per category. Persisted between picks.
public struct LineState: Codable, Equatable {
    public var history: [String: [String]]

    public init(history: [String: [String]] = [:]) {
        self.history = history
    }
}

/// The chosen line. `speak` is false when the frequency dial says to stay quiet; the text still shows.
public struct LinePick: Equatable {
    public let id: String
    public let text: String
    public let speak: Bool
}

/// Picks what to say. Ported from `reference-js/core.js`.
///
/// `rng()` is consumed in a fixed order so that every port stays in lockstep:
///  1. only when a target pool exists: one value to choose target lines over generic ones
///  2. one value to choose the line
///  3. one value to decide whether it is spoken
public enum Lines {
    public static let historyLength = 5
    public static let targetBias = 0.6

    public static func pick(bank: LineBank, state: inout LineState, category: String, target: String?,
                            frequency: Double, rng: () -> Double) -> LinePick? {
        let generic = bank[category] ?? []
        var targeted = [Line]()
        if let target = target, !target.isEmpty {
            targeted = bank["target:" + target] ?? []
        }

        var pool = generic
        var key = category
        if !targeted.isEmpty {
            let roll = rng()
            if roll < targetBias || generic.isEmpty {
                pool = targeted
                key = "target:" + (target ?? "")
            }
        }
        if pool.isEmpty { return nil }

        var recent = state.history[key] ?? []
        var available = pool.filter { !recent.contains($0.id) }
        if available.isEmpty {
            recent = []
            available = pool
        }

        let r = rng()
        let index = Swift.min(available.count - 1, Int((r * Double(available.count)).rounded(.down)))
        let line = available[Swift.max(0, index)]

        // Remember the last few so he never hears the same one back to back,
        // but never remember so many that the pool runs dry.
        let keep = Swift.max(0, Swift.min(historyLength, pool.count - 1))
        recent.append(line.id)
        if keep == 0 {
            recent = []
        } else if recent.count > keep {
            recent = Array(recent.suffix(keep))
        }
        state.history[key] = recent

        let speak = rng() < frequency
        return LinePick(id: line.id, text: line.text, speak: speak)
    }

    /// A tiny built-in bank so the app still talks if `lines.json` is missing.
    public static let fallbackBank: LineBank = [
        "open_site": [Line(id: "fb-os1", text: "It's done. Don't ask how.")],
        "open_app": [Line(id: "fb-oa1", text: "She's running, boss.")],
        "open_path": [Line(id: "fb-op1", text: "The drawer is open.")],
        "open_tool": [Line(id: "fb-ot1", text: "At your service.")],
        "all_in_tune": [Line(id: "fb-at1", text: "Bellissimo. She sings.")],
        "timer_done": [Line(id: "fb-td1", text: "Time's up, boss.")],
        "bookmark_moved": [Line(id: "fb-bm1", text: "I remember where you stopped.")],
        "explained": [Line(id: "fb-ex1", text: "Here. In plain words.")],
        "saved": [Line(id: "fb-sv1", text: "I'll hold onto this.")],
        "pulled": [Line(id: "fb-pl1", text: "From the vault, for you.")],
        "another": [Line(id: "fb-an1", text: "Fine. Another.")],
        "empty_stash": [Line(id: "fb-es1", text: "The vault is empty, boss.")],
        "unknown": [Line(id: "fb-un1", text: "Never heard of it.")],
        "muted_on": [Line(id: "fb-mo1", text: "My lips, sealed.")],
        "muted_off": [Line(id: "fb-mf1", text: "I'm back.")]
    ]
}
