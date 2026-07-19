import Testing
import Foundation
@testable import FeatureBuilder
import DomainKit
import TestSupport

/// Coverage of `BuilderViewModel`'s task-1.5 additions: `summary` reactivity,
/// `workoutLevelIssues`, and `issues(forSegmentID:)` row-level lookup.
@MainActor
@Suite("BuilderViewModel — summary and issue-by-segment")
struct BuilderViewModelSummaryTests {
    private typealias Fixtures = BuilderViewModelFixtures

    private func makeViewModel(
        workouts: [Workout] = [],
        workout: Workout? = nil
    ) -> Fixtures.Harness {
        Fixtures.makeViewModel(workouts: workouts, workout: workout)
    }

    // MARK: - summary

    @Test("summary is all-zero for a fresh, segment-less draft")
    func summaryEmptyForFreshDraft() {
        let viewModel = makeViewModel().viewModel
        #expect(viewModel.summary.totalDistanceMeters == 0)
        #expect(viewModel.summary.totalDurationSeconds == 0)
        #expect(viewModel.summary.openGoalStepCount == 0)
    }

    @Test("summary recomputes after addSegment, matching WorkoutSummaryPolicy directly")
    func summaryReactsToAddSegment() {
        let viewModel = makeViewModel().viewModel
        viewModel.name = "Tempo Run"
        let step = SegmentStep(intent: .tempo, goal: .distance(meters: 5_000))
        viewModel.addSegment(.tempo)
        viewModel.replaceSegment(id: viewModel.segments[0].id, with: .step(step))

        #expect(viewModel.summary.totalDistanceMeters == 5_000)
        #expect(viewModel.summary == WorkoutSummaryPolicy.summarize(viewModel.workout))
    }

    @Test("summary reports an open-goal step once it's added, and drops it again once deleted")
    func summaryReactsToOpenGoalAddAndDelete() {
        let viewModel = makeViewModel().viewModel
        viewModel.addSegment(.easy)
        #expect(viewModel.summary.openGoalStepCount == 1)
        #expect(viewModel.summary.hasOpenGoalSteps == true)

        viewModel.deleteSegment(id: viewModel.segments[0].id)
        #expect(viewModel.summary.openGoalStepCount == 0)
        #expect(viewModel.summary.hasOpenGoalSteps == false)
    }

    @Test("summary multiplies an interval block's step goals by its repetitions")
    func summaryMultipliesIntervalBlockByRepetitions() {
        let viewModel = makeViewModel().viewModel
        viewModel.addSegment(.intervalBlock)
        guard case let .intervalBlock(blockID, steps, _) = viewModel.segments[0] else {
            Issue.record("Expected an .intervalBlock segment")
            return
        }
        let rewired = WorkoutSegment.intervalBlock(
            id: blockID,
            steps: steps.map { intervalStep in
                var updated = intervalStep
                updated.step.goal = intervalStep.purpose == .work ? .distance(meters: 400) : .duration(seconds: 60)
                return updated
            },
            repetitions: 4
        )
        viewModel.replaceSegment(id: blockID, with: rewired)

        #expect(viewModel.summary.totalDistanceMeters == 1_600)
        #expect(viewModel.summary.totalDurationSeconds == 240)
    }

    // MARK: - workoutLevelIssues

    @Test("workoutLevelIssues surfaces workout-anchored issues, excluding segment-anchored ones")
    func workoutLevelIssuesExcludesSegmentAnchoredOnes() {
        let viewModel = makeViewModel().viewModel
        // Name left empty (workout-level) and a bad segment goal (segment-level).
        let step = SegmentStep(intent: .tempo, goal: .distance(meters: -5))
        viewModel.addSegment(.tempo)
        viewModel.replaceSegment(id: viewModel.segments[0].id, with: .step(step))

        #expect(viewModel.workoutLevelIssues.contains(ValidationIssue(rule: .workoutNameEmpty, locator: .workout)))
        #expect(!viewModel.workoutLevelIssues.contains { $0.locator != .workout })
    }

    @Test("workoutLevelIssues is empty once the workout has a name and at least one segment")
    func workoutLevelIssuesEmptyOnceFixed() {
        let viewModel = makeViewModel().viewModel
        viewModel.name = "Easy Run"
        viewModel.addSegment(.easy)
        #expect(viewModel.workoutLevelIssues.isEmpty)
    }

    // MARK: - issues(forSegmentID:)

    @Test("issues(forSegmentID:) returns the issue anchored to a bad top-level step")
    func issuesForSegmentIDFindsBadTopLevelStep() {
        let viewModel = makeViewModel().viewModel
        viewModel.name = "Bad Workout"
        let step = SegmentStep(intent: .tempo, goal: .distance(meters: -5))
        viewModel.addSegment(.tempo)
        let originalSegmentID = viewModel.segments[0].id
        viewModel.replaceSegment(id: originalSegmentID, with: .step(step))

        // `replaceSegment` swaps in `step` verbatim, so the segment's *own*
        // id is now `step.id` (see `WorkoutSegment.id` for `.step`), not the
        // pre-replacement `originalSegmentID`.
        let found = viewModel.issues(forSegmentID: step.id)
        #expect(found.contains(ValidationIssue(rule: .goalDistanceNotPositive(meters: -5), locator: .segment(id: step.id))))
    }

    @Test("issues(forSegmentID:) returns issues anchored to a step nested inside an interval block")
    func issuesForSegmentIDFindsNestedIntervalStep() {
        let viewModel = makeViewModel().viewModel
        viewModel.name = "Bad Interval Workout"
        viewModel.addSegment(.intervalBlock)
        guard case let .intervalBlock(blockID, steps, repetitions) = viewModel.segments[0] else {
            Issue.record("Expected an .intervalBlock segment")
            return
        }
        var badSteps = steps
        badSteps[0].step.goal = .duration(seconds: -1)
        let badStepID = badSteps[0].step.id
        viewModel.replaceSegment(id: blockID, with: .intervalBlock(id: blockID, steps: badSteps, repetitions: repetitions))

        let found = viewModel.issues(forSegmentID: blockID)
        #expect(found.contains(
            ValidationIssue(
                rule: .goalDurationNotPositive(seconds: -1),
                locator: .intervalStep(blockID: blockID, stepID: badStepID)
            )
        ))
    }

    @Test("issues(forSegmentID:) returns the block-level issue for zero repetitions")
    func issuesForSegmentIDFindsBlockLevelIssue() {
        let viewModel = makeViewModel().viewModel
        viewModel.name = "Bad Interval Workout"
        viewModel.addSegment(.intervalBlock)
        guard case let .intervalBlock(blockID, steps, _) = viewModel.segments[0] else {
            Issue.record("Expected an .intervalBlock segment")
            return
        }
        viewModel.replaceSegment(id: blockID, with: .intervalBlock(id: blockID, steps: steps, repetitions: 0))

        let found = viewModel.issues(forSegmentID: blockID)
        #expect(found.contains(
            ValidationIssue(rule: .intervalBlockRepetitionsNotPositive(repetitions: 0), locator: .segment(id: blockID))
        ))
    }

    @Test("issues(forSegmentID:) returns empty for a clean segment even when other issues exist elsewhere")
    func issuesForSegmentIDEmptyForCleanSegment() {
        let viewModel = makeViewModel().viewModel
        // Leaves the name empty (a workout-level issue) on purpose.
        viewModel.addSegment(.easy)
        let cleanSegmentID = viewModel.segments[0].id

        #expect(viewModel.issues(forSegmentID: cleanSegmentID).isEmpty)
    }
}
