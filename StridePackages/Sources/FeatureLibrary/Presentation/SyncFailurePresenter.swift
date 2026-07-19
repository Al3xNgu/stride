import DomainKit

/// Maps `SyncFailureReason` into runner-facing copy for a failed sync job's
/// detail view/alert.
///
/// Like `FeatureBuilder`'s `ValidationMessagePresenter`, the switch is
/// exhaustive with no `default:` case, so a new `SyncFailureReason` case
/// fails this file's compilation instead of silently rendering a blank
/// detail.
enum SyncFailurePresenter {
    /// A human-readable, actionable message for `reason`.
    static func message(for reason: SyncFailureReason) -> String {
        switch reason {
        case .notAuthorized:
            return "Stride isn't authorized to schedule workouts on your Apple Watch. " +
                "Open the Watch app on your iPhone to allow access, then try again."

        case .invalidComposition:
            return "This workout couldn't be converted into something the Watch app understands. " +
                "Try adjusting its segments and sending again."

        case .noPairedWatch:
            return "No paired Apple Watch was found, or the Workout app isn't installed on it."

        case let .transient(description):
            return "A temporary problem occurred while sending this to your Watch: \(description). " +
                "Stride will retry automatically."
        }
    }
}
