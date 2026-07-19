import DomainKit

/// Maps `BadgeState` into the library row badge's label text and SF Symbol
/// name.
///
/// Both switches are exhaustive with no `default:` case (same rationale as
/// `SyncFailurePresenter`): a new `BadgeState` case fails this file's
/// compilation instead of silently rendering a blank/missing badge.
enum LibraryBadgePresenter {
    /// The badge's label text for `state`.
    static func label(for state: BadgeState) -> String {
        switch state {
        case .notSynced:
            return "Not Sent"
        case .pending:
            return "Queued"
        case .syncing:
            return "Sending…"
        case .synced:
            return "On Watch"
        case .stale:
            return "Needs Re-send"
        case .failed:
            return "Failed"
        case .abandoned:
            return "Couldn't Send"
        case .completedRunLinked:
            return "Completed"
        }
    }

    /// The badge's SF Symbol name for `state`.
    static func systemImageName(for state: BadgeState) -> String {
        switch state {
        case .notSynced:
            return "icloud.slash"
        case .pending:
            return "clock"
        case .syncing:
            return "arrow.triangle.2.circlepath"
        case .synced:
            return "checkmark.circle.fill"
        case .stale:
            return "exclamationmark.arrow.triangle.2.circlepath"
        case .failed:
            return "xmark.octagon.fill"
        case .abandoned:
            return "exclamationmark.octagon"
        case .completedRunLinked:
            return "flag.checkered.circle.fill"
        }
    }
}
