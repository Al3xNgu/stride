import Foundation

/// A typed, human-readable reason a `SyncJob` failed.
///
/// Modeled as an enum (rather than a bare `String`) per CLAUDE.md's "errors
/// must be typed" rule, while still carrying a description for transient
/// failures whose underlying cause is only known at the call site.
public enum SyncFailureReason: Equatable, Hashable, Codable, Sendable {
    /// WorkoutKit/Watch authorization has not been granted.
    case notAuthorized
    /// The domain `Workout` failed to map to a valid WorkoutKit composition.
    case invalidComposition
    /// No Apple Watch is currently paired.
    case noPairedWatch
    /// A transient failure (network, system busy, etc.) with a
    /// human-readable description, eligible for retry with backoff.
    case transient(description: String)
}

/// The state of a `SyncJob`, per the state machine in
/// `docs/ARCHITECTURE.md` §7:
///
/// ```
/// draft -> pending -> syncing -> synced -> (completedRunLinked | stale)
///                        |
///                        +-> failed -> pending (retry) | abandoned
/// ```
public enum SyncJobState: Equatable, Hashable, Codable, Sendable {
    /// The job has been created but not yet queued for sync.
    case draft
    /// The job is queued and waiting to be picked up.
    case pending
    /// The job is actively being synced to WorkoutKit.
    case syncing
    /// The job succeeded; the workout is scheduled/on the Watch.
    case synced
    /// The job failed with a typed reason; may be retried (back to
    /// `.pending`) or abandoned.
    case failed(SyncFailureReason)
    /// The job was abandoned after failure and will not be retried
    /// automatically.
    case abandoned
    /// A completed `HKWorkout` has been linked back to this sync job's
    /// workout (successful attribution after `.synced`).
    case completedRunLinked
    /// The underlying workout was edited after this job reached `.synced`,
    /// making the scheduled Watch copy stale; the user should be prompted
    /// to re-send.
    case stale
}

/// A record of one sync attempt/schedule of a `Workout` to the Apple Watch
/// Workout app via WorkoutKit.
///
/// `SyncJob` exists because sync is a process, not a property of `Workout`:
/// keeping it separate means a workout can have a history of syncs, retries
/// are auditable, and the library's sync badge is a cheap query
/// (`docs/ARCHITECTURE.md` §5). The WorkoutKit plan identifier is stored as
/// an opaque `String?` — DomainKit must never import WorkoutKit itself.
public struct SyncJob: Identifiable, Equatable, Hashable, Codable, Sendable {
    /// Stable identity of this sync job.
    public let id: UUID
    /// The `Workout` this job is syncing.
    public var workoutID: UUID
    /// Current state in the §7 state machine.
    public var state: SyncJobState
    /// When this job was created.
    public var createdAt: Date
    /// When this job was last updated.
    public var updatedAt: Date
    /// Opaque WorkoutKit plan identifier, once scheduled. DomainKit treats
    /// this as an opaque string; only DataKit's WorkoutKit adapter
    /// interprets it.
    public var planIdentifier: String?
    /// The date the user scheduled this workout for, if a specific
    /// date/time was chosen (as opposed to an immediate "Send to Watch").
    public var scheduledDate: Date?
    /// Number of sync attempts made so far, for retry/backoff bookkeeping.
    public var attemptCount: Int

    /// Creates a sync job.
    public init(
        id: UUID = UUID(),
        workoutID: UUID,
        state: SyncJobState = .draft,
        createdAt: Date,
        updatedAt: Date,
        planIdentifier: String? = nil,
        scheduledDate: Date? = nil,
        attemptCount: Int = 0
    ) {
        self.id = id
        self.workoutID = workoutID
        self.state = state
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.planIdentifier = planIdentifier
        self.scheduledDate = scheduledDate
        self.attemptCount = attemptCount
    }
}
