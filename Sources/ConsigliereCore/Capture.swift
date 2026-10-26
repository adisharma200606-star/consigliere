import Foundation

/// Reading "remind me to call mom tomorrow at 5" into a title and a time. Ported from `reference-js/capture.js`.
///
/// Times are "wall-clock milliseconds": the number you would get for what the clock on the wall says, if the
/// wall clock were in UTC. The parser never thinks about time zones; `wall(from:)` and `date(fromWall:)`
/// convert to and from real dates using the Mac's own calendar.
public enum ReminderParser {

    public struct Result: Equatable {
        public let title: String
        /// Nil when no time was mentioned.
        public let dueWall: Int?
    }

    private static let minute = 60_000
    private static let hour = 3_600_000
    private static let day = 86_400_000

    private static let weekdays: [String: Int] = [
        "sun": 0, "sunday": 0, "mon": 1, "monday": 1, "tue": 2, "tues": 2, "tuesday": 2, "wed": 3, "weds": 3,
        "wednesday": 3, "thu": 4, "thur": 4, "thurs": 4, "thursday": 4, "fri": 5, "friday": 5, "sat": 6, "saturday": 6
    ]
    private static let units: [String: Int] = [
        "m": 60_000, "min": 60_000, "mins": 60_000, "minute": 60_000, "minutes": 60_000,
        "h": 3_600_000, "hr": 3_600_000, "hrs": 3_600_000, "hour": 3_600_000, "hours": 3_600_000,
        "d": 86_400_000, "day": 86_400_000, "days": 86_400_000,
        "w": 604_800_000, "week": 604_800_000, "weeks": 604_800_000
    ]
    private static let partsOfDay: [String: Int] = [
        "morning": 9, "afternoon": 15, "evening": 19, "night": 20, "tonight": 20, "noon": 12, "midday": 12, "midnight": 0
    ]
    private static let leadIn: Set<String> = ["me", "to", "that", "about"]
    private static let dangling: Set<String> = ["at", "on", "by", "in", "for", "to", "around", "the", "this", "next", "and"]

    private struct Clock {
        var hour: Int
        var minute: Int
        var meridiem: String?
        var hasColon: Bool
    }

    private static func isKept(_ c: Character) -> Bool {
        return c.isASCII && (c.isLetter || c.isNumber || c == ":")
    }

    /// Lowercase, with anything that is not a letter, a digit or ":" trimmed off both ends.
    private static func bare(_ token: String) -> String {
        var chars = Array(token.lowercased())
        while let first = chars.first, !isKept(first) { chars.removeFirst() }
        while let last = chars.last, !isKept(last) { chars.removeLast() }
        return String(chars)
    }

    private static func isDigits(_ s: String) -> Bool {
        return !s.isEmpty && s.allSatisfy { $0.isASCII && $0.isNumber }
    }

    /// "20min" to (20, "min"). Nil unless it is digits followed by letters and nothing else.
    private static func splitGlued(_ s: String) -> (Int, String)? {
        let digits = s.prefix { $0.isASCII && $0.isNumber }
        let letters = s.dropFirst(digits.count)
        guard !digits.isEmpty, !letters.isEmpty, letters.allSatisfy({ $0.isASCII && $0.isLetter }), let n = Int(digits) else { return nil }
        return (n, String(letters))
    }

    /// "5", "5pm", "5:30", "5:30pm", "17:30".
    private static func readClock(_ word: String) -> Clock? {
        var rest = Substring(word)
        var meridiem: String? = nil
        if rest.hasSuffix("am") || rest.hasSuffix("pm") {
            meridiem = String(rest.suffix(2))
            rest = rest.dropLast(2)
        }
        let pieces = rest.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard pieces.count == 1 || pieces.count == 2 else { return nil }
        guard isDigits(pieces[0]), pieces[0].count <= 2, let h = Int(pieces[0]) else { return nil }
        var m = 0
        if pieces.count == 2 {
            guard isDigits(pieces[1]), pieces[1].count == 2, let parsed = Int(pieces[1]) else { return nil }
            m = parsed
        }
        if h > 23 || m > 59 { return nil }
        if meridiem != nil && (h < 1 || h > 12) { return nil }
        return Clock(hour: h, minute: m, meridiem: meridiem, hasColon: pieces.count == 2)
    }

    /// Understands: in 20 minutes, in an hour, in half an hour, in 2 days, today, tonight, tomorrow,
    /// day after tomorrow, friday / on friday / next friday (the coming one), at 5, at 5pm, 5:30 pm, 17:30,
    /// noon, midnight, morning, afternoon, evening. A day with no time means 9:00 (for "today" after 9:00, an
    /// hour or two from now). A time that has already passed today means tomorrow. A bare hour from 1 to 6
    /// means the afternoon.
    public static func parse(_ text: String, nowWall: Int) -> Result {
        var tokens = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        while tokens.count > 1, leadIn.contains(bare(tokens[0])) { tokens.removeFirst() }
        let words = tokens.map { bare($0) }
        var used = [Bool](repeating: false, count: tokens.count)

        var relative: Int? = nil
        var dayOffset: Int? = nil
        var clock: Clock? = nil
        var partOfDay: Int? = nil

        func word(_ index: Int) -> String? {
            return index >= 0 && index < words.count ? words[index] : nil
        }
        func take(_ from: Int, _ count: Int) {
            for k in from..<(from + count) where k >= 0 && k < used.count { used[k] = true }
        }

        var i = 0
        while i < words.count {
            defer { i += 1 }
            if used[i] { continue }
            let w = words[i]
            let next = word(i + 1)
            let after = word(i + 2)

            // in 20 minutes / in 20min / in an hour / in half an hour
            if w == "in", relative == nil, let next = next {
                if next == "half", after == "an", word(i + 3) == "hour" {
                    relative = 30 * minute
                    take(i, 4)
                    continue
                }
                if next == "a" || next == "an", let after = after, let unit = units[after] {
                    relative = unit
                    take(i, 3)
                    continue
                }
                if isDigits(next), let n = Int(next), let after = after, let unit = units[after] {
                    relative = n * unit
                    take(i, 3)
                    continue
                }
                if let (n, letters) = splitGlued(next), let unit = units[letters] {
                    relative = n * unit
                    take(i, 2)
                    continue
                }
            }

            if dayOffset == nil {
                if w == "day", next == "after", after == "tomorrow" || after == "tmrw" {
                    dayOffset = 2
                    take(i, 3)
                    continue
                }
                if w == "today" {
                    dayOffset = 0
                    take(i, 1)
                    continue
                }
                if w == "tomorrow" || w == "tmrw" || w == "tmr" {
                    dayOffset = 1
                    take(i, 1)
                    continue
                }
                if w == "tonight" {
                    dayOffset = 0
                    partOfDay = 20
                    take(i, 1)
                    continue
                }
                if let target = weekdays[w] {
                    // 1 January 1970 was a Thursday.
                    let today = ((nowWall / day) + 4) % 7
                    let ahead = (target - today + 7) % 7
                    dayOffset = ahead == 0 ? 7 : ahead
                    var lead = 0
                    if i > 0, !used[i - 1], let before = word(i - 1), before == "on" || before == "next" || before == "this" {
                        lead = 1
                    }
                    take(i - lead, 1 + lead)
                    continue
                }
            }

            if clock == nil, partOfDay == nil, w != "tonight", let h = partsOfDay[w] {
                partOfDay = h
                var back = 0
                if i >= 2, word(i - 2) == "in", word(i - 1) == "the", !used[i - 1], !used[i - 2] {
                    back = 2
                } else if i >= 1, !used[i - 1], let before = word(i - 1), before == "this" || before == "at" || before == "the" {
                    back = 1
                }
                take(i - back, 1 + back)
                continue
            }

            if clock == nil, var c = readClock(w) {
                var introduced = false
                if i > 0, !used[i - 1], let before = word(i - 1), before == "at" || before == "by" || before == "around" {
                    introduced = true
                }
                let separateMeridiem = c.meridiem == nil && (next == "am" || next == "pm")
                if c.meridiem != nil || c.hasColon || separateMeridiem || introduced {
                    var valid = true
                    if separateMeridiem {
                        c.meridiem = next
                        if c.hour < 1 || c.hour > 12 { valid = false }
                    }
                    if valid {
                        clock = c
                        take(introduced ? i - 1 : i, (introduced ? 1 : 0) + 1 + (separateMeridiem ? 1 : 0))
                        continue
                    }
                }
            }
        }

        // Put the time together.
        var due: Int? = nil
        if let relative = relative, dayOffset == nil, clock == nil, partOfDay == nil {
            due = nowWall + relative
        } else if dayOffset != nil || clock != nil || partOfDay != nil {
            let midnight = nowWall - (nowWall % day)
            var h = 9
            var m = 0
            var guessed = false
            if let c = clock {
                h = c.hour
                m = c.minute
                if c.meridiem == "pm" && h < 12 { h += 12 }
                if c.meridiem == "am" && h == 12 { h = 0 }
                if c.meridiem == nil && !c.hasColon && h >= 1 && h <= 6 {
                    h += 12                                  // "at 5" means 17:00
                } else if c.meridiem == nil && !c.hasColon && h >= 7 && h <= 11 {
                    guessed = true                           // "at 9" could be either
                }
            } else if let p = partOfDay {
                h = p
            }
            var when = midnight + (dayOffset ?? 0) * day + h * hour + m * minute + (relative ?? 0)
            if dayOffset == nil && when <= nowWall {
                if guessed && when + 12 * hour > nowWall {
                    when += 12 * hour                        // 9 has passed, so he means 21:00
                } else {
                    when += day
                }
            } else if dayOffset == 0 && clock == nil && partOfDay == nil && when <= nowWall {
                // "today" with no time, and 9:00 has gone: the top of the next hour, plus one.
                when = nowWall - (nowWall % hour) + 2 * hour
            }
            due = when
        }

        // What is left is the title.
        var kept = [String]()
        for (index, token) in tokens.enumerated() where !used[index] { kept.append(token) }
        if kept.count < tokens.count {
            while kept.count > 1, let last = kept.last, dangling.contains(bare(last)) { kept.removeLast() }
        }
        var title = kept.joined(separator: " ")
        while let last = title.last, last == " " || last == "," || last == ";" || last == ":" || last == "." || last == "-" {
            title.removeLast()
        }
        title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty { title = tokens.joined(separator: " ") }
        return Result(title: title, dueWall: due)
    }

    // MARK: saying it back, and real dates

    private static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? calendar.timeZone
        return calendar
    }

    /// "Today 17:00", "Tomorrow 09:00", "Fri 25 Sep 16:05": how the notch confirms what it understood.
    public static func describe(dueWall: Int?, nowWall: Int) -> String {
        guard let dueWall = dueWall else { return "no time set" }
        let parts = utcCalendar.dateComponents([.month, .day, .hour, .minute, .weekday],
                                               from: Date(timeIntervalSince1970: Double(dueWall) / 1000))
        let two: (Int) -> String = { $0 < 10 ? "0\($0)" : "\($0)" }
        let time = "\(two(parts.hour ?? 0)):\(two(parts.minute ?? 0))"
        let days = dueWall / day - nowWall / day
        if days == 0 { return "Today \(time)" }
        if days == 1 { return "Tomorrow \(time)" }
        let names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        let weekday = names[((parts.weekday ?? 1) - 1 + 7) % 7]
        let month = months[((parts.month ?? 1) - 1 + 12) % 12]
        return "\(weekday) \(parts.day ?? 1) \(month) \(time)"
    }

    /// What the wall clock says right now, as wall-clock milliseconds.
    public static func wall(from date: Date, calendar: Calendar = .current) -> Int {
        let local = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let asUTC = utcCalendar.date(from: local) ?? date
        return Int((asUTC.timeIntervalSince1970 * 1000).rounded())
    }

    /// The real moment at which the wall clock will show `wall`.
    public static func date(fromWall wall: Int, calendar: Calendar = .current) -> Date {
        let parts = utcCalendar.dateComponents([.year, .month, .day, .hour, .minute, .second],
                                               from: Date(timeIntervalSince1970: Double(wall) / 1000))
        return calendar.date(from: parts) ?? Date(timeIntervalSince1970: Double(wall) / 1000)
    }
}
