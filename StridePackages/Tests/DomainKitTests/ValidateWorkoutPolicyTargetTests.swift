import Testing
import Foundation
@testable import DomainKit

/// Target-sanity, locator, accumulation, and end-to-end coverage for
/// `ValidateWorkoutPolicy`. Split from `ValidateWorkoutPolicyTests.swift`
/// (structural rules) to stay under SwiftLint's type_body_length.
@Suite("ValidateWorkoutPolicy — targets, locators, accumulation")
struct ValidateWorkoutPolicyTargetTests {
    private typealias Fixtures = ValidateWorkoutPolicyFixtures

    // MARK: - Pace target sanity

    @Test("Pace target with positive lower bound passes")
    func paceTargetPositiveLowerBoundPasses() {
        let step = SegmentStep(intent: .tempo, goal: .open, target: .pace(range: 0.2...0.3))
        let workout = Fixtures.makeWorkout(segments: [.step(step)])
        let issues = ValidateWorkoutPolicy.validate(workout)
        #expect(!issues.contains(where: { if case .paceRangeNotPositive = $0.rule { return true }; return false }))
    }

    @Test("Pace target with 0 lower bound (boundary) reports paceRangeNotPositive")
    func paceTargetZeroLowerBoundReported() {
        let step = SegmentStep(intent: .tempo, goal: .open, target: .pace(range: 0...0.3))
        let workout = Fixtures.makeWorkout(segments: [.step(step)])
        let issues = ValidateWorkoutPolicy.validate(workout)
        #expect(
            issues.contains(
                ValidationIssue(
                    rule: .paceRangeNotPositive(lowerBound: 0, upperBound: 0.3),
                    locator: .segment(id: step.id)
                )
            )
        )
    }

    // Note: ClosedRange<Double> traps on construction if lowerBound > upperBound,
    // so an inverted pace range is unrepresentable in this domain model and is
    // intentionally not exercised here (would crash the test process, not
    // produce a validation issue).

    // MARK: - Heart-rate targets

    @Test("Heart-rate zone within 1...5 passes", arguments: [1, 2, 3, 4, 5])
    func heartRateZoneInBoundsPasses(zone: Int) {
        let step = SegmentStep(intent: .tempo, goal: .open, target: .heartRate(.zone(zone)))
        let workout = Fixtures.makeWorkout(segments: [.step(step)])
        let issues = ValidateWorkoutPolicy.validate(workout)
        #expect(!issues.contains(where: { if case .heartRateZoneOutOfBounds = $0.rule { return true }; return false }))
    }

    @Test("Heart-rate zone outside 1...5 reports heartRateZoneOutOfBounds", arguments: [0, -1, 6, 100])
    func heartRateZoneOutOfBoundsReported(zone: Int) {
        let step = SegmentStep(intent: .tempo, goal: .open, target: .heartRate(.zone(zone)))
        let workout = Fixtures.makeWorkout(segments: [.step(step)])
        let issues = ValidateWorkoutPolicy.validate(workout)
        #expect(
            issues.contains(
                ValidationIssue(rule: .heartRateZoneOutOfBounds(zone: zone), locator: .segment(id: step.id))
            )
        )
    }

    @Test("Heart-rate range with positive bounds passes")
    func heartRateRangePositivePasses() {
        let step = SegmentStep(intent: .tempo, goal: .open, target: .heartRate(.range(140...160)))
        let workout = Fixtures.makeWorkout(segments: [.step(step)])
        let issues = ValidateWorkoutPolicy.validate(workout)
        #expect(!issues.contains(where: { if case .heartRateRangeNotPositive = $0.rule { return true }; return false }))
    }

    @Test("Heart-rate range with 0 lower bound (boundary) reports heartRateRangeNotPositive")
    func heartRateRangeZeroLowerBoundReported() {
        let step = SegmentStep(intent: .tempo, goal: .open, target: .heartRate(.range(0...160)))
        let workout = Fixtures.makeWorkout(segments: [.step(step)])
        let issues = ValidateWorkoutPolicy.validate(workout)
        #expect(
            issues.contains(
                ValidationIssue(
                    rule: .heartRateRangeNotPositive(lowerBound: 0, upperBound: 160),
                    locator: .segment(id: step.id)
                )
            )
        )
    }

    // MARK: - Cadence target sanity

    @Test("Cadence range with positive bounds passes")
    func cadenceRangePositivePasses() {
        let step = SegmentStep(intent: .tempo, goal: .open, target: .cadence(range: 170...180))
        let workout = Fixtures.makeWorkout(segments: [.step(step)])
        let issues = ValidateWorkoutPolicy.validate(workout)
        #expect(!issues.contains(where: { if case .cadenceRangeNotPositive = $0.rule { return true }; return false }))
    }

    @Test("Cadence range with 0 lower bound (boundary) reports cadenceRangeNotPositive")
    func cadenceRangeZeroLowerBoundReported() {
        let step = SegmentStep(intent: .tempo, goal: .open, target: .cadence(range: 0...180))
        let workout = Fixtures.makeWorkout(segments: [.step(step)])
        let issues = ValidateWorkoutPolicy.validate(workout)
        #expect(
            issues.contains(
                ValidationIssue(
                    rule: .cadenceRangeNotPositive(lowerBound: 0, upperBound: 180),
                    locator: .segment(id: step.id)
                )
            )
        )
    }

    // MARK: - Recursion into interval-block steps, with correct locators

    @Test("Violation inside an interval block's step reports an intervalStep locator with block and step ids")
    func intervalStepViolationHasCorrectLocator() {
        let badStep = SegmentStep(intent: .work, goal: .distance(meters: -1))
        let goodStep = SegmentStep(intent: .recovery, goal: .duration(seconds: 60))
        let blockID = UUID()
        let segment = WorkoutSegment.intervalBlock(
            id: blockID,
            steps: [
                IntervalStep(purpose: .work, step: badStep),
                IntervalStep(purpose: .recovery, step: goodStep)
            ],
            repetitions: 4
        )
        let workout = Fixtures.makeWorkout(segments: [segment])
        let issues = ValidateWorkoutPolicy.validate(workout)
        #expect(
            issues.contains(
                ValidationIssue(
                    rule: .goalDistanceNotPositive(meters: -1),
                    locator: .intervalStep(blockID: blockID, stepID: badStep.id)
                )
            )
        )
        #expect(!issues.contains(where: { $0.locator == .intervalStep(blockID: blockID, stepID: goodStep.id) }))
    }

    // MARK: - Multi-violation accumulation

    @Test("A workout with 3+ distinct issues reports all of them")
    func multipleViolationsAllReported() {
        let badGoalStep = SegmentStep(intent: .easy, goal: .distance(meters: 0))
        let emptyBlockID = UUID()
        let emptyBlock = WorkoutSegment.intervalBlock(id: emptyBlockID, steps: [], repetitions: 0)
        let workout = Fixtures.makeWorkout(name: "  ", segments: [.step(badGoalStep), emptyBlock])

        let issues = ValidateWorkoutPolicy.validate(workout)

        #expect(issues.contains(ValidationIssue(rule: .workoutNameEmpty, locator: .workout)))
        #expect(
            issues.contains(
                ValidationIssue(rule: .goalDistanceNotPositive(meters: 0), locator: .segment(id: badGoalStep.id))
            )
        )
        #expect(
            issues.contains(
                ValidationIssue(
                    rule: .intervalBlockRepetitionsNotPositive(repetitions: 0),
                    locator: .segment(id: emptyBlockID)
                )
            )
        )
        #expect(
            issues.contains(ValidationIssue(rule: .intervalBlockHasNoSteps, locator: .segment(id: emptyBlockID)))
        )
        #expect(issues.count >= 4)
    }

    // MARK: - isValid convenience

    @Test("isValid returns false when there are issues")
    func isValidFalseWhenIssuesExist() {
        let workout = Fixtures.makeWorkout(segments: [])
        #expect(!ValidateWorkoutPolicy.isValid(workout))
    }

    @Test("isValid returns true when there are no issues")
    func isValidTrueWhenNoIssues() {
        let step = SegmentStep(intent: .easy, goal: .open)
        let workout = Fixtures.makeWorkout(segments: [.step(step)])
        #expect(ValidateWorkoutPolicy.isValid(workout))
    }

    // MARK: - Fully valid realistic workout

    @Test("A realistic warm-up + 4x(work+recovery) + cool-down workout produces no issues")
    func realisticValidWorkoutProducesNoIssues() {
        let warmUp = SegmentStep(
            intent: .warmUp,
            goal: .duration(seconds: 600),
            target: .pace(range: 0.35...0.4)
        )
        let work = IntervalStep(
            purpose: .work,
            step: SegmentStep(
                intent: .work,
                goal: .distance(meters: 400),
                target: .pace(range: 0.2...0.22)
            )
        )
        let recovery = IntervalStep(
            purpose: .recovery,
            step: SegmentStep(
                intent: .recovery,
                goal: .duration(seconds: 90),
                target: .heartRate(.zone(2))
            )
        )
        let intervalBlock = WorkoutSegment.intervalBlock(steps: [work, recovery], repetitions: 4)
        let coolDown = SegmentStep(
            intent: .coolDown,
            goal: .duration(seconds: 300),
            target: .cadence(range: 160...170)
        )

        let workout = Fixtures.makeWorkout(
            name: "4x400m Intervals",
            segments: [.step(warmUp), intervalBlock, .step(coolDown)]
        )

        #expect(ValidateWorkoutPolicy.validate(workout) == [])
    }
}
