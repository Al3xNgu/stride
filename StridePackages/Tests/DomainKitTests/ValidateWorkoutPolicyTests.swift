import Testing
import Foundation
@testable import DomainKit

/// Shared fixtures for `ValidateWorkoutPolicy` test suites, split across
/// files to stay under SwiftLint's type_body_length. See also
/// `ValidateWorkoutPolicyTargetTests.swift` for target/locator/accumulation
/// coverage.
enum ValidateWorkoutPolicyFixtures {
    static let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)

    static func makeWorkout(
        name: String = "Valid Workout",
        segments: [WorkoutSegment] = []
    ) -> Workout {
        Workout(name: name, segments: segments, createdAt: referenceDate, updatedAt: referenceDate)
    }
}

/// Structural rule coverage for `ValidateWorkoutPolicy`: workout-level
/// checks (segments present, non-empty name), interval-block repetitions
/// and step-count rules, and goal positivity rules.
@Suite("ValidateWorkoutPolicy — structural rules")
struct ValidateWorkoutPolicyTests {
    private typealias Fixtures = ValidateWorkoutPolicyFixtures

    // MARK: - Workout has ≥1 segment

    @Test("Empty segments array reports workoutHasNoSegments")
    func emptySegmentsReported() {
        let workout = Fixtures.makeWorkout(segments: [])
        let issues = ValidateWorkoutPolicy.validate(workout)
        #expect(issues.contains(ValidationIssue(rule: .workoutHasNoSegments, locator: .workout)))
    }

    @Test("A single valid segment does not report workoutHasNoSegments")
    func nonEmptySegmentsPasses() {
        let step = SegmentStep(intent: .easy, goal: .open)
        let workout = Fixtures.makeWorkout(segments: [.step(step)])
        let issues = ValidateWorkoutPolicy.validate(workout)
        #expect(!issues.contains(ValidationIssue(rule: .workoutHasNoSegments, locator: .workout)))
    }

    // MARK: - Workout name non-empty (trimmed)

    @Test("Empty name reports workoutNameEmpty", arguments: ["", "   ", "\n\t "])
    func emptyOrWhitespaceNameReported(name: String) {
        let step = SegmentStep(intent: .easy, goal: .open)
        let workout = Fixtures.makeWorkout(name: name, segments: [.step(step)])
        let issues = ValidateWorkoutPolicy.validate(workout)
        #expect(issues.contains(ValidationIssue(rule: .workoutNameEmpty, locator: .workout)))
    }

    @Test("Non-empty name does not report workoutNameEmpty")
    func nonEmptyNamePasses() {
        let step = SegmentStep(intent: .easy, goal: .open)
        let workout = Fixtures.makeWorkout(name: "5K Tempo", segments: [.step(step)])
        let issues = ValidateWorkoutPolicy.validate(workout)
        #expect(!issues.contains(where: { $0.rule == .workoutNameEmpty }))
    }

    // MARK: - Interval block repetitions ≥ 1

    @Test("Interval block with 0 repetitions reports the violation")
    func intervalBlockZeroRepetitionsReported() {
        let intervalStep = IntervalStep(purpose: .work, step: SegmentStep(intent: .work, goal: .open))
        let blockID = UUID()
        let segment = WorkoutSegment.intervalBlock(id: blockID, steps: [intervalStep], repetitions: 0)
        let workout = Fixtures.makeWorkout(segments: [segment])
        let issues = ValidateWorkoutPolicy.validate(workout)
        #expect(
            issues.contains(
                ValidationIssue(
                    rule: .intervalBlockRepetitionsNotPositive(repetitions: 0),
                    locator: .segment(id: blockID)
                )
            )
        )
    }

    @Test("Interval block with negative repetitions reports the violation")
    func intervalBlockNegativeRepetitionsReported() {
        let intervalStep = IntervalStep(purpose: .work, step: SegmentStep(intent: .work, goal: .open))
        let blockID = UUID()
        let segment = WorkoutSegment.intervalBlock(id: blockID, steps: [intervalStep], repetitions: -3)
        let workout = Fixtures.makeWorkout(segments: [segment])
        let issues = ValidateWorkoutPolicy.validate(workout)
        #expect(
            issues.contains(
                ValidationIssue(
                    rule: .intervalBlockRepetitionsNotPositive(repetitions: -3),
                    locator: .segment(id: blockID)
                )
            )
        )
    }

    @Test("Interval block with exactly 1 repetition (boundary) does not report the repetitions violation")
    func intervalBlockOneRepetitionPasses() {
        let intervalStep = IntervalStep(purpose: .work, step: SegmentStep(intent: .work, goal: .open))
        let blockID = UUID()
        let segment = WorkoutSegment.intervalBlock(id: blockID, steps: [intervalStep], repetitions: 1)
        let workout = Fixtures.makeWorkout(segments: [segment])
        let issues = ValidateWorkoutPolicy.validate(workout)
        #expect(!issues.contains(where: { if case .intervalBlockRepetitionsNotPositive = $0.rule { return true }; return false }))
    }

    // MARK: - Interval block needs ≥1 step

    @Test("Interval block with no steps reports intervalBlockHasNoSteps")
    func intervalBlockEmptyStepsReported() {
        let blockID = UUID()
        let segment = WorkoutSegment.intervalBlock(id: blockID, steps: [], repetitions: 4)
        let workout = Fixtures.makeWorkout(segments: [segment])
        let issues = ValidateWorkoutPolicy.validate(workout)
        #expect(issues.contains(ValidationIssue(rule: .intervalBlockHasNoSteps, locator: .segment(id: blockID))))
    }

    @Test("Interval block with one step does not report intervalBlockHasNoSteps")
    func intervalBlockOneStepPasses() {
        let intervalStep = IntervalStep(purpose: .work, step: SegmentStep(intent: .work, goal: .open))
        let blockID = UUID()
        let segment = WorkoutSegment.intervalBlock(id: blockID, steps: [intervalStep], repetitions: 4)
        let workout = Fixtures.makeWorkout(segments: [segment])
        let issues = ValidateWorkoutPolicy.validate(workout)
        #expect(!issues.contains(where: { $0.rule == .intervalBlockHasNoSteps }))
    }

    // MARK: - Goals: strictly positive distance/duration; .open always valid

    @Test("Goal.distance with 0 meters (boundary) reports goalDistanceNotPositive")
    func goalDistanceZeroReported() {
        let step = SegmentStep(intent: .easy, goal: .distance(meters: 0))
        let workout = Fixtures.makeWorkout(segments: [.step(step)])
        let issues = ValidateWorkoutPolicy.validate(workout)
        #expect(
            issues.contains(
                ValidationIssue(rule: .goalDistanceNotPositive(meters: 0), locator: .segment(id: step.id))
            )
        )
    }

    @Test("Goal.distance with negative meters reports goalDistanceNotPositive")
    func goalDistanceNegativeReported() {
        let step = SegmentStep(intent: .easy, goal: .distance(meters: -100))
        let workout = Fixtures.makeWorkout(segments: [.step(step)])
        let issues = ValidateWorkoutPolicy.validate(workout)
        #expect(
            issues.contains(
                ValidationIssue(rule: .goalDistanceNotPositive(meters: -100), locator: .segment(id: step.id))
            )
        )
    }

    @Test("Goal.distance with positive meters passes")
    func goalDistancePositivePasses() {
        let step = SegmentStep(intent: .easy, goal: .distance(meters: 1_000))
        let workout = Fixtures.makeWorkout(segments: [.step(step)])
        let issues = ValidateWorkoutPolicy.validate(workout)
        #expect(!issues.contains(where: { if case .goalDistanceNotPositive = $0.rule { return true }; return false }))
    }

    @Test("Goal.duration with 0 seconds (boundary) reports goalDurationNotPositive")
    func goalDurationZeroReported() {
        let step = SegmentStep(intent: .easy, goal: .duration(seconds: 0))
        let workout = Fixtures.makeWorkout(segments: [.step(step)])
        let issues = ValidateWorkoutPolicy.validate(workout)
        #expect(
            issues.contains(
                ValidationIssue(rule: .goalDurationNotPositive(seconds: 0), locator: .segment(id: step.id))
            )
        )
    }

    @Test("Goal.duration with negative seconds reports goalDurationNotPositive")
    func goalDurationNegativeReported() {
        let step = SegmentStep(intent: .easy, goal: .duration(seconds: -30))
        let workout = Fixtures.makeWorkout(segments: [.step(step)])
        let issues = ValidateWorkoutPolicy.validate(workout)
        #expect(
            issues.contains(
                ValidationIssue(rule: .goalDurationNotPositive(seconds: -30), locator: .segment(id: step.id))
            )
        )
    }

    @Test("Goal.duration with positive seconds passes")
    func goalDurationPositivePasses() {
        let step = SegmentStep(intent: .easy, goal: .duration(seconds: 600))
        let workout = Fixtures.makeWorkout(segments: [.step(step)])
        let issues = ValidateWorkoutPolicy.validate(workout)
        #expect(!issues.contains(where: { if case .goalDurationNotPositive = $0.rule { return true }; return false }))
    }

    @Test("Goal.open never reports a goal violation")
    func goalOpenAlwaysPasses() {
        let step = SegmentStep(intent: .easy, goal: .open)
        let workout = Fixtures.makeWorkout(segments: [.step(step)])
        let issues = ValidateWorkoutPolicy.validate(workout)
        #expect(issues.isEmpty)
    }
}
