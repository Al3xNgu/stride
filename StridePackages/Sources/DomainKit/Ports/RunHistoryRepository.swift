import Foundation

/// A typed error surfaced by a `RunHistoryRepository` implementation.
public enum RunHistoryRepositoryError: Error, Equatable, Hashable, Sendable {
    /// No `CompletedRun` exists for the given id.
    case runNotFound(id: UUID)
    /// No `PersonalBest` exists for the given id.
    case personalBestNotFound(id: UUID)
    /// An unexpected underlying failure, with a human-readable description.
    case underlying(String)
}

/// Persists and queries `CompletedRun` projections and `PersonalBest` records.
///
/// `CompletedRun` and `PersonalBest` are grouped onto a single port rather
/// than split across two: `docs/ARCHITECTURE.md` §9.4's storage table lists
/// "CompletedRun projections, splits, PRs, HK anchors" as one SwiftData
/// grouping (all rebuildable, cache/derived data), and §8's ingestion flow
/// treats PR persistence as the direct, same-transaction continuation of run
/// ingestion (`IngestCompletedRunsUseCase`: upsert run -> compute PRs ->
/// persist). Decision judgment call: §6's component table's one-line
/// `WorkoutRepository` row ("CRUD for workouts, sync jobs, PRs, prefs") reads
/// as informal shorthand for "the SwiftData layer" rather than a literal
/// protocol boundary — taken literally it would also put `UserPreferences`
/// (UserDefaults-backed, per the same §9.4 table) on `WorkoutRepository`,
/// which contradicts the diagram's dedicated `UserDefaultsPreferences`
/// adapter. Flagged for reviewer confirmation.
///
/// Deletion is modeled as a tombstone (`markDeleted`) rather than physical
/// removal, matching `CompletedRun.isDeleted` and the §8 ingestion note that
/// HealthKit deletions are handled by "tombstoning the projection" so
/// dependent records (e.g. a `PersonalBest` referencing the run) remain
/// explainable; this also anticipates task 1.12's deletion-sync needs.
public protocol RunHistoryRepository: Sendable {
    /// Inserts or replaces `run`, keyed by `run.id` (the source `HKWorkout`
    /// UUID) — idempotent upsert, per §8.
    func upsert(_ run: CompletedRun) async throws

    /// Fetches every non-tombstoned and tombstoned run (callers filter on
    /// `isDeleted` as needed).
    func fetchAll() async throws -> [CompletedRun]

    /// Fetches the run with the given id, or `nil` if none exists.
    func fetch(id: UUID) async throws -> CompletedRun?

    /// Fetches every run whose `date` falls within `startDate...endDate`.
    func fetch(from startDate: Date, to endDate: Date) async throws -> [CompletedRun]

    /// Marks the run with the given id as deleted (tombstone), leaving the
    /// projection itself in place. Throws `RunHistoryRepositoryError.runNotFound`
    /// if no such run exists.
    func markDeleted(id: UUID) async throws

    /// Persists `splits` for `runID`, replacing any splits previously saved
    /// for that run.
    ///
    /// Splits are derived once, at ingestion time, from a run's cumulative
    /// distance samples (`docs/ARCHITECTURE.md` §5/§8) and then persisted
    /// alongside the run projection — per §9.4's storage table, "CompletedRun
    /// projections, **splits**, PRs, HK anchors" are one SwiftData grouping —
    /// so History/Records screens can display them instantly offline without
    /// re-deriving them from HealthKit on every read.
    func saveSplits(_ splits: [Split], for runID: UUID) async throws

    /// Fetches every split saved for `runID`, ordered by `index` ascending.
    ///
    /// Returns an empty array (never throws `runNotFound`) when `runID` is
    /// unknown or has no splits saved yet — an empty result is a normal,
    /// expected state (e.g. a run that hasn't finished split derivation),
    /// not an error.
    func fetchSplits(runID: UUID) async throws -> [Split]

    /// Persists `personalBest`, inserting it if new or replacing the
    /// existing value if `personalBest.id` already exists.
    func savePersonalBest(_ personalBest: PersonalBest) async throws

    /// Fetches every stored personal best (current and superseded records).
    func fetchPersonalBests() async throws -> [PersonalBest]

    /// Fetches the current personal best for `milestoneID`, or `nil` if none
    /// has been set yet.
    ///
    /// `PersonalBest` has no superseded flag (§5: "plus superseded records
    /// for 'PR history'" are just other stored `PersonalBest`s that share a
    /// `milestoneID`), so "current" is defined here, precisely, as: among
    /// every stored record for `milestoneID`, the one with the lowest
    /// `elapsedSeconds`; ties broken by the latest `achievedAt`; remaining
    /// ties broken by `id.uuidString` ascending, for total determinism.
    /// Implementations MUST apply exactly this ordering.
    func fetchPersonalBest(milestoneID: UUID) async throws -> PersonalBest?

    /// Deletes the personal best with the given id (e.g. pruning a
    /// superseded record).
    func deletePersonalBest(id: UUID) async throws
}
