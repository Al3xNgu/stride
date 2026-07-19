import Testing
import Foundation
@testable import FeatureLibrary
import DomainKit
import TestSupport

/// Shared harness for `LibraryViewModel` test suites, mirroring
/// `FeatureBuilderTests/BuilderViewModelFixtures.swift`'s shape.
@MainActor
enum LibraryViewModelFixtures {
    nonisolated static let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)

    /// A view model plus every fake backing it, so tests can assert against
    /// the repository/watch service/clock as well as the view model under
    /// test.
    struct Harness {
        let viewModel: LibraryViewModel
        let repository: FakeWorkoutRepository
        let watchSync: FakeWatchSyncService
        let clock: FakeClock
        let coordinator: SyncCoordinator
    }

    static func makeWorkout(name: String = "Tempo Run", now: Date = referenceDate) -> Workout {
        Workout(
            name: name,
            segments: [.step(SegmentStep(intent: .tempo, goal: .distance(meters: 5_000)))],
            createdAt: now,
            updatedAt: now
        )
    }

    static func makeViewModel(
        workouts: [Workout] = [],
        syncJobs: [SyncJob] = [],
        watchIsSupported: Bool = true,
        watchAuthorizationState: WatchAuthorizationState = .authorized,
        maxAttempts: Int = 3
    ) -> Harness {
        let repository = FakeWorkoutRepository(workouts: workouts, syncJobs: syncJobs)
        let watchSync = FakeWatchSyncService(isSupported: watchIsSupported, authorizationState: watchAuthorizationState)
        let clock = FakeClock(currentDate: referenceDate)
        let coordinator = SyncCoordinator(
            repository: repository,
            watchSyncService: watchSync,
            clock: clock,
            maxAttempts: maxAttempts
        )
        let viewModel = LibraryViewModel(workoutRepository: repository, syncCoordinator: coordinator, clock: clock)
        return Harness(viewModel: viewModel, repository: repository, watchSync: watchSync, clock: clock, coordinator: coordinator)
    }
}
