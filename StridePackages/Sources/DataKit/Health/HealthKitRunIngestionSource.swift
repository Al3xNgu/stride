import DomainKit
import Foundation

/// One `CompletedRun` projection paired with its derived per-distance
/// splits, as produced by a single HealthKit ingestion fetch.
public struct IngestedRun: Equatable, Hashable, Sendable {
    /// The projected run.
    public var run: CompletedRun
    /// Splits derived from the run's cumulative-distance series
    /// (`SplitDerivation`), ordered by `index` ascending.
    public var splits: [Split]

    /// Creates an ingested run.
    public init(run: CompletedRun, splits: [Split]) {
        self.run = run
        self.splits = splits
    }
}

/// The result of one `HealthKitRunIngestionSource.fetchRunningWorkouts` call.
public struct HealthKitRunFetchResult: Equatable, Hashable, Sendable {
    /// Every running workout added or changed since the supplied anchor,
    /// already projected and split.
    public var ingestedRuns: [IngestedRun]
    /// UUIDs of workouts HealthKit reports as deleted since the supplied
    /// anchor — callers tombstone (`RunHistoryRepository.markDeleted`) the
    /// matching `CompletedRun`s, per `docs/ARCHITECTURE.md` §8.
    public var deletedWorkoutIDs: [UUID]
    /// The anchor to persist and pass as `since:` on the next call. The
    /// caller owns persistence (this type never reads/writes UserDefaults or
    /// SwiftData itself).
    public var newAnchor: Data

    /// Creates a fetch result.
    public init(ingestedRuns: [IngestedRun], deletedWorkoutIDs: [UUID], newAnchor: Data) {
        self.ingestedRuns = ingestedRuns
        self.deletedWorkoutIDs = deletedWorkoutIDs
        self.newAnchor = newAnchor
    }
}

/// A typed error surfaced by a `HealthKitRunIngestionSource` implementation.
public enum HealthKitIngestionError: Error, Equatable, Hashable, Sendable {
    /// HealthKit is not available on this device (e.g. no Health app store,
    /// or running on a platform where `HKHealthStore.isHealthDataAvailable()`
    /// is `false`).
    case notAvailable
    /// The read-authorization request itself failed (not the same as being
    /// denied — HealthKit gives no API to detect read denial; see
    /// `docs/RESEARCH-LOG.md` 2026-07-19 Task 1.10 §3).
    case authorizationFailed(String)
    /// A caller-supplied anchor `Data` blob could not be decoded back into
    /// an `HKQueryAnchor`.
    case anchorDecodeFailed
    /// An unexpected underlying failure, with a human-readable description.
    case underlying(String)
}

/// A narrow, DataKit-local protocol for the HealthKit *ingestion* side of run
/// history: read-only authorization priming, plus an anchored incremental
/// fetch of running `HKWorkout`s with per-workout split derivation already
/// applied.
///
/// This is deliberately **not** an implementation of
/// `DomainKit.RunHistoryRepository`, and deliberately **not** a new
/// `DomainKit` port. `RunHistoryRepository`'s own doc comment (and
/// `docs/ARCHITECTURE.md` §9.4's storage table, "CompletedRun projections,
/// splits, PRs, HK anchors" as one SwiftData grouping) frames it as the
/// *persistence* side of run history — naturally a SwiftData-backed
/// implementation, symmetric with `SwiftDataWorkoutRepository`. HealthKit's
/// job is upstream of that: read completed runs *from HealthKit* and hand
/// back ready-to-upsert projections; a future `IngestCompletedRunsUseCase`
/// (task 1.12, `DomainKit`) is the orchestrator that pulls from a source like
/// this one and pushes into `RunHistoryRepository` (`docs/ARCHITECTURE.md`
/// §8, steps 1-4). Modeling ingestion as its own small protocol — rather
/// than folding "read from HealthKit" methods onto `RunHistoryRepository`, or
/// adding a brand-new `DomainKit` port unilaterally — keeps `DomainKit`
/// HealthKit-free (CLAUDE.md rule 1) while still giving DataKit a swappable,
/// fakeable seam of its own for this task's scope. **Flagged for reviewer
/// confirmation**: if 1.12's use case needs to depend on this abstraction
/// directly (rather than a thin DataKit-only wrapper calling it), promoting
/// this shape into a `DomainKit` port is a small, mechanical follow-up — not
/// something this task should decide unilaterally.
///
/// The anchor is opaque `Data`, supplied and returned by the caller on every
/// call — this type never persists it itself (no UserDefaults/SwiftData
/// access here), per `docs/RESEARCH-LOG.md` 2026-07-19 Task 1.10 §1's
/// anchor-ownership note and this task's scope boundary.
public protocol HealthKitRunIngestionSource: Sendable {
    /// Requests read-only HealthKit authorization for workout/distance/
    /// heart-rate reads, but only when HealthKit reports we haven't asked
    /// yet (`statusForAuthorizationRequest(...) == .shouldRequest` —
    /// RESEARCH-LOG §3). A no-op once authorization has already been
    /// requested once, since HealthKit gives no way to tell whether that
    /// prior request was granted or denied for reads.
    func requestAuthorizationIfNeeded() async throws

    /// Fetches every running `HKWorkout` added, changed, or deleted since
    /// `anchor` (`nil` = initial full fetch), producing a `CompletedRun` +
    /// derived `Split`s (cut every `splitDistanceMeters`, e.g.
    /// `SplitDerivation.kilometerMeters` or `.mileMeters`) per added/changed
    /// workout, plus any deleted workout UUIDs and the anchor to persist for
    /// the next call.
    func fetchRunningWorkouts(
        since anchor: Data?,
        splitDistanceMeters: Double
    ) async throws -> HealthKitRunFetchResult
}
