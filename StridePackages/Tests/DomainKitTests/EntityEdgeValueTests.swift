import Testing
import Foundation
@testable import DomainKit

/// Entities are "dumb" value types: at the entity layer they must store
/// whatever they're given, including values that validation (task 0.4) will
/// later reject. This suite pins that entities do NOT reject empty
/// segments, zero/negative distances/durations, or zero repetitions.
@Suite("Entity edge values (validation-free storage)")
struct EntityEdgeValueTests {
    @Test("Workout allows an empty segments array")
    func workoutAllowsEmptySegments() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let workout = Workout(name: "Untitled", createdAt: now, updatedAt: now)
        #expect(workout.segments.isEmpty)
    }

    @Test("Goal.distance stores zero meters without crashing")
    func goalDistanceZeroMeters() {
        let goal = Goal.distance(meters: 0)
        if case let .distance(meters) = goal {
            #expect(meters == 0)
        } else {
            Issue.record("Expected .distance case")
        }
    }

    @Test("Goal.distance stores negative meters without crashing")
    func goalDistanceNegativeMeters() {
        let goal = Goal.distance(meters: -500)
        if case let .distance(meters) = goal {
            #expect(meters == -500)
        } else {
            Issue.record("Expected .distance case")
        }
    }

    @Test("Goal.duration stores zero seconds without crashing")
    func goalDurationZeroSeconds() {
        let goal = Goal.duration(seconds: 0)
        if case let .duration(seconds) = goal {
            #expect(seconds == 0)
        } else {
            Issue.record("Expected .duration case")
        }
    }

    @Test("Goal.duration stores negative seconds without crashing")
    func goalDurationNegativeSeconds() {
        let goal = Goal.duration(seconds: -60)
        if case let .duration(seconds) = goal {
            #expect(seconds == -60)
        } else {
            Issue.record("Expected .duration case")
        }
    }

    @Test("intervalBlock stores zero repetitions without crashing")
    func intervalBlockZeroRepetitions() {
        let segment = WorkoutSegment.intervalBlock(
            steps: [IntervalStep(purpose: .work, step: SegmentStep(intent: .work, goal: .open))],
            repetitions: 0
        )
        if case let .intervalBlock(_, _, repetitions) = segment {
            #expect(repetitions == 0)
        } else {
            Issue.record("Expected .intervalBlock case")
        }
    }

    @Test("intervalBlock stores negative repetitions without crashing")
    func intervalBlockNegativeRepetitions() {
        let segment = WorkoutSegment.intervalBlock(
            steps: [IntervalStep(purpose: .work, step: SegmentStep(intent: .work, goal: .open))],
            repetitions: -1
        )
        if case let .intervalBlock(_, _, repetitions) = segment {
            #expect(repetitions == -1)
        } else {
            Issue.record("Expected .intervalBlock case")
        }
    }

    @Test("intervalBlock stores an empty steps array without crashing")
    func intervalBlockEmptySteps() {
        let segment = WorkoutSegment.intervalBlock(steps: [], repetitions: 4)
        if case let .intervalBlock(_, steps, _) = segment {
            #expect(steps.isEmpty)
        } else {
            Issue.record("Expected .intervalBlock case")
        }
    }

    @Test("Workout stores updatedAt earlier than createdAt without crashing (nonsensical but not entity's job)")
    func workoutAllowsUpdatedBeforeCreated() {
        let created = Date(timeIntervalSince1970: 1_700_000_000)
        let updated = created.addingTimeInterval(-1_000)
        let workout = Workout(name: "Weird", createdAt: created, updatedAt: updated)
        #expect(workout.updatedAt < workout.createdAt)
    }

    @Test("PersonalBest stores negative elapsedSeconds without crashing")
    func personalBestNegativeElapsed() {
        let pb = PersonalBest(
            milestoneID: UUID(),
            elapsedSeconds: -10,
            completedRunID: UUID(),
            achievedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        #expect(pb.elapsedSeconds == -10)
    }
}
