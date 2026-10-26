import AppKit
import SwiftUI

/// The character out of the notch: a small window that flies around the screen with him in it.
///
/// He comes out for two reasons:
///   - a job is due (`flyOut`): he wanders silently, bolder each time he is ignored, and a click opens the
///     job card. If nobody clicks him for `roamSeconds`, he flies home and `onGaveUp` runs.
///   - you typed `pet` (`comeOutToPlay`): he wanders around the screen to be played with, and goes home by
///     himself, silently, after a few minutes with nobody touching him.
///
/// Either way you can play with him:
///   rub the mouse over him   hearts, a wiggle, and now and then a line (`onPetted`)
///   drag and let go          he is thrown: tumbles, bounces off the edges, gets dizzy, grumbles (`onThrown`)
///   click (play)             a hop and a heart
///   right-click              the menu from `menuProvider` (Follow me, Fetch, Go home)
///
/// The window is bigger than he is, to leave room for hearts and his speech bubble, but it is transparent
/// there, so every click that misses him lands on whatever is underneath.
@MainActor
final class Roamer {
    var onClick: () -> Void = {}
    var onGaveUp: () -> Void = {}
    var menuProvider: () -> NSMenu? = { nil }
    var onPetted: () -> Void = {}
    var onThrown: () -> Void = {}
    var onFetched: () -> Void = {}
    /// He went home after being left alone while playing. Silent.
    var onPlayOver: () -> Void = {}

    private(set) var isOut = false
    /// Out because of "pet", not because of a job.
    private(set) var isPlaying = false

    private enum Motion {
        /// Following his path (a job's boldness level, or the play wander).
        case path
        case holding(at: CGPoint)
        case dragging
        case thrown
        case dizzy(until: Date)
        case following(until: Date)
        case awaitingFetch(until: Date)
        case fetching(to: CGPoint)
        case returning(since: Date, from: CGPoint, fromScale: CGFloat, then: () -> Void)
    }

    private let look = Look()
    private var panel: NSPanel?
    private var ticker: Timer?
    private var motion = Motion.path
    private var level = 0
    private var size: CGFloat = 64
    private var started = Date()
    private var lastTick = Date()
    private var giveUpAt = Date.distantFuture
    private var lastTouch = Date()
    private var center = CGPoint.zero
    private var scale: CGFloat = 1
    private var velocity = CGVector.zero
    private var grabOffset = CGVector.zero
    private var dragSamples: [(CGPoint, Date)] = []
    private var rubbed: CGFloat = 0
    private var lastPetLine = Date.distantPast
    private var fetchMonitors: [Any] = []

    /// How long he plays with nobody touching him before going home. Short: Adi does not want him lingering.
    private static let playPatience: TimeInterval = 12
    /// The longest he is ever out to play, touched or not. Then home, whatever he is doing.
    private static let playLimit: TimeInterval = 45
    private var playEndsAt = Date.distantFuture

    /// Where he is (his body, not the bigger window), in screen coordinates. The job card goes beside this.
    var frame: NSRect {
        let side = size * scale
        return NSRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side)
    }

    // MARK: out and home

    /// Out about a job.
    func flyOut(level: Int, size: CGFloat, frames: CharacterFrames, roamSeconds: Double) {
        isPlaying = false
        self.level = max(0, min(3, level))
        giveUpAt = Date().addingTimeInterval(max(20, roamSeconds))
        launch(size: size, frames: frames)
    }

    /// Out to play ("pet"). If he is already out playing, he comes over to the cursor.
    func comeOutToPlay(size: CGFloat, frames: CharacterFrames) {
        if isOut && isPlaying {
            touched()
            motion = .following(until: Date().addingTimeInterval(4))
            return
        }
        isPlaying = true
        giveUpAt = .distantFuture
        playEndsAt = Date().addingTimeInterval(Roamer.playLimit)
        launch(size: size, frames: frames)
    }

    private func launch(size: CGFloat, frames: CharacterFrames) {
        self.size = max(24, size)
        look.frames = frames
        look.flying = true
        look.rotation = 0
        started = Date()
        lastTick = Date()
        lastTouch = Date()
        if !isOut {
            center = Roamer.home
            scale = 0.3
        }
        motion = .path
        isOut = true
        makePanel()
        panel?.orderFrontRegardless()
        startTicking()
    }

    /// Stays where he is (while his job card is open).
    func hold() {
        guard isOut else { return }
        motion = .holding(at: center)
        look.flying = false
        giveUpAt = .distantFuture
    }

    /// Back into the notch. `then` runs once he has arrived.
    func goHome(then: @escaping () -> Void = {}) {
        guard isOut else {
            then()
            return
        }
        stopFetchMonitors()
        look.flying = true
        look.rotation = 0
        motion = .returning(since: Date(), from: center, fromScale: scale, then: then)
    }

    /// A short line in a speech bubble above him. The voice is the Brain's business.
    func say(_ text: String) {
        look.bubble = text
        look.bubbleUntil = Date().addingTimeInterval(1.6 + Double(text.count) * 0.05)
    }

    func startFollowing(seconds: TimeInterval = 20) {
        guard isOut else { return }
        touched()
        motion = .following(until: Date().addingTimeInterval(seconds))
    }

    /// The next click anywhere on the screen is where he flies. Gives up after ten seconds.
    func startFetch() {
        guard isOut else { return }
        touched()
        motion = .awaitingFetch(until: Date().addingTimeInterval(10))
        say("click somewhere")
        stopFetchMonitors()
        let handler: (NSEvent) -> Void = { [weak self] _ in
            let point = NSEvent.mouseLocation
            Task { @MainActor in
                guard let self = self, case .awaitingFetch = self.motion else { return }
                self.stopFetchMonitors()
                self.motion = .fetching(to: point)
            }
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown, handler: handler) { fetchMonitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown, handler: { event in handler(event); return event }) {
            fetchMonitors.append(local)
        }
    }

    private var isReturning: Bool {
        if case .returning = motion { return true }
        return false
    }

    private func stopFetchMonitors() {
        fetchMonitors.forEach { NSEvent.removeMonitor($0) }
        fetchMonitors = []
    }

    private func touched() {
        lastTouch = Date()
        if !isPlaying, giveUpAt != .distantFuture { giveUpAt = max(giveUpAt, Date().addingTimeInterval(60)) }
    }

    // MARK: the mouse (called by the window)

    fileprivate func mouseDown(at point: CGPoint) {
        grabOffset = CGVector(dx: center.x - point.x, dy: center.y - point.y)
        dragSamples = [(point, Date())]
    }

    fileprivate func drag(to point: CGPoint) {
        if case .dragging = motion {} else {
            stopFetchMonitors()
            motion = .dragging
            look.flying = true
            touched()
        }
        center = CGPoint(x: point.x + grabOffset.dx, y: point.y + grabOffset.dy)
        dragSamples.append((point, Date()))
        dragSamples = dragSamples.filter { Date().timeIntervalSince($0.1) < 0.12 }
    }

    fileprivate func release() {
        guard case .dragging = motion else { return }
        if let first = dragSamples.first, let last = dragSamples.last, last.1.timeIntervalSince(first.1) > 0.005 {
            let dt = last.1.timeIntervalSince(first.1)
            velocity = CGVector(dx: (last.0.x - first.0.x) / dt, dy: (last.0.y - first.0.y) / dt)
        } else {
            velocity = .zero
        }
        // A gentle let-go is a put-down, not a throw.
        motion = hypot(velocity.dx, velocity.dy) > 250 ? .thrown : .path
    }

    fileprivate func click() {
        touched()
        if isPlaying {
            look.hopAt = Date()
            look.addHeart()
        } else {
            onClick()
        }
    }

    fileprivate func rub(by distance: CGFloat) {
        if case .dragging = motion { return }
        touched()
        rubbed += distance
        guard rubbed > 28 else { return }
        rubbed = 0
        look.addHeart()
        look.wiggleUntil = Date().addingTimeInterval(0.5)
        if Date().timeIntervalSince(lastPetLine) > 6 {
            lastPetLine = Date()
            onPetted()
        }
    }

    fileprivate func menu() -> NSMenu? {
        touched()
        return menuProvider()
    }

    // MARK: the window

    private func makePanel() {
        if panel != nil { return }
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.acceptsMouseMovedEvents = true
        // Above ordinary windows and the menu bar, below the notch sensor and the notch itself.
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]

        let catcher = ClickCatcher(frame: panel.contentLayoutRect)
        catcher.roamer = self
        let host = NSHostingView(rootView: RoamerView(look: look))
        host.frame = catcher.bounds
        host.autoresizingMask = [.width, .height]
        catcher.autoresizingMask = [.width, .height]
        catcher.addSubview(host)
        panel.contentView = catcher
        self.panel = panel
    }

    private func startTicking() {
        ticker?.invalidate()
        // 30 times a second is smooth enough and easy on the battery.
        ticker = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func stop() {
        ticker?.invalidate()
        ticker = nil
        stopFetchMonitors()
        panel?.orderOut(nil)
        isOut = false
        isPlaying = false
    }

    // MARK: moving

    /// Where the notch is: he leaves from here and comes back here.
    private static var home: CGPoint {
        let screen = NotchController.preferredScreen
        if let notch = screen.consigliereNotchFrame { return CGPoint(x: notch.midX, y: notch.midY) }
        return CGPoint(x: screen.frame.midX, y: screen.frame.maxY - 12)
    }

    private var bounds: NSRect {
        return NotchController.preferredScreen.visibleFrame
    }

    /// Where his path wants him at `t` seconds, and how big.
    private func pathTarget(_ t: Double) -> (CGPoint, CGFloat) {
        let f = bounds
        if isPlaying {
            // A lazy wander over the upper two thirds of the screen.
            return (CGPoint(x: f.midX + sin(t * 0.21) * f.width * 0.38, y: f.minY + f.height * 0.6 + sin(t * 0.37) * f.height * 0.2), 1)
        }
        let top = f.maxY - size * 0.75
        switch level {
        case 0:
            return (CGPoint(x: f.midX + sin(t * 0.9) * 40, y: top + sin(t * 3) * 4), 1)
        case 1:
            return (CGPoint(x: f.midX + sin(t * 0.22) * f.width * 0.42, y: top + sin(t * 1.7) * 8), 1)
        case 2:
            return (CGPoint(x: f.midX + sin(t * 0.3) * f.width * 0.4, y: f.maxY - f.height * 0.22 + sin(t * 0.53) * f.height * 0.12), 1.5)
        default:
            // A figure of eight around the middle of the screen.
            return (CGPoint(x: f.midX + sin(t * 0.5) * f.width * 0.28, y: f.midY + sin(t * 1.0) * f.height * 0.2), 2)
        }
    }

    /// Moves towards `goal`: quickly when far, settling as he arrives, never faster than `maxSpeed`.
    private func seek(_ goal: CGPoint, rate: CGFloat, maxSpeed: CGFloat, dt: CGFloat) -> CGPoint {
        var step = CGVector(dx: (goal.x - center.x) * min(1, rate * dt), dy: (goal.y - center.y) * min(1, rate * dt))
        let length = hypot(step.dx, step.dy)
        let limit = maxSpeed * dt
        if length > limit { step = CGVector(dx: step.dx / length * limit, dy: step.dy / length * limit) }
        return CGPoint(x: center.x + step.dx, y: center.y + step.dy)
    }

    private func tick() {
        guard isOut else { return }
        let now = Date()
        let dt = CGFloat(min(0.1, now.timeIntervalSince(lastTick)))
        lastTick = now
        let t = now.timeIntervalSince(started)
        var next = center
        var nextScale = scale

        // Out to play too long, or left alone: home, from any mode (following, fetching, dizzy...).
        if isPlaying, !isReturning, now >= playEndsAt || now.timeIntervalSince(lastTouch) > Roamer.playPatience {
            goHome { [weak self] in self?.onPlayOver() }
        }

        switch motion {
        case .path:
            let (goal, goalScale) = pathTarget(t)
            next = seek(goal, rate: 2.2, maxSpeed: 700, dt: dt)
            nextScale = scale + (goalScale - scale) * min(1, 3 * dt)
            look.flying = true
            if !isPlaying, now >= giveUpAt {
                goHome { [weak self] in self?.onGaveUp() }
            }
        case .holding(let spot):
            next = CGPoint(x: spot.x, y: spot.y + sin(t * 2.5) * 2)
        case .dragging:
            next = center
            nextScale = scale + (1.1 - scale) * min(1, 6 * dt)
        case .thrown:
            next = CGPoint(x: center.x + velocity.dx * dt, y: center.y + velocity.dy * dt)
            let half = size * scale / 2
            let f = bounds
            if next.x < f.minX + half || next.x > f.maxX - half {
                velocity.dx = -velocity.dx * 0.6
                next.x = min(max(next.x, f.minX + half), f.maxX - half)
            }
            if next.y < f.minY + half || next.y > f.maxY - half {
                velocity.dy = -velocity.dy * 0.6
                next.y = min(max(next.y, f.minY + half), f.maxY - half)
            }
            let friction = pow(0.94, 60 * dt)
            velocity = CGVector(dx: velocity.dx * friction, dy: velocity.dy * friction)
            let speed = hypot(velocity.dx, velocity.dy)
            look.rotation += Double(speed * dt * 0.9) * (velocity.dx >= 0 ? 1 : -1)
            if speed < 50 {
                motion = .dizzy(until: now.addingTimeInterval(1.4))
                look.dizzyUntil = now.addingTimeInterval(1.4)
            }
        case .dizzy(let until):
            look.rotation *= Double(pow(0.85, 60 * dt))
            look.flying = false
            if now >= until {
                look.rotation = 0
                motion = .path
                onThrown()
            }
        case .following(let until):
            let mouse = NSEvent.mouseLocation
            let side = size * scale
            // Just above and beside the cursor, so he never sits on what you are pointing at.
            let goal = CGPoint(x: mouse.x + (mouse.x > center.x ? -side * 0.8 : side * 0.8), y: mouse.y + side * 0.5)
            next = seek(goal, rate: 4, maxSpeed: 1100, dt: dt)
            nextScale = scale + (1 - scale) * min(1, 3 * dt)
            if now >= until { motion = .path }
        case .awaitingFetch(let until):
            next = CGPoint(x: center.x, y: center.y + sin(t * 6) * 1.5)
            if now >= until {
                stopFetchMonitors()
                motion = .path
            }
        case .fetching(let spot):
            next = seek(spot, rate: 3.5, maxSpeed: 1200, dt: dt)
            nextScale = scale + (1 - scale) * min(1, 3 * dt)
            if hypot(spot.x - next.x, spot.y - next.y) < 8 {
                look.hopAt = now
                motion = .path
                onFetched()
            }
        case .returning(let since, let from, let fromScale, let then):
            let p = ease(min(1, now.timeIntervalSince(since) / 0.9))
            next = lerp(from, Roamer.home, p)
            nextScale = fromScale + (0.2 - fromScale) * CGFloat(p)
            if p >= 1 {
                stop()
                then()
                return
            }
        }

        if abs(next.x - center.x) > 0.4 { look.facingLeft = next.x < center.x }
        center = next
        scale = nextScale
        layout()
    }

    /// Sizes and places the window around him: his body in the middle, room above for the bubble and hearts.
    private func layout() {
        let side = size * scale
        let margin = max(70, size * 0.9)
        let width = max(240, side + margin * 2)
        let height = side + margin * 2
        if look.side != side { look.side = side }
        if look.margin != margin { look.margin = margin }
        panel?.setFrame(NSRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height), display: true)
    }

    private func ease(_ p: Double) -> Double {
        return p < 0.5 ? 2 * p * p : 1 - pow(-2 * p + 2, 2) / 2
    }

    private func lerp(_ a: CGPoint, _ b: CGPoint, _ p: Double) -> CGPoint {
        return CGPoint(x: a.x + (b.x - a.x) * p, y: a.y + (b.y - a.y) * p)
    }

    /// His body's rectangle inside the window, for the window's own hit testing.
    fileprivate var bodyInWindow: NSRect {
        let side = look.side
        guard let size = panel?.frame.size else { return .zero }
        return NSRect(x: (size.width - side) / 2, y: (size.height - side) / 2, width: side, height: side)
    }
}

// MARK: - What is drawn

/// Everything the view shows. Changed by the Roamer, drawn by `RoamerView`.
private final class Look: ObservableObject {
    struct Heart: Identifiable {
        let id = UUID()
        let born = Date()
        let drift: CGFloat
    }

    @Published var frames = CharacterFrames.bundled
    @Published var flying = true
    @Published var facingLeft = false
    @Published var side: CGFloat = 64
    @Published var margin: CGFloat = 70
    @Published var rotation: Double = 0
    @Published var wiggleUntil = Date.distantPast
    @Published var hopAt = Date.distantPast
    @Published var dizzyUntil = Date.distantPast
    @Published var hearts: [Heart] = []
    @Published var bubble: String? = nil
    @Published var bubbleUntil = Date.distantPast

    func addHeart() {
        hearts = hearts.filter { Date().timeIntervalSince($0.born) < 1.2 }
        hearts.append(Heart(drift: CGFloat.random(in: -18...18)))
    }
}

private struct RoamerView: View {
    @ObservedObject var look: Look

    var body: some View {
        TimelineView(.animation) { context in
            let now = context.date
            let wiggle = now < look.wiggleUntil ? sin(now.timeIntervalSinceReferenceDate * 40) * 6 : 0
            let hopAge = now.timeIntervalSince(look.hopAt)
            let hop = hopAge < 0.35 ? -sin(hopAge / 0.35 * .pi) * 14 : 0

            ZStack {
                CharacterView(frames: look.frames, flying: look.flying, facingLeft: look.facingLeft)
                    .frame(width: look.side, height: look.side)
                    .rotationEffect(.degrees(look.rotation + wiggle))
                    .offset(y: hop)
                    .shadow(color: .black.opacity(0.35), radius: 3, y: -1)

                if now < look.dizzyUntil {
                    DizzyStars(time: now.timeIntervalSinceReferenceDate)
                        .offset(y: -look.side * 0.55)
                }

                ForEach(look.hearts) { heart in
                    let age = now.timeIntervalSince(heart.born)
                    if age < 1.1 {
                        PixelHeart()
                            .frame(width: 14, height: 12)
                            .offset(x: heart.drift + sin(age * 6) * 3, y: -look.side * 0.45 - CGFloat(age) * 46)
                            .opacity(1 - age / 1.1)
                    }
                }

                if let text = look.bubble, now < look.bubbleUntil {
                    SpeechBubble(text: text)
                        .offset(y: -look.side / 2 - 28)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .allowsHitTesting(false)
    }
}

/// A heart drawn as pixels.
private struct PixelHeart: View {
    private static let rows = [
        ".##.##.",
        "#######",
        "#######",
        ".#####.",
        "..###..",
        "...#...",
    ]

    var body: some View {
        Canvas { context, size in
            let cell = min(size.width / 7, size.height / 6)
            for (y, row) in Self.rows.enumerated() {
                for (x, ch) in row.enumerated() where ch == "#" {
                    context.fill(Path(CGRect(x: CGFloat(x) * cell, y: CGFloat(y) * cell, width: cell, height: cell)),
                                 with: .color(Color(red: 1, green: 0.36, blue: 0.48)))
                }
            }
        }
    }
}

/// Three little pixel stars circling his head after he has been thrown.
private struct DizzyStars: View {
    let time: Double

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                let angle = time * 5 + Double(i) * 2.094
                Canvas { context, size in
                    let c = size.width / 3
                    for (x, y) in [(1, 0), (0, 1), (1, 1), (2, 1), (1, 2)] {
                        context.fill(Path(CGRect(x: CGFloat(x) * c, y: CGFloat(y) * c, width: c, height: c)), with: .color(.yellow))
                    }
                }
                .frame(width: 9, height: 9)
                .offset(x: cos(angle) * 18, y: sin(angle) * 5)
            }
        }
    }
}

/// What he says, in a small box above his head: black, a hairline border, monospaced, like the rest of the notch.
private struct SpeechBubble: View {
    let text: String

    var body: some View {
        Text(text.lowercased())
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Rectangle().fill(Color.black))
            .overlay(Rectangle().stroke(Color.white.opacity(0.8), lineWidth: 2))
            .fixedSize()
    }
}

// MARK: - The mouse

/// Takes the clicks, drags and rubs that land on his body. Anything else falls through to the window
/// underneath, because the rest of this window is transparent.
private final class ClickCatcher: NSView {
    weak var roamer: Roamer?
    private var dragged = false
    private var downAt = CGPoint.zero
    private var lastMove: CGPoint?
    private var area: NSTrackingArea?

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let roamer = roamer else { return nil }
        let local = convert(point, from: superview)
        return roamer.bodyInWindow.contains(local) ? self : nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area = area { removeTrackingArea(area) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        self.area = area
    }

    override func mouseDown(with event: NSEvent) {
        dragged = false
        downAt = NSEvent.mouseLocation
        roamer?.mouseDown(at: downAt)
    }

    override func mouseDragged(with event: NSEvent) {
        let point = NSEvent.mouseLocation
        if !dragged && hypot(point.x - downAt.x, point.y - downAt.y) < 4 { return }
        dragged = true
        roamer?.drag(to: point)
    }

    override func mouseUp(with event: NSEvent) {
        if dragged {
            roamer?.release()
        } else {
            roamer?.click()
        }
    }

    override func mouseMoved(with event: NSEvent) {
        let point = NSEvent.mouseLocation
        let local = convert(event.locationInWindow, from: nil)
        defer { lastMove = point }
        guard let roamer = roamer, roamer.bodyInWindow.contains(local), let last = lastMove else { return }
        roamer.rub(by: hypot(point.x - last.x, point.y - last.y))
    }

    override func mouseExited(with event: NSEvent) {
        lastMove = nil
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let menu = roamer?.menu() else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
}
