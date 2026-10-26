import AppKit
import ConsigliereCore
import SwiftUI

/// Three slides that explain the whole thing. Shown once on first launch; after that from the "?" in
/// settings, or by typing "help" in the notch. The hotkeys shown are whatever the config says right now.
@MainActor
final class TutorialWindow {
    // Still the app's old name on purpose, so the tutorial does not show again after the rename.
    private static let seenKey = "brochacho.tutorialSeen.v1"
    private var window: NSWindow?

    static var hasBeenSeen: Bool {
        return UserDefaults.standard.bool(forKey: seenKey)
    }

    func show(hotkeys: Hotkeys, theme: NotchTheme) {
        UserDefaults.standard.set(true, forKey: TutorialWindow.seenKey)
        window?.close()
        let view = TutorialView(slides: TutorialWindow.slides(hotkeys), theme: theme) { [weak self] in self?.window?.close() }
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.backgroundColor = NSColor(red: 0.012, green: 0.016, blue: 0.024, alpha: 1)
        window.setContentSize(NSSize(width: 560, height: 440))
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// "ctrl+opt+space" as the Mac writes it: ⌃⌥Space.
    static func symbols(_ hotkey: String) -> String {
        let parts = hotkey.lowercased().split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces) }
        return parts.map { part -> String in
            switch part {
            case "cmd", "command": return "⌘"
            case "opt", "option", "alt": return "⌥"
            case "ctrl", "control": return "⌃"
            case "shift": return "⇧"
            case "space": return "Space"
            case "return", "enter": return "↩"
            default: return part.uppercased()
            }
        }.joined()
    }

    struct Slide {
        let title: String
        let lines: [(key: String, text: String)]
    }

    static func slides(_ hotkeys: Hotkeys) -> [Slide] {
        return [
            Slide(title: "Type a name.", lines: [
                (symbols(hotkeys.openBox), "opens the notch. Type yt, gmail, steam, any app on this Mac. Enter."),
                ("hold " + symbols(hotkeys.talk), "and say it instead. Let go when you are done."),
                ("yt berserk", "a site's name, then words, searches that site."),
                ("what is…", "anything that reads like a question gets a short answer.")
            ]),
            Slide(title: "Keep it. Get it back.", lines: [
                ("drag", "a link, a picture or a file onto the notch to keep it."),
                (symbols(hotkeys.saveTab), "keeps the page you are looking at."),
                ("click", "the notch, or type bored, and he hands one back."),
                (symbols(hotkeys.markPlace), "remembers where you stopped reading.")
            ]),
            Slide(title: "Little tools.", lines: [
                ("tune", "a guitar and ukulele tuner.  timer 10  counts down."),
                ("remind me…", "to call mom tomorrow at 5.  note  buy strings."),
                ("notes · reminders", "glance at what you saved, tick things off."),
                ("one eighty", "flips the screen.  settings  ·  help  ·  right-click the notch.")
            ])
        ]
    }
}

private struct TutorialView: View {
    let slides: [TutorialWindow.Slide]
    let theme: NotchTheme
    let close: () -> Void
    @State private var index = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(String(format: "%02d / %02d", index + 1, slides.count))
                .font(theme.mono(10))
                .kerning(1)
                .foregroundStyle(NotchTheme.faint)
                .padding(.top, 40)

            Text(slides[index].title.liner)
                .font(theme.font(46, .thin))
                .kerning(-1.5)
                .foregroundStyle(NotchTheme.text)
                .padding(.top, 8)
                .padding(.bottom, 24)

            VStack(alignment: .leading, spacing: 0) {
                Rectangle().fill(NotchTheme.hairline).frame(height: 1)
                ForEach(Array(slides[index].lines.enumerated()), id: \.offset) { _, line in
                    HStack(alignment: .firstTextBaseline, spacing: 16) {
                        Text(line.key.liner)
                            .font(theme.mono(11))
                            .foregroundStyle(theme.accent)
                            .frame(width: 150, alignment: .leading)
                        Text(line.text.liner)
                            .font(theme.font(14, .light))
                            .foregroundStyle(Color(white: 0.82))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 11)
                    .overlay(alignment: .bottom) { Rectangle().fill(NotchTheme.hairline).frame(height: 1) }
                }
            }
            .id(index)
            .transition(.opacity)

            Spacer()

            HStack(spacing: 6) {
                ForEach(0..<slides.count, id: \.self) { dot in
                    Rectangle()
                        .fill(dot == index ? theme.accent : Color.white.opacity(0.2))
                        .frame(width: dot == index ? 22 : 10, height: 1)
                }
                Spacer()
                if index > 0 {
                    Button("back") { withAnimation(theme.spring) { index -= 1 } }
                        .buttonStyle(PillButtonStyle(theme: theme))
                }
                Button(index == slides.count - 1 ? "done" : "next") {
                    if index == slides.count - 1 {
                        close()
                    } else {
                        withAnimation(theme.spring) { index += 1 }
                    }
                }
                .buttonStyle(PillButtonStyle(theme: theme))
                .keyboardShortcut(.defaultAction)
            }
            .padding(.bottom, 30)
        }
        .padding(.horizontal, 44)
        .frame(width: 560, height: 440, alignment: .topLeading)
        .background(
            ZStack {
                Color(red: 0.012, green: 0.016, blue: 0.024)
                // One raking beam of light from the top left, like the wallpaper it was designed from.
                LinearGradient(colors: [.clear, theme.accent.opacity(0.08), .clear], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .rotationEffect(.degrees(-8))
                    .scaleEffect(1.4)
                if let grain = NotchTheme.grainImage {
                    Image(nsImage: grain).resizable(resizingMode: .tile).opacity(theme.grain)
                }
            }
        )
        .foregroundStyle(NotchTheme.text)
    }
}
