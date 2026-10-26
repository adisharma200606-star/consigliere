import AppKit
import ConsigliereCore
import Foundation

/// "play beabadoobee", "pause", "next", "louder", "volume 30". The Google Home part.
///
/// Spotify can be told to play a particular thing by AppleScript, but only if you already know its
/// address ("spotify:artist:…"). Finding that address from words needs Spotify's own search, which needs a
/// free developer key (developer.spotify.com → Create app; copy the Client ID and Client secret into
/// settings). Without the key, "play beabadoobee" opens Spotify's search for it instead, one click short.
///
/// Apple Music needs no key: it searches your library by AppleScript and plays the first match.
///
/// Everything here runs on the main thread. AppleScript (and macOS's "may Consigliere control Spotify?" prompt)
/// must; run from a background thread after the search, it failed silently. Each attempt is written to
/// ~/.consigliere/music.log, readable with `cat`, so a failure says exactly which step went wrong.
@MainActor
enum MusicPlayer {

    enum Outcome {
        case playing(String)
        case searching(String)
        case failed(String)
    }

    static let clientIDAccount = "spotify-client-id"
    static let clientSecretAccount = "spotify-client-secret"

    // MARK: playing something by name

    static func play(_ words: String, player: String) async -> Outcome {
        let query = words.trimmingCharacters(in: .whitespacesAndNewlines)
        var log = MusicLog(query: query, player: player)
        defer { log.write() }

        if query.isEmpty {
            return playPause(player: player) ? .playing("") : .failed("Nothing to play.")
        }
        if player == "music" { return playFromLibrary(query) }

        let id = AskClient.Keychain.read(account: clientIDAccount) ?? ""
        let secret = AskClient.Keychain.read(account: clientSecretAccount) ?? ""
        log.add("keys: client id \(id.isEmpty ? "missing" : "present"), secret \(secret.isEmpty ? "missing" : "present")")

        if !id.isEmpty, !secret.isEmpty {
            do {
                let found = try await SpotifySearch.best(for: query, clientID: id, secret: secret, log: &log)
                guard let found = found else {
                    log.add("search found nothing")
                    return .failed("Spotify found nothing called \(query).")
                }
                // Spotify only reliably *plays* a song. Given an artist or album address on its own, newer
                // versions just open that page. So it is always a song, played inside its artist or album,
                // which also keeps the next songs coming from the same place.
                var script = "tell application \"Spotify\" to play track \"\(escaped(found.uri))\""
                if let context = found.context { script += " in context \"\(escaped(context))\"" }
                log.add("script: \(script)")
                if let problem = run(script) {
                    log.add("script failed: \(problem.text)")
                    return .failed(problem.forNotch)
                }
                log.add("played")
                return .playing(found.name)
            } catch let problem as SpotifyProblem where problem.step == "token" && (problem.status == 400 || problem.status == 401) {
                // A wrong key will not fix itself. Say so, rather than quietly opening the search page.
                log.add("search failed: \(problem)")
                return .failed(problem.body.contains("secret") ? "Spotify says the client secret is wrong. Settings, Jobs and music."
                                                               : "Spotify does not know that client ID. Settings, Jobs and music.")
            } catch {
                log.add("search failed: \(error)")
                // Fall through to the search page, which still gets him there.
            }
        }
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? query
        log.add("opening spotify:search:\(encoded)")
        if let url = URL(string: "spotify:search:\(encoded)"), NSWorkspace.shared.open(url) {
            return .searching(query)
        }
        return .failed("Spotify is not installed.")
    }

    private static func playFromLibrary(_ query: String) -> Outcome {
        let source = """
        tell application "Music"
            set found to (search playlist "Library" for "\(escaped(query))")
            if found is {} then return ""
            play item 1 of found
            return name of item 1 of found
        end tell
        """
        guard let name = runScriptForString(source) else { return .failed("Music would not play. Check Privacy, Automation.") }
        return name.isEmpty ? .failed("Nothing in your library called \(query).") : .playing(name)
    }

    // MARK: controls

    private static func appName(_ player: String) -> String {
        return player == "music" ? "Music" : "Spotify"
    }

    @discardableResult
    static func playPause(player: String) -> Bool {
        return runScript("tell application \"\(appName(player))\" to playpause")
    }

    @discardableResult
    static func next(player: String) -> Bool {
        return runScript("tell application \"\(appName(player))\" to next track")
    }

    /// The Mac's own volume, by `step` out of 100. Works whatever is playing.
    @discardableResult
    static func nudgeVolume(by step: Int) -> Bool {
        return runScript("set volume output volume ((output volume of (get volume settings)) + (\(step)))")
    }

    /// "volume 30". Nil when the words are not a number from 0 to 100.
    static func setVolume(_ words: String) -> Int? {
        let digits = words.filter { $0.isNumber }
        guard let level = Int(digits), (0...100).contains(level) else { return nil }
        return runScript("set volume output volume \(level)") ? level : nil
    }

    // MARK: AppleScript

    private static func escaped(_ text: String) -> String {
        return text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// What went wrong with a script: AppleScript's number and message, and a sentence for the notch.
    struct ScriptProblem {
        let number: Int
        let message: String

        var text: String { "\(number) \(message)" }

        var forNotch: String {
            switch number {
            case -1743: return "macOS won't let me control Spotify. Privacy & Security, Automation, Consigliere."
            case -600: return "Spotify isn't open."
            default: return "Spotify said no (\(number))."
            }
        }
    }

    /// Runs a script. Nil means it worked.
    private static func run(_ source: String) -> ScriptProblem? {
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        guard let error = error else { return nil }
        NSLog("Consigliere: music script failed: \(error)")
        return ScriptProblem(number: (error[NSAppleScript.errorNumber] as? Int) ?? 0,
                             message: (error[NSAppleScript.errorMessage] as? String) ?? "")
    }

    @discardableResult
    private static func runScript(_ source: String) -> Bool {
        return run(source) == nil
    }

    private static func runScriptForString(_ source: String) -> String? {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error = error {
            NSLog("Consigliere: music script failed: \(error)")
            return nil
        }
        return result?.stringValue ?? ""
    }
}

/// The story of the last "play", written to ~/.consigliere/music.log. Never the keys themselves.
struct MusicLog {
    private var lines: [String]

    init(query: String, player: String) {
        lines = ["\(Date()) play \"\(query)\" in \(player)"]
    }

    mutating func add(_ line: String) {
        lines.append(line)
    }

    func write() {
        let url = ConsiglierePaths.configDirectory.appendingPathComponent("music.log")
        try? Data((lines.joined(separator: "\n") + "\n").utf8).write(to: url, options: .atomic)
    }
}

/// Spotify's search, with the "client credentials" kind of key: no logging in, it only looks things up.
private enum SpotifySearch {
    struct Found {
        /// Always a song ("spotify:track:…"), except for a playlist, which is the last resort.
        let uri: String
        let name: String
        /// The artist or album the song plays inside, so the music carries on after it.
        let context: String?
    }

    private struct Token: Decodable {
        let access_token: String
    }

    private struct Results: Decodable {
        struct Album: Decodable {
            let uri: String
        }
        struct Item: Decodable {
            let uri: String
            let name: String
            /// Only songs have one.
            let album: Album?
        }
        struct Page: Decodable {
            let items: [Item?]
        }
        let artists: Page?
        let tracks: Page?
        let playlists: Page?
    }

    /// When the words are an artist's name ("beabadoobee"): their best-known song, played inside the artist.
    /// Otherwise the best matching song, played inside its album. A playlist only if there is no song at all.
    static func best(for query: String, clientID: String, secret: String, log: inout MusicLog) async throws -> Found? {
        let token = try await fetchToken(clientID: clientID, secret: secret)
        log.add("token: ok")
        let results = try await search(query, types: "artist,track,playlist", token: token)
        log.add("search: artist \(results.artists?.items.compactMap { $0 }.first?.name ?? "-"), song \(results.tracks?.items.compactMap { $0 }.first?.name ?? "-")")

        let wanted = TextTools.normalize(query)
        if let artist = results.artists?.items.compactMap({ $0 }).first, TextTools.normalize(artist.name) == wanted {
            // Search ranks an artist's songs by popularity, so the first one is a fair "play this artist".
            let theirs = try await search("artist:\"\(artist.name)\"", types: "track", token: token)
            if let song = theirs.tracks?.items.compactMap({ $0 }).first {
                return Found(uri: song.uri, name: artist.name, context: artist.uri)
            }
        }
        if let song = results.tracks?.items.compactMap({ $0 }).first {
            return Found(uri: song.uri, name: song.name, context: song.album?.uri)
        }
        if let list = results.playlists?.items.compactMap({ $0 }).first {
            return Found(uri: list.uri, name: list.name, context: nil)
        }
        return nil
    }

    private static func search(_ query: String, types: String, token: String) async throws -> Results {
        var parts = URLComponents(string: "https://api.spotify.com/v1/search")
        parts?.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "type", value: types),
            URLQueryItem(name: "limit", value: "1")
        ]
        guard let url = parts?.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw SpotifyProblem(step: "search", status: status, body: String(decoding: data.prefix(300), as: UTF8.self)) }
        return try JSONDecoder().decode(Results.self, from: data)
    }

    private static func fetchToken(clientID: String, secret: String) async throws -> String {
        guard let url = URL(string: "https://accounts.spotify.com/api/token") else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 8
        let basic = Data("\(clientID):\(secret)".utf8).base64EncodedString()
        request.setValue("Basic \(basic)", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("grant_type=client_credentials".utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw SpotifyProblem(step: "token", status: status, body: String(decoding: data.prefix(300), as: UTF8.self)) }
        return try JSONDecoder().decode(Token.self, from: data).access_token
    }
}

/// Spotify answered with something other than "OK". Its own words go into music.log.
struct SpotifyProblem: Error, CustomStringConvertible {
    let step: String
    let status: Int
    let body: String

    var description: String { "\(step) HTTP \(status): \(body)" }
}

