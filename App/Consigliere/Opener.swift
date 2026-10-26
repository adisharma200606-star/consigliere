import AppKit
import ConsigliereCore

/// Carries out an `ActionPlan`. The brain decides, this file does.
enum Opener {

    /// Opens a site, an app or a folder. Returns false when it could not.
    @discardableResult
    static func run(_ plan: ActionPlan, config: Config) -> Bool {
        switch plan {
        case .openURL(let url, let profile, _):
            return openInBrave(url, profileDirectory: config.brave.profileDirectory(for: profile), brave: config.brave)
        case .openApp(let bundleID, let entry):
            return openApp(bundleID, name: entry)
        case .openPath(let path, _):
            return NSWorkspace.shared.open(URL(fileURLWithPath: ConsiglierePaths.expandTilde(path)))
        case .openTool, .ask:
            return false    // these are handled by the Brain, not here
        }
    }

    /// Launches Brave's own program file with the profile and the address.
    ///
    /// `open -a "Brave Browser" --args ...` would be simpler, but macOS throws the arguments away when Brave
    /// is already running, and Brave is always already running. Started this way, the new process hands the
    /// address to the running Brave, in the right profile, and exits.
    static func openInBrave(_ address: String, profileDirectory: String, brave: BraveConfig) -> Bool {
        let binary = URL(fileURLWithPath: brave.binaryPath)
        if FileManager.default.isExecutableFile(atPath: binary.path) {
            let process = Process()
            process.executableURL = binary
            process.arguments = ["--profile-directory=\(profileDirectory)", address]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                return true
            } catch {
                NSLog("Consigliere: could not start Brave: \(error)")
            }
        }
        // Brave is not where the config says. Fall back to whatever the default browser is.
        guard let url = URL(string: address) else { return false }
        return NSWorkspace.shared.open(url)
    }

    /// Opens an app. `target` is normally a bundle identifier ("com.valvesoftware.steam"), but a path to an
    /// .app works too. If neither finds anything, the app is looked for by name in the usual folders, so a
    /// wrong bundle identifier in the config still opens "Steam.app" for an entry called "steam".
    static func openApp(_ target: String, name: String = "") -> Bool {
        var url: URL? = nil
        if target.hasSuffix(".app"), FileManager.default.fileExists(atPath: ConsiglierePaths.expandTilde(target)) {
            url = URL(fileURLWithPath: ConsiglierePaths.expandTilde(target))
        } else {
            url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: target)
        }
        if url == nil { url = findApp(named: name.isEmpty ? target : name) }
        guard let appURL = url else {
            NSLog("Consigliere: could not find an app for \(target)")
            return false
        }
        NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
        return true
    }

    /// "whatsapp" finds WhatsApp.app. Case and spaces do not matter.
    static func findApp(named name: String) -> URL? {
        let wanted = TextTools.normalize(name)
        guard !wanted.isEmpty else { return nil }
        for folder in AppIndex.folders {
            guard let items = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { continue }
            for item in items where item.hasSuffix(".app") {
                if TextTools.normalize(String(item.dropLast(4))) == wanted {
                    return folder.appendingPathComponent(item)
                }
            }
        }
        return nil
    }

    /// Opens something from the stash. Links go to the personal Brave profile; files open in their own app.
    /// Notes have nothing to open: the notch shows them.
    @discardableResult
    static func open(_ item: StashItem, config: Config) -> Bool {
        switch item.kind {
        case "url":
            return openInBrave(item.payload, profileDirectory: config.brave.personalProfileDir, brave: config.brave)
        case "file", "image":
            return NSWorkspace.shared.open(URL(fileURLWithPath: item.payload))
        default:
            return true
        }
    }
}
