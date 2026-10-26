import AppKit

/// What was dropped on the notch.
enum DroppedThing {
    case link(URL)
    case text(String)
    case file(URL)
    case image(NSImage)
}

/// An invisible window that sits over the physical notch all the time.
///
/// DynamicNotchKit removes its window completely while the notch is closed, so without this there would be
/// nothing to click and nothing to drop onto. It does three jobs:
///   click        hand back something from the stash
///   right-click  a small menu: settings, mute, quit
///   drop         save what was dropped
/// On a screen with no notch it is not shown at all, because it would sit over the middle of the menu bar.
@MainActor
final class NotchSensor {
    var onClick: () -> Void = {}
    var onDrop: ([DroppedThing]) -> Void = { _ in }
    var menuProvider: () -> NSMenu? = { nil }

    private var panel: NSPanel?
    private var observer: NSObjectProtocol?

    func start() {
        place()
        observer = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                          object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.place() }
        }
    }

    private func place() {
        panel?.close()
        panel = nil
        guard let screen = NSScreen.screens.first(where: { $0.consigliereNotchFrame != nil }),
              let notch = screen.consigliereNotchFrame else { return }

        // A little taller than the notch, so a drop does not have to be pixel-perfect.
        let frame = NSRect(x: notch.minX, y: notch.minY - 6, width: notch.width, height: notch.height + 6)
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        // Above the menu bar, so clicks in the notch reach us. Below DynamicNotchKit's own window.
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

        let view = SensorView(frame: NSRect(origin: .zero, size: frame.size))
        view.sensor = self
        panel.contentView = view
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
        self.panel = panel
    }

    fileprivate func clicked() { onClick() }
    fileprivate func dropped(_ things: [DroppedThing]) { onDrop(things) }
    fileprivate func menu() -> NSMenu? { menuProvider() }
}

private final class SensorView: NSView {
    weak var sensor: NotchSensor?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.URL, .fileURL, .string, .tiff, .png])
    }

    required init?(coder: NSCoder) {
        fatalError("not used")
    }

    // macOS sends clicks straight through pixels that are completely transparent. A fill this faint is
    // invisible (and the notch hides those pixels anyway) but it is enough for the window to get the click.
    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.01).setFill()
        bounds.fill()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        sensor?.clicked()
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let menu = sensor?.menu() else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let board = sender.draggingPasteboard
        var things = [DroppedThing]()

        if let urls = board.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
            for url in urls {
                things.append(url.isFileURL ? .file(url) : .link(url))
            }
        }
        if things.isEmpty, let images = board.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage], let image = images.first {
            things.append(.image(image))
        }
        if things.isEmpty, let text = board.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            if let url = URL(string: text), let scheme = url.scheme, scheme == "http" || scheme == "https" {
                things.append(.link(url))
            } else {
                things.append(.text(text))
            }
        }
        guard !things.isEmpty else { return false }
        sensor?.dropped(things)
        return true
    }
}
