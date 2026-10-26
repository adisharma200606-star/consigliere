import AppKit
import ConsigliereCore

/// Finds the apps installed on this Mac, so any of them can be opened by name without adding an entry first.
/// Scanning takes a fraction of a second and runs off the main thread.
enum AppIndex {
    static var folders: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/Applications/Utilities"),
            URL(fileURLWithPath: "/System/Applications"),
            URL(fileURLWithPath: "/System/Applications/Utilities"),
            home.appendingPathComponent("Applications")
        ]
    }

    /// Every .app in the usual folders, plus one folder deeper in /Applications (where some installers put
    /// their apps). Apple's own and the person's apps both count.
    static func scan() -> [InstalledApps.Found] {
        let manager = FileManager.default
        var found = [InstalledApps.Found]()

        func add(_ url: URL) {
            let name = manager.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
            let bundleID = Bundle(url: url)?.bundleIdentifier
            if bundleID == Bundle.main.bundleIdentifier { return }     // not itself
            found.append(InstalledApps.Found(name: name, bundleID: bundleID, path: url.path))
        }

        for folder in folders {
            guard let items = try? manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey],
                                                               options: [.skipsHiddenFiles]) else { continue }
            for item in items {
                if item.pathExtension == "app" {
                    add(item)
                } else if folder.path == "/Applications",
                          (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                          let inner = try? manager.contentsOfDirectory(at: item, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                    for app in inner where app.pathExtension == "app" { add(app) }
                }
            }
        }
        return found
    }

    /// Information about one app the person picked in the settings window.
    static func describe(_ url: URL) -> (name: String, bundleID: String?) {
        let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        return (name, Bundle(url: url)?.bundleIdentifier)
    }
}
