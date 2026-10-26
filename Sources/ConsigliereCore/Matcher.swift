import Foundation

/// How well a query matched an entry, best first. Ported from `reference-js/core.js`.
/// "Strong" bands are safe to act on from speech without a confirming key press.
public enum Band: Int, Comparable, Equatable {
    case unranked = 0      // not matched at all; used for the "most used" list
    case edit = 1          // "utube" -> "youtube"
    case prefixEdit = 2    // "youto" -> "youtube" (speech mishearing)
    case subsequence = 3   // "ytb" -> "youtube" (same first letter required)
    case acronym = 4       // "vsc" -> "visual studio code"
    case wordPrefix = 5    // "code" -> "vs code"
    case prefix = 6        // "you" -> "youtube"
    case exact = 7         // "yt" == alias "yt"

    public static func < (lhs: Band, rhs: Band) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }

    /// The name used in the golden fixtures.
    public var name: String {
        switch self {
        case .unranked: return "none"
        case .edit: return "edit"
        case .prefixEdit: return "prefixEdit"
        case .subsequence: return "subsequence"
        case .acronym: return "acronym"
        case .wordPrefix: return "wordPrefix"
        case .prefix: return "prefix"
        case .exact: return "exact"
        }
    }

    /// From this band upwards a match is trusted without confirmation.
    public static let strongFrom: Band = .acronym
}

/// One ranked result.
public struct Hit: Equatable {
    public let entry: CatalogEntry
    public let band: Band
    public let quality: Double
    public let usage: Int

    public init(entry: CatalogEntry, band: Band, quality: Double, usage: Int) {
        self.entry = entry
        self.band = band
        self.quality = quality
        self.usage = usage
    }
}

public enum MatchMode: String, Equatable {
    /// Nothing typed. Results are the most used things.
    case empty
    /// Results are ranked. The first one is what Enter opens.
    case open
    /// The first word or two named a searchable site (or a tool that takes words). `query` holds the rest.
    case search
    /// It reads like a question. `query` holds the question and there are no results.
    case ask
    /// Nothing matched.
    case nothing = "none"
}

/// The answer to "what did he mean by this text?".
public struct Decision: Equatable {
    public let mode: MatchMode
    public let results: [Hit]
    public let query: String?
    /// True when it is safe to act without a confirming Enter or tap. Speech must check this.
    public let confident: Bool

    public init(mode: MatchMode, results: [Hit], query: String?, confident: Bool) {
        self.mode = mode
        self.results = results
        self.query = query
        self.confident = confident
    }
}

public enum Matcher {

    /// Words people say or type around the name of a thing. They carry no meaning here, so they are
    /// dropped before matching. This is what lets "play me some youtube" work without a command language.
    public static let filler: [String] = [
        "open", "launch", "start", "run", "go", "goto", "to", "play", "me", "some", "the",
        "my", "show", "please", "hey", "yo", "consigliere", "up", "a", "set"
    ]

    /// The box works like a browser's address bar: a name opens the thing, anything that reads like a
    /// question gets asked. These are the words a question starts with.
    public static let questionWords: [String] = [
        "how", "what", "whats", "why", "who", "whos", "when", "where", "which", "is", "are", "can", "could",
        "does", "do", "did", "should", "would", "explain", "define", "meaning", "tell"
    ]

    private static func askDecision(_ text: String, confident: Bool) -> Decision {
        var question = Substring(text)
        while let first = question.first, first == "?" || first.isWhitespace {
            question = question.dropFirst()
        }
        let cleaned = String(question).trimmingCharacters(in: .whitespacesAndNewlines)
        return Decision(mode: .ask, results: [], query: cleaned, confident: confident)
    }

    private struct Score {
        let band: Band
        let quality: Double
    }

    /// Score one normalised query against one raw key (a name or an alias).
    private static func scoreKey(_ q: String, _ rawKey: String) -> Score? {
        let key = TextTools.normalize(rawKey)
        if q.isEmpty || key.isEmpty { return nil }
        let qLen = q.utf8.count
        let keyLen = key.utf8.count

        if q == key { return Score(band: .exact, quality: 1) }
        if key.hasPrefix(q) { return Score(band: .prefix, quality: Double(qLen) / Double(keyLen)) }

        let ws = TextTools.words(rawKey)
        if qLen >= 2 && ws.count >= 2 {
            for w in ws.dropFirst() where w.hasPrefix(q) {
                return Score(band: .wordPrefix, quality: Double(qLen) / Double(w.utf8.count))
            }
            let acronym = String(ws.compactMap { $0.first })
            if acronym.hasPrefix(q) {
                return Score(band: .acronym, quality: Double(qLen) / Double(acronym.utf8.count))
            }
        }

        if qLen >= 2, let qFirst = q.utf8.first, let keyFirst = key.utf8.first, qFirst == keyFirst {
            if let span = TextTools.subsequenceSpan(q, in: key), span > 0 {
                return Score(band: .subsequence, quality: Double(qLen) / Double(span))
            }
        }

        if qLen >= 4 {
            let head = String(decoding: Array(key.utf8.prefix(qLen)), as: UTF8.self)
            let prefixDistance = TextTools.editDistance(q, head)
            let prefixMax = qLen >= 6 ? 2 : 1
            if prefixDistance <= prefixMax {
                return Score(band: .prefixEdit, quality: -Double(prefixDistance))
            }
            let distance = TextTools.editDistance(q, key)
            let distanceMax = keyLen <= 5 ? 1 : 2
            if distance <= distanceMax {
                return Score(band: .edit, quality: -Double(distance))
            }
        }
        return nil
    }

    /// Best score for an entry across its name and aliases.
    private static func scoreEntry(_ q: String, _ entry: CatalogEntry) -> Score? {
        var best: Score? = nil
        for key in entry.keys {
            guard let s = scoreKey(q, key) else { continue }
            if let b = best {
                if s.band > b.band || (s.band == b.band && s.quality > b.quality) { best = s }
            } else {
                best = s
            }
        }
        return best
    }

    /// Rank the catalog for a normalised query.
    /// Order: band, then how often he opens it, then match quality, then name.
    /// "Within the same match quality, the thing you open most wins."
    public static func rank(_ q: String, catalog: [CatalogEntry], usage: [String: Int]) -> [Hit] {
        var hits = [Hit]()
        for entry in catalog {
            if let s = scoreEntry(q, entry) {
                hits.append(Hit(entry: entry, band: s.band, quality: s.quality, usage: usage[entry.name] ?? 0))
            }
        }
        hits.sort { a, b in
            if a.band != b.band { return a.band > b.band }
            if a.usage != b.usage { return a.usage > b.usage }
            if a.quality != b.quality { return a.quality > b.quality }
            return a.entry.name < b.entry.name
        }
        return hits
    }

    /// Every entry, most used first. Things never used keep the order they have in the catalog.
    public static func mostUsed(catalog: [CatalogEntry], usage: [String: Int]) -> [Hit] {
        let indexed = catalog.enumerated().map { (index: $0.offset, hit: Hit(entry: $0.element, band: .unranked, quality: 0, usage: usage[$0.element.name] ?? 0)) }
        let sorted = indexed.sorted { a, b in
            if a.hit.usage != b.hit.usage { return a.hit.usage > b.hit.usage }
            return a.index < b.index
        }
        return sorted.map { $0.hit }
    }

    /// Entries that accept more words around their name: searchable sites ("yt berserk amv") and tools that
    /// take words ("timer 10"). `toolsOnly` is used for the trailing form ("10 min timer").
    private static func exactEntryWithSearch(_ head: String, catalog: [CatalogEntry], toolsOnly: Bool = false) -> CatalogEntry? {
        for entry in catalog {
            let takes = toolsOnly ? (entry.kind == .tool && entry.takesWords) : (entry.searchTemplate != nil || entry.takesWords)
            if !takes { continue }
            for key in entry.keys where TextTools.normalize(key) == head {
                return entry
            }
        }
        return nil
    }

    private static func stripLeadingFiller(_ tokens: [String]) -> [String] {
        var i = 0
        while i < tokens.count && filler.contains(TextTools.normalize(tokens[i])) {
            i += 1
        }
        return i == tokens.count ? tokens : Array(tokens[i...])
    }

    /// The one entry point. Raw text in (typed or spoken), decision out.
    ///
    /// Steps, in order:
    ///  1. drop leading filler words
    ///  2. the whole input is an exact name or alias: open
    ///  3. the first two or one words exactly name a searchable site, or a tool that takes words: search
    ///  3b. the last two or one words exactly name a tool that takes words ("10 min timer"): search
    ///  4. the whole input ranks strongly: open
    ///  5. a shorter run of leading words ranks strongly: open ("gmail inbox")
    ///  6. the whole input ranks weakly: open, not confident
    ///  7. several words that match nothing: ask, not confident
    ///  8. otherwise: nothing
    /// Before all of that: a question mark at either end means ask, and after step 3b so does a leading question word.
    public static func match(_ input: String, catalog: [CatalogEntry], usage: [String: Int] = [:], limit: Int = 4) -> Decision {
        if TextTools.normalize(input).isEmpty {
            let top = Array(mostUsed(catalog: catalog, usage: usage).prefix(limit))
            return Decision(mode: .empty, results: top, query: nil, confident: false)
        }

        // A question mark always means "ask".
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasSuffix("?") || trimmed.hasPrefix("?") {
            return askDecision(trimmed, confident: true)
        }

        let rawTokens = input.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let tokens = stripLeadingFiller(rawTokens)
        let whole = TextTools.normalize(tokens.joined())

        let ranked = rank(whole, catalog: catalog, usage: usage)
        if let first = ranked.first, first.band == .exact {
            return Decision(mode: .open, results: Array(ranked.prefix(limit)), query: nil, confident: true)
        }

        if tokens.count >= 2 {
            let maxHead = Swift.min(2, tokens.count - 1)
            var k = maxHead
            while k >= 1 {
                let head = TextTools.normalize(tokens[0..<k].joined())
                if let entry = exactEntryWithSearch(head, catalog: catalog) {
                    let hit = Hit(entry: entry, band: .exact, quality: 1, usage: usage[entry.name] ?? 0)
                    let query = tokens[k...].joined(separator: " ")
                    return Decision(mode: .search, results: [hit], query: query, confident: true)
                }
                k -= 1
            }
        }

        // The same, the other way round, for tools only: "10 min timer".
        if tokens.count >= 2 {
            var t = Swift.min(2, tokens.count - 1)
            while t >= 1 {
                let tail = TextTools.normalize(tokens[(tokens.count - t)...].joined())
                if let tool = exactEntryWithSearch(tail, catalog: catalog, toolsOnly: true) {
                    let hit = Hit(entry: tool, band: .exact, quality: 1, usage: usage[tool.name] ?? 0)
                    let query = tokens[0..<(tokens.count - t)].joined(separator: " ")
                    return Decision(mode: .search, results: [hit], query: query, confident: true)
                }
                t -= 1
            }
        }

        // "play beabadoobee": "play" is a filler word, so "play me some youtube" still opens YouTube. Only when what
        // follows is not strongly one of his things does it go to the music tool, before it could be read as a question.
        if rawTokens.count >= 2, TextTools.normalize(rawTokens[0]) == "play", tokens.count < rawTokens.count,
           let music = catalog.first(where: { $0.kind == .tool && $0.target == "music" && $0.takesWords }) {
            let strong = ranked.first.map { $0.band >= Band.strongFrom } ?? false
            if !strong {
                let hit = Hit(entry: music, band: .exact, quality: 1, usage: usage[music.name] ?? 0)
                return Decision(mode: .search, results: [hit], query: tokens.joined(separator: " "), confident: true)
            }
        }

        // It starts like a question and is more than one word: ask.
        if tokens.count >= 2 && questionWords.contains(TextTools.normalize(tokens[0])) {
            return askDecision(tokens.joined(separator: " "), confident: true)
        }

        if let first = ranked.first, first.band >= Band.strongFrom {
            return Decision(mode: .open, results: Array(ranked.prefix(limit)), query: nil, confident: true)
        }

        if tokens.count >= 2 {
            var n = tokens.count - 1
            while n >= 1 {
                let partial = rank(TextTools.normalize(tokens[0..<n].joined()), catalog: catalog, usage: usage)
                if let first = partial.first, first.band >= Band.strongFrom {
                    return Decision(mode: .open, results: Array(partial.prefix(limit)), query: nil, confident: true)
                }
                n -= 1
            }
        }

        if !ranked.isEmpty {
            return Decision(mode: .open, results: Array(ranked.prefix(limit)), query: nil, confident: false)
        }
        // Several words that match nothing are a question, not an error.
        if tokens.count >= 2 {
            return askDecision(tokens.joined(separator: " "), confident: false)
        }
        return Decision(mode: .nothing, results: [], query: nil, confident: false)
    }
}
