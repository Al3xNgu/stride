import DomainKit
import Foundation

/// A typed error surfaced by `LibraryViewModel`'s send/schedule/retry
/// operations, for failures that happen *before* (or entirely outside of) a
/// `SyncJob` state transition the badge can represent.
///
/// Per `ScheduleWorkoutUseCase`'s doc comment, a pre-flight validation
/// failure or a "no such workout" error is thrown *before* any `SyncJob` is
/// created/mutated — there is no job for `BadgeState` to reflect, so it must
/// be surfaced separately. `WorkoutRepository` failures mid-flow propagate
/// the same way ("not a sync failure the state machine can represent").
/// A `WatchSyncService` failure (e.g. `.notAuthorized`), by contrast, *is*
/// captured as `SyncJob.state == .failed(reason)` by the use case itself and
/// never reaches this type — that path is presented via `BadgeState.failed`
/// and `SyncFailurePresenter` instead.
public enum LibrarySendError: Equatable, Hashable, Sendable {
    /// No `Workout` exists for the id the caller sent/scheduled.
    case workoutNotFound(id: UUID)
    /// The workout failed pre-flight structural validation; every violation
    /// found is included.
    case invalidWorkout([ValidationIssue])
    /// A `WorkoutRepository` operation elsewhere in the flow failed.
    case repository(WorkoutRepositoryError)
    /// An unrecognized underlying failure, with a human-readable description.
    case underlying(String)

    /// Maps any error thrown by `SyncCoordinator.scheduleWorkout` (which
    /// itself rethrows `ScheduleWorkoutUseCase`'s and `WorkoutRepository`'s
    /// errors untouched) onto this vocabulary.
    static func map(_ error: Error) -> LibrarySendError {
        if let scheduleError = error as? ScheduleWorkoutError {
            switch scheduleError {
            case let .workoutNotFound(id):
                return .workoutNotFound(id: id)
            case let .invalidWorkout(issues):
                return .invalidWorkout(issues)
            }
        }
        if let repositoryError = error as? WorkoutRepositoryError {
            return .repository(repositoryError)
        }
        return .underlying(String(describing: error))
    }
}
