import Testing
import Foundation
@testable import FeatureBuilder
import DomainKit
import TestSupport

/// Shared harness for `BuilderViewModel` test suites, so
/// `BuilderViewModelTests` (happy-path coverage) and
/// `BuilderViewModelAdversarialTests` (edge cases) build the view model the
/// same way without duplicating the fake wiring.
@MainActor
enum BuilderViewModelFixtures {
    static let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)

    /// A view model plus the fakes backing it, so tests can assert against
    /// the repository/clock as well as the view model under test.
    struct Harness {
        let viewModel: BuilderViewModel
        let repository: FakeWorkoutRepository
        let clock: FakeClock
    }

    static func makeViewModel(
        workouts: [Workout] = [],
        workout: Workout? = nil
    ) -> Harness {
        let repository = FakeWorkoutRepository(workouts: workouts)
        let clock = FakeClock(currentDate: referenceDate)
        let viewModel = BuilderViewModel(workoutRepository: repository, clock: clock, workout: workout)
        return Harness(viewModel: viewModel, repository: repository, clock: clock)
    }
}
