import Testing
import Foundation
@testable import DomainKit

/// Duplicate-id ambiguity, ordering determinism, and `isValid`/`issues.isEmpty`
/// consistency coverage for `ValidateWorkoutPolicy`. Split from
/// `ValidateWorkoutPolicyAdversarialTests.swift` to stay under SwiftLint's
/// file_length/type_body_length, mirroring the existing structural/target split.
@Suite("ValidateWorkoutPolicy — adversarial (identity, ordering, consistency)")
struct WorkoutPolicyAdversarialIdentityTests {
    private typealias Fixtures = ValidateWorkoutPolicyFixtures

    // MARK: - Duplicate segment ids (entity layer permits this)

    // Observation, not a bug: the policy has no notion of "segment identity
    // uniqueness" — it is a pure structural checker keyed off whatever ids
    // the caller supplies. If two top-level `.step` segments share a `UUID`,
    // both are validated independently and both issues carry the *same*
    // locator, so presentation code cannot distinguish which occurrence an
    // issue belongs to. This is a latent ambiguity in `ValidationLocator`
    // itself (ids are assumed unique) rather than a defect in this policy;
    // flagged for awareness, not asserted as wrong.
    @Test("Two segments sharing the same id both report issues, with identical (ambiguous) locators")
    func duplicateSegmentIdsBothReportWithSameLocator() {
        let sharedID = UUID()
        let step1 = SegmentStep(id: sharedID, intent: .easy, goal: .distance(meters: -1))
        let step2 = SegmentStep(id: sharedID, intent: .work, goal: .distance(meters: -2))
        let workout = Fixtures.makeWorkout(segments: [.step(step1), .step(step2)])
        let issues = ValidateWorkoutPolicy.validate(workout)

        let matchingLocatorIssues = issues.filter { $0.locator == .segment(id: sharedID) }
        #expect(matchingLocatorIssues.count == 2)
        #expect(
            matchingLocatorIssues.contains(
                ValidationIssue(rule: .goalDistanceNotPositive(meters: -1), locator: .segment(id: sharedID))
            )
        )
        #expect(
            matchingLocatorIssues.contains(
                ValidationIssue(rule: .goalDistanceNotPositive(meters: -2), locator: .segment(id: sharedID))
            )
        )
    }

    // MARK: - Determinism / stable ordering

    @Test("Validating the same multi-violation workout twice yields identical issue order")
    func validationOrderIsDeterministicAcrossRuns() {
        let blockID = UUID()
        let badStep1 = SegmentStep(intent: .work, goal: .distance(meters: -1))
        let badStep2 = SegmentStep(intent: .recovery, goal: .duration(seconds: -5))
        let block = WorkoutSegment.intervalBlock(
            id: blockID,
            steps: [
                IntervalStep(purpose: .work, step: badStep1),
                IntervalStep(purpose: .recovery, step: badStep2)
            ],
            repetitions: 0
        )
        let trailingBadStep = SegmentStep(intent: .easy, goal: .distance(meters: 0))
        let workout = Fixtures.makeWorkout(name: "", segments: [block, .step(trailingBadStep)])

        let firstRun = ValidateWorkoutPolicy.validate(workout)
        let secondRun = ValidateWorkoutPolicy.validate(workout)

        #expect(firstRun == secondRun)
        #expect(firstRun.count > 1)
    }

    // MARK: - isValid / issues.isEmpty consistency (property-style)

    @Test(
        "isValid(workout) == validate(workout).isEmpty across a spread of fixtures",
        arguments: [
            WorkoutPolicyAdversarialIdentityTests.emptyWorkout(),
            WorkoutPolicyAdversarialIdentityTests.singleValidStepWorkout(),
            WorkoutPolicyAdversarialIdentityTests.blankNameWorkout(),
            WorkoutPolicyAdversarialIdentityTests.badGoalWorkout(),
            WorkoutPolicyAdversarialIdentityTests.nestedValidIntervalWorkout(),
            WorkoutPolicyAdversarialIdentityTests.nestedInvalidIntervalWorkout(),
            WorkoutPolicyAdversarialIdentityTests.nanGoalWorkout()
        ]
    )
    func isValidMatchesIssuesEmpty(workout: Workout) {
        #expect(ValidateWorkoutPolicy.isValid(workout) == ValidateWorkoutPolicy.validate(workout).isEmpty)
    }

    private static func emptyWorkout() -> Workout {
        Fixtures.makeWorkout(segments: [])
    }

    private static func singleValidStepWorkout() -> Workout {
        Fixtures.makeWorkout(segments: [.step(SegmentStep(intent: .easy, goal: .open))])
    }

    private static func blankNameWorkout() -> Workout {
        Fixtures.makeWorkout(name: "   ", segments: [.step(SegmentStep(intent: .easy, goal: .open))])
    }

    private static func badGoalWorkout() -> Workout {
        Fixtures.makeWorkout(segments: [.step(SegmentStep(intent: .easy, goal: .distance(meters: -1)))])
    }

    private static func nestedValidIntervalWorkout() -> Workout {
        let work = IntervalStep(purpose: .work, step: SegmentStep(intent: .work, goal: .distance(meters: 400)))
        let recoveryStep = SegmentStep(intent: .recovery, goal: .duration(seconds: 60))
        let recovery = IntervalStep(purpose: .recovery, step: recoveryStep)
        return Fixtures.makeWorkout(segments: [.intervalBlock(steps: [work, recovery], repetitions: 4)])
    }

    private static func nestedInvalidIntervalWorkout() -> Workout {
        let work = IntervalStep(purpose: .work, step: SegmentStep(intent: .work, goal: .distance(meters: -400)))
        return Fixtures.makeWorkout(segments: [.intervalBlock(steps: [work], repetitions: 0)])
    }

    private static func nanGoalWorkout() -> Workout {
        Fixtures.makeWorkout(segments: [.step(SegmentStep(intent: .easy, goal: .distance(meters: .nan)))])
    }
}
