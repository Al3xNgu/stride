import Testing
import Foundation
@testable import FeatureLibrary
import DomainKit

/// Coverage of `LibrarySendError.map(_:)`'s translation of every error a
/// `SyncCoordinator.scheduleWorkout` call can throw.
@Suite("LibrarySendError")
struct LibrarySendErrorTests {
    @Test("ScheduleWorkoutError.workoutNotFound maps to .workoutNotFound")
    func mapsWorkoutNotFound() {
        let id = UUID()
        #expect(LibrarySendError.map(ScheduleWorkoutError.workoutNotFound(id: id)) == .workoutNotFound(id: id))
    }

    @Test("ScheduleWorkoutError.invalidWorkout maps to .invalidWorkout, preserving every issue")
    func mapsInvalidWorkout() {
        let issues = [ValidationIssue(rule: .workoutHasNoSegments, locator: .workout)]
        #expect(LibrarySendError.map(ScheduleWorkoutError.invalidWorkout(issues)) == .invalidWorkout(issues))
    }

    @Test("WorkoutRepositoryError maps to .repository")
    func mapsRepositoryError() {
        let error = WorkoutRepositoryError.underlying("disk full")
        #expect(LibrarySendError.map(error) == .repository(error))
    }

    @Test("an unrecognized error maps to .underlying with its description")
    func mapsUnrecognizedError() {
        struct Unrecognized: Error {}
        guard case .underlying = LibrarySendError.map(Unrecognized()) else {
            Issue.record("Expected .underlying")
            return
        }
    }
}
