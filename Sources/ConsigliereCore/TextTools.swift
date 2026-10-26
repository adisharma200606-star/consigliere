import Foundation

/// Small text helpers. Ported line for line from `reference-js/core.js`.
/// Everything works on ASCII bytes after normalising, which keeps indexing simple and fast.
public enum TextTools {

    /// Lowercase and strip everything except a-z and 0-9. "You Tube!" becomes "youtube".
    public static func normalize(_ s: String) -> String {
        var out = [UInt8]()
        for byte in s.lowercased().utf8 where isAlnum(byte) {
            out.append(byte)
        }
        return String(decoding: out, as: UTF8.self)
    }

    /// Lowercase words, split on anything that is not a-z or 0-9.
    public static func words(_ s: String) -> [String] {
        var result = [String]()
        var current = [UInt8]()
        for byte in s.lowercased().utf8 {
            if isAlnum(byte) {
                current.append(byte)
            } else if !current.isEmpty {
                result.append(String(decoding: current, as: UTF8.self))
                current.removeAll(keepingCapacity: true)
            }
        }
        if !current.isEmpty {
            result.append(String(decoding: current, as: UTF8.self))
        }
        return result
    }

    /// Classic Levenshtein distance.
    public static func editDistance(_ a: String, _ b: String) -> Int {
        let x = Array(a.utf8)
        let y = Array(b.utf8)
        if x == y { return 0 }
        if x.isEmpty { return y.count }
        if y.isEmpty { return x.count }
        var prev = Array(0...y.count)
        for i in 1...x.count {
            var cur = [Int](repeating: 0, count: y.count + 1)
            cur[0] = i
            for k in 1...y.count {
                let cost = x[i - 1] == y[k - 1] ? 0 : 1
                cur[k] = Swift.min(prev[k] + 1, cur[k - 1] + 1, prev[k - 1] + cost)
            }
            prev = cur
        }
        return prev[y.count]
    }

    /// Greedy earliest subsequence match. Returns how many characters of `key` the match spans
    /// (last matched index minus first matched index, plus one), or nil when `q` is not a subsequence.
    public static func subsequenceSpan(_ q: String, in key: String) -> Int? {
        let query = Array(q.utf8)
        let target = Array(key.utf8)
        if query.isEmpty { return nil }
        var first = -1
        var last = -1
        var qi = 0
        for (i, byte) in target.enumerated() {
            if qi >= query.count { break }
            if byte == query[qi] {
                if first < 0 { first = i }
                last = i
                qi += 1
            }
        }
        return qi == query.count ? last - first + 1 : nil
    }

    /// Percent-encode everything except RFC 3986 unreserved characters (A-Z a-z 0-9 - . _ ~).
    public static func encodeQuery(_ s: String) -> String {
        let hex = Array("0123456789ABCDEF".utf8)
        var out = [UInt8]()
        for byte in s.utf8 {
            let unreserved = isAlnumAnyCase(byte) || byte == 0x2D || byte == 0x2E || byte == 0x5F || byte == 0x7E
            if unreserved {
                out.append(byte)
            } else {
                out.append(0x25)
                out.append(hex[Int(byte >> 4)])
                out.append(hex[Int(byte & 0x0F)])
            }
        }
        return String(decoding: out, as: UTF8.self)
    }

    private static func isAlnum(_ byte: UInt8) -> Bool {
        return (byte >= 0x30 && byte <= 0x39) || (byte >= 0x61 && byte <= 0x7A)
    }

    private static func isAlnumAnyCase(_ byte: UInt8) -> Bool {
        return isAlnum(byte) || (byte >= 0x41 && byte <= 0x5A)
    }
}
