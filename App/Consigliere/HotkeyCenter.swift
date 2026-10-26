import AppKit
import HotKey

/// Turns "ctrl+opt+space" from the config into a registered global hotkey.
///
/// Registration uses the old Carbon hotkey system (through the HotKey library), which needs no special
/// permission and reports both key-down and key-up. Its one limit: a hotkey must contain a normal key,
/// so a modifier alone (just "right option") cannot be used.
@MainActor
final class HotkeyCenter {
    private var registered = [HotKey]()

    /// Returns false when the text could not be understood, so the caller can say so.
    @discardableResult
    func register(_ text: String, onDown: @escaping () -> Void, onUp: (() -> Void)? = nil) -> Bool {
        guard let combo = HotkeyCenter.parse(text) else { return false }
        let hotKey = HotKey(keyCombo: combo)
        hotKey.keyDownHandler = onDown
        hotKey.keyUpHandler = onUp
        registered.append(hotKey)
        return true
    }

    func removeAll() {
        registered.removeAll()
    }

    /// "cmd+shift+k", "opt+space", "ctrl+opt+s". The last piece is the key; the others are modifiers.
    static func parse(_ text: String) -> KeyCombo? {
        let pieces = text.lowercased().split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let keyName = pieces.last, !keyName.isEmpty, let key = Key(string: keyName) else { return nil }
        var modifiers: NSEvent.ModifierFlags = []
        for piece in pieces.dropLast() {
            switch piece {
            case "cmd", "command": modifiers.insert(.command)
            case "opt", "option", "alt": modifiers.insert(.option)
            case "ctrl", "control": modifiers.insert(.control)
            case "shift": modifiers.insert(.shift)
            default: return nil
            }
        }
        return KeyCombo(key: key, modifiers: modifiers)
    }
}
