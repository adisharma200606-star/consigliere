import AppKit
import ConsigliereCore
import EventKit

/// Puts a thought where it belongs: Apple Notes or Apple Reminders. Both sync to the iPhone by themselves.
enum CaptureWriter {

    // MARK: Notes (AppleScript: Notes has no other way in)

    /// Makes a note without bringing Notes to the front. Returns the note's id ("x-coredata://…"), which can
    /// open it again later, or nil if Notes refused.
    static func makeNote(_ text: String) -> String? {
        let body = htmlEscaped(text).replacingOccurrences(of: "\n", with: "<br>")
        let source = """
        tell application "Notes"
            set newNote to make new note with properties {body:"\(appleScriptEscaped(body))"}
            return id of newNote
        end tell
        """
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error = error {
            NSLog("Consigliere: Notes said no: \(error)")
            return nil
        }
        return result?.stringValue ?? ""
    }

    /// Brings Notes forward on one particular note. Falls back to just opening Notes.
    static func showNote(id: String?) {
        guard let id = id, !id.isEmpty else {
            _ = Opener.openApp("com.apple.Notes", name: "Notes")
            return
        }
        let source = """
        tell application "Notes"
            activate
            show note id "\(appleScriptEscaped(id))"
        end tell
        """
        if !run(source) { _ = Opener.openApp("com.apple.Notes", name: "Notes") }
    }

    /// Adds a few lines to the day's diary note, making the note first if `noteID` is nil or the note has gone
    /// (deleted, say). The note is titled `title`, so Notes lists one diary note per day. Returns the note's id,
    /// to pass back in next time, or nil if Notes refused.
    static func appendToDiary(noteID: String?, title: String, lines: String) -> String? {
        let body = htmlEscaped(lines).replacingOccurrences(of: "\n", with: "<br>")
        let find = noteID.map { id in
            """
                try
                    set theNote to note id "\(appleScriptEscaped(id))"
                end try
            """
        } ?? ""
        let source = """
        tell application "Notes"
            set theNote to missing value
        \(find)
            if theNote is missing value then
                set theNote to make new note with properties {body:"<h1>\(appleScriptEscaped(htmlEscaped(title)))</h1>"}
            end if
            set body of theNote to (body of theNote) & "<div>\(appleScriptEscaped(body))</div><div><br></div>"
            return id of theNote
        end tell
        """
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error = error {
            NSLog("Consigliere: Notes would not take the diary: \(error)")
            return nil
        }
        return result?.stringValue ?? ""
    }

    /// Opens Notes on a fresh, empty note, ready to type.
    static func openFreshNote() -> Bool {
        let source = """
        tell application "Notes"
            activate
            set fresh to make new note with properties {body:""}
            show fresh
        end tell
        """
        return run(source)
    }

    private static func run(_ source: String) -> Bool {
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error = error {
            NSLog("Consigliere: Notes said no: \(error)")
            return false
        }
        return true
    }

    private static func appleScriptEscaped(_ text: String) -> String {
        return text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func htmlEscaped(_ text: String) -> String {
        return text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }

    // MARK: Reminders (EventKit)

    private static let store = EKEventStore()

    private static func withAccess(_ then: @escaping (Bool) -> Void) {
        if #available(macOS 14.0, *) {
            store.requestFullAccessToReminders { granted, _ in then(granted) }
        } else {
            store.requestAccess(to: .reminder) { granted, _ in then(granted) }
        }
    }

    /// Makes a reminder. `due` nil means a plain to-do. `completion` runs on the main thread with the
    /// reminder's identifier on success, or nil.
    static func makeReminder(title: String, due: Date?, completion: @escaping (String?) -> Void) {
        withAccess { granted in
            guard granted, let calendar = store.defaultCalendarForNewReminders() else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            let reminder = EKReminder(eventStore: store)
            reminder.title = title
            reminder.calendar = calendar
            if let due = due {
                reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: due)
                reminder.addAlarm(EKAlarm(absoluteDate: due))     // this is what makes the phone buzz
            }
            do {
                try store.save(reminder, commit: true)
                let identifier = reminder.calendarItemIdentifier
                DispatchQueue.main.async { completion(identifier) }
            } catch {
                NSLog("Consigliere: could not save the reminder: \(error)")
                DispatchQueue.main.async { completion(nil) }
            }
        }
    }

    /// One reminder, as the glance shows it.
    struct Upcoming {
        let identifier: String
        let title: String
        let due: Date?
    }

    /// Reminders that are not done yet, from every list, soonest first; the ones with no date come last.
    /// `completion` runs on the main thread; nil means Consigliere may not read Reminders.
    static func upcomingReminders(limit: Int, completion: @escaping ([Upcoming]?) -> Void) {
        withAccess { granted in
            guard granted else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
            store.fetchReminders(matching: predicate) { reminders in
                let items = (reminders ?? []).map { reminder -> Upcoming in
                    let due = reminder.dueDateComponents.flatMap { Calendar.current.date(from: $0) }
                    return Upcoming(identifier: reminder.calendarItemIdentifier, title: reminder.title ?? "", due: due)
                }
                let sorted = items.sorted { a, b in
                    switch (a.due, b.due) {
                    case let (x?, y?): return x < y
                    case (.some, .none): return true
                    case (.none, .some): return false
                    case (.none, .none): return a.title < b.title
                    }
                }
                DispatchQueue.main.async { completion(Array(sorted.prefix(limit))) }
            }
        }
    }

    /// Ticks a reminder off (or back on). `completion` gets true if it was saved.
    static func setDone(_ identifier: String, done: Bool, completion: @escaping (Bool) -> Void) {
        guard let reminder = store.calendarItem(withIdentifier: identifier) as? EKReminder else {
            completion(false)
            return
        }
        reminder.isCompleted = done
        do {
            try store.save(reminder, commit: true)
            completion(true)
        } catch {
            NSLog("Consigliere: could not tick the reminder: \(error)")
            completion(false)
        }
    }

    static func openReminders() {
        _ = Opener.openApp("com.apple.reminders")
    }
}
