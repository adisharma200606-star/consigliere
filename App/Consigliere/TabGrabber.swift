import AppKit

/// Asks the browser in front which page it is showing. Used by the save hotkey and by "mark my place".
///
/// This is AppleScript, so the first time it runs macOS asks whether Consigliere may control the browser.
/// Saying no means these two hotkeys do nothing; everything else still works.
enum TabGrabber {
    struct Tab {
        let url: String
        let title: String
    }

    /// Chromium browsers all answer the same question; Safari words it differently.
    private static let chromiumApps = ["Brave Browser", "Google Chrome", "Arc", "Microsoft Edge"]

    static func frontTab() -> Tab? {
        let front = NSWorkspace.shared.frontmostApplication?.localizedName ?? ""
        var candidates = [front] + chromiumApps + ["Safari"]
        candidates = candidates.filter { !$0.isEmpty }

        var tried = Set<String>()
        for app in candidates where !tried.contains(app) {
            tried.insert(app)
            guard isRunning(app) else { continue }
            if let tab = ask(app) { return tab }
        }
        return nil
    }

    private static func isRunning(_ name: String) -> Bool {
        return NSWorkspace.shared.runningApplications.contains { $0.localizedName == name }
    }

    private static func ask(_ app: String) -> Tab? {
        let source: String
        if app == "Safari" {
            source = """
            tell application "Safari"
                if (count of windows) is 0 then return ""
                set theTab to current tab of front window
                return (URL of theTab) & linefeed & (name of theTab)
            end tell
            """
        } else if chromiumApps.contains(app) {
            source = """
            tell application "\(app)"
                if (count of windows) is 0 then return ""
                set theTab to active tab of front window
                return (URL of theTab) & linefeed & (title of theTab)
            end tell
            """
        } else {
            return nil
        }

        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return nil }
        let result = script.executeAndReturnError(&error)
        if let error = error {
            NSLog("Consigliere: \(app) would not say which tab is in front: \(error)")
            return nil
        }
        guard let text = result.stringValue, !text.isEmpty else { return nil }
        let lines = text.components(separatedBy: "\n")
        guard let url = lines.first, url.hasPrefix("http") else { return nil }
        let title = lines.dropFirst().joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return Tab(url: url, title: title)
    }
}
