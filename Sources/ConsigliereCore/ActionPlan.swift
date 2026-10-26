import Foundation

/// A plain description of what the shell should do. The brain decides, the app executes.
public enum ActionPlan: Equatable {
    /// Open a URL in Brave. `profile` is "personal" or "work"; the app maps it to a real profile directory.
    case openURL(url: String, profile: String, entry: String)
    /// Open an app by bundle identifier.
    case openApp(bundleID: String, entry: String)
    /// Open a file or folder. The path may start with "~".
    case openPath(path: String, entry: String)
    /// Show something built into Consigliere in the notch: "tuner" or "timer".
    /// `argument` holds any words typed with the name, so "timer 10" arrives as tool "timer", argument "10".
    case openTool(tool: String, argument: String?, entry: String)
    /// Ask the question and show a short answer in the notch. The only plan that needs the internet.
    case ask(question: String)

    /// The catalog entry name this plan came from. Used to count usage and to pick a line.
    public var entryName: String {
        switch self {
        case .openURL(_, _, let entry): return entry
        case .openApp(_, let entry): return entry
        case .openPath(_, let entry): return entry
        case .openTool(_, _, let entry): return entry
        case .ask: return ""
        }
    }

    /// The line category that fits this plan.
    public var lineCategory: String {
        switch self {
        case .openURL: return "open_site"
        case .openApp: return "open_app"
        case .openPath: return "open_path"
        case .openTool: return "open_tool"
        case .ask: return "explained"
        }
    }

    /// Turn a decision into a plan. Returns nil when there is nothing to do.
    public static func make(from decision: Decision) -> ActionPlan? {
        if decision.mode == .ask {
            guard let question = decision.query, !question.isEmpty else { return nil }
            return .ask(question: question)
        }
        guard let first = decision.results.first else { return nil }
        if decision.mode == .empty || decision.mode == .nothing { return nil }
        let entry = first.entry

        if decision.mode == .search && entry.kind == .tool {
            return .openTool(tool: entry.target, argument: decision.query, entry: entry.name)
        }

        if decision.mode == .search {
            guard let template = entry.searchTemplate else { return nil }
            let encoded = TextTools.encodeQuery(decision.query ?? "")
            var url = template
            if let range = template.range(of: "{q}") {
                url = template.replacingCharacters(in: range, with: encoded)
            }
            return .openURL(url: url, profile: entry.profile ?? "personal", entry: entry.name)
        }

        switch entry.kind {
        case .site: return .openURL(url: entry.target, profile: entry.profile ?? "personal", entry: entry.name)
        case .app: return .openApp(bundleID: entry.target, entry: entry.name)
        case .path: return .openPath(path: entry.target, entry: entry.name)
        case .tool: return .openTool(tool: entry.target, argument: nil, entry: entry.name)
        }
    }

    /// Tapping a row opens that row rather than the top one. Builds the decision for a single chosen hit.
    public static func make(from decision: Decision, choosing index: Int) -> ActionPlan? {
        guard decision.results.indices.contains(index) else { return nil }
        let mode: MatchMode = decision.mode == .empty ? .open : decision.mode
        let narrowed = Decision(mode: mode, results: [decision.results[index]], query: decision.query, confident: true)
        return make(from: narrowed)
    }
}
