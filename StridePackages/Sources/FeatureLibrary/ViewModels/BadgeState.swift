import DomainKit

/// A view-facing projection of a workout's latest `SyncJob`, collapsing the
/// "never synced" case (`fetchLatestSyncJob` returned `nil`) into its own
/// case so `LibraryViewModel.Row`/the badge view never need to unwrap an
/// `Optional<SyncJob>` themselves.
///
/// Mirrors every `SyncJobState` case 1:1 (`.draft` also collapses to
/// `.notSynced`: per `ScheduleWorkoutUseCase`'s doc comment, a `.draft` job is
/// only ever a transient in-memory value on the very first send — it is
/// always advanced to `.pending` before its first persist, so a caller reading
/// `fetchLatestSyncJob` should never actually observe it, but the case is
/// mapped defensively rather than assumed unreachable).
public enum BadgeState: Equatable, Hashable, Sendable {
    /// No `SyncJob` has ever been recorded for this workout (or its one
    /// existing job is still `.draft`).
    case notSynced
    /// A send is queued and waiting to be picked up.
    case pending
    /// A send is actively in flight.
    case syncing
    /// The workout is synced/scheduled on the Watch.
    case synced
    /// The workout was edited after its last successful sync; the Watch copy
    /// is out of date and the user should be prompted to re-send.
    case stale
    /// The most recent send attempt failed with a typed, presentable reason.
    case failed(SyncFailureReason)
    /// The job failed repeatedly and was abandoned; retrying requires an
    /// explicit user action (`LibraryViewModel.retryFailed(workoutID:)`).
    case abandoned
    /// A completed `HKWorkout` has been linked back to this sync job.
    case completedRunLinked

    /// Maps `job` (or `nil`, for "never synced") onto its `BadgeState`.
    ///
    /// Exhaustive over every `SyncJobState` case with no `default:`, so a new
    /// case added to `SyncJobState` fails this file's compilation instead of
    /// silently falling through to `.notSynced` (same rationale as
    /// `FeatureBuilder`'s `ValidationMessagePresenter`).
    public static func from(_ job: SyncJob?) -> BadgeState {
        guard let job else { return .notSynced }
        switch job.state {
        case .draft:
            return .notSynced
        case .pending:
            return .pending
        case .syncing:
            return .syncing
        case .synced:
            return .synced
        case .stale:
            return .stale
        case let .failed(reason):
            return .failed(reason)
        case .abandoned:
            return .abandoned
        case .completedRunLinked:
            return .completedRunLinked
        }
    }
}
