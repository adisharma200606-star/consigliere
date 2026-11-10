import Foundation

// Key gestures: double-tap a modifier key, or hold one, instead of a typed-out hotkey.
// Port of reference-js/taps.js: it must reproduce fixtures/taps.json exactly.
//
//   double-tap Option   -> open the box
//   double-tap Control  -> save the page in front
//   hold right Option   -> talk; let go to run
//
// Why: hotkeys written as text ("ctrl+opt+s") break on one typo, and opt+space sits confusingly next to the
// Mac's own cmd+space. A modifier key types nothing, so tapping it twice is safe in any app.
// This file is only the deciding part; the app feeds it key events and the time (in milliseconds).

public enum ModifierKey: String, Codable, Equatable, Sendable {
    case option, control, command, shift
}

public enum KeySide: String, Codable, Equatable, Sendable {
    case left, right
}

public enum TapEvent: Equatable, Sendable {
    case double(ModifierKey)
    case holdStart
    case holdEnd

    /// The same names reference-js/taps.js uses: "double:option", "holdStart", "holdEnd".
    public var name: String {
        switch self {
        case .double(let key): return "double:" + key.rawValue
        case .holdStart: return "holdStart"
        case .holdEnd: return "holdEnd"
        }
    }
}

public struct TapDetector: Equatable, Sendable {
    /// A tap is a press no longer than this.
    public static let tapMax = 300
    /// The second tap must start within this long of the first ending.
    public static let gapMax = 350
    /// Right Option held alone this long starts talking.
    public static let holdAfter = 350

    private var downKey: ModifierKey?
    private var downSide: KeySide?
    private var downAt = 0
    /// False once anything else was pressed while the modifier was down.
    private var clean = false
    private var lastTapKey: ModifierKey?
    private var lastTapUpAt = 0
    public private(set) var holding = false

    public init() {}

    /// A modifier went down. `alone` is false when another modifier was already held.
    public mutating func down(_ key: ModifierKey, side: KeySide, at t: Int, alone: Bool) -> TapEvent? {
        if holding { return nil }
        guard alone else {
            self = TapDetector()
            return nil
        }
        downKey = key
        downSide = side
        downAt = t
        clean = true
        return nil
    }

    /// A modifier was let go.
    public mutating func up(_ key: ModifierKey, at t: Int) -> TapEvent? {
        if holding {
            guard key == downKey else { return nil }
            self = TapDetector()
            return .holdEnd
        }
        let wasTap = downKey == key && clean && (t - downAt) <= TapDetector.tapMax
        var event: TapEvent?
        if wasTap {
            if lastTapKey == key && (downAt - lastTapUpAt) <= TapDetector.gapMax {
                event = .double(key)
                lastTapKey = nil
            } else {
                lastTapKey = key
                lastTapUpAt = t
            }
        } else {
            lastTapKey = nil
        }
        downKey = nil
        downSide = nil
        clean = false
        return event
    }

    /// Any normal key or a mouse button: whatever was going on is not a tap. A hold in progress carries on.
    public mutating func other() {
        clean = false
        lastTapKey = nil
    }

    /// Time passing: has right Option been held alone long enough to start talking?
    public mutating func tick(at t: Int) -> TapEvent? {
        if !holding && downKey == .option && downSide == .right && clean && (t - downAt) >= TapDetector.holdAfter {
            holding = true
            return .holdStart
        }
        return nil
    }
}
