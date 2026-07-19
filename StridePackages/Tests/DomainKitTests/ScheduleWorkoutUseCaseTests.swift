import Testing
import Foundation
@testable import DomainKit
import TestSupport

/// Shared fixtures for `ScheduleWorkoutUseCase`/`SyncCoordinator` tests.
enum ScheduleWorkoutFixtures {
    static let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)

    /// A structurally-valid single-segment workout.
    static func makeWorkout(
        id: UUID = UUID(),
        name: String = "Easy 5k",
        updatedAt: Date = referenceDate
    ) -> Workout {
        let step = SegmentStep(intent: .easy, goal: .distance(meters: 5_000))
        return Workout(
            id: id,
            name: name,
            segments: [.step(step)],
            createdAt: referenceDate,
            updatedAt: updatedAt
        )
    }

    /// A structurally-invalid workout (no segments) for validation-failure tests.
    static func makeInvalidWorkout(id: UUID = UUID()) -> Workout {
        Workout(id: id, name: "Broken", segments: [], createdAt: referenceDate, updatedAt: referenceDate)
    }
}

@Suite("ScheduleWorkoutUseCase")
struct ScheduleWorkoutUseCaseTests {
    private typealias Fixtures = ScheduleWorkoutFixtures

    // MARK: - Happy path

    @Test("pending -> syncing -> synced, each transition persisted, plan id stable")
    func happyPathPersistsEveryTransition() async throws {
        let workout = Fixtures.makeWorkout()
        let repository = FakeWorkoutRepository(workouts: [workout])
        let watchSync = FakeWatchSyncService()
        let clock = FakeClock(currentDate: Fixtures.referenceDate)
        let useCase = ScheduleWorkoutUseCase(repository: repository, watchSyncService: watchSync, clock: clock)

        let job = try await useCase.execute(workoutID: workout.id)

        #expect(job.state == .synced)
        #expect(job.attemptCount == 1)
        #expect(job.planIdentifier == job.id.uuidString)

        // Every transition was persisted along the way — the fake's final
        // stored value reflects the last save, so assert on the repository
        // directly for the durable result.
        let persisted = try await repository.fetchSyncJob(id: job.id)
        #expect(persisted == job)

        // The `WatchSyncService` was called with the job's own id as the
        // stable plan identifier.
        #expect(watchSync.scheduleCalls.count == 1)
        #expect(watchSync.scheduleCalls.first?.planID == job.id)
    }

    @Test("re-sending the same workout reuses the existing SyncJob's id (stable plan identifier)")
    func resendReusesJobID() async throws {
        let workout = Fixtures.makeWorkout()
        let repository = FakeWorkoutRepository(workouts: [workout])
        let watchSync = FakeWatchSyncService()
        let clock = FakeClock(currentDate: Fixtures.referenceDate)
        let useCase = ScheduleWorkoutUseCase(repository: repository, watchSyncService: watchSync, clock: clock)

        let first = try await useCase.execute(workoutID: workout.id)
        let second = try await useCase.execute(workoutID: workout.id)

        #expect(first.id == second.id)
        #expect(second.attemptCount == 2)
        #expect(watchSync.scheduleCalls.map(\.planID) == [first.id, first.id])
    }

    // MARK: - Validation / not-found

    @Test("Missing workout throws workoutNotFound, no SyncJob is created")
    func missingWorkoutThrows() async throws {
        let repository = FakeWorkoutRepository()
        let watchSync = FakeWatchSyncService()
        let clock = FakeClock(currentDate: Fixtures.referenceDate)
        let useCase = ScheduleWorkoutUseCase(repository: repository, watchSyncService: watchSync, clock: clock)
        let missingID = UUID()

        await #expect(throws: ScheduleWorkoutError.workoutNotFound(id: missingID)) {
            try await useCase.execute(workoutID: missingID)
        }
        #expect(try await repository.fetchSyncJobs(workoutID: missingID).isEmpty)
    }

    @Test("Invalid workout throws invalidWorkout, no SyncJob is created")
    func invalidWorkoutThrows() async throws {
        let workout = Fixtures.makeInvalidWorkout()
        let repository = FakeWorkoutRepository(workouts: [workout])
        let watchSync = FakeWatchSyncService()
        let clock = FakeClock(currentDate: Fixtures.referenceDate)
        let useCase = ScheduleWorkoutUseCase(repository: repository, watchSyncService: watchSync, clock: clock)

        do {
            _ = try await useCase.execute(workoutID: workout.id)
            Issue.record("Expected invalidWorkout to be thrown")
        } catch ScheduleWorkoutError.invalidWorkout(let issues) {
            #expect(!issues.isEmpty)
        }
        #expect(try await repository.fetchSyncJobs(workoutID: workout.id).isEmpty)
    }

    // MARK: - WatchSyncError -> SyncFailureReason mapping

    @Test(
        "Every WatchSyncError maps to the documented SyncFailureReason",
        arguments: [
            (WatchSyncError.unauthorized(.denied), SyncFailureReason.notAuthorized),
            (WatchSyncError.unsupported, SyncFailureReason.noPairedWatch),
            (WatchSyncError.watchNotPaired, SyncFailureReason.noPairedWatch),
            (WatchSyncError.workoutApplicationNotInstalled, SyncFailureReason.noPairedWatch),
            (WatchSyncError.invalidComposition(reason: "bad goal"), SyncFailureReason.invalidComposition),
            (WatchSyncError.underlying("boom"), SyncFailureReason.transient(description: "boom"))
        ]
    )
    func failureReasonMapping(_ pair: (WatchSyncError, SyncFailureReason)) async throws {
        let (watchError, expectedReason) = pair
        let workout = Fixtures.makeWorkout()
        let repository = FakeWorkoutRepository(workouts: [workout])
        let watchSync = FakeWatchSyncService()
        watchSync.errorToThrow = watchError
        let clock = FakeClock(currentDate: Fixtures.referenceDate)
        let useCase = ScheduleWorkoutUseCase(repository: repository, watchSyncService: watchSync, clock: clock)

        let job = try await useCase.execute(workoutID: workout.id)

        #expect(job.state == .failed(expectedReason))
        #expect(job.attemptCount == 1)
    }

    @Test("every WatchSyncError case is exhaustively mapped end-to-end — a new case is a compile error until handled here")
    func everyWatchSyncErrorCaseIsExhaustivelyMapped() async throws {
        // No `default:` — a new `WatchSyncError` case added in the future
        // fails to compile right here until its expected `SyncFailureReason`
        // is decided, per the task's "exhaustive switch ... breaks here".
        func expectedReason(for error: WatchSyncError) -> SyncFailureReason {
            switch error {
            case .unauthorized:
                return .notAuthorized
            case .unsupported:
                return .noPairedWatch
            case .notScheduled:
                return .transient(description: "no scheduled entry found for this plan")
            case .watchNotPaired:
                return .noPairedWatch
            case .workoutApplicationNotInstalled:
                return .noPairedWatch
            case .invalidComposition:
                return .invalidComposition
            case .underlying(let description):
                return .transient(description: description)
            }
        }

        let allCases: [WatchSyncError] = [
            .unauthorized(.denied),
            .unsupported,
            .notScheduled,
            .watchNotPaired,
            .workoutApplicationNotInstalled,
            .invalidComposition(reason: "bad goal"),
            .underlying("boom")
        ]

        for watchError in allCases {
            let workout = Fixtures.makeWorkout()
            let repository = FakeWorkoutRepository(workouts: [workout])
            let watchSync = FakeWatchSyncService()
            watchSync.errorToThrow = watchError
            let clock = FakeClock(currentDate: Fixtures.referenceDate)
            let useCase = ScheduleWorkoutUseCase(repository: repository, watchSyncService: watchSync, clock: clock)

            let job = try await useCase.execute(workoutID: workout.id)

            #expect(job.state == .failed(expectedReason(for: watchError)), "mismatch for \(watchError)")
        }
    }

    @Test("notScheduled from schedule() is treated as a retryable transient failure")
    func notScheduledMapsToTransient() async throws {
        let workout = Fixtures.makeWorkout()
        let repository = FakeWorkoutRepository(workouts: [workout])
        let watchSync = FakeWatchSyncService()
        watchSync.errorToThrow = WatchSyncError.notScheduled
        let clock = FakeClock(currentDate: Fixtures.referenceDate)
        let useCase = ScheduleWorkoutUseCase(repository: repository, watchSyncService: watchSync, clock: clock)

        let job = try await useCase.execute(workoutID: workout.id)

        guard case .failed(.transient) = job.state else {
            Issue.record("Expected .failed(.transient), got \(job.state)")
            return
        }
    }
}
