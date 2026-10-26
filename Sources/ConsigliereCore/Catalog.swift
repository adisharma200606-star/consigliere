import Foundation

/// What kind of thing a catalog entry opens.
public enum EntryKind: String, Codable, Equatable, Sendable {
    case site
    case app
    case path
    /// Something built into Consigliere itself, like the tuner. `target` names the tool.
    case tool
}

/// One thing Consigliere can open. Adding a thing to the app means adding one of these to the config.
public struct CatalogEntry: Codable, Equatable, Sendable {
    /// The name that is matched against. Lowercase by convention ("youtube", "vs code").
    public var name: String
    /// How the name is shown on screen ("YouTube"). Falls back to `name`.
    public var display: String?
    /// Other things he might type or say for it ("yt").
    public var aliases: [String]
    public var kind: EntryKind
    /// A URL for sites, a bundle identifier for apps, a file path for paths, a tool name for tools.
    public var target: String
    /// Which Brave profile a site opens in: "personal" or "work". Sites only.
    public var profile: String?
    /// When present, typing the name followed by more words searches the site. "{q}" is replaced by the query.
    public var searchTemplate: String?
    /// True for tools that accept more words after (or before) their name: "timer 10", "10 min timer".
    public var takesWords: Bool
    /// True for bookmarks that remember where he left off. Only living entries are ever moved by the
    /// "remember where I am" hotkey, so "youtube" is never overwritten by a video.
    public var living: Bool

    public init(name: String, display: String? = nil, aliases: [String] = [], kind: EntryKind, target: String,
                profile: String? = nil, searchTemplate: String? = nil, takesWords: Bool = false, living: Bool = false) {
        self.name = name
        self.display = display
        self.aliases = aliases
        self.kind = kind
        self.target = target
        self.profile = profile
        self.searchTemplate = searchTemplate
        self.takesWords = takesWords
        self.living = living
    }

    private enum CodingKeys: String, CodingKey {
        case name, display, aliases, kind, target, profile, searchTemplate, takesWords, living
    }

    // Hand-written so that a config entry may leave `aliases` out.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        display = try c.decodeIfPresent(String.self, forKey: .display)
        aliases = try c.decodeIfPresent([String].self, forKey: .aliases) ?? []
        kind = try c.decode(EntryKind.self, forKey: .kind)
        target = try c.decode(String.self, forKey: .target)
        profile = try c.decodeIfPresent(String.self, forKey: .profile)
        searchTemplate = try c.decodeIfPresent(String.self, forKey: .searchTemplate)
        takesWords = try c.decodeIfPresent(Bool.self, forKey: .takesWords) ?? false
        living = try c.decodeIfPresent(Bool.self, forKey: .living) ?? false
    }

    // Hand-written so that the two flags are only written to config.json when they are switched on.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(display, forKey: .display)
        try c.encode(aliases, forKey: .aliases)
        try c.encode(kind, forKey: .kind)
        try c.encode(target, forKey: .target)
        try c.encodeIfPresent(profile, forKey: .profile)
        try c.encodeIfPresent(searchTemplate, forKey: .searchTemplate)
        if takesWords { try c.encode(true, forKey: .takesWords) }
        if living { try c.encode(true, forKey: .living) }
    }

    /// The name to show on screen.
    public var shownName: String {
        return display ?? name
    }

    /// Every string this entry can be matched by: its name, then its aliases.
    public var keys: [String] {
        return [name] + aliases
    }
}
