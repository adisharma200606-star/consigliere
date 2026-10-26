import Foundation

/// "Ask": a short answer in the notch. This file holds everything about it that does not need the internet:
/// what gets sent, and how the reply is split into a sentence to read and a command to copy.
/// Ported from `reference-js/core.js`. The app target does the actual network call.
public enum Ask {

    /// The standing instructions sent with every question.
    public static let rules = [
        "You are answering inside a tiny panel at the top of a Mac screen.",
        "Reply in at most three short sentences of plain English. No preamble, no markdown, no lists.",
        "The reader is a self-taught builder who is new to coding, so avoid jargon or explain it in passing.",
        "If the best answer is a command or a line of code, give one sentence first, then put the command alone on the last line, starting with \"$ \".",
        "If you are not sure, say so in one sentence. If it needs information from today and you cannot look it up, say that plainly instead of guessing."
    ].joined(separator: " ")

    /// The most copied text that is ever sent along.
    public static let maxClipCharacters = 6000

    public struct Prompt: Equatable {
        public let system: String
        public let user: String
    }

    public struct Answer: Equatable {
        /// The part to read.
        public let text: String
        /// When the reply ended with a "$ " line: the command, ready to copy.
        public let command: String?
    }

    /// Does the question point at something he copied? "what does this mean", "explain this".
    public static func wantsClipboard(_ question: String) -> Bool {
        return TextTools.words(question).contains { $0 == "this" || $0 == "these" }
    }

    /// The two texts sent to the model. `clip` is whatever he last copied; it is only included when the
    /// question points at it, so an unrelated question never leaks the clipboard.
    public static func build(question: String, clip: String?) -> Prompt {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        var user = q
        if let clip = clip, !clip.isEmpty, wantsClipboard(q) {
            let cut = clip.count > maxClipCharacters
            user = q + "\n\nHere is what I copied" + (cut ? " (cut short)" : "") + ":\n" + String(clip.prefix(maxClipCharacters))
        }
        return Prompt(system: rules, user: user)
    }

    /// Splits a reply into the part to read and, when the last line starts with "$ ", a command to copy.
    public static func shape(_ reply: String) -> Answer {
        var lines = reply.replacingOccurrences(of: "\r", with: "")
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        var command: String? = nil
        if let last = lines.last, last.hasPrefix("$ ") {
            let candidate = String(last.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            command = candidate.isEmpty ? nil : candidate
            lines.removeLast()
        }
        return Answer(text: lines.joined(separator: " "), command: command)
    }

    // MARK: request body

    private struct Message: Encodable {
        let role: String
        let content: String
    }

    private struct Body: Encodable {
        let model: String
        let max_tokens: Int
        let system: String
        let messages: [Message]
    }

    /// The JSON body for one question. Headers, the address and the key are the app's business.
    public static func requestBody(prompt: Prompt, model: String, maxTokens: Int) throws -> Data {
        let body = Body(model: model, max_tokens: maxTokens, system: prompt.system,
                        messages: [Message(role: "user", content: prompt.user)])
        return try JSONEncoder().encode(body)
    }
}
