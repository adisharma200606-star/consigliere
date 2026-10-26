import AppKit
import ConsigliereCore
import SwiftUI

/// The pictures of the character: sitting (idle) and flying.
///
/// Where they come from, first match wins:
///   1. `character.folder` in the config (~/.consigliere/character by default). Either
///        - an animated GIF: idle.gif (and fly.gif if flying looks different), or any one .gif;
///        - or numbered PNGs: idle_0.png, idle_1.png… and fly_0.png, fly_1.png…;
///      A folder with any other pictures in it uses those as the idle frames.
///   2. The little dragon that ships inside the app (scripts/make_sprites.py).
/// Someone else's art (a Dragonite) belongs in the folder, never in the repo.
struct CharacterFrames {
    var idle: [NSImage]
    var fly: [NSImage]
    /// Seconds per frame. A GIF brings its own; numbered PNGs use these defaults.
    var idleInterval = 0.55
    var flyInterval = 0.14
    /// The pictures face left (most game sprites face you, slightly left). The views mirror them to face right.
    var facesLeft = false

    static func load(folder: String, facesLeft: Bool = false) -> CharacterFrames {
        let url = URL(fileURLWithPath: ConsiglierePaths.expandTilde(folder), isDirectory: true)
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? [])
            .filter { name in ["png", "gif"].contains((name as NSString).pathExtension.lowercased()) }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }

        /// The frames in some files, and the GIF's own speed if they came from a GIF.
        func frames(_ list: [String]) -> ([NSImage], Double?) {
            if let gif = list.first(where: { $0.lowercased().hasSuffix(".gif") }) {
                return gifFrames(url.appendingPathComponent(gif)) ?? ([], nil)
            }
            return (list.compactMap { NSImage(contentsOf: url.appendingPathComponent($0)) }, nil)
        }

        var (idle, idleSpeed) = frames(names.filter { $0.lowercased().hasPrefix("idle") })
        let (fly, flySpeed) = frames(names.filter { $0.lowercased().hasPrefix("fly") })
        if idle.isEmpty { (idle, idleSpeed) = frames(names.filter { !$0.lowercased().hasPrefix("fly") }) }
        if idle.isEmpty { return bundled }

        var result = CharacterFrames(idle: idle, fly: fly.isEmpty ? idle : fly, facesLeft: facesLeft)
        if let speed = idleSpeed { result.idleInterval = speed }
        // With no flying pictures, he flies with the idle ones, at the idle ones' own speed if they had one.
        if let speed = flySpeed ?? (fly.isEmpty ? idleSpeed : nil) { result.flyInterval = speed }
        return result
    }

    /// Every frame of an animated GIF, and its average time per frame.
    private static func gifFrames(_ url: URL) -> ([NSImage], Double)? {
        guard let data = try? Data(contentsOf: url), let rep = NSBitmapImageRep(data: data) else { return nil }
        let count = (rep.value(forProperty: .frameCount) as? Int) ?? 1
        var images = [NSImage]()
        var total = 0.0
        for index in 0..<max(1, count) {
            if count > 1 { rep.setProperty(.currentFrame, withValue: index) }
            guard let cg = rep.cgImage else { continue }
            images.append(NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height)))
            total += (rep.value(forProperty: .currentFrameDuration) as? Double) ?? 0.1
        }
        guard !images.isEmpty else { return nil }
        return (images, max(0.03, total / Double(images.count)))
    }

    /// The little dragon. Xcode flattens resources, so they sit at the top of the bundle; the folder is a fallback.
    static let bundled: CharacterFrames = {
        let image: (String) -> NSImage? = { name in
            let url = Bundle.main.url(forResource: name, withExtension: "png")
                ?? Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "character")
            return url.flatMap { NSImage(contentsOf: $0) }
        }
        let idle = ["dragon_idle_0", "dragon_idle_1"].compactMap(image)
        let fly = ["dragon_fly_0", "dragon_fly_1"].compactMap(image)
        if idle.isEmpty { NSLog("Consigliere: the dragon's pictures are missing from the app") }
        return CharacterFrames(idle: idle, fly: fly.isEmpty ? idle : fly)
    }()
}

/// The character, animated. Pixel art stays crisp because it is scaled without smoothing.
struct CharacterView: View {
    let frames: CharacterFrames
    var flying = false
    /// Which way he should face on screen. The pictures are mirrored as needed, whichever way they were drawn.
    var facingLeft = false

    var body: some View {
        let list = flying ? frames.fly : frames.idle
        let interval = flying ? frames.flyInterval : frames.idleInterval
        TimelineView(.periodic(from: .now, by: interval)) { context in
            let index = list.isEmpty ? 0 : Int(context.date.timeIntervalSinceReferenceDate / interval) % list.count
            Group {
                if list.indices.contains(index) {
                    Image(nsImage: list[index])
                        .interpolation(.none)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Color.clear
                }
            }
            .scaleEffect(x: facingLeft != frames.facesLeft ? -1 : 1, y: 1)
        }
    }
}
