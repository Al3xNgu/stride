import Testing
import Foundation
@testable import FeatureLibrary
import DomainKit
import TestSupport

/// Coverage of `LibraryViewModel`'s load/send/schedule/retry/delete flows
/// against `TestSupport` fakes wired through a real `SyncCoordinator` (per
/// the type's doc comment — the coordinator's own transition logic is never
/// re-implemented, only exercised, the same way `SyncCoordinatorTests` does).
@MainActor
@Suite("LibraryViewModel")
struct LibraryViewModelTests {
    private typealias Fixtures = LibraryViewModelFixtures
    private let referenceDate = Fixtures.referenceDate

    // MARK: - load()

    @Test("load() produces one row per workout, each paired with its latest sync job")
    func loadProducesRowsWithLatestJob() async {
        let workoutA = Fixtures.makeWorkout(name: "A", now: referenceDate)
        let workoutB = Fixtures.makeWorkout(name: "B", now: referenceDate.addingTimeInterval(10))
        let olderJob = SyncJob(
            workoutID: workoutB.id, state: .pending, createdAt: referenceDate, updatedAt: referenceDate
        )
        let newerJob = SyncJob(
            workoutID: workoutB.id, state: .synced, createdAt: referenceDate,
            updatedAt: referenceDate.addingTimeInterval(5)
        )
        let harness = Fixtures.makeViewModel(workouts: [workoutA, workoutB], syncJobs: [olderJob, newerJob])

        await harness.viewModel.load()

        #expect(harness.viewModel.loadError == nil)
        #expect(harness.viewModel.rows.count == 2)
        // Most-recently-updated workout first.
        #expect(harness.viewModel.rows.map(\.workout.id) == [workoutB.id, workoutA.id])

        let rowA = harness.viewModel.rows.first { $0.workout.id == workoutA.id }
        #expect(rowA?.latestSyncJob == nil)
        #expect(rowA?.badgeState == .notSynced)

        let rowB = harness.viewModel.rows.first { $0.workout.id == workoutB.id }
        #expect(rowB?.latestSyncJob?.id == newerJob.id)
        #expect(rowB?.badgeState == .synced)
    }

    @Test("load() surfaces a typed error and leaves rows unchanged on failure")
    func loadFailureSurfacesError() async {
        let harness = Fixtures.makeViewModel(workouts: [Fixtures.makeWorkout()])
        await harness.viewModel.load()
        #expect(harness.viewModel.rows.count == 1)

        harness.repository.errorToThrow = WorkoutRepositoryError.underlying("disk full")
        await harness.viewModel.load()

        #expect(harness.viewModel.loadError == .underlying("disk full"))
        #expect(harness.viewModel.rows.count == 1)
    }

    // MARK: - sendToWatch

    @Test("sendToWatch happy path updates the row's badge to synced")
    func sendToWatchHappyPathUpdatesBadge() async {
        let workout = Fixtures.makeWorkout()
        let harness = Fixtures.makeViewModel(workouts: [workout])
        await harness.viewModel.load()
        #expect(harness.viewModel.rows.first?.badgeState == .notSynced)

        await harness.viewModel.sendToWatch(workoutID: workout.id)

        #expect(harness.viewModel.sendError == nil)
        #expect(harness.viewModel.sendingWorkoutIDs.isEmpty)
        #expect(harness.viewModel.rows.first?.badgeState == .synced)
        #expect(harness.watchSync.scheduleCalls.count == 1)
        #expect(harness.watchSync.scheduleCalls.first?.date == nil)
    }

    @Test("sendToWatch surfaces a mapped failure reason via the row's badge, not sendError")
    func sendToWatchFailurePathSurfacesReason() async {
        let workout = Fixtures.makeWorkout()
        let harness = Fixtures.makeViewModel(workouts: [workout], watchAuthorizationState: .denied)
        await harness.viewModel.load()

        await harness.viewModel.sendToWatch(workoutID: workout.id)

        #expect(harness.viewModel.sendError == nil)
        #expect(harness.viewModel.rows.first?.badgeState == .failed(.notAuthorized))
    }

    @Test("sendToWatch on an unknown workout id surfaces LibrarySendError.workoutNotFound")
    func sendToWatchUnknownWorkoutSurfacesSendError() async {
        let harness = Fixtures.makeViewModel()
        let unknownID = UUID()

        await harness.viewModel.sendToWatch(workoutID: unknownID)

        #expect(harness.viewModel.sendError == .workoutNotFound(id: unknownID))
    }

    @Test("clearSendError resets sendError to nil")
    func clearSendErrorResets() async {
        let harness = Fixtures.makeViewModel()
        await harness.viewModel.sendToWatch(workoutID: UUID())
        #expect(harness.viewModel.sendError != nil)

        harness.viewModel.clearSendError()

        #expect(harness.viewModel.sendError == nil)
    }

    // MARK: - scheduleForDate

    @Test("scheduleForDate passes the chosen date through to the watch sync service")
    func scheduleForDatePassesDateThrough() async {
        let workout = Fixtures.makeWorkout()
        let harness = Fixtures.makeViewModel(workouts: [workout])
        await harness.viewModel.load()
        let scheduledDate = referenceDate.addingTimeInterval(3_600 * 24)

        await harness.viewModel.scheduleForDate(workoutID: workout.id, date: scheduledDate)

        #expect(harness.watchSync.scheduleCalls.count == 1)
        #expect(harness.watchSync.scheduleCalls.first?.date == scheduledDate)
        #expect(harness.viewModel.rows.first?.latestSyncJob?.scheduledDate == scheduledDate)
        #expect(harness.viewModel.rows.first?.badgeState == .synced)
    }

    // MARK: - retryFailed

    @Test("retryFailed re-sends a failed job, reusing its previously chosen date, and clears the badge on success")
    func retryFailedResendsPreservingDate() async {
        let workout = Fixtures.makeWorkout()
        let harness = Fixtures.makeViewModel(workouts: [workout], watchAuthorizationState: .denied)
        await harness.viewModel.load()
        let scheduledDate = referenceDate.addingTimeInterval(3_600)

        await harness.viewModel.scheduleForDate(workoutID: workout.id, date: scheduledDate)
        #expect(harness.viewModel.rows.first?.badgeState == .failed(.notAuthorized))

        harness.watchSync.authorizationState = .authorized
        await harness.viewModel.retryFailed(workoutID: workout.id)

        #expect(harness.viewModel.rows.first?.badgeState == .synced)
        #expect(harness.watchSync.scheduleCalls.count == 2)
        #expect(harness.watchSync.scheduleCalls.last?.date == scheduledDate)
    }

    // MARK: - delete

    @Test("delete removes the row and cascades its sync job history from the repository")
    func deleteRemovesRowAndCascadesSyncJobs() async {
        let workout = Fixtures.makeWorkout()
        let harness = Fixtures.makeViewModel(workouts: [workout])
        await harness.viewModel.load()
        await harness.viewModel.sendToWatch(workoutID: workout.id)
        #expect(harness.viewModel.rows.count == 1)
        let jobsBeforeDelete = try? await harness.repository.fetchSyncJobs(workoutID: workout.id)
        #expect(!(jobsBeforeDelete ?? []).isEmpty)

        await harness.viewModel.delete(workoutID: workout.id)

        #expect(harness.viewModel.rows.isEmpty)
        #expect(harness.viewModel.deleteError == nil)
        let persistedWorkout = try? await harness.repository.fetch(id: workout.id)
        #expect(persistedWorkout == nil)
        let jobsAfterDelete = try? await harness.repository.fetchSyncJobs(workoutID: workout.id)
        #expect((jobsAfterDelete ?? []).isEmpty)
        // Deleting local intent does not itself unschedule a still-synced
        // Watch plan (see `LibraryViewModel.delete`'s doc comment) — pin that
        // documented behavior so a future change to it is a deliberate,
        // reviewed decision rather than an accidental regression.
        #expect(harness.watchSync.removeCalls.isEmpty)
    }

    @Test("delete surfaces a typed error and leaves the row in place on failure")
    func deleteFailureSurfacesError() async {
        let workout = Fixtures.makeWorkout()
        let harness = Fixtures.makeViewModel(workouts: [workout])
        await harness.viewModel.load()
        harness.repository.errorToThrow = WorkoutRepositoryError.underlying("locked")

        await harness.viewModel.delete(workoutID: workout.id)

        #expect(harness.viewModel.deleteError == .underlying("locked"))
        #expect(harness.viewModel.rows.count == 1)
    }

    // MARK: - reconcileOnForeground

    @Test("reconcileOnForeground repairs a job removed on the Watch and reloads rows to reflect it")
    func reconcileOnForegroundRepairsAndReloads() async {
        let workout = Fixtures.makeWorkout()
        let harness = Fixtures.makeViewModel(workouts: [workout])
        await harness.viewModel.load()
        await harness.viewModel.sendToWatch(workoutID: workout.id)
        guard let planID = harness.viewModel.rows.first?.latestSyncJob?.planIdentifier.flatMap({ UUID(uuidString: $0) }) else {
            Issue.record("Expected a plan id after a successful send")
            return
        }
        try? await harness.watchSync.remove(planID: planID)

        await harness.viewModel.reconcileOnForeground()

        #expect(harness.viewModel.reconcileError == nil)
        guard case .failed(.transient) = harness.viewModel.rows.first?.badgeState else {
            Issue.record("Expected .failed(.transient), got \(String(describing: harness.viewModel.rows.first?.badgeState))")
            return
        }
    }

    // MARK: - Row refresh resilience

    @Test("A transient repository error during post-send refresh leaves the existing row untouched")
    func transientRefreshErrorKeepsRow() async {
        let workout = Fixtures.makeWorkout()
        let harness = Fixtures.makeViewModel(workouts: [workout])
        await harness.viewModel.load()
        #expect(harness.viewModel.rows.count == 1)

        // The send itself succeeds (the coordinator persisted .synced before
        // the error is injected)... then the row refresh's reads fail.
        harness.repository.errorToThrow = nil
        await harness.viewModel.sendToWatch(workoutID: workout.id)
        harness.repository.errorToThrow = WorkoutRepositoryError.underlying("transient read failure")
        await harness.viewModel.retryFailed(workoutID: workout.id)

        // The row must survive: a thrown read error is not "the workout is
        // gone" and must not delete or blank the row.
        harness.repository.errorToThrow = nil
        #expect(harness.viewModel.rows.count == 1)
        #expect(harness.viewModel.rows.first?.workout.id == workout.id)
    }
}
