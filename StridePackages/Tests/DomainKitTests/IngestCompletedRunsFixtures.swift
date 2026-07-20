import Testing
import Foundation
@testable import DomainKit
import TestSupport

/// Shared fixtures for `IngestCompletedRunsUseCase` tests, split across
/// `IngestCompletedRunsUseCaseTests` (upsert/tombstone/empty-batch),
/// `IngestCompletedRunsAttributionTests`, and `IngestCompletedRunsPersonalBestTests`
/// (keeping each suite under swiftlint's `type_body_length`, mirroring how
/// `PersonalBestPolicy` coverage is split across three files).
enum IngestCompletedRunsFixtures {
    static let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)

    static func makeRun(
        id: UUID = UUID(),
        date: Date? = nil,
        distanceMeters: Double = Milestone.fiveK.distanceMeters,
        durationSeconds: TimeInterval = 1_200,
        workoutID: UUID? = nil,
        isDeleted: Bool = false
    ) -> CompletedRun {
        CompletedRun(
            id: id,
            date: date ?? referenceDate,
            distanceMeters: distanceMeters,
            durationSeconds: durationSeconds,
            source: "Apple Watch",
            workoutID: workoutID,
            isDeleted: isDeleted
        )
    }

    static func makeSplit(runID: UUID, index: Int) -> Split {
        Split(runID: runID, index: index, distanceMeters: 1_000, durationSeconds: 240)
    }

    /// A fully-wired `IngestCompletedRunsUseCase` plus the fakes/coordinator
    /// backing it, grouped into one type (rather than a tuple) to stay under
    /// swiftlint's `large_tuple` rule.
    ///
    /// The use case is wired against a **real `SyncCoordinator`** over the
    /// fakes (the `SyncCoordinatorTests` pattern), not a direct
    /// `WorkoutRepository` write — `SyncCoordinator` is the sole owner of
    /// every `SyncJob` transition (`IngestCompletedRunsUseCase`'s doc
    /// comment), so exercising the use case without it would miss exactly
    /// the lock/race behavior these tests need to prove.
    struct Harness {
        let useCase: IngestCompletedRunsUseCase
        let runHistory: FakeRunHistoryRepository
        let workouts: FakeWorkoutRepository
        let watchSync: FakeWatchSyncService
        let coordinator: SyncCoordinator
        let clock: FakeClock
    }

    static func makeHarness(
        runHistory: FakeRunHistoryRepository = FakeRunHistoryRepository(),
        workouts: FakeWorkoutRepository = FakeWorkoutRepository(),
        watchSync: FakeWatchSyncService = FakeWatchSyncService(),
        clock: FakeClock? = nil,
        milestones: [Milestone] = Milestone.mvpPresets,
        attributionWindow: TimeInterval = 6 * 60 * 60
    ) -> Harness {
        let resolvedClock = clock ?? FakeClock(currentDate: referenceDate)
        let coordinator = SyncCoordinator(repository: workouts, watchSyncService: watchSync, clock: resolvedClock)
        let useCase = IngestCompletedRunsUseCase(
            runHistoryRepository: runHistory,
            workoutRepository: workouts,
            syncCoordinator: coordinator,
            milestones: milestones,
            attributionWindow: attributionWindow
        )
        return Harness(
            useCase: useCase,
            runHistory: runHistory,
            workouts: workouts,
            watchSync: watchSync,
            coordinator: coordinator,
            clock: resolvedClock
        )
    }

    /// A `.synced` sync job scheduled at `scheduledDate` for a fresh workout,
    /// pre-seeded into `workouts`. Returns the created workout id.
    @discardableResult
    static func seedSyncedJob(
        in workouts: FakeWorkoutRepository,
        scheduledDate: Date,
        workoutID: UUID = UUID()
    ) async throws -> UUID {
        let workout = ScheduleWorkoutFixtures.makeWorkout(id: workoutID)
        try await workouts.save(workout)
        let job = SyncJob(
            workoutID: workoutID,
            state: .synced,
            createdAt: referenceDate,
            updatedAt: referenceDate,
            planIdentifier: UUID().uuidString,
            scheduledDate: scheduledDate
        )
        try await workouts.saveSyncJob(job)
        return workoutID
    }
}
