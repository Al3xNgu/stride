import Testing
import Foundation
import DomainKit
@testable import DataKit

/// Trap-guard coverage: non-positive/non-finite goal values must never
/// reach the WorkoutKit translation layer — they must throw here instead
/// (RESEARCH-LOG 2026-07-10 "spike crash root-caused"). Split from
/// `WatchCompositionPlannerTests.swift` to stay under the repo's
/// `file_length` lint threshold; fixtures are shared via the
/// `WatchCompositionPlannerFixtures` enum defined there.
@Suite("WatchCompositionPlanner — trap guard")
struct WatchCompositionPlannerTrapGuardTests {
    private typealias Fixtures = WatchCompositionPlannerFixtures

    @Test(
        "Non-positive or non-finite distance goals throw, never trap",
        arguments: [0.0, -1.0, -100.0, Double.nan, Double.infinity, -Double.infinity]
    )
    func nonPositiveDistanceGoalThrows(meters: Double) {
        let workout = Fixtures.makeWorkout(segments: [.step(Fixtures.step(intent: .easy, goal: .distance(meters: meters)))])
        #expect(throws: WatchSyncError.self) {
            _ = try WatchCompositionPlanner.plan(for: workout)
        }
    }

    @Test(
        "Non-positive or non-finite duration goals throw, never trap",
        arguments: [0.0, -1.0, -300.0, Double.nan, Double.infinity, -Double.infinity]
    )
    func nonPositiveDurationGoalThrows(seconds: Double) {
        let workout = Fixtures.makeWorkout(segments: [.step(Fixtures.step(intent: .easy, goal: .duration(seconds: seconds)))])
        #expect(throws: WatchSyncError.self) {
            _ = try WatchCompositionPlanner.plan(for: workout)
        }
    }

    @Test("A strictly-positive, finite distance goal does not throw")
    func positiveDistanceGoalPasses() throws {
        let workout = Fixtures.makeWorkout(segments: [.step(Fixtures.step(intent: .easy, goal: .distance(meters: 5_000)))])
        _ = try WatchCompositionPlanner.plan(for: workout)
    }

    @Test("An .open goal never throws regardless of any other value")
    func openGoalNeverThrows() throws {
        let workout = Fixtures.makeWorkout(segments: [.step(Fixtures.step(intent: .easy, goal: .open))])
        _ = try WatchCompositionPlanner.plan(for: workout)
    }

    @Test("A non-finite pace target upper bound throws")
    func infinitePaceUpperBoundThrows() {
        let target = Target.pace(range: 0.2...Double.infinity)
        let workout = Fixtures.makeWorkout(segments: [
            .step(Fixtures.step(intent: .tempo, goal: .open, target: target))
        ])
        #expect(throws: WatchSyncError.self) {
            _ = try WatchCompositionPlanner.plan(for: workout)
        }
    }

    @Test("A non-positive heart-rate range lower bound throws")
    func nonPositiveHeartRateRangeThrows() {
        let target = Target.heartRate(.range(0...150))
        let workout = Fixtures.makeWorkout(segments: [
            .step(Fixtures.step(intent: .tempo, goal: .open, target: target))
        ])
        #expect(throws: WatchSyncError.self) {
            _ = try WatchCompositionPlanner.plan(for: workout)
        }
    }

    @Test("A non-positive cadence range lower bound throws")
    func nonPositiveCadenceRangeThrows() {
        let target = Target.cadence(range: 0...180)
        let workout = Fixtures.makeWorkout(segments: [
            .step(Fixtures.step(intent: .tempo, goal: .open, target: target))
        ])
        #expect(throws: WatchSyncError.self) {
            _ = try WatchCompositionPlanner.plan(for: workout)
        }
    }

    @Test("A heart-rate zone outside 1...5 throws (ValidateWorkoutPolicy pre-flight)")
    func outOfBoundsHeartRateZoneThrows() {
        let target = Target.heartRate(.zone(9))
        let workout = Fixtures.makeWorkout(segments: [
            .step(Fixtures.step(intent: .tempo, goal: .open, target: target))
        ])
        #expect(throws: WatchSyncError.self) {
            _ = try WatchCompositionPlanner.plan(for: workout)
        }
    }

    @Test("A zero pace-range lower bound throws")
    func zeroPaceLowerBoundThrows() {
        let target = Target.pace(range: 0.0...0.3)
        let workout = Fixtures.makeWorkout(segments: [
            .step(Fixtures.step(intent: .tempo, goal: .open, target: target))
        ])
        #expect(throws: WatchSyncError.self) {
            _ = try WatchCompositionPlanner.plan(for: workout)
        }
    }

    // NOTE: an adversarial "ValidateWorkoutPolicy passes but the planner's
    // defense-in-depth still must catch it" scenario was attempted here for
    // pace/heart-rate/cadence upper bounds (which the domain policy checks
    // only for finiteness, not positivity — see its doc comment) by
    // constructing an inverted `ClosedRange<Double>` via
    // `ClosedRange(uncheckedBounds:)`. This is NOT constructible: unlike
    // `Range`, `ClosedRange`'s `lowerBound <= upperBound` invariant is
    // enforced by a `precondition` even through the "unchecked" initializer
    // (reproduced live: `Swift/ClosedRange.swift:91: Fatal error: ClosedRange
    // requires lowerBound <= upperBound`, verified for both an inverted pair
    // and a NaN lower bound). So a `Target.pace`/`.heartRate(.range)`/
    // `.cadence` can never hold an inverted or NaN-containing range through
    // any public Swift API — the domain policy's upper-bound-finite-only
    // check is therefore safe in practice, and the planner's extra
    // positivity check on those upper bounds is unreachable-but-harmless
    // defense in depth, not a live bug. (Scalar `Goal` values remain a real
    // NaN/negative injection point — see the parameterized goal tests above
    // — because `Goal.distance`/`.duration` carry a bare `Double`, not a
    // `ClosedRange`.)

    @Test("A subnormal-tiny positive, finite goal value does not throw: the trap floor is exactly zero, not 'too small'")
    func subnormalTinyPositiveGoalDoesNotThrow() throws {
        let workout = Fixtures.makeWorkout(segments: [
            .step(Fixtures.step(intent: .easy, goal: .distance(meters: Double.leastNonzeroMagnitude)))
        ])
        _ = try WatchCompositionPlanner.plan(for: workout)
    }

    @Test("A non-positive goal/target nested inside an interval block's work step throws, not just top-level steps")
    func invalidGoalInsideIntervalWorkStepThrows() {
        let work = IntervalStep(purpose: .work, step: Fixtures.step(intent: .work, goal: .distance(meters: 0)))
        let recovery = IntervalStep(purpose: .recovery, step: Fixtures.step(intent: .recovery, goal: .distance(meters: 200)))
        let workout = Fixtures.makeWorkout(segments: [.intervalBlock(steps: [work, recovery], repetitions: 6)])
        #expect(throws: WatchSyncError.self) {
            _ = try WatchCompositionPlanner.plan(for: workout)
        }
    }

    @Test("A non-positive target nested inside an interval block's recovery step throws, not just top-level steps")
    func invalidTargetInsideIntervalRecoveryStepThrows() {
        let target = Target.pace(range: 0.0...0.5)
        let work = IntervalStep(purpose: .work, step: Fixtures.step(intent: .work, goal: .distance(meters: 400)))
        let recovery = IntervalStep(
            purpose: .recovery,
            step: Fixtures.step(intent: .recovery, goal: .open, target: target)
        )
        let workout = Fixtures.makeWorkout(segments: [.intervalBlock(steps: [work, recovery], repetitions: 6)])
        #expect(throws: WatchSyncError.self) {
            _ = try WatchCompositionPlanner.plan(for: workout)
        }
    }

    @Test("A non-positive goal in the warmup step throws")
    func invalidGoalInWarmupStepThrows() {
        let workout = Fixtures.makeWorkout(segments: [
            .step(Fixtures.step(intent: .warmUp, goal: .duration(seconds: -1))),
            .step(Fixtures.step(intent: .easy, goal: .duration(seconds: 300)))
        ])
        #expect(throws: WatchSyncError.self) {
            _ = try WatchCompositionPlanner.plan(for: workout)
        }
    }

    @Test("A non-positive goal in the cooldown step throws")
    func invalidGoalInCooldownStepThrows() {
        let workout = Fixtures.makeWorkout(segments: [
            .step(Fixtures.step(intent: .easy, goal: .duration(seconds: 300))),
            .step(Fixtures.step(intent: .coolDown, goal: .duration(seconds: Double.nan)))
        ])
        #expect(throws: WatchSyncError.self) {
            _ = try WatchCompositionPlanner.plan(for: workout)
        }
    }
}

/// Pace-target -> speed-alert conversion: exact reciprocal math and the
/// bounds swap (faster/smaller seconds-per-meter -> higher meters-per-second).
@Suite("WatchCompositionPlanner — pace inversion math")
struct WatchCompositionPlannerPaceTests {
    private typealias Fixtures = WatchCompositionPlannerFixtures

    @Test("Pace range bounds are inverted to speed and swapped, with exact values")
    func paceRangeInvertedAndSwapped() throws {
        // 0.25 s/m (faster) ... 0.5 s/m (slower) -> 4.0 m/s ... 2.0 m/s domain
        // range, which becomes the *speed* range 2.0...4.0 m/s (slower bound
        // first) after the swap.
        let target = Target.pace(range: 0.25...0.5)
        let workout = Fixtures.makeWorkout(segments: [
            .step(Fixtures.step(intent: .tempo, goal: .open, target: target))
        ])
        let plan = try WatchCompositionPlanner.plan(for: workout)
        #expect(plan.blocks[0].steps.first?.step.alert == .paceRange(lowerMetersPerSecond: 2.0, upperMetersPerSecond: 4.0))
    }

    @Test("A narrow, fast pace range still inverts and swaps correctly")
    func narrowFastPaceRange() throws {
        // 5:00/km == 0.2 s/m ... 4:30/km == 0.18 s/m — note the *faster*
        // pace (0.18) is numerically smaller and is the domain lowerBound.
        let target = Target.pace(range: 0.18...0.2)
        let workout = Fixtures.makeWorkout(segments: [
            .step(Fixtures.step(intent: .work, goal: .open, target: target))
        ])
        let plan = try WatchCompositionPlanner.plan(for: workout)
        let expectedLower = 1 / 0.2
        let expectedUpper = 1 / 0.18
        guard case let .paceRange(lower, upper)? = plan.blocks[0].steps.first?.step.alert else {
            Issue.record("expected a paceRange alert")
            return
        }
        #expect(abs(lower - expectedLower) < 1e-9)
        #expect(abs(upper - expectedUpper) < 1e-9)
    }

    @Test("A degenerate pace range with equal bounds inverts to an equal (zero-width) speed range")
    func degenerateEqualBoundsPaceRange() throws {
        let target = Target.pace(range: 0.25...0.25)
        let workout = Fixtures.makeWorkout(segments: [
            .step(Fixtures.step(intent: .tempo, goal: .open, target: target))
        ])
        let plan = try WatchCompositionPlanner.plan(for: workout)
        #expect(plan.blocks[0].steps.first?.step.alert == .paceRange(lowerMetersPerSecond: 4.0, upperMetersPerSecond: 4.0))
    }

    @Test("Heart-rate range and cadence range targets pass through as bpm/steps-per-minute, unchanged")
    func heartRateAndCadencePassThroughUnchanged() throws {
        let hrTarget = Target.heartRate(.range(140...160))
        let cadenceTarget = Target.cadence(range: 170...180)
        let workout = Fixtures.makeWorkout(segments: [
            .step(Fixtures.step(intent: .tempo, goal: .open, target: hrTarget)),
            .step(Fixtures.step(intent: .tempo, goal: .open, target: cadenceTarget))
        ])
        let plan = try WatchCompositionPlanner.plan(for: workout)
        #expect(plan.blocks[0].steps.first?.step.alert == .heartRateRange(lowerBPM: 140, upperBPM: 160))
        #expect(plan.blocks[1].steps.first?.step.alert == .cadenceRange(lowerStepsPerMinute: 170, upperStepsPerMinute: 180))
    }

    @Test("A heart-rate zone target passes through as-is")
    func heartRateZonePassesThrough() throws {
        let target = Target.heartRate(.zone(4))
        let workout = Fixtures.makeWorkout(segments: [
            .step(Fixtures.step(intent: .tempo, goal: .open, target: target))
        ])
        let plan = try WatchCompositionPlanner.plan(for: workout)
        #expect(plan.blocks[0].steps.first?.step.alert == .heartRateZone(4))
    }

    @Test(
        "A heart-rate zone outside 1...5 is rejected by the planner's own guard, not just the policy",
        arguments: [0, -1, 6, Int.max]
    )
    func heartRateZoneOutOfBoundsRejected(_ zone: Int) {
        let workout = Fixtures.makeWorkout(segments: [
            .step(Fixtures.step(intent: .tempo, goal: .open, target: .heartRate(.zone(zone))))
        ])
        #expect(throws: WatchSyncError.self) {
            _ = try WatchCompositionPlanner.plan(for: workout)
        }
    }
}
