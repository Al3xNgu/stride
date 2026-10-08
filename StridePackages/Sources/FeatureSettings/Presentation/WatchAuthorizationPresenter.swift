import DomainKit

/// Maps `WatchAuthorizationState` into runner-facing copy and the request
/// affordance's availability for the Settings screen's Watch permission row.
///
/// Like `FeatureBuilder`'s `ValidationMessagePresenter`, every switch is
/// exhaustive with no `default:` case, so a new `WatchAuthorizationState`
/// case fails this file's compilation instead of silently rendering stale
/// copy or an incorrect action affordance.
enum WatchAuthorizationPresenter {
    /// A short status label for `state`, e.g. for a settings row's trailing text.
    static func statusLabel(for state: WatchAuthorizationState) -> String {
        switch state {
        case .notDetermined:
            return "Not Requested"
        case .restricted:
            return "Restricted"
        case .denied:
            return "Denied"
        case .authorized:
            return "Authorized"
        }
    }

    /// A longer, actionable description for `state`, shown beneath the row.
    static func detail(for state: WatchAuthorizationState) -> String {
        switch state {
        case .notDetermined:
            return "Allow Stride to schedule workouts on your paired Apple Watch."
        case .restricted:
            return "Watch scheduling is restricted on this device (e.g. by parental controls) and can't be changed here."
        case .denied:
            return "Stride can't schedule workouts on your Apple Watch. To re-enable access, " +
                "open the Watch app on your iPhone and allow Stride under My Watch > Workout."
        case .authorized:
            return "Stride can schedule workouts on your paired Apple Watch."
        }
    }

    /// Whether a "Request Access" action should be shown for `state`.
    ///
    /// Only `.notDetermined` gets an action: `.denied`/`.restricted` have no
    /// in-API re-prompt (RESEARCH-LOG §5 — recovery is the Watch app on
    /// iPhone, not a repeated request here), and `.authorized` needs none.
    static func canRequestAuthorization(for state: WatchAuthorizationState) -> Bool {
        switch state {
        case .notDetermined:
            return true
        case .restricted, .denied, .authorized:
            return false
        }
    }
}
