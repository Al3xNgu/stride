import Testing
import Foundation
@testable import FeatureHistory
import DomainKit
import TestSupport

/// Shared harness for `HistoryViewModel` test suites, mirroring
/// `FeatureLibraryTests/LibraryViewModelFixtures.swift`'s shape.
@MainActor
enum HistoryViewModelFixtures {
    nonisolated static let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)

    /// A UTC-fixed calendar, so month/year-boundary grouping assertions are
    /// deterministic regardless of the machine running the tests.
    static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }

    /// A view model plus every fake backing it, so tests can assert against
    /// the repositories as well as the view model under test.
    struct Harness {
        let viewModel: HistoryViewModel
        let runRepository: FakeRunHistoryRepository
        let workoutRepository: FakeWorkoutRepository
    }

    static func makeRun(
        id: UUID = UUID(),
        date: Date = referenceDate,
        distanceMeters: Double = 5_000,
        durationSeconds: TimeInterval = 1_500,
        workoutID: UUID? = nil,
        isDeleted: Bool = false
    ) -> CompletedRun {
        CompletedRun(
            id: id,
            date: date,
            distanceMeters: distanceMeters,
            durationSeconds: durationSeconds,
            source: "Apple Watch",
            workoutID: workoutID,
            isDeleted: isDeleted
        )
    }

    static func makeWorkout(id: UUID = UUID(), name: String = "5k Tempo", now: Date = referenceDate) -> Workout {
        Workout(id: id, name: name, createdAt: now, updatedAt: now)
    }

    static func makeViewModel(
        runs: [CompletedRun] = [],
        workouts: [Workout] = [],
        calendar: Calendar? = nil
    ) -> Harness {
        let runRepository = FakeRunHistoryRepository(runs: runs)
        let workoutRepository = FakeWorkoutRepository(workouts: workouts)
        let viewModel = HistoryViewModel(
            runHistoryRepository: runRepository,
            workoutRepository: workoutRepository,
            calendar: calendar ?? utcCalendar
        )
        return Harness(viewModel: viewModel, runRepository: runRepository, workoutRepository: workoutRepository)
    }

    /// Builds a UTC date at noon, avoiding midnight/DST edge ambiguity.
    static func date(year: Int, month: Int, day: Int) -> Date {
        utcCalendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? referenceDate
    }
}
