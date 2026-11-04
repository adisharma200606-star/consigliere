import AppKit
import ApplicationServices
import ConsigliereCore
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

// MARK: - Text replacement in Brave

/// Makes the Text Replacements list from System Settings → Keyboard work in Brave, which ignores it.
///
/// While Brave is the app in front, it follows the keys typed (only there, only in memory, only the last few
/// letters: `TypingBuffer` in ConsigliereCore decides). When a shortcut is followed by a space or punctuation,
/// it presses backspace over the shortcut and types the phrase. macOS itself keeps password fields away from it
/// ("secure input"), so nothing typed there is ever seen.
///
/// It needs one permission, Accessibility (System Settings → Privacy & Security → Accessibility → Consigliere),
/// both to see keys typed in another app and to type into it. Without it, nothing happens and nothing breaks.
///
/// (It sits in this file, rather than its own, only because a new app file has to be added to the Xcode project
/// by the cloud build; it can move to TextReplacer.swift whenever that is convenient.)
@MainActor
final class TextReplacer {
    private var config = TextReplacementConfig()
    private var list: [TextReplacement] = []
    private var listLoadedAt = Date.distantPast
    private var buffer = TypingBuffer()
    private var monitors: [Any] = []
    private var appObserver: NSObjectProtocol?
    private var permissionTimer: Timer?
    private var promptedThisLaunch = false
    /// True while it is typing a phrase itself, so it never reacts to its own keys.
    private var injecting = false
    /// Stamped on every key it types, for the same reason.
    nonisolated static let marker: Int64 = 0x436F_6E73
    private let typingQueue = DispatchQueue(label: "consigliere.text-replacement")

    func apply(_ newConfig: TextReplacementConfig) {
        config = newConfig
        stop()
        guard config.on else { return }
        listLoadedAt = .distantPast
        if AXIsProcessTrusted() {
            start()
        } else {
            askForPermission()
        }
    }

    private func start() {
        stop()
        let keys = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Read everything needed now, on the spot; the event itself is not passed on.
            let ours = event.cgEvent?.getIntegerValueField(.eventSourceUserData) == TextReplacer.marker
            let keyCode = event.keyCode
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let characters = event.characters ?? ""
            Task { @MainActor in self?.keyDown(keyCode: keyCode, flags: flags, characters: characters, ours: ours) }
        }
        let clicks = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            // A click moves the cursor somewhere else: what was typed before no longer counts.
            Task { @MainActor in self?.buffer.reset() }
        }
        monitors = [keys, clicks].compactMap { $0 }
        appObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.buffer.reset()
                self?.reloadListIfStale()
            }
        }
        reloadListIfStale()
        writeLog("on, permission granted")
    }

    private func stop() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors = []
        if let observer = appObserver { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        appObserver = nil
        permissionTimer?.invalidate()
        permissionTimer = nil
        buffer.reset()
    }

    /// Shows macOS's own "allow Consigliere to control this computer" prompt once per launch, then checks every
    /// two seconds and starts by itself the moment the switch is turned on.
    private func askForPermission() {
        if !promptedThisLaunch {
            promptedThisLaunch = true
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }
        writeLog("waiting for the Accessibility permission (System Settings → Privacy & Security → Accessibility → Consigliere)")
        permissionTimer?.invalidate()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, AXIsProcessTrusted() else { return }
                self.permissionTimer?.invalidate()
                self.permissionTimer = nil
                self.start()
            }
        }
    }

    private var inChosenApp: Bool {
        guard let id = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return false }
        return config.apps.contains { id.hasPrefix($0) }
    }

    private func keyDown(keyCode: UInt16, flags: NSEvent.ModifierFlags, characters: String, ours: Bool) {
        guard !ours, !injecting else { return }
        guard inChosenApp else {
            buffer.reset()
            return
        }
        // ⌘ or ⌃ shortcuts (copy, paste, undo…) and keys that move the cursor: start afresh.
        if flags.contains(.command) || flags.contains(.control) {
            buffer.reset()
            return
        }
        switch keyCode {
        case 51:    // backspace
            if flags.contains(.option) { buffer.reset() } else { buffer.backspace() }
            return
        case 36, 76, 48, 53, 117, 115, 119, 116, 121, 123, 124, 125, 126:
            // return, keypad enter, tab, escape, forward delete, home, end, page up/down, arrows
            buffer.reset()
            return
        default:
            break
        }
        for ch in characters {
            if let expansion = buffer.type(ch, list: list) {
                replace(expansion)
                return
            }
        }
    }

    /// Backspace over the shortcut and its delimiter, then type the phrase and the delimiter.
    private func replace(_ expansion: Expansion) {
        injecting = true
        let marker = TextReplacer.marker
        typingQueue.async { [weak self] in
            // Let Brave take the delimiter key first, so the backspaces land after it.
            usleep(40_000)
            let source = CGEventSource(stateID: .hidSystemState)
            func post(_ event: CGEvent?) {
                guard let event = event else { return }
                event.flags = []                     // a still-held Shift must not turn backspace into something else
                event.setIntegerValueField(.eventSourceUserData, value: marker)
                event.post(tap: .cghidEventTap)
                usleep(3_000)
            }
            func press(_ key: CGKeyCode, shift: Bool = false) {
                let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
                let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
                if shift {
                    down?.flags = .maskShift
                    up?.flags = .maskShift
                    for e in [down, up] {
                        e?.setIntegerValueField(.eventSourceUserData, value: marker)
                        e?.post(tap: .cghidEventTap)
                        usleep(3_000)
                    }
                } else {
                    post(down)
                    post(up)
                }
            }
            func typeText(_ text: String) {
                // A few characters per key event: Chromium takes them happily that way. Never split an emoji.
                var chunk: [UniChar] = []
                func flush() {
                    guard !chunk.isEmpty else { return }
                    for keyDown in [true, false] {
                        let e = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: keyDown)
                        chunk.withUnsafeBufferPointer { e?.keyboardSetUnicodeString(stringLength: $0.count, unicodeString: $0.baseAddress) }
                        post(e)
                    }
                    chunk = []
                }
                for ch in text {
                    let units = Array(String(ch).utf16)
                    if chunk.count + units.count > 16 { flush() }
                    chunk.append(contentsOf: units)
                }
                flush()
            }

            for _ in 0..<expansion.deleteCount { press(51) }
            // A new line in a phrase is Shift+Return, which makes a line break in chat boxes instead of sending.
            let lines = expansion.insert.components(separatedBy: "\n")
            for (index, line) in lines.enumerated() {
                if index > 0 { press(36, shift: true) }
                typeText(line)
            }
            usleep(20_000)
            Task { @MainActor in self?.injecting = false }
        }
    }

    /// The list is read again whenever an app comes to the front and it is more than 30 seconds old, so a
    /// change in System Settings shows up without restarting anything.
    private func reloadListIfStale() {
        guard Date().timeIntervalSince(listLoadedAt) > 30 else { return }
        listLoadedAt = Date()
        let extra = config.extra
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let fromDatabase = TextReplacer.readDatabase()
            let globals = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)
            let fromDefaults = MacTextReplacements.parseDefaults(globals?["NSUserDictionaryReplacementItems"] as? [[String: Any]] ?? [])
            let merged = MacTextReplacements.merged([extra, fromDatabase, fromDefaults])
            let counts = "\(merged.count) shortcuts (System Settings: \(fromDatabase.count), older macOS copy: \(fromDefaults.count), config extra: \(extra.count))"
            Task { @MainActor in
                self?.list = merged
                self?.writeLog("list loaded: \(counts)")
            }
        }
    }

    /// macOS keeps the list in a small SQLite database. The sqlite3 tool that ships with macOS reads it,
    /// read-only, without touching anything.
    nonisolated private static func readDatabase() -> [TextReplacement] {
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/KeyboardServices/TextReplacements.db").path
        guard FileManager.default.fileExists(atPath: path) else { return [] }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = ["-readonly", "-json", path, MacTextReplacements.query]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return []
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return MacTextReplacements.parseSQLiteJSON(data)
    }

    /// ~/.consigliere/text-replacement.log: whether it is on, the permission, and how many shortcuts it found.
    /// Never what was typed, and never the phrases.
    private func writeLog(_ line: String) {
        let url = ConsiglierePaths.configDirectory.appendingPathComponent("text-replacement.log")
        let stamp = ISO8601DateFormatter().string(from: Date())
        let old = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let lines: [String] = old.split(separator: "\n").suffix(49).map { String($0) }
        let text: String = (lines + ["\(stamp) \(line)"]).joined(separator: "\n") + "\n"
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }
}
