import Foundation

/// Smart jobs: asking Claude what opens a job and which folder it belongs in, for the jobs the plain rules in
/// `Jobs` could not place. Everything here works without the internet: who needs help, the words sent, the
/// request body, and how the reply is checked. The app target does the network call (`SmartJobsClient`).
/// Ported from `reference-js/smart.js`; `fixtures/smart.json` keeps the two in step.
///
/// Why it is careful:
///  - Only jobs that still lack a starter or a folder are sent, so most jobs never leave the Mac and cost nothing.
///  - Only job titles, the names of things that can be opened, and folder names are sent. Never addresses,
///    notes, the clipboard or anything else.
///  - The reply can only pick names that exist. Anything else is thrown away, so a made-up app never opens.
public enum Smart {

    /// The standing instructions. Short, because every word is paid for on every request.
    public static let rules = [
        "You sort the jobs on one person's to-do list for an app on his Mac.",
        "For each job, pick from \"Things to open\" the one thing he would open to do that job, or null when nothing clearly fits (a phone call, a chore away from the computer, a job too vague to tell).",
        "Then pick from \"Folders\" the folder the job belongs in, or null when none fits.",
        "Write every name exactly as it appears in the lists. Never invent one."
    ].joined(separator: " ")

    /// The most jobs sent at once, and the most names of things to open. Keeps one request small and cheap.
    public static let maxJobs = 20
    public static let maxCandidates = 400
    /// Room for a short thought plus the answer for twenty jobs. Only what is actually written is paid for.
    public static let maxTokens = 2048

    /// The shape the reply must have, as JSON. Fixed, so the API can reuse it from one request to the next.
    public static let schemaJSON = """
    {"type":"object","properties":{"jobs":{"type":"array","items":{"type":"object","properties":{"id":{"type":"string"},"opens":{"anyOf":[{"type":"string"},{"type":"null"}]},"folder":{"anyOf":[{"type":"string"},{"type":"null"}]}},"required":["id","opens","folder"],"additionalProperties":false}}},"required":["jobs"],"additionalProperties":false}
    """

    public struct Prompt: Equatable, Decodable {
        public let system: String
        public let user: String
    }

    /// What came back for one job. Either may be nil; at least one is not.
    public struct Suggestion: Equatable, Decodable {
        public let id: String
        public let starter: String?
        public let group: String?
    }

    /// The jobs worth asking about: not finished, and missing a starter, or a folder when there are folders.
    public static func needingHelp(_ day: JobDay, ids: [String], groups: [String]) -> [Job] {
        let asked = Set(ids)
        let found = day.jobs.filter { job in
            asked.contains(job.id) && job.isLive && (job.starter == nil || (!groups.isEmpty && job.group == nil))
        }
        return Array(found.prefix(maxJobs))
    }

    /// Names that can be picked: every entry except tools (a job never starts the timer), each name once.
    public static func candidates(_ catalog: [CatalogEntry]) -> [String] {
        var seen = Set<String>()
        var out = [String]()
        for entry in catalog where entry.kind != .tool {
            let key = TextTools.normalize(entry.name)
            if key.isEmpty || seen.contains(key) { continue }
            seen.insert(key)
            out.append(entry.name)
        }
        return Array(out.prefix(maxCandidates))
    }

    /// The words sent. Lists first, then the jobs, one per line with their id.
    public static func prompt(for jobs: [Job], catalog: [CatalogEntry], groups: [String]) -> Prompt {
        var lines = ["Things to open:", candidates(catalog).joined(separator: ", "), ""]
        lines += ["Folders:", groups.isEmpty ? "(none, so folder is always null)" : groups.joined(separator: ", "), ""]
        lines.append("Jobs:")
        lines += jobs.map { "\($0.id): \($0.title)" }
        return Prompt(system: rules, user: lines.joined(separator: "\n"))
    }

    /// The exact spelling from `names` that matches `value`, or nil. Case and spacing do not matter.
    private static func pick(_ value: Any?, from names: [String]) -> String? {
        guard let text = value as? String else { return nil }
        let key = TextTools.normalize(text)
        if key.isEmpty { return nil }
        return names.first { TextTools.normalize($0) == key }
    }

    /// Reads the reply text, only for jobs that were asked about, only with names that exist. Text that is not
    /// the expected JSON gives an empty list: nothing changes.
    public static func readReply(_ text: String, askedIDs: [String], catalog: [CatalogEntry], groups: [String]) -> [Suggestion] {
        guard let data = text.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = parsed["jobs"] as? [Any] else { return [] }
        let names = candidates(catalog)
        let asked = Set(askedIDs)
        var seen = Set<String>()
        var out = [Suggestion]()
        for case let item as [String: Any] in items {
            guard let id = item["id"] as? String, asked.contains(id), !seen.contains(id) else { continue }
            seen.insert(id)
            let starter = pick(item["opens"], from: names)
            let group = pick(item["folder"], from: groups)
            if starter == nil && group == nil { continue }
            out.append(Suggestion(id: id, starter: starter, group: group))
        }
        return out
    }

    /// The JSON body for one request. `effort` "low" keeps thinking (which is paid for) to a minimum; an empty
    /// string leaves it out, for older models that do not take it.
    public static func requestBody(prompt: Prompt, model: String, effort: String) throws -> Data {
        let schema = try JSONSerialization.jsonObject(with: Data(schemaJSON.utf8))
        var output: [String: Any] = ["format": ["type": "json_schema", "schema": schema]]
        if !effort.isEmpty { output["effort"] = effort }
        let body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "system": prompt.system,
            "messages": [["role": "user", "content": prompt.user]],
            "output_config": output
        ]
        return try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
    }
}
