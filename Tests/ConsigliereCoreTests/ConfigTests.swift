import Foundation
import XCTest
@testable import ConsigliereCore

final class ConfigTests: XCTestCase {

    func testAMissingFileIsCreatedWithDefaults() throws {
        let url = try temporaryDirectory().appendingPathComponent("config.json")
        let loaded = ConfigStore.load(from: url)
        XCTAssertNil(loaded.problem)
        XCTAssertEqual(loaded.config, Config())
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(ConfigStore.load(from: url).config, Config(), "defaults must survive a round trip through JSON")
    }

    func testAPartialConfigKeepsDefaultsForEverythingElse() throws {
        let url = try temporaryDirectory().appendingPathComponent("config.json")
        let json = """
        {
          "hotkeys": { "open": "ctrl+space" },
          "theme": { "motion": { "stiffness": 400 }, "look": { "glowStrength": 0.3 } },
          "catalog": [ { "name": "reddit", "kind": "site", "target": "https://www.reddit.com" } ]
        }
        """
        try Data(json.utf8).write(to: url)

        let config = ConfigStore.load(from: url).config
        XCTAssertEqual(config.hotkeys.openBox, "ctrl+space")
        XCTAssertEqual(config.hotkeys.talk, Hotkeys().talk)
        XCTAssertEqual(config.theme.motion.stiffness, 400)
        XCTAssertEqual(config.theme.motion.damping, MotionTheme().damping)
        XCTAssertEqual(config.theme.look.accent, LookTheme.nocturneAccent, "no accent means an old config: it moves to Nocturne")
        XCTAssertEqual(config.theme.look.glowColors, LookTheme.nocturneGlow)
        XCTAssertEqual(config.theme.voice, VoiceTheme())
        XCTAssertEqual(config.brave, BraveConfig())
        XCTAssertEqual(config.catalog.count, 1)
        XCTAssertEqual(config.catalog[0].aliases, [])
    }

    func testJobsCharacterAndMusicSettings() throws {
        let json = """
        { "jobs": { "bedtime": "23:45", "dayStart": "nine", "maxLevel": 9, "bindings": { "gym": "youtube" } },
          "character": { "size": 96 } }
        """
        let config = try JSONDecoder().decode(Config.self, from: Data(json.utf8))
        XCTAssertEqual(config.jobs.bedtime, "23:45")
        XCTAssertEqual(config.jobs.cooldownMinutes, JobsConfig().cooldownMinutes)
        XCTAssertEqual(config.jobs.bindings, ["gym": "youtube"])
        XCTAssertEqual(config.jobs.settings.bedtimeMin, 23 * 60 + 45)
        XCTAssertEqual(config.jobs.settings.dayStartMin, JobSettings().dayStartMin, "a time it cannot read falls back")
        XCTAssertEqual(config.jobs.settings.maxLevel, 3, "boldness is capped")
        XCTAssertEqual(config.character.size, 96)
        XCTAssertFalse(config.character.roam)
        XCTAssertEqual(config.music, MusicConfig())
        XCTAssertEqual(JobsConfig().settings, JobSettings(), "the config's defaults and the brain's agree")
    }

    func testABrokenConfigIsLeftAloneAndDefaultsAreUsed() throws {
        let url = try temporaryDirectory().appendingPathComponent("config.json")
        let broken = Data("{ \"hotkeys\": oops".utf8)
        try broken.write(to: url)

        let loaded = ConfigStore.load(from: url)
        XCTAssertEqual(loaded.config, Config())
        XCTAssertNotNil(loaded.problem)
        XCTAssertEqual(try Data(contentsOf: url), broken, "a typo in the config must never wipe it")
    }

    func testColourParsing() {
        XCTAssertEqual(LookTheme.rgb(hex: "#FF0000")?.red, 1)
        XCTAssertEqual(LookTheme.rgb(hex: "#FF0000")?.green, 0)
        XCTAssertEqual(LookTheme.rgb(hex: "00ff00")?.green, 1)
        XCTAssertNil(LookTheme.rgb(hex: "nonsense"))

        let broken = LookTheme(glowColors: ["#00FF00", "nonsense"])
        let rgb = broken.glowRGB
        XCTAssertEqual(rgb.count, 3, "always three colours, whatever the config says")
        XCTAssertEqual(rgb[0].green, 1)
        XCTAssertEqual(rgb[1].red, 0x16 / 255.0, accuracy: 0.001, "an unreadable colour falls back to Nocturne's")
        XCTAssertEqual(rgb[2].blue, 0x22 / 255.0, accuracy: 0.001, "a missing colour falls back to Nocturne's")
        XCTAssertEqual(LookTheme(accent: "junk").accentRGB.red, 0xA9 / 255.0, accuracy: 0.001)
    }

    func testAnOldAuroraConfigMovesToNocturneButANewOneIsKept() throws {
        let old = ##"{ "palette": "aurora", "glowColors": ["#FF375F", "#0A84FF", "#BF5AF2"], "glowStrength": 0.8, "textSize": 21 }"##
        let migrated = try JSONDecoder().decode(LookTheme.self, from: Data(old.utf8))
        XCTAssertEqual(migrated.palette, "nocturne")
        XCTAssertEqual(migrated.glowColors, LookTheme.nocturneGlow)
        XCTAssertEqual(migrated.textSize, 21, "sizes he chose survive the move")

        let chosen = ##"{ "accent": "#FFFFFF", "glowColors": ["#111111", "#222222", "#333333"], "grain": 0 }"##
        let kept = try JSONDecoder().decode(LookTheme.self, from: Data(chosen.utf8))
        XCTAssertEqual(kept.accent, "#FFFFFF")
        XCTAssertEqual(kept.glowColors, ["#111111", "#222222", "#333333"])
        XCTAssertEqual(kept.grain, 0)
    }

    func testFeedbackAgreesWithTheReference() throws {
        struct SpecFixture: Decodable {
            let sound: String?
            let haptic: String?
        }
        let expected = try Fixtures.load([String: SpecFixture].self, "feedback.json")
        XCTAssertEqual(Set(expected.keys), Set(FeedbackEvent.allCases.map { $0.rawValue }), "the same events on both sides")
        for event in FeedbackEvent.allCases {
            let spec = Feedback.spec(for: event)
            XCTAssertEqual(spec.sound, expected[event.rawValue]?.sound, event.rawValue)
            XCTAssertEqual(spec.haptic?.rawValue, expected[event.rawValue]?.haptic, event.rawValue)
        }
    }

    func testProfilesAndTilde() {
        let brave = BraveConfig(personalProfileDir: "Default", workProfileDir: "Profile 2")
        XCTAssertEqual(brave.profileDirectory(for: "work"), "Profile 2")
        XCTAssertEqual(brave.profileDirectory(for: "personal"), "Default")
        XCTAssertEqual(brave.profileDirectory(for: "anything else"), "Default")
        XCTAssertTrue(ConsiglierePaths.expandTilde("~/Downloads").hasSuffix("/Downloads"))
        XCTAssertFalse(ConsiglierePaths.expandTilde("~/Downloads").hasPrefix("~"))
        XCTAssertEqual(ConsiglierePaths.expandTilde("/tmp/x"), "/tmp/x")
    }
}
