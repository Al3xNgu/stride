import Testing
import Foundation
@testable import DomainKit

/// Coverage of `WorkoutSummaryPolicy`: empty/only-open/mixed workouts,
/// interval-block repetition multiplication (including zero repetitions),
/// and blocks containing both distance and duration goals.
@Suite("WorkoutSummaryPolicy")
struct WorkoutSummaryPolicyTests {
    private let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeWorkout(segments: [WorkoutSegment]) -> Workout {
        Workout(name: "Summary Fixture", segments: segments, createdAt: referenceDate, updatedAt: referenceDate)
    }

    // MARK: - Empty workout

    @Test("An empty workout summarizes to all zeros")
    func emptyWorkout() {
        let workout = makeWorkout(segments: [])
        let summary = WorkoutSummaryPolicy.summarize(workout)

        #expect(summary.totalDistanceMeters == 0)
        #expect(summary.totalDurationSeconds == 0)
        #expect(summary.openGoalStepCount == 0)
        #expect(summary.hasOpenGoalSteps == false)
    }

    // MARK: - Only-open workout

    @Test("A workout of only open-goal steps contributes zero totals but reports every open step")
    func onlyOpenSteps() {
        let workout = makeWorkout(segments: [
            .step(SegmentStep(intent: .warmUp, goal: .open)),
            .step(SegmentStep(intent: .easy, goal: .open)),
            .step(SegmentStep(intent: .coolDown, goal: .open))
        ])
        let summary = WorkoutSummaryPolicy.summarize(workout)

        #expect(summary.totalDistanceMeters == 0)
        #expect(summary.totalDurationSeconds == 0)
        #expect(summary.openGoalStepCount == 3)
        #expect(summary.hasOpenGoalSteps == true)
    }

    // MARK: - Mixed top-level goals

    @Test("A mix of distance, duration, and open top-level steps sums each total independently")
    func mixedTopLevelGoals() {
        let workout = makeWorkout(segments: [
            .step(SegmentStep(intent: .warmUp, goal: .duration(seconds: 600))),
            .step(SegmentStep(intent: .tempo, goal: .distance(meters: 5_000))),
            .step(SegmentStep(intent: .easy, goal: .open)),
            .step(SegmentStep(intent: .coolDown, goal: .duration(seconds: 300)))
        ])
        let summary = WorkoutSummaryPolicy.summarize(workout)

        #expect(summary.totalDistanceMeters == 5_000)
        #expect(summary.totalDurationSeconds == 900)
        #expect(summary.openGoalStepCount == 1)
    }

    // MARK: - Interval block × repetitions

    @Test("An interval block's distance goal is multiplied by its repetitions")
    func intervalBlockDistanceMultiplication() {
        let workout = makeWorkout(segments: [
            .intervalBlock(
                steps: [
                    IntervalStep(purpose: .work, step: SegmentStep(intent: .work, goal: .distance(meters: 400)))
                ],
                repetitions: 6
            )
        ])
        let summary = WorkoutSummaryPolicy.summarize(workout)

        #expect(summary.totalDistanceMeters == 2_400)
        #expect(summary.totalDurationSeconds == 0)
        #expect(summary.openGoalStepCount == 0)
    }

    @Test("An interval block with zero repetitions contributes zero to the totals")
    func intervalBlockZeroRepetitions() {
        let workout = makeWorkout(segments: [
            .intervalBlock(
                steps: [
                    IntervalStep(purpose: .work, step: SegmentStep(intent: .work, goal: .distance(meters: 400))),
                    IntervalStep(purpose: .recovery, step: SegmentStep(intent: .recovery, goal: .duration(seconds: 60)))
                ],
                repetitions: 0
            )
        ])
        let summary = WorkoutSummaryPolicy.summarize(workout)

        #expect(summary.totalDistanceMeters == 0)
        #expect(summary.totalDurationSeconds == 0)
    }

    @Test("An interval block's open-goal step is still reported once even with zero repetitions")
    func intervalBlockZeroRepetitionsStillReportsOpenStep() {
        let workout = makeWorkout(segments: [
            .intervalBlock(
                steps: [
                    IntervalStep(purpose: .work, step: SegmentStep(intent: .work, goal: .open))
                ],
                repetitions: 0
            )
        ])
        let summary = WorkoutSummaryPolicy.summarize(workout)

        #expect(summary.openGoalStepCount == 1)
    }

    @Test("A negative repetitions value is clamped to zero rather than negating totals")
    func intervalBlockNegativeRepetitionsClampsToZero() {
        let workout = makeWorkout(segments: [
            .intervalBlock(
                id: UUID(),
                steps: [
                    IntervalStep(purpose: .work, step: SegmentStep(intent: .work, goal: .distance(meters: 400)))
                ],
                repetitions: -3
            )
        ])
        let summary = WorkoutSummaryPolicy.summarize(workout)

        #expect(summary.totalDistanceMeters == 0)
    }

    // MARK: - Both goal kinds in one block

    @Test("A block with a distance work step and a duration recovery step multiplies both totals independently")
    func bothGoalKindsInOneBlock() {
        let workout = makeWorkout(segments: [
            .intervalBlock(
                steps: [
                    IntervalStep(purpose: .work, step: SegmentStep(intent: .work, goal: .distance(meters: 1_000))),
                    IntervalStep(purpose: .recovery, step: SegmentStep(intent: .recovery, goal: .duration(seconds: 120)))
                ],
                repetitions: 5
            )
        ])
        let summary = WorkoutSummaryPolicy.summarize(workout)

        #expect(summary.totalDistanceMeters == 5_000)
        #expect(summary.totalDurationSeconds == 600)
        #expect(summary.openGoalStepCount == 0)
    }

    // MARK: - Combined workout: top-level steps + a block

    @Test("Top-level steps and an interval block accumulate together")
    func topLevelStepsPlusIntervalBlock() {
        let workout = makeWorkout(segments: [
            .step(SegmentStep(intent: .warmUp, goal: .duration(seconds: 600))),
            .intervalBlock(
                steps: [
                    IntervalStep(purpose: .work, step: SegmentStep(intent: .work, goal: .distance(meters: 1_000))),
                    IntervalStep(purpose: .recovery, step: SegmentStep(intent: .recovery, goal: .duration(seconds: 120)))
                ],
                repetitions: 5
            ),
            .step(SegmentStep(intent: .coolDown, goal: .duration(seconds: 600))),
            .step(SegmentStep(intent: .easy, goal: .open))
        ])
        let summary = WorkoutSummaryPolicy.summarize(workout)

        #expect(summary.totalDistanceMeters == 5_000)
        #expect(summary.totalDurationSeconds == 600 + 600 + 600)
        #expect(summary.openGoalStepCount == 1)
    }
}
