import Testing
import Foundation
@testable import FeatureRecords
import DomainKit
import TestSupport

/// Shared harness for `RecordsViewModel` test suites, mirroring
/// `FeatureLibraryTests/LibraryViewModelFixtures.swift`'s shape.
@MainActor
enum RecordsViewModelFixtures {
    nonisolated static let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)

    /// A view model plus every fake backing it, so tests can assert against
    /// the repositories as well as the view model under test.
    struct Harness {
        let viewModel: RecordsViewModel
        let runRepository: FakeRunHistoryRepository
        let workoutRepository: FakeWorkoutRepository
    }

    static func makeRun(
        id: UUID = UUID(),
        date: Date = referenceDate,
        workoutID: UUID? = nil,
        isDeleted: Bool = false
    ) -> CompletedRun {
        CompletedRun(
            id: id,
            date: date,
            distanceMeters: 5_000,
            durationSeconds: 1_200,
            source: "Apple Watch",
            workoutID: workoutID,
            isDeleted: isDeleted
        )
    }

    static func makeWorkout(id: UUID = UUID(), name: String = "5k Tempo", now: Date = referenceDate) -> Workout {
        Workout(id: id, name: name, createdAt: now, updatedAt: now)
    }

    static func makePersonalBest(
        id: UUID = UUID(),
        milestoneID: UUID,
        elapsedSeconds: TimeInterval,
        completedRunID: UUID,
        achievedAt: Date = referenceDate
    ) -> PersonalBest {
        PersonalBest(
            id: id,
            milestoneID: milestoneID,
            elapsedSeconds: elapsedSeconds,
            completedRunID: completedRunID,
            achievedAt: achievedAt
        )
    }

    static func makeViewModel(
        runs: [CompletedRun] = [],
        workouts: [Workout] = [],
        personalBests: [PersonalBest] = [],
        includeWorkoutRepository: Bool = true,
        milestones: [Milestone] = Milestone.mvpPresets
    ) -> Harness {
        let runRepository = FakeRunHistoryRepository(runs: runs, personalBests: personalBests)
        let workoutRepository = FakeWorkoutRepository(workouts: workouts)
        let viewModel = RecordsViewModel(
            runHistoryRepository: runRepository,
            workoutRepository: includeWorkoutRepository ? workoutRepository : nil,
            milestones: milestones
        )
        return Harness(viewModel: viewModel, runRepository: runRepository, workoutRepository: workoutRepository)
    }
}
