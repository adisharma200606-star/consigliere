import AppKit
import SwiftUI
import ConsigliereCore

/// The entry point. There is no main window: the app lives in the notch and is driven by hotkeys.
/// Everything interesting is set up by `AppDelegate`, which owns the `Brain`.
@main
struct ConsigliereApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // A scene is required. Settings has its own window, opened by SettingsWindow, so this one stays empty.
        Settings {
            EmptyView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var brain: Brain?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // LSUIElement already hides the Dock icon; this makes sure of it when run from Xcode.
        NSApp.setActivationPolicy(.accessory)
        NotchTheme.registerFonts()
        // Before the brain loads anything: carry the files over from when the app was called Brochacho.
        for line in ConsiglierePaths.moveOldFolders() { NSLog("Consigliere: \(line)") }
        let brain = Brain()
        brain.start()
        self.brain = brain
    }

    func applicationWillTerminate(_ notification: Notification) {
        brain?.shutDown()
    }
}
