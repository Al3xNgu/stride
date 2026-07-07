import Testing
import Foundation
@testable import DomainKit

/// Sanity checks that `Hashable` conformances are internally consistent
/// (equal values hash equal) across the entity set, and that `Sendable`
/// value types can cross an isolation boundary without ceremony (compile-
/// time proof via `@Sendable` closure capture).
@Suite("Hashable / Sendable sanity")
struct HashableSendableSanityTests {
    @Test("Equal Workouts hash equal")
    func equalWorkoutsHashEqual() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let id = UUID()
        let first = Workout(id: id, name: "Run", createdAt: now, updatedAt: now)
        let second = Workout(id: id, name: "Run", createdAt: now, updatedAt: now)
        #expect(first == second)
        #expect(first.hashValue == second.hashValue)
    }

    @Test("Equal SyncJobStates (including failed with reason) hash equal")
    func equalSyncJobStatesHashEqual() {
        let first = SyncJobState.failed(.transient(description: "x"))
        let second = SyncJobState.failed(.transient(description: "x"))
        #expect(first == second)
        #expect(first.hashValue == second.hashValue)
    }

    @Test("Equal Milestones hash equal")
    func equalMilestonesHashEqual() {
        #expect(Milestone.fiveK.hashValue == Milestone.fiveK.hashValue)
    }

    @Test("Equal CompletedRuns hash equal")
    func equalCompletedRunsHashEqual() {
        let id = UUID()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let first = CompletedRun(id: id, date: date, distanceMeters: 5_000, durationSeconds: 1_500, source: "Watch")
        let second = CompletedRun(id: id, date: date, distanceMeters: 5_000, durationSeconds: 1_500, source: "Watch")
        #expect(first == second)
        #expect(first.hashValue == second.hashValue)
    }

    @Test("SegmentIntent can be used as a Dictionary key (Hashable + used by UserPreferences)")
    func segmentIntentUsableAsDictionaryKey() {
        var prefs = UserPreferences()
        prefs.defaultPacesByIntent[.tempo] = 0.28
        #expect(prefs.defaultPacesByIntent[.tempo] == 0.28)
    }

    @Test("Sendable entities can be captured in a @Sendable closure without a compiler error")
    func sendableClosureCapture() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let workout = Workout(name: "Sendable check", createdAt: now, updatedAt: now)
        let job = SyncJob(workoutID: workout.id, createdAt: now, updatedAt: now)
        let closure: @Sendable () -> UUID = {
            job.workoutID
        }
        #expect(closure() == workout.id)
    }
}
