import ConsigliereCore
import Foundation
import Security

/// Sends one question to the Claude API and brings back the answer.
///
/// The key lives in the Mac's Keychain, never in a file. Spending is counted per month against
/// `ask.monthlyBudgetUSD`, using the token counts the API reports with every reply.
enum AskClient {

    enum Problem: Error {
        case noKey
        case overBudget(spent: Double, budget: Double)
        case server(String)
        case network(String)
    }

    // MARK: asking

    static func ask(question: String, clip: String?, config: AskConfig) async throws -> Ask.Answer {
        guard let key = Keychain.read(), !key.isEmpty else { throw Problem.noKey }
        let spent = Spending.thisMonth()
        if spent >= config.monthlyBudgetUSD { throw Problem.overBudget(spent: spent, budget: config.monthlyBudgetUSD) }

        let prompt = Ask.build(question: question, clip: clip)
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else { throw Problem.network("bad address") }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try Ask.requestBody(prompt: prompt, model: config.model, maxTokens: config.maxTokens)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw Problem.network(error.localizedDescription)
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            let message = (try? JSONDecoder().decode(ErrorReply.self, from: data))?.error.message ?? "HTTP \(status)"
            throw Problem.server(message)
        }

        let reply = try JSONDecoder().decode(Reply.self, from: data)
        Spending.add(config.cost(inputTokens: reply.usage.input_tokens, outputTokens: reply.usage.output_tokens))
        let text = reply.content.compactMap { $0.type == "text" ? $0.text : nil }.joined(separator: "\n")
        return Ask.shape(text)
    }

    /// What to show in the notch when asking did not work.
    static func explain(_ error: Error) -> String {
        guard let problem = error as? Problem else { return "That did not work." }
        switch problem {
        case .noKey:
            return "I need a Claude API key for that. Type settings, then add it under Ask."
        case .overBudget(let spent, let budget):
            return String(format: "This month's budget is used up ($%.2f of $%.2f). It resets next month, or raise it in the config.", spent, budget)
        case .server(let message):
            return "Claude said no: \(message)"
        case .network(let message):
            return "I could not reach Claude. \(message)"
        }
    }

    private struct Reply: Decodable {
        struct Block: Decodable {
            let type: String
            let text: String?
        }
        struct Usage: Decodable {
            let input_tokens: Int
            let output_tokens: Int
        }
        let content: [Block]
        let usage: Usage
    }

    private struct ErrorReply: Decodable {
        struct Detail: Decodable { let message: String }
        let error: Detail
    }

    // MARK: the key

    enum Keychain {
        // Still the app's old name on purpose: the keys already saved in the Keychain are filed under it.
        private static let service = "com.adi.brochacho"
        /// The Claude key. Internal rather than private only because it is a default argument below.
        static let claudeAccount = "anthropic-api-key"

        /// `account` names which secret: the Claude key by default, or the Spotify keys (see MusicPlayer).
        static func read(account: String = claudeAccount) -> String? {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne
            ]
            var item: CFTypeRef?
            guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        }

        /// Saves the key, replacing any earlier one. An empty string removes it.
        @discardableResult
        static func write(_ key: String, account: String = claudeAccount) -> Bool {
            let base: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account
            ]
            SecItemDelete(base as CFDictionary)
            let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return true }
            var add = base
            add[kSecValueData as String] = Data(trimmed.utf8)
            return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
        }
    }

    // MARK: the budget

    enum Spending {
        private struct Ledger: Codable {
            var month: String
            var usd: Double
        }

        private static var file: URL { ConsiglierePaths.configDirectory.appendingPathComponent("ask-spending.json") }

        private static var currentMonth: String {
            let parts = Calendar.current.dateComponents([.year, .month], from: Date())
            return String(format: "%04d-%02d", parts.year ?? 0, parts.month ?? 0)
        }

        static func thisMonth() -> Double {
            guard let ledger = try? JSONFile.read(Ledger.self, from: file), ledger.month == currentMonth else { return 0 }
            return ledger.usd
        }

        static func add(_ usd: Double) {
            let ledger = Ledger(month: currentMonth, usd: thisMonth() + usd)
            try? JSONFile.write(ledger, to: file)
        }
    }
}
