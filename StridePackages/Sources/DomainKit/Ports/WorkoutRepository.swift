import Foundation

/// A typed error surfaced by a `WorkoutRepository` implementation.
public enum WorkoutRepositoryError: Error, Equatable, Hashable, Sendable {
    /// No `Workout` exists for the given id.
    case workoutNotFound(id: UUID)
    /// No `SyncJob` exists for the given id.
    case syncJobNotFound(id: UUID)
    /// An unexpected underlying failure, with a human-readable description.
    case underlying(String)
}

/// Persists and queries `Workout`s and their `SyncJob` history.
///
/// Abstracts the SwiftData adapter described in `docs/ARCHITECTURE.md` §4/§9.4
/// ("Workout definitions, segments" and "SyncJobs + WorkoutKit plan IDs" both
/// live in SwiftData). `SyncJob` persistence is grouped onto this port rather
/// than a separate one because a `SyncJob` has no life outside the `Workout`
/// it belongs to (§5: "Workout -> SyncJob is one-to-many history") and the §7
/// sync state machine reads/writes both together — e.g. reconciliation loads
/// a workout's latest job to decide whether to mark it `.stale`.
public protocol WorkoutRepository: Sendable {
    /// Persists `workout`, inserting it if new or replacing the existing
    /// value if `workout.id` already exists.
    func save(_ workout: Workout) async throws

    /// Fetches every saved workout.
    func fetchAll() async throws -> [Workout]

    /// Fetches the workout with the given id, or `nil` if none exists.
    func fetch(id: UUID) async throws -> Workout?

    /// Deletes the workout with the given id, if it exists, and
    /// cascade-deletes every `SyncJob` recorded for that workout.
    ///
    /// A `SyncJob` has no life independent of the `Workout` it belongs to
    /// (§5: "Workout -> SyncJob is one-to-many history"), so removing the
    /// workout must remove its sync history too — matching the cascade
    /// relationship the future SwiftData model will declare.
    func delete(id: UUID) async throws

    /// Persists `syncJob`, inserting it if new or replacing the existing
    /// value if `syncJob.id` already exists.
    func saveSyncJob(_ syncJob: SyncJob) async throws

    /// Fetches the sync job with the given id, or `nil` if none exists.
    func fetchSyncJob(id: UUID) async throws -> SyncJob?

    /// Fetches every sync job recorded for `workoutID`, in no particular
    /// order — callers that need "the current state" should use
    /// `fetchLatestSyncJob(workoutID:)` instead.
    func fetchSyncJobs(workoutID: UUID) async throws -> [SyncJob]

    /// Fetches the most recently updated sync job for `workoutID` (the one
    /// that drives the library's sync badge — `docs/ARCHITECTURE.md` §5), or
    /// `nil` if the workout has never been synced.
    func fetchLatestSyncJob(workoutID: UUID) async throws -> SyncJob?
}
