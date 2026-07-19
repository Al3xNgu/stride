import Testing
import Foundation
@testable import DomainKit
import TestSupport

/// `SyncCoordinator` state-machine legality (no illegal transition is ever
/// persisted for any `SyncJobState`), exact backoff-timing math, and
/// reconciliation-adversarial edge cases that don't need the dedicated
/// actor-isolated test doubles in `SyncCoordinatorConcurrencyTests.swift`.
@Suite("SyncCoordinator — state machine, backoff, reconciliation")
struct SyncCoordinatorStateMachineTests {
    private typealias Fixtures = ScheduleWorkoutFixtures

    // MARK: - State-machine legality

    @Test("SyncJobState's cases are exhaustively enumerated — a new case is a compile error until updated here")
    func syncJobStateCasesAreExhaustivelyEnumerated() {
        func isKnownCase(_ state: SyncJobState) -> Bool {
            switch state {
            case .draft, .pending, .syncing, .synced, .failed, .abandoned, .completedRunLinked, .stale:
                return true
            }
        }
        #expect(isKnownCase(.draft))
    }

    @Test(
        "reconcile leaves a job in every non-.synced state completely untouched — no illegal transition is ever persisted",
        arguments: [
            SyncJobState.draft,
            .pending,
            .syncing,
            .failed(.notAuthorized),
            .failed(.invalidComposition),
            .failed(.noPairedWatch),
            .failed(.transient(description: "busy")),
            .abandoned,
            .completedRunLinked,
            .stale
        ]
    )
    func reconcileLeavesNonSyncedStatesUntouched(_ state: SyncJobState) async throws {
        let workout = Fixtures.makeWorkout()
        let repository = FakeWorkoutRepository(workouts: [workout])
        let seeded = SyncJob(
            workoutID: workout.id,
            state: state,
            createdAt: Fixtures.referenceDate,
            updatedAt: Fixtures.referenceDate
        )
        try await repository.saveSyncJob(seeded)
        let watchSync = FakeWatchSyncService()
        let clock = FakeClock(currentDate: Fixtures.referenceDate)
        let coordinator = SyncCoordinator(repository: repository, watchSyncService: watchSync, clock: clock)

        let report = try await coordinator.reconcile()

        #expect(report.markedStale.isEmpty)
        #expect(report.markedFailed.isEmpty)
        #expect(report.orphanedPlanIDs.isEmpty)
        let persisted = try await repository.fetchSyncJob(id: seeded.id)
        #expect(persisted?.state == state)
        #expect(persisted?.updatedAt == seeded.updatedAt, "job was re-saved even though nothing should have changed it")
    }

    @Test("retryDueJobs never touches an already-.synced job — nothing is ever registered for retry once a job succeeds")
    func retryDueJobsNeverRetriesAlreadySyncedJob() async throws {
        let workout = Fixtures.makeWorkout()
        let repository = FakeWorkoutRepository(workouts: [workout])
        let watchSync = FakeWatchSyncService()
        let clock = FakeClock(currentDate: Fixtures.referenceDate)
        let coordinator = SyncCoordinator(repository: repository, watchSyncService: watchSync, clock: clock)

        let synced = try await coordinator.scheduleWorkout(workoutID: workout.id)
        #expect(synced.state == .synced)

        clock.advance(by: 100_000)
        let retried = try await coordinator.retryDueJobs()

        #expect(retried.isEmpty)
        #expect(watchSync.scheduleCalls.count == 1)
        let persisted = try await repository.fetchSyncJob(id: synced.id)
        #expect(persisted?.state == .synced)
    }

    // MARK: - Backoff math

    @Test("default backoff is exactly 30s then 60s; attempt 3 (the default cap) is abandoned, not scheduled for a 4th timer")
    func defaultBackoffScheduleIsExactAndCapsAtThree() async throws {
        let workout = Fixtures.makeWorkout()
        let repository = FakeWorkoutRepository(workouts: [workout])
        let watchSync = FakeWatchSyncService()
        watchSync.errorToThrow = WatchSyncError.underlying("busy")
        let clock = FakeClock(currentDate: Fixtures.referenceDate)
        // Defaults: maxAttempts 3, backoffBaseSeconds 30.
        let coordinator = SyncCoordinator(repository: repository, watchSyncService: watchSync, clock: clock)

        let first = try await coordinator.scheduleWorkout(workoutID: workout.id)
        #expect(first.attemptCount == 1)

        // Just short of the first boundary (base * 2^0 = 30s) — must not fire.
        clock.advance(by: 29)
        #expect(try await coordinator.retryDueJobs().isEmpty)
        #expect(watchSync.scheduleCalls.count == 1)

        clock.advance(by: 1)
        let second = try await coordinator.retryDueJobs()
        #expect(second.count == 1)
        #expect(second.first?.attemptCount == 2)
        #expect(watchSync.scheduleCalls.count == 2)

        // Just short of the second boundary (base * 2^1 = 60s) — must not fire.
        clock.advance(by: 59)
        #expect(try await coordinator.retryDueJobs().isEmpty)
        #expect(watchSync.scheduleCalls.count == 2)

        clock.advance(by: 1)
        let third = try await coordinator.retryDueJobs()
        #expect(third.count == 1)
        #expect(third.first?.attemptCount == 3)
        #expect(watchSync.scheduleCalls.count == 3)

        // Attempt 3 == maxAttempts and is still transiently failing: abandoned,
        // not scheduled for a fourth timer.
        let persisted = try await repository.fetchSyncJob(id: first.id)
        #expect(persisted?.state == .abandoned)

        clock.advance(by: 100_000)
        #expect(try await coordinator.retryDueJobs().isEmpty)
        #expect(watchSync.scheduleCalls.count == 3)
    }

    // MARK: - Reconciliation adversarial

    @Test("reconcile is a total no-op when there are no local workouts and nothing scheduled on the Watch")
    func reconcileNoOpWhenBothSidesEmpty() async throws {
        let repository = FakeWorkoutRepository()
        let watchSync = FakeWatchSyncService()
        let clock = FakeClock(currentDate: Fixtures.referenceDate)
        let coordinator = SyncCoordinator(repository: repository, watchSyncService: watchSync, clock: clock)

        let report = try await coordinator.reconcile()

        #expect(report == ReconciliationReport())
    }

    @Test("reconcile de-duplicates repeated plan ids from the Watch — an orphan is reported once, not once per duplicate")
    func reconcileDeduplicatesRepeatedWatchPlanIDs() async throws {
        let repository = FakeWorkoutRepository()
        let duplicatePlanID = UUID()
        let watchSync = FakeWatchSyncService(scheduledWorkouts: [
            ScheduledWatchWorkout(id: duplicatePlanID),
            ScheduledWatchWorkout(id: duplicatePlanID, scheduledDate: Fixtures.referenceDate)
        ])
        let clock = FakeClock(currentDate: Fixtures.referenceDate)
        let coordinator = SyncCoordinator(repository: repository, watchSyncService: watchSync, clock: clock)

        let report = try await coordinator.reconcile()

        #expect(report.orphanedPlanIDs == [duplicatePlanID])
        #expect(report.markedFailed.isEmpty)
        #expect(report.markedStale.isEmpty)
    }

    @Test("a workout deleted locally after being synced surfaces its still-scheduled Watch plan as orphaned, not dropped")
    func reconcileSurfacesOrphanFromDeletedWorkout() async throws {
        let workout = Fixtures.makeWorkout()
        let repository = FakeWorkoutRepository(workouts: [workout])
        let watchSync = FakeWatchSyncService()
        let clock = FakeClock(currentDate: Fixtures.referenceDate)
        let coordinator = SyncCoordinator(repository: repository, watchSyncService: watchSync, clock: clock)

        let synced = try await coordinator.scheduleWorkout(workoutID: workout.id)
        #expect(synced.state == .synced)

        // Deleting a workout is local-only — nothing here removes it from
        // WorkoutKit, so the plan is still scheduled on the (fake) Watch.
        try await repository.delete(id: workout.id)

        let report = try await coordinator.reconcile()

        #expect(report.orphanedPlanIDs == [synced.id])
        #expect(report.markedFailed.isEmpty)
        #expect(report.markedStale.isEmpty)
        let persisted = try await repository.fetchSyncJob(id: synced.id)
        #expect(persisted == nil, "the deleted job must stay deleted, not be resurrected")
    }
}
