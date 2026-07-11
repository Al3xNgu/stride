import Foundation

/// A typed error surfaced by a DataKit mapper when persisted data cannot be
/// mapped back into (or encoded from) its domain shape.
///
/// Mapper failures must never crash or silently drop data (CLAUDE.md's "no
/// force-unwraps... errors are typed and surfaced, not swallowed"). Every
/// case here is caught by the repository that invoked the mapper and
/// translated into that repository's own port error (e.g.
/// `WorkoutRepositoryError.underlying`), so callers above `DataKit` never
/// see this type directly.
public enum DataKitError: Error, Equatable, Hashable, Sendable {
    /// A `WorkoutModel` (or one of its `WorkoutSegmentModel` rows) could not
    /// be decoded back into a domain `Workout` — e.g. corrupted segment
    /// data or an unrecognized `activityRaw` value.
    case corruptedWorkout(workoutID: UUID, reason: String)
    /// A `SyncJobModel`'s encoded `stateData` could not be decoded back into
    /// a domain `SyncJobState`.
    case corruptedSyncState(syncJobID: UUID, reason: String)
    /// A domain value failed to encode to its persisted representation.
    /// Reachable in practice: `Goal`/`Target` carry bare `Double` fields, and
    /// `JSONEncoder`'s default non-conforming-float strategy throws for
    /// NaN/Infinity values (covered by DataKitTests), so mappers must stay
    /// total rather than force-trying the encode.
    case encodingFailed(reason: String)
}

extension DataKitError: CustomStringConvertible {
    /// A human-readable description, used to build the owning port's
    /// `.underlying(String)` error case.
    public var description: String {
        switch self {
        case let .corruptedWorkout(workoutID, reason):
            return "Workout \(workoutID) has corrupted persisted data: \(reason)"
        case let .corruptedSyncState(syncJobID, reason):
            return "SyncJob \(syncJobID) has corrupted persisted state: \(reason)"
        case let .encodingFailed(reason):
            return "Failed to encode a domain value for persistence: \(reason)"
        }
    }
}
