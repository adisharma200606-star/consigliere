import AppIntents
import Foundation

/// Lets a Focus mode keep him in the notch.
///
/// In System Settings → Focus → (a Focus, say Study) → Focus filters → Add filter → Consigliere, switch on
/// "Stay in the notch". While that Focus is on he never flies out about a job; a small head beside the
/// notch is the only sign something is waiting. Other Focus modes are not affected.
///
/// macOS calls `perform()` when the Focus turns on (with your setting) and again when it turns off (with the
/// default, false), so the default has to mean "normal".
@available(macOS 13.0, *)
struct ConsigliereFocusFilter: SetFocusFilterIntent {
    static var title: LocalizedStringResource = "Keep Consigliere in the notch"
    static var description: IntentDescription? = IntentDescription("While this Focus is on, he never flies out about your jobs.")

    @Parameter(title: "Stay in the notch", default: false)
    var stayInNotch: Bool

    var displayRepresentation: DisplayRepresentation {
        return DisplayRepresentation(title: stayInNotch ? "Stays in the notch" : "May fly out")
    }

    func perform() async throws -> some IntentResult {
        FocusQuiet.isOn = stayInNotch
        return .result()
    }
}

/// What the Focus filter last said. Kept in the app's own defaults, because macOS may call the filter while
/// the Brain is busy (or before it exists).
enum FocusQuiet {
    // Still the app's old name on purpose, so the saved setting carries over from Brochacho.
    private static let key = "brochacho.focusQuiet"

    static var isOn: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}
