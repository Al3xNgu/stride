import Testing
import Foundation
@testable import DomainKit
import TestSupport

/// `SyncCoordinator`'s core retry/stale/foreground-reconcile behavior.
///
/// State-machine-legality, backoff-math, and reconciliation-adversarial
/// coverage lives in `SyncCoordinatorStateMachineTests.swift`; concurrency
/// and reentrancy coverage (which need dedicated actor-isolated test doubles)
/// lives in `SyncCoordinatorConcurrencyTests.swift` — split out to keep each
/// suite within the repo's file/type-length lint limits.
@Suite("SyncCoordinator")
struct SyncCoordinatorTests {
    private typealias Fixtures = ScheduleWorkoutFixtures

    // MARK: - Retry with backoff

    @Test("transient failure is retried after its backoff elapses, not before, and succeeds on attempt 2")
    func retryAfterBackoffSucceeds() async throws {
        let workout = Fixtures.makeWorkout()
        let repository = FakeWorkoutRepository(workouts: [workout])
        let watchSync = FakeWatchSyncService()
        let clock = FakeClock(currentDate: Fixtures.referenceDate)
        let coordinator = SyncCoordinator(
            repository: repository,
            watchSyncService: watchSync,
            clock: clock,
            maxAttempts: 3,
            backoffBaseSeconds: 10
        )

        watchSync.errorToThrow = WatchSyncError.underlying("busy")
        let failed = try await coordinator.scheduleWorkout(workoutID: workout.id)
        guard case .failed(.transient) = failed.state else {
            Issue.record("Expected first attempt to fail transiently, got \(failed.state)")
            return
        }
        #expect(failed.attemptCount == 1)
        #expect(watchSync.scheduleCalls.count == 1)

        // Not due yet — retrying immediately must not re-attempt.
        let tooEarly = try await coordinator.retryDueJobs()
        #expect(tooEarly.isEmpty)
        #expect(watchSync.scheduleCalls.count == 1)

        // Advance exactly to the documented backoff (base * 2^0 = 10s) and
        // let the underlying call succeed this time.
        clock.advance(by: 10)
        watchSync.errorToThrow = nil
        let retried = try await coordinator.retryDueJobs()

        #expect(retried.count == 1)
        #expect(retried.first?.state == .synced)
        #expect(retried.first?.attemptCount == 2)
        #expect(watchSync.scheduleCalls.count == 2)
        // The plan id stayed stable across the retry (replace semantics).
        #expect(watchSync.scheduleCalls.map(\.planID) == [failed.id, failed.id])
    }

    @Test("a permanent failure (e.g. not authorized) is never auto-retried")
    func permanentFailureIsNotRetried() async throws {
        let workout = Fixtures.makeWorkout()
        let repository = FakeWorkoutRepository(workouts: [workout])
        let watchSync = FakeWatchSyncService()
        watchSync.errorToThrow = WatchSyncError.unauthorized(.denied)
        let clock = FakeClock(currentDate: Fixtures.referenceDate)
        let coordinator = SyncCoordinator(repository: repository, watchSyncService: watchSync, clock: clock)

        let job = try await coordinator.scheduleWorkout(workoutID: workout.id)
        #expect(job.state == .failed(.notAuthorized))

        clock.advance(by: 10_000)
        let retried = try await coordinator.retryDueJobs()
        #expect(retried.isEmpty)
        #expect(watchSync.scheduleCalls.count == 1)
    }

    @Test("a transient failure that exhausts maxAttempts is abandoned, not retried forever")
    func exhaustedRetriesAreAbandoned() async throws {
        let workout = Fixtures.makeWorkout()
        let repository = FakeWorkoutRepository(workouts: [workout])
        let watchSync = FakeWatchSyncService()
        watchSync.errorToThrow = WatchSyncError.underlying("always busy")
        let clock = FakeClock(currentDate: Fixtures.referenceDate)
        let coordinator = SyncCoordinator(
            repository: repository,
            watchSyncService: watchSync,
            clock: clock,
            maxAttempts: 2,
            backoffBaseSeconds: 5
        )

        let first = try await coordinator.scheduleWorkout(workoutID: workout.id)
        #expect(first.attemptCount == 1)

        clock.advance(by: 5)
        let secondAttempt = try await coordinator.retryDueJobs()
        #expect(secondAttempt.count == 1)
        #expect(secondAttempt.first?.attemptCount == 2)

        // maxAttempts (2) reached with the failure still transient — the
        // job is abandoned, not scheduled for a third retry.
        let persisted = try await repository.fetchSyncJob(id: first.id)
        #expect(persisted?.state == .abandoned)

        clock.advance(by: 10_000)
        let thirdAttempt = try await coordinator.retryDueJobs()
        #expect(thirdAttempt.isEmpty)
        #expect(watchSync.scheduleCalls.count == 2)
    }

    // MARK: - Stale on edit

    @Test("a synced job is marked stale once its workout is edited afterward")
    func syncedJobGoesStaleOnEdit() async throws {
        let workout = Fixtures.makeWorkout()
        let repository = FakeWorkoutRepository(workouts: [workout])
        let watchSync = FakeWatchSyncService()
        let clock = FakeClock(currentDate: Fixtures.referenceDate)
        let coordinator = SyncCoordinator(repository: repository, watchSyncService: watchSync, clock: clock)

        let synced = try await coordinator.scheduleWorkout(workoutID: workout.id)
        #expect(synced.state == .synced)

        clock.advance(by: 60)
        var edited = workout
        edited.name = "Easy 5k (edited)"
        edited.updatedAt = clock.now()
        try await repository.save(edited)

        let staleJob = try await coordinator.markStaleIfEdited(workoutID: workout.id)
        #expect(staleJob?.state == .stale)

        let persisted = try await repository.fetchSyncJob(id: synced.id)
        #expect(persisted?.state == .stale)
    }

    @Test("markStaleIfEdited is a no-op when the workout has not changed since sync")
    func markStaleIfEditedNoOpWhenUnchanged() async throws {
        let workout = Fixtures.makeWorkout()
        let repository = FakeWorkoutRepository(workouts: [workout])
        let watchSync = FakeWatchSyncService()
        let clock = FakeClock(currentDate: Fixtures.referenceDate)
        let coordinator = SyncCoordinator(repository: repository, watchSyncService: watchSync, clock: clock)

        let synced = try await coordinator.scheduleWorkout(workoutID: workout.id)
        let result = try await coordinator.markStaleIfEdited(workoutID: workout.id)

        #expect(result == nil)
        let persisted = try await repository.fetchSyncJob(id: synced.id)
        #expect(persisted?.state == .synced)
    }

    // MARK: - Foreground reconciliation

    @Test("reconcile marks a synced job failed when it vanishes from the Watch")
    func reconcileMarksMissingSyncedJobFailed() async throws {
        let workout = Fixtures.makeWorkout()
        let repository = FakeWorkoutRepository(workouts: [workout])
        let watchSync = FakeWatchSyncService()
        let clock = FakeClock(currentDate: Fixtures.referenceDate)
        let coordinator = SyncCoordinator(repository: repository, watchSyncService: watchSync, clock: clock)

        let synced = try await coordinator.scheduleWorkout(workoutID: workout.id)
        #expect(synced.state == .synced)

        // The user removes it directly on the Watch.
        try await watchSync.remove(planID: synced.id)

        let report = try await coordinator.reconcile()

        #expect(report.markedFailed == [synced.id])
        #expect(report.markedStale.isEmpty)

        let persisted = try await repository.fetchSyncJob(id: synced.id)
        guard case .failed(.transient) = persisted?.state else {
            Issue.record("Expected .failed(.transient), got \(String(describing: persisted?.state))")
            return
        }
    }

    @Test("reconcile flags Watch-side plans with no matching local job as orphaned, without mutating anything")
    func reconcileFlagsOrphans() async throws {
        let repository = FakeWorkoutRepository()
        let watchSync = FakeWatchSyncService()
        let clock = FakeClock(currentDate: Fixtures.referenceDate)
        let coordinator = SyncCoordinator(repository: repository, watchSyncService: watchSync, clock: clock)

        let orphanPlanID = UUID()
        let noDate: Date? = nil
        try await watchSync.schedule(planID: orphanPlanID, workout: Fixtures.makeWorkout(), at: noDate)

        let report = try await coordinator.reconcile()

        #expect(report.orphanedPlanIDs == [orphanPlanID])
        #expect(report.markedFailed.isEmpty)
        #expect(report.markedStale.isEmpty)
        // No local job exists, and none is created.
        #expect(try await repository.fetchAll().isEmpty)
    }

    @Test("reconcile leaves a synced job alone when it is still present on the Watch")
    func reconcileLeavesStillPresentJobAlone() async throws {
        let workout = Fixtures.makeWorkout()
        let repository = FakeWorkoutRepository(workouts: [workout])
        let watchSync = FakeWatchSyncService()
        let clock = FakeClock(currentDate: Fixtures.referenceDate)
        let coordinator = SyncCoordinator(repository: repository, watchSyncService: watchSync, clock: clock)

        let synced = try await coordinator.scheduleWorkout(workoutID: workout.id)

        let report = try await coordinator.reconcile()

        #expect(report.markedFailed.isEmpty)
        #expect(report.markedStale.isEmpty)
        #expect(report.orphanedPlanIDs.isEmpty)
        let persisted = try await repository.fetchSyncJob(id: synced.id)
        #expect(persisted?.state == .synced)
    }

    @Test("reconcile prefers stale-on-edit over marking a job failed for the same job")
    func reconcilePrefersStaleOverFailed() async throws {
        let workout = Fixtures.makeWorkout()
        let repository = FakeWorkoutRepository(workouts: [workout])
        let watchSync = FakeWatchSyncService()
        let clock = FakeClock(currentDate: Fixtures.referenceDate)
        let coordinator = SyncCoordinator(repository: repository, watchSyncService: watchSync, clock: clock)

        let synced = try await coordinator.scheduleWorkout(workoutID: workout.id)
        try await watchSync.remove(planID: synced.id)

        clock.advance(by: 60)
        var edited = workout
        edited.updatedAt = clock.now()
        try await repository.save(edited)

        let report = try await coordinator.reconcile()

        #expect(report.markedStale == [synced.id])
        #expect(report.markedFailed.isEmpty)
    }

}
