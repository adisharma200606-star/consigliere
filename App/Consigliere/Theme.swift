import AppKit
import ConsigliereCore
import CoreText
import SwiftUI

/// The look, "Nocturne, liner notes", turned from config values into things SwiftUI can use.
///
/// The idea: the back of a CD booklet at night. Thin Helvetica Neue for what matters, lowercase, small
/// monospaced labels for everything else, hairline rules instead of boxes, one steel-blue accent, a line of
/// light along the notch's bottom edge and a little film grain. Nothing tilted, nothing handwritten.
struct NotchTheme: Equatable {
    var accent: Color
    var glowColors: [Color]
    var glowStrength: Double
    var grain: Double
    var textSize: CGFloat
    var caretPulse: Double
    var stiffness: Double
    var damping: Double

    /// The line he says. Same as the accent in this look.
    var tint: Color { accent }

    /// The same spring as the phone prototype: mass 1, and the two numbers from the config.
    var spring: Animation {
        return .interpolatingSpring(mass: 1, stiffness: stiffness, damping: damping, initialVelocity: 0)
    }

    // The ink. Named for what they are used for, so the views read plainly.
    static let text = Color(red: 0.945, green: 0.957, blue: 0.976)         // #F1F4F9, what matters
    static let secondary = Color(red: 0.435, green: 0.486, blue: 0.573)    // #6F7C92, labels
    static let faint = Color(red: 0.373, green: 0.420, blue: 0.502)        // #5F6B80, the quietest labels
    static let hairline = Color(red: 0.90, green: 0.92, blue: 0.95).opacity(0.10)
    static let dim = secondary

    // Kept for the tuner: a string that is off reads pale, one that is in tune reads bright.
    static var off: Color { secondary }
    static let ok = Color.white
    static let row = Color.white.opacity(0.06)

    init(_ theme: Theme) {
        let a = theme.look.accentRGB
        accent = Color(red: a.red, green: a.green, blue: a.blue)
        glowColors = theme.look.glowRGB.map { Color(red: $0.red, green: $0.green, blue: $0.blue) }
        glowStrength = theme.look.glowStrength
        grain = max(0, min(1, theme.look.grain))
        textSize = CGFloat(theme.look.textSize)
        caretPulse = max(0.15, theme.look.caretBlinkMs / 1000)
        stiffness = theme.motion.stiffness
        damping = theme.motion.damping
    }

    /// Helvetica Neue ships with every Mac. These are its PostScript names.
    func font(_ size: CGFloat, _ weight: HelveticaWeight = .regular) -> Font {
        return .custom(weight.rawValue, size: size)
    }

    /// The small labels: IBM Plex Mono, bundled with the app. Falls back to the system's monospaced font.
    func mono(_ size: CGFloat, medium: Bool = false) -> Font {
        let name = medium ? "IBMPlexMono-Medium" : "IBMPlexMono-Regular"
        if NSFont(name: name, size: size) != nil { return .custom(name, size: size) }
        return .system(size: size, weight: medium ? .medium : .regular, design: .monospaced)
    }

    enum HelveticaWeight: String {
        case ultraLight = "HelveticaNeue-UltraLight"
        case thin = "HelveticaNeue-Thin"
        case light = "HelveticaNeue-Light"
        case regular = "HelveticaNeue"
        case medium = "HelveticaNeue-Medium"
        case bold = "HelveticaNeue-Bold"
    }

    // MARK: resources

    /// Makes the bundled fonts available to this app. Called once at launch.
    static func registerFonts() {
        for name in ["IBMPlexMono-Regular", "IBMPlexMono-Medium"] {
            let url = Bundle.main.url(forResource: name, withExtension: "ttf")
                ?? Bundle.main.url(forResource: name, withExtension: "ttf", subdirectory: "fonts")
            guard let url = url else {
                NSLog("Consigliere: font \(name).ttf is missing from the app")
                continue
            }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    /// The grain texture, tiled over the open notch.
    static let grainImage: NSImage? = {
        let url = Bundle.main.url(forResource: "grain", withExtension: "png")
            ?? Bundle.main.url(forResource: "grain", withExtension: "png", subdirectory: "textures")
        return url.flatMap { NSImage(contentsOf: $0) }
    }()
}

/// Lowercase, the way everything reads in this look. Apps keep their own capitals in the settings window.
extension String {
    var liner: String { lowercased() }
}
