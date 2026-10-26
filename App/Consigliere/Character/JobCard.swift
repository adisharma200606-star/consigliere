import AppKit
import SwiftUI

/// The small card that opens beside the character when you click him: what the job is, a line from him
/// (shown, not spoken: he still has not said a word), and two or three buttons.
@MainActor
final class JobCard {
    /// Runs with the index of the button pressed.
    var onButton: (Int) -> Void = { _ in }
    /// Runs when the card is dismissed by clicking somewhere else.
    var onDismiss: () -> Void = {}

    private(set) var isOpen = false

    private final class Content: ObservableObject {
        @Published var line = ""
        @Published var title = ""
        @Published var detail = ""
        @Published var buttons: [String] = []
        @Published var theme: NotchTheme

        init(theme: NotchTheme) {
            self.theme = theme
        }
    }

    private var content: Content?
    private var panel: NSPanel?
    private var clickMonitor: Any?

    /// Opens beside `beside` (his window's frame), on whichever side has more room.
    func show(line: String, title: String, detail: String, buttons: [String], theme: NotchTheme, beside: NSRect) {
        let content = self.content ?? Content(theme: theme)
        content.theme = theme
        content.line = line
        content.title = title
        content.detail = detail
        content.buttons = buttons
        self.content = content

        let host = FirstClickHostingView(rootView: CardView(content: content, press: { [weak self] index in self?.pressed(index) }))
        let size = host.fittingSize
        let screen = NotchController.preferredScreen.visibleFrame
        var x = beside.midX > screen.midX ? beside.minX - size.width - 10 : beside.maxX + 10
        x = min(max(screen.minX + 8, x), screen.maxX - size.width - 8)
        var y = beside.midY - size.height / 2
        y = min(max(screen.minY + 8, y), screen.maxY - size.height - 8)

        let panel = self.panel ?? NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = host
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
        panel.orderFrontRegardless()
        self.panel = panel
        isOpen = true

        if clickMonitor == nil {
            // A click in another app means "not now": the card closes and he goes home.
            clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                Task { @MainActor in
                    guard let self = self, self.isOpen else { return }
                    self.close()
                    self.onDismiss()
                }
            }
        }
    }

    func close() {
        isOpen = false
        panel?.orderOut(nil)
        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
            clickMonitor = nil
        }
    }

    private func pressed(_ index: Int) {
        close()
        onButton(index)
    }

    private struct CardView: View {
        @ObservedObject var content: Content
        let press: (Int) -> Void

        var body: some View {
            let theme = content.theme
            VStack(alignment: .leading, spacing: 8) {
                if !content.line.isEmpty {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("—").font(theme.mono(11))
                        Text(content.line.liner)
                            .font(theme.font(theme.textSize * 0.8, .light))
                            .kerning(0.4)
                    }
                    .foregroundStyle(theme.tint)
                }
                Text(content.title.liner)
                    .font(theme.font(theme.textSize * 1.6, .thin))
                    .foregroundStyle(NotchTheme.text)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if !content.detail.isEmpty {
                    Text(content.detail.liner)
                        .font(theme.mono(10))
                        .kerning(0.4)
                        .foregroundStyle(NotchTheme.secondary)
                }
                HStack(spacing: 8) {
                    ForEach(Array(content.buttons.enumerated()), id: \.offset) { index, title in
                        Button(title) { press(index) }
                            .buttonStyle(PillButtonStyle(theme: theme))
                    }
                }
                .padding(.top, 4)
            }
            .padding(16)
            .frame(width: 300, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.black)
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.white.opacity(0.12), lineWidth: 1))
            )
        }
    }
}

/// SwiftUI buttons in a window that is not the key window would otherwise eat the first click.
private final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
