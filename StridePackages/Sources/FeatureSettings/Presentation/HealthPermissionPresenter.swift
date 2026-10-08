import DomainKit

/// Maps `HealthPermissionStatus` into runner-facing copy for the Settings
/// screen's HealthKit permission row.
///
/// Exhaustive with no `default:` case (same rationale as
/// `WatchAuthorizationPresenter`): a new `HealthPermissionStatus` case fails
/// this file's compilation instead of silently rendering stale copy.
enum HealthPermissionPresenter {
    /// A short status label for `status`, e.g. for a settings row's trailing text.
    static func statusLabel(for status: HealthPermissionStatus) -> String {
        switch status {
        case .unknown:
            return "Unknown"
        case .shouldRequest:
            return "Not Requested"
        case .unnecessary:
            return "Requested"
        }
    }

    /// A longer description for `status`, shown beneath the row.
    ///
    /// HealthKit deliberately hides read denial (see
    /// `HealthPermissionPriming`'s doc comment), so this never claims access
    /// was granted — only that a request has (or hasn't) been made.
    static func detail(for status: HealthPermissionStatus) -> String {
        switch status {
        case .unknown:
            return "Stride couldn't determine whether it has asked to read your run history from Health yet."
        case .shouldRequest:
            return "Allow Stride to read your runs, distance, and heart rate from Health to build your history and records."
        case .unnecessary:
            return "Stride has already asked for access to Health. If runs aren't appearing, check " +
                "Health > Data Access & Devices > Stride."
        }
    }

    /// Whether a "Grant Access" action should be shown for `status`.
    ///
    /// Unlike Watch authorization, re-requesting HealthKit access is safe
    /// even when `.unnecessary` (it shows no new prompt, per
    /// `HealthPermissionPriming`'s doc comment) — an action is offered for
    /// every status so the user can always retry after checking Health
    /// settings.
    static func canRequestAccess(for status: HealthPermissionStatus) -> Bool {
        switch status {
        case .unknown, .shouldRequest, .unnecessary:
            return true
        }
    }

    /// A user-facing explanation for an operational failure while asking for
    /// Health access. The diagnostic text in `.underlying` is intentionally
    /// omitted so framework implementation details do not leak into the UI.
    static func errorMessage(for error: HealthPermissionPrimingError) -> String {
        switch error {
        case .unavailable:
            return "Health data isn't available on this device."
        case .requestFailed:
            return "Stride couldn't request access to Health. Try again later."
        case .underlying:
            return "Stride couldn't check Health access. Try again later."
        }
    }
}
