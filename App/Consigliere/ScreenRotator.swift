import AppKit
import ConsigliereCore
import CoreGraphics
import Darwin
import RotationBridge

/// Turns the screen upside down and back ("one eighty").
///
/// The private-API calls live in `RotationBridge` (Objective-C; see `App/RotationBridge/.../RotationBridge.m`
/// for why it is not Swift). This file decides which screen, which direction, and — the important part —
/// checks that the screen *actually* turned before calling it done.
///
/// Why the checking matters: every way of asking macOS to rotate a screen can come back "fine" while
/// nothing happens. That is exactly what went wrong with an HDMI screen plugged in: one way of asking
/// works with only the built-in screen, and is quietly ignored once a second screen joins. So this asks
/// one way, watches what macOS itself reports (`CGDisplayRotation`, a public and honest reading), and only
/// if the screen has not moved does it try the next way. Asking again is harmless: each request names the
/// exact angle wanted ("be at 180"), not "turn by 180", so a late-arriving earlier request cannot undo it.
///
/// Every attempt is written to `~/.consigliere/flip.log` (overwritten each time), so if a future macOS
/// breaks this, one `cat` shows which ways were tried and what macOS said.
@MainActor
enum ScreenRotator {

    enum Outcome {
        case rotated(to: Int)
        case failed(String)
        /// A flip is already in progress (the screen can take a second or two to turn).
        case busy
    }

    private static var isBusy = false

    // MARK: - Which screen

    static func onlineDisplays() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return [] }
        return Array(ids.prefix(Int(count)))
    }

    /// The laptop's own screen when it is on (lid open), otherwise the main screen (lid closed, so the
    /// only thing to look at is the external one).
    ///
    /// With the lid closed macOS usually drops the built-in screen from the list altogether; when it
    /// still lists it, it is neither active (drawn to) nor part of a mirror pair, so it is skipped. (A
    /// mirrored laptop screen can also report "not active", because macOS only draws to the primary of a
    /// pair, which is why mirroring counts as "on".)
    static var targetDisplay: CGDirectDisplayID {
        let builtIn = onlineDisplays().first {
            CGDisplayIsBuiltin($0) != 0 && (CGDisplayIsActive($0) != 0 || CGDisplayIsInMirrorSet($0) != 0)
        }
        return builtIn ?? CGMainDisplayID()
    }

    /// The current rotation in whole degrees: 0, 90, 180 or 270.
    static func currentRotation(of display: CGDirectDisplayID) -> Int {
        let degrees = Int(CGDisplayRotation(display).rounded()) % 360
        return (degrees + 360) % 360
    }

    // MARK: - Flipping

    /// Upside down if it is upright, upright if it is anything else.
    static func toggleOneEighty() async -> Outcome {
        guard !isBusy else { return .busy }
        isBusy = true
        defer { isBusy = false }

        let display = targetDisplay
        let target = currentRotation(of: display) == 180 ? 0 : 180
        var log = Report()
        log.add("flip: \(describe(display)) is at \(currentRotation(of: display))°, want \(target)°")
        for other in onlineDisplays() where other != display { log.add("also connected: \(describe(other))") }

        // The ways to ask, in order. Each is (which display to ask about, which method).
        var attempts: [(CGDirectDisplayID, Int32)] = [(display, 0), (display, 1), (display, 2)]

        // Mirroring (the same picture on the laptop and the HDMI screen): macOS treats the pair as one
        // screen whose settings belong to the "primary" of the two. If that is the other screen, asking
        // about the laptop alone may be ignored, so as a last resort ask about the primary instead —
        // and if that turns only the HDMI screen and not the laptop, put the HDMI screen back.
        let mirrored = CGDisplayIsInMirrorSet(display) != 0
        let primary = CGDisplayPrimaryDisplay(display)
        if mirrored && primary != display && primary != 0 {
            log.add("mirroring is on; the primary of the pair is \(describe(primary))")
            attempts += [(primary, 0), (primary, 1)]
        }

        for (asked, method) in attempts {
            let askedBefore = currentRotation(of: asked)
            var errorPointer: UnsafeMutablePointer<CChar>?
            let result = ConsigliereRotate(asked, Int32(target), method, &errorPointer)
            let problem = errorPointer.map { String(cString: $0) }
            if let errorPointer = errorPointer { free(errorPointer) }

            let label = "method \(method) on display \(asked)"
            if result != 0 {
                log.add("\(label): refused (\(problem ?? "code \(result)"))")
                continue
            }
            if await waitUntil(display, isAt: target, seconds: 2.0) {
                log.add("\(label): worked, now at \(currentRotation(of: display))°")
                log.save()
                return .rotated(to: target)
            }
            log.add("\(label): accepted, but the screen did not move (still \(currentRotation(of: display))°)")

            // Asked about the other screen of a mirror pair, and it alone turned: undo that.
            if asked != display && currentRotation(of: asked) != askedBefore {
                _ = ConsigliereRotate(asked, Int32(askedBefore), 0, nil)
                log.add("put display \(asked) back to \(askedBefore)°")
            }
        }

        // One last look: with two screens connected macOS can take a while to reconfigure both, and the
        // first request may simply have landed late.
        if await waitUntil(display, isAt: target, seconds: 1.5) {
            log.add("worked late, now at \(target)°")
            log.save()
            return .rotated(to: target)
        }

        log.add("gave up")
        log.save()
        let canRotate = ConsigliereCanRotate(display)
        if mirrored {
            return .failed("macOS won't turn a mirrored screen. Set the HDMI screen to Extended display, then 180 again")
        }
        if canRotate == 0 {
            return .failed("macOS says this screen can't be turned right now")
        }
        return .failed("macOS ignored every way of asking. Details: ~/.consigliere/flip.log")
    }

    /// Polls macOS's own reading of the rotation until it matches, or time runs out.
    private static func waitUntil(_ display: CGDirectDisplayID, isAt degrees: Int, seconds: Double) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if currentRotation(of: display) == degrees { return true }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return currentRotation(of: display) == degrees
    }

    private static func describe(_ display: CGDirectDisplayID) -> String {
        var traits: [String] = []
        traits.append(CGDisplayIsBuiltin(display) != 0 ? "built-in" : "external")
        if CGDisplayIsMain(display) != 0 { traits.append("main") }
        if CGDisplayIsActive(display) == 0 { traits.append("switched off") }
        if CGDisplayIsInMirrorSet(display) != 0 { traits.append("mirrored") }
        traits.append("at \(currentRotation(of: display))°")
        let canRotate = ConsigliereCanRotate(display)
        traits.append(canRotate == 1 ? "can rotate" : canRotate == 0 ? "says it cannot rotate" : "rotation unknown")
        return "display \(display) (\(traits.joined(separator: ", ")))"
    }

    /// The lines of one flip attempt: sent to the system log as they happen, and saved to
    /// ~/.consigliere/flip.log at the end.
    private struct Report {
        private var lines: [String] = []

        mutating func add(_ line: String) {
            NSLog("Consigliere: [rotate] \(line)")
            lines.append(line)
        }

        func save() {
            let url = ConsiglierePaths.configDirectory.appendingPathComponent("flip.log")
            let stamp = ISO8601DateFormatter().string(from: Date())
            let text = ([stamp] + lines).joined(separator: "\n") + "\n"
            try? text.data(using: .utf8)?.write(to: url)
        }
    }
}
