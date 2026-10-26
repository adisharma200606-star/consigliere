import AppKit
import ConsigliereCore
import DynamicNotchKit
import SwiftUI

/// Opens and closes the notch. A thin wrapper around DynamicNotchKit that adds the three things a launcher
/// needs and the library does not do by itself: taking the keyboard at once, closing on Escape or a click
/// elsewhere, and moving the selection with the arrow keys.
@MainActor
final class NotchController {
    private let model: NotchModel
    private let notch: DynamicNotch<NotchRootView, CompactLeadingView, CompactTrailingView>
    private var keyMonitor: Any?
    private var clickMonitor: Any?

    private(set) var isOpen = false
    /// Called when the person dismisses the notch themselves (Escape, or a click somewhere else).
    var onDismiss: () -> Void = {}
    /// Called on Return/Enter while the box is open. Handled here, in the same reliable local key
    /// monitor as Escape and the arrow keys, rather than relying only on SwiftUI's TextField `.onSubmit` —
    /// a real case existed where Return stopped reaching that callback (remote input via iPhone Mirroring)
    /// while every other key kept working fine through this monitor.
    var onEnter: () -> Void = {}

    init(model: NotchModel) {
        self.model = model
        // Hover behaviour is left empty on purpose. The library's "keep visible while hovering" would hold the
        // notch open after an action if the pointer happened to be resting near the top of the screen.
        notch = DynamicNotch(hoverBehavior: [], style: .auto) {
            NotchRootView(model: model)
        } compactLeading: {
            CompactLeadingView(model: model)
        } compactTrailing: {
            CompactTrailingView(model: model)
        }
        apply(model.theme)
        installMonitors()
    }

    /// Pushes the look into the notch: the spring from the config, and the glow.
    func apply(_ theme: NotchTheme) {
        notch.transitionConfiguration = DynamicNotchTransitionConfiguration(
            openingAnimation: theme.spring,
            closingAnimation: .smooth(duration: 0.3),
            conversionAnimation: theme.spring,
            skipIntermediateHides: true
        )
        notch.glowColors = theme.glowColors
        notch.glowStrength = theme.glowStrength
        notch.rimColor = theme.accent.opacity(0.85)
        notch.grainImage = theme.grain > 0 ? NotchTheme.grainImage : nil
        notch.grainOpacity = theme.grain
    }

    /// The screen with the notch if there is one, then the laptop's own screen, then the main screen.
    /// The middle step matters with "one eighty" and an HDMI screen plugged in: upside down, the laptop
    /// screen's notch is at the bottom, so macOS stops reporting a notch at the top, and without this the
    /// box would jump to the HDMI screen (usually "main") instead of staying where you are looking.
    static var preferredScreen: NSScreen {
        if let notched = NSScreen.screens.first(where: { $0.consigliereNotchFrame != nil }) { return notched }
        if let builtIn = NSScreen.screens.first(where: { $0.consigliereIsBuiltIn }) { return builtIn }
        return NSScreen.main ?? NSScreen.screens[0]
    }

    /// Opens the notch. `takeKeyboard` is true for the box, false for a line that only needs to be read.
    func open(takeKeyboard: Bool) {
        isOpen = true
        let screen = NotchController.preferredScreen
        Task { await notch.expand(on: screen) }
        guard takeKeyboard else { return }

        // `expand` only returns after its animation. The window exists long before that, so take the
        // keyboard as soon as it appears instead of waiting: typing must work from the first moment.
        Task { @MainActor in
            for _ in 0..<40 {
                if let window = notch.windowController?.window {
                    window.makeKey()
                    model.focusToken += 1
                    return
                }
                try? await Task.sleep(nanoseconds: 10_000_000)
            }
        }
    }

    /// Closes the notch. While a timer is running it shrinks to the compact form, which shows the time left.
    func close() {
        isOpen = false
        let screen = NotchController.preferredScreen
        // The small timer beside the notch only exists on a screen with a notch (for example, not while the
        // screen is flipped upside down). The same place shows his head when a job is waiting.
        let showCompact = (model.timerText != nil || model.jobWaiting) && screen.consigliereNotchFrame != nil
        Task {
            if showCompact {
                await notch.compact(on: screen)
            } else {
                await notch.hide()
            }
        }
    }

    /// While closed, switches between nothing and the small form beside the notch, when what it shows changes.
    func refreshClosed() {
        if !isOpen { close() }
    }

    private func installMonitors() {
        // Keys pressed while our panel has the keyboard.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.isOpen else { return event }
            switch event.keyCode {
            case 53:    // Escape
                self.onDismiss()
                return nil
            case 36, 76:  // Return, and the numeric-keypad Enter. On the jobs list it adds what was typed.
                if self.model.screen == .input || self.model.screen == .jobs {
                    self.onEnter()
                    return nil
                }
                return event
            case 125:   // down arrow
                if self.model.screen == .input { self.model.moveSelection(1); return nil }
                return event
            case 126:   // up arrow
                if self.model.screen == .input { self.model.moveSelection(-1); return nil }
                return event
            default:
                return event
            }
        }
        // A click anywhere outside our own windows. Global monitors only ever see other apps' events.
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, self.isOpen else { return }
                self.onDismiss()
            }
        }
    }
}

extension NSScreen {
    /// True for the laptop's own screen.
    var consigliereIsBuiltIn: Bool {
        guard let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
        return CGDisplayIsBuiltin(CGDirectDisplayID(number.uint32Value)) != 0
    }

    /// The rectangle of the physical notch in screen coordinates, or nil on a screen without one.
    /// (DynamicNotchKit has the same calculation, but keeps it private.)
    var consigliereNotchFrame: NSRect? {
        guard let left = auxiliaryTopLeftArea?.width, let right = auxiliaryTopRightArea?.width else { return nil }
        let height = safeAreaInsets.top
        let width = frame.width - left - right
        guard width > 0, height > 0 else { return nil }
        return NSRect(x: frame.midX - width / 2, y: frame.maxY - height, width: width, height: height)
    }
}
