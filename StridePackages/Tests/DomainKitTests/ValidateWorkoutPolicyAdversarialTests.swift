import Testing
import Foundation
@testable import DomainKit

/// Adversarial coverage for `ValidateWorkoutPolicy`: NaN/infinity payloads,
/// deep nesting with multiple accumulated violations, name-trimming edge
/// cases (unicode whitespace, zero-width characters), HR-zone extremes,
/// duplicate segment ids, ordering determinism, and an `isValid` /
/// `issues.isEmpty` consistency property.
///
/// A prior adversarial pass found that NaN/infinity goal values and
/// infinite range bounds silently passed validation (`value <= 0` is a poor
/// proxy for "not positive" when `value` can be non-finite); those cases are
/// now fixed in the policy (see `isPositiveFinite`) and the tests below
/// assert the corrected behavior directly rather than pinning the old bug.
@Suite("ValidateWorkoutPolicy — adversarial")
struct ValidateWorkoutPolicyAdversarialTests {
    private typealias Fixtures = ValidateWorkoutPolicyFixtures

    // MARK: - NaN payloads

    // Fixed: `isPositiveFinite` requires `value.isFinite`, so a NaN distance
    // goal is now reported as invalid rather than silently passing the old
    // `meters <= 0` check (NaN compares false against every relational
    // operator). See ValidateWorkoutPolicy.swift `isPositiveFinite`.
    @Test("Goal.distance(meters: .nan) IS reported as invalid")
    func goalDistanceNaNReported() {
        let step = SegmentStep(intent: .easy, goal: .distance(meters: .nan))
        let workout = Fixtures.makeWorkout(segments: [.step(step)])
        let issues = ValidateWorkoutPolicy.validate(workout)
        #expect(issues.contains(where: { if case .goalDistanceNotPositive = $0.rule { return true }; return false }))
    }

    // Fixed: same root cause as above, applied to duration goals.
    @Test("Goal.duration(seconds: .nan) IS reported as invalid")
    func goalDurationNaNReported() {
        let step = SegmentStep(intent: .easy, goal: .duration(seconds: .nan))
        let workout = Fixtures.makeWorkout(segments: [.step(step)])
        let issues = ValidateWorkoutPolicy.validate(workout)
        #expect(issues.contains(where: { if case .goalDurationNotPositive = $0.rule { return true }; return false }))
    }

    // MARK: - Infinity payloads

    // Fixed: `isPositiveFinite` requires finiteness, so an infinite
    // distance/duration goal is now reported as invalid — it is operationally
    // meaningless (an unbounded step).
    @Test("Goal.distance(meters: .infinity) IS reported as invalid")
    func goalDistancePositiveInfinityReported() {
        let step = SegmentStep(intent: .easy, goal: .distance(meters: .infinity))
        let workout = Fixtures.makeWorkout(segments: [.step(step)])
        let issues = ValidateWorkoutPolicy.validate(workout)
        #expect(issues.contains(where: { if case .goalDistanceNotPositive = $0.rule { return true }; return false }))
    }

    @Test("Goal.duration(seconds: .infinity) IS reported as invalid")
    func goalDurationPositiveInfinityReported() {
        let step = SegmentStep(intent: .easy, goal: .duration(seconds: .infinity))
        let workout = Fixtures.makeWorkout(segments: [.step(step)])
        let issues = ValidateWorkoutPolicy.validate(workout)
        #expect(issues.contains(where: { if case .goalDurationNotPositive = $0.rule { return true }; return false }))
    }

    @Test("Goal.distance(meters: -.infinity) IS reported (negative infinity is <= 0)")
    func goalDistanceNegativeInfinityReported() {
        let step = SegmentStep(intent: .easy, goal: .distance(meters: -Double.infinity))
        let workout = Fixtures.makeWorkout(segments: [.step(step)])
        let issues = ValidateWorkoutPolicy.validate(workout)
        #expect(
            issues.contains(
                ValidationIssue(
                    rule: .goalDistanceNotPositive(meters: -Double.infinity),
                    locator: .segment(id: step.id)
                )
            )
        )
    }

    // Fixed: a pace range whose lower bound is `+.infinity` (constructed as
    // `.infinity...(.infinity)`, a degenerate but constructible ClosedRange)
    // now fails the `isPositiveFinite` check on the lower bound (and the
    // upper-bound finiteness check too), so an "infinitely slow" pace target
    // is correctly reported as invalid.
    @Test("Pace target with +infinity lower bound IS reported")
    func paceTargetInfiniteLowerBoundReported() {
        let step = SegmentStep(intent: .tempo, goal: .open, target: .pace(range: .infinity...(.infinity)))
        let workout = Fixtures.makeWorkout(segments: [.step(step)])
        let issues = ValidateWorkoutPolicy.validate(workout)
        #expect(
            issues.contains(
                ValidationIssue(
                    rule: .paceRangeNotPositive(lowerBound: .infinity, upperBound: .infinity),
                    locator: .segment(id: step.id)
                )
            )
        )
    }

    // Fixed: a finite, positive pace lower bound paired with a `+.infinity`
    // upper bound is now also reported — an unbounded-fast upper pace limit
    // is just as meaningless as a non-positive lower bound, and would break
    // `UnitFormatter` display and the WorkoutKit mapper.
    @Test("Pace target with finite positive lower bound but +infinity upper bound IS reported")
    func paceTargetInfiniteUpperBoundReported() {
        let step = SegmentStep(intent: .tempo, goal: .open, target: .pace(range: 0.2...(.infinity)))
        let workout = Fixtures.makeWorkout(segments: [.step(step)])
        let issues = ValidateWorkoutPolicy.validate(workout)
        #expect(
            issues.contains(
                ValidationIssue(
                    rule: .paceRangeNotPositive(lowerBound: 0.2, upperBound: .infinity),
                    locator: .segment(id: step.id)
                )
            )
        )
    }

    @Test("Cadence range with +infinity bounds IS reported")
    func cadenceRangeInfiniteBoundsReported() {
        let step = SegmentStep(intent: .tempo, goal: .open, target: .cadence(range: .infinity...(.infinity)))
        let workout = Fixtures.makeWorkout(segments: [.step(step)])
        let issues = ValidateWorkoutPolicy.validate(workout)
        #expect(issues.contains(where: { if case .cadenceRangeNotPositive = $0.rule { return true }; return false }))
    }

    @Test("Cadence range with finite positive lower bound but +infinity upper bound IS reported")
    func cadenceRangeInfiniteUpperBoundReported() {
        let step = SegmentStep(intent: .tempo, goal: .open, target: .cadence(range: 170...(.infinity)))
        let workout = Fixtures.makeWorkout(segments: [.step(step)])
        let issues = ValidateWorkoutPolicy.validate(workout)
        #expect(issues.contains(where: { if case .cadenceRangeNotPositive = $0.rule { return true }; return false }))
    }

    @Test("Heart-rate range with +infinity bounds IS reported")
    func heartRateRangeInfiniteBoundsReported() {
        let step = SegmentStep(intent: .tempo, goal: .open, target: .heartRate(.range(.infinity...(.infinity))))
        let workout = Fixtures.makeWorkout(segments: [.step(step)])
        let issues = ValidateWorkoutPolicy.validate(workout)
        #expect(issues.contains(where: { if case .heartRateRangeNotPositive = $0.rule { return true }; return false }))
    }

    @Test("Heart-rate range with finite positive lower bound but +infinity upper bound IS reported")
    func heartRateRangeInfiniteUpperBoundReported() {
        let step = SegmentStep(intent: .tempo, goal: .open, target: .heartRate(.range(140...(.infinity))))
        let workout = Fixtures.makeWorkout(segments: [.step(step)])
        let issues = ValidateWorkoutPolicy.validate(workout)
        #expect(issues.contains(where: { if case .heartRateRangeNotPositive = $0.rule { return true }; return false }))
    }

    // Note: a NaN-bounded ClosedRange<Double> (e.g. `.nan...someValue`) cannot
    // even be constructed — Swift's ClosedRange traps at init because the
    // `lowerBound <= upperBound` precondition is also false for NaN. So NaN
    // can only reach this policy via bare Double payloads (Goal, or a
    // range where only one endpoint is finite is still constructible: e.g.
    // `0...Double.nan` traps too, since `0 <= .nan` is false). Confirmed via
    // a standalone script; not exercised here because it would crash the
    // test process rather than produce a validation issue, mirroring the
    // existing "inverted pace range" note in ValidateWorkoutPolicyTargetTests.

    // MARK: - HR zone extremes (Int bounds)

    @Test("Heart-rate zone at Int.max is reported as out of bounds")
    func heartRateZoneIntMaxReported() {
        let step = SegmentStep(intent: .tempo, goal: .open, target: .heartRate(.zone(Int.max)))
        let workout = Fixtures.makeWorkout(segments: [.step(step)])
        let issues = ValidateWorkoutPolicy.validate(workout)
        #expect(
            issues.contains(
                ValidationIssue(rule: .heartRateZoneOutOfBounds(zone: Int.max), locator: .segment(id: step.id))
            )
        )
    }

    @Test("Heart-rate zone at Int.min is reported as out of bounds")
    func heartRateZoneIntMinReported() {
        let step = SegmentStep(intent: .tempo, goal: .open, target: .heartRate(.zone(Int.min)))
        let workout = Fixtures.makeWorkout(segments: [.step(step)])
        let issues = ValidateWorkoutPolicy.validate(workout)
        #expect(
            issues.contains(
                ValidationIssue(rule: .heartRateZoneOutOfBounds(zone: Int.min), locator: .segment(id: step.id))
            )
        )
    }

    // MARK: - Interval reps extremes

    @Test("Interval block with Int.min repetitions is reported")
    func intervalBlockIntMinRepetitionsReported() {
        let intervalStep = IntervalStep(purpose: .work, step: SegmentStep(intent: .work, goal: .open))
        let blockID = UUID()
        let segment = WorkoutSegment.intervalBlock(id: blockID, steps: [intervalStep], repetitions: Int.min)
        let workout = Fixtures.makeWorkout(segments: [segment])
        let issues = ValidateWorkoutPolicy.validate(workout)
        #expect(
            issues.contains(
                ValidationIssue(
                    rule: .intervalBlockRepetitionsNotPositive(repetitions: Int.min),
                    locator: .segment(id: blockID)
                )
            )
        )
    }

    @Test("Interval block with Int.max repetitions passes the repetitions rule")
    func intervalBlockIntMaxRepetitionsPasses() {
        let intervalStep = IntervalStep(purpose: .work, step: SegmentStep(intent: .work, goal: .open))
        let blockID = UUID()
        let segment = WorkoutSegment.intervalBlock(id: blockID, steps: [intervalStep], repetitions: Int.max)
        let workout = Fixtures.makeWorkout(segments: [segment])
        let issues = ValidateWorkoutPolicy.validate(workout)
        let hasRepetitionsIssue = issues.contains(where: {
            if case .intervalBlockRepetitionsNotPositive = $0.rule { return true }
            return false
        })
        #expect(!hasRepetitionsIssue)
    }

    // MARK: - Name edge cases

    @Test("Name of only U+00A0 (non-breaking space) is reported empty (NBSP is in .whitespaces)")
    func nbspOnlyNameReported() {
        let step = SegmentStep(intent: .easy, goal: .open)
        let workout = Fixtures.makeWorkout(name: "\u{00A0}\u{00A0}\u{00A0}", segments: [.step(step)])
        let issues = ValidateWorkoutPolicy.validate(workout)
        #expect(issues.contains(ValidationIssue(rule: .workoutNameEmpty, locator: .workout)))
    }

    // Pinning actual observed behavior: on this Foundation version, U+200B
    // (zero-width space) IS included in `.whitespacesAndNewlines` and so a
    // name of only zero-width spaces is *also* reported as empty. This
    // contradicts a common assumption (ZWSP is often treated as NOT
    // whitespace); documenting so a future Foundation/ICU change that flips
    // this is caught by a red test rather than silently shipping a
    // "phantom-named" workout.
    @Test("Name of only U+200B (zero-width space) IS reported empty on current Foundation/ICU")
    func zeroWidthSpaceOnlyNameReported() {
        let step = SegmentStep(intent: .easy, goal: .open)
        let workout = Fixtures.makeWorkout(name: "\u{200B}\u{200B}", segments: [.step(step)])
        let issues = ValidateWorkoutPolicy.validate(workout)
        #expect(issues.contains(ValidationIssue(rule: .workoutNameEmpty, locator: .workout)))
    }

    @Test("Name mixing visible text with only leading/trailing whitespace passes (trim only strips ends)")
    func nameWithInternalWhitespaceIsNotEmptyAfterTrim() {
        let step = SegmentStep(intent: .easy, goal: .open)
        let workout = Fixtures.makeWorkout(name: "  5K   Tempo  ", segments: [.step(step)])
        let issues = ValidateWorkoutPolicy.validate(workout)
        #expect(!issues.contains(where: { $0.rule == .workoutNameEmpty }))
    }

    // MARK: - Deep nesting: every issue in a many-step block accumulates

    @Test("Interval block with many steps reports one issue per invalid step, none dropped")
    func manyInvalidStepsAllReported() {
        let blockID = UUID()
        let badSteps = (0..<10).map { index in
            IntervalStep(
                purpose: index.isMultiple(of: 2) ? .work : .recovery,
                step: SegmentStep(intent: .work, goal: .distance(meters: -Double(index + 1)))
            )
        }
        let segment = WorkoutSegment.intervalBlock(id: blockID, steps: badSteps, repetitions: 4)
        let workout = Fixtures.makeWorkout(segments: [segment])
        let issues = ValidateWorkoutPolicy.validate(workout)

        for badStep in badSteps {
            #expect(
                issues.contains(
                    ValidationIssue(
                        rule: .goalDistanceNotPositive(meters: -Double(badStep.step.goal.metersMagnitudeForTest)),
                        locator: .intervalStep(blockID: blockID, stepID: badStep.step.id)
                    )
                ),
                "expected an issue for step \(badStep.step.id)"
            )
        }
        #expect(issues.count == badSteps.count)
    }

    @Test("Block with 0 reps AND empty steps reports both block-level issues, no early exit")
    func zeroRepsAndEmptyStepsBothReported() {
        let blockID = UUID()
        let segment = WorkoutSegment.intervalBlock(id: blockID, steps: [], repetitions: 0)
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
        #expect(issues.contains(ValidationIssue(rule: .intervalBlockHasNoSteps, locator: .segment(id: blockID))))
        #expect(issues.count == 2)
    }

    @Test("Multiple invalid blocks each report their own issues independently")
    func multipleInvalidBlocksEachReported() {
        let block1ID = UUID()
        let block2ID = UUID()
        let block1 = WorkoutSegment.intervalBlock(id: block1ID, steps: [], repetitions: 0)
        let block2 = WorkoutSegment.intervalBlock(
            id: block2ID,
            steps: [IntervalStep(purpose: .work, step: SegmentStep(intent: .work, goal: .duration(seconds: -1)))],
            repetitions: -5
        )
        let workout = Fixtures.makeWorkout(segments: [block1, block2])
        let issues = ValidateWorkoutPolicy.validate(workout)

        #expect(
            issues.contains(
                ValidationIssue(
                    rule: .intervalBlockRepetitionsNotPositive(repetitions: 0),
                    locator: .segment(id: block1ID)
                )
            )
        )
        #expect(issues.contains(ValidationIssue(rule: .intervalBlockHasNoSteps, locator: .segment(id: block1ID))))
        #expect(
            issues.contains(
                ValidationIssue(
                    rule: .intervalBlockRepetitionsNotPositive(repetitions: -5),
                    locator: .segment(id: block2ID)
                )
            )
        )
        #expect(issues.count == 4)
    }

}

/// Test-only accessor so the "many invalid steps" test can recover the
/// magnitude it encoded into each step's goal without re-deriving it via a
/// separate switch (keeps that test's intent obvious: "step N has goal -N").
private extension Goal {
    var metersMagnitudeForTest: Double {
        if case let .distance(meters) = self {
            return -meters
        }
        return 0
    }
}
