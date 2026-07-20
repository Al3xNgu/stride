import Testing
import Foundation
@testable import DomainKit
import TestSupport

/// A `WorkoutRepository` decorator whose `fetchLatestSyncJob(workoutID:)`
/// mutates its own backing store to `.stale` immediately after returning the
/// FIRST lookup for `raceWorkoutID` — deterministically simulating
/// `SyncCoordinator` concurrently marking a job stale (via
/// `markStaleIfEdited`/`reconcile`) in the window between
/// `IngestCompletedRunsUseCase`'s pre-lock attribution snapshot (the first
/// call) and `SyncCoordinator.linkCompletedRun`'s own fresh, in-lock re-fetch
/// of the same job (the second call) — without needing real concurrent
/// `Task`s, since both reads happen from the same synchronous `execute(_:)`
/// call. Every other call is forwarded to `inner` unmodified. Matches the
/// decorator-around-a-fake style `SyncCoordinatorConcurrencyTests` uses for
/// race-shaped coverage.
private final class StaleAfterFirstLookupWorkoutRepository: WorkoutRepository, @unchecked Sendable {
    private let inner: FakeWorkoutRepository
    private let raceWorkoutID: UUID
    private var hasBeenLookedUp = false

    init(inner: FakeWorkoutRepository, raceWorkoutID: UUID) {
        self.inner = inner
        self.raceWorkoutID = raceWorkoutID
    }

    func save(_ workout: Workout) async throws { try await inner.save(workout) }
    func fetchAll() async throws -> [Workout] { try await inner.fetchAll() }
    func fetch(id: UUID) async throws -> Workout? { try await inner.fetch(id: id) }
    func delete(id: UUID) async throws { try await inner.delete(id: id) }
    func saveSyncJob(_ syncJob: SyncJob) async throws { try await inner.saveSyncJob(syncJob) }
    func fetchSyncJob(id: UUID) async throws -> SyncJob? { try await inner.fetchSyncJob(id: id) }
    func fetchSyncJobs(workoutID: UUID) async throws -> [SyncJob] {
        try await inner.fetchSyncJobs(workoutID: workoutID)
    }

    func fetchLatestSyncJob(workoutID: UUID) async throws -> SyncJob? {
        let job = try await inner.fetchLatestSyncJob(workoutID: workoutID)
        if workoutID == raceWorkoutID, !hasBeenLookedUp {
            hasBeenLookedUp = true
            if var raced = job {
                // Persist the "raced" state directly into `inner` — the NEXT
                // lookup (the coordinator's in-lock re-fetch) sees `.stale`,
                // exactly as if a concurrent `SyncCoordinator` call had
                // landed in between.
                raced.state = .stale
                try await inner.saveSyncJob(raced)
            }
        }
        return job
    }
}

/// Coverage of `IngestCompletedRunsUseCase`'s schedule-window attribution
/// heuristic: hit, miss (out-of-window and no-candidate), the ambiguous
/// nearest-wins tie-break, the exact-delta workoutID tie-break, idempotent
/// re-ingestion (no re-run/re-link), the pre-attributed-override case, and
/// the stale-at-link-time race the `SyncCoordinator`-owned write closes.
@Suite("IngestCompletedRunsUseCase — attribution")
struct IngestCompletedRunsAttributionTests {
    private typealias Fixtures = IngestCompletedRunsFixtures

    @Test("A run within the schedule window is attributed to its workout, and the SyncJob is linked")
    func attributionHit() async throws {
        let harness = Fixtures.makeHarness()
        let scheduledDate = Fixtures.referenceDate
        let workoutID = try await Fixtures.seedSyncedJob(in: harness.workouts, scheduledDate: scheduledDate)
        let run = Fixtures.makeRun(date: scheduledDate.addingTimeInterval(30 * 60))

        let report = try await harness.useCase.execute(IngestionBatch(runs: [IngestedRun(run: run)]))

        #expect(report.attributedRunIDs[run.id] == workoutID)
        #expect(harness.runHistory.runsByID[run.id]?.workoutID == workoutID)
        let job = try #require(await harness.workouts.fetchLatestSyncJob(workoutID: workoutID))
        #expect(job.state == .completedRunLinked)
    }

    @Test("A run outside every schedule window is left unattributed")
    func attributionMiss() async throws {
        let harness = Fixtures.makeHarness(attributionWindow: 60 * 60)
        let scheduledDate = Fixtures.referenceDate
        try await Fixtures.seedSyncedJob(in: harness.workouts, scheduledDate: scheduledDate)
        let run = Fixtures.makeRun(date: scheduledDate.addingTimeInterval(3 * 60 * 60))

        let report = try await harness.useCase.execute(IngestionBatch(runs: [IngestedRun(run: run)]))

        #expect(report.attributedRunIDs[run.id] == nil)
        #expect(harness.runHistory.runsByID[run.id]?.workoutID == nil)
    }

    @Test("No candidate schedule (no synced job) leaves the run unattributed")
    func attributionMissWithNoScheduledJobs() async throws {
        let harness = Fixtures.makeHarness()
        let run = Fixtures.makeRun()

        _ = try await harness.useCase.execute(IngestionBatch(runs: [IngestedRun(run: run)]))

        #expect(harness.runHistory.runsByID[run.id]?.workoutID == nil)
    }

    @Test("Ambiguous match (two candidates in window): nearest scheduledDate wins")
    func attributionAmbiguousNearestWins() async throws {
        let harness = Fixtures.makeHarness()
        let nearWorkoutID = try await Fixtures.seedSyncedJob(
            in: harness.workouts, scheduledDate: Fixtures.referenceDate.addingTimeInterval(-10 * 60)
        )
        try await Fixtures.seedSyncedJob(
            in: harness.workouts, scheduledDate: Fixtures.referenceDate.addingTimeInterval(-90 * 60)
        )
        let run = Fixtures.makeRun(date: Fixtures.referenceDate)

        let report = try await harness.useCase.execute(IngestionBatch(runs: [IngestedRun(run: run)]))

        #expect(report.attributedRunIDs[run.id] == nearWorkoutID)
        #expect(harness.runHistory.runsByID[run.id]?.workoutID == nearWorkoutID)
    }

    @Test("Ambiguous match with an exact tie in delta: lexicographically smaller workoutID wins")
    func attributionExactTieBrokenByWorkoutID() async throws {
        let harness = Fixtures.makeHarness()
        let lowID = UUID(uuidString: "00000000-0000-0000-0000-000000000001") ?? UUID()
        let highID = UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF") ?? UUID()
        try await Fixtures.seedSyncedJob(
            in: harness.workouts, scheduledDate: Fixtures.referenceDate.addingTimeInterval(-60), workoutID: highID
        )
        try await Fixtures.seedSyncedJob(
            in: harness.workouts, scheduledDate: Fixtures.referenceDate.addingTimeInterval(60), workoutID: lowID
        )
        let run = Fixtures.makeRun(date: Fixtures.referenceDate)

        let report = try await harness.useCase.execute(IngestionBatch(runs: [IngestedRun(run: run)]))

        #expect(report.attributedRunIDs[run.id] == lowID)
    }

    @Test("Re-ingesting an already-attributed run does not re-run the heuristic or re-link the job")
    func attributionIsNotReRunOnReingestion() async throws {
        let harness = Fixtures.makeHarness()
        let workoutID = try await Fixtures.seedSyncedJob(in: harness.workouts, scheduledDate: Fixtures.referenceDate)
        let run = Fixtures.makeRun(date: Fixtures.referenceDate)

        let firstReport = try await harness.useCase.execute(IngestionBatch(runs: [IngestedRun(run: run)]))
        #expect(firstReport.attributedRunIDs[run.id] == workoutID)

        harness.clock.advance(by: 10)
        let secondReport = try await harness.useCase.execute(IngestionBatch(runs: [IngestedRun(run: run)]))

        #expect(secondReport.attributedRunIDs[run.id] == nil, "no re-attribution reported the second time")
        #expect(harness.runHistory.runsByID[run.id]?.workoutID == workoutID)
        let job = try #require(await harness.workouts.fetchLatestSyncJob(workoutID: workoutID))
        #expect(job.updatedAt == Fixtures.referenceDate, "the job was not re-saved on the second, already-attributed ingestion")
    }

    @Test("An incoming run with a pre-set workoutID overrides the heuristic")
    func preAttributedIncomingRunSkipsHeuristic() async throws {
        let harness = Fixtures.makeHarness()
        try await Fixtures.seedSyncedJob(in: harness.workouts, scheduledDate: Fixtures.referenceDate)
        let overrideWorkoutID = UUID()
        let run = Fixtures.makeRun(date: Fixtures.referenceDate, workoutID: overrideWorkoutID)

        let report = try await harness.useCase.execute(IngestionBatch(runs: [IngestedRun(run: run)]))

        #expect(report.attributedRunIDs[run.id] == nil)
        #expect(harness.runHistory.runsByID[run.id]?.workoutID == overrideWorkoutID)
    }

    // MARK: - Stale-at-link-time race (SyncCoordinator-owned write)

    @Test("A job that races to .stale between attribution and link is NOT linked, but the run's attribution still persists")
    func staleAtLinkTimeIsNotOverwrittenButRunAttributionStillPersists() async throws {
        let underlyingWorkouts = FakeWorkoutRepository()
        let workoutID = try await Fixtures.seedSyncedJob(in: underlyingWorkouts, scheduledDate: Fixtures.referenceDate)
        let racingWorkouts = StaleAfterFirstLookupWorkoutRepository(inner: underlyingWorkouts, raceWorkoutID: workoutID)

        let runHistory = FakeRunHistoryRepository()
        let watchSync = FakeWatchSyncService()
        let clock = FakeClock(currentDate: Fixtures.referenceDate)
        let coordinator = SyncCoordinator(repository: racingWorkouts, watchSyncService: watchSync, clock: clock)
        let useCase = IngestCompletedRunsUseCase(
            runHistoryRepository: runHistory,
            workoutRepository: racingWorkouts,
            syncCoordinator: coordinator
        )
        let run = Fixtures.makeRun(date: Fixtures.referenceDate)

        let report = try await useCase.execute(IngestionBatch(runs: [IngestedRun(run: run)]))

        // Attribution itself still matched (the FIRST read saw `.synced`) —
        // the run-side attribution is independent of the job-state
        // transition and must persist regardless of the race below.
        #expect(report.attributedRunIDs[run.id] == workoutID)
        #expect(runHistory.runsByID[run.id]?.workoutID == workoutID)

        // But the link was declined: by the time `SyncCoordinator`'s
        // in-lock re-fetch ran (the SECOND read), the job had already
        // "raced" to `.stale` — it must remain `.stale`, never overwritten
        // to `.completedRunLinked`.
        let job = try #require(await underlyingWorkouts.fetchLatestSyncJob(workoutID: workoutID))
        #expect(job.state == .stale)
    }
}
