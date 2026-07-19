#if canImport(WorkoutKit)
import DomainKit
import Foundation
import HealthKit
import WorkoutKit

/// Translates a platform-independent `WorkoutCompositionPlan`
/// (`WatchCompositionPlanner`) into a WorkoutKit `WorkoutPlan`.
///
/// Wrapped in `#if canImport(WorkoutKit)` because WorkoutKit does not exist
/// on macOS (CLAUDE.md rule 2), where `swift test` runs the rest of
/// `DataKitTests` — all value validation and the pace-inversion math already
/// happened in `WatchCompositionPlanner`, so this layer is a thin, mostly
/// non-throwing structural translation, matching WorkoutKit's own
/// non-throwing composition initializers (RESEARCH-LOG 2026-07-06 §1). Every
/// WorkoutKit symbol below was read verbatim from the shipped
/// `WorkoutKit.swiftinterface` (see `docs/RESEARCH-LOG.md` 2026-07-06 §0.5)
/// — none are invented (CLAUDE.md rule 8).
@available(iOS 17.0, macOS 15.0, *)
enum WorkoutKitCompositionMapper {
    /// Builds a `WorkoutPlan` for `workout` under the stable identity
    /// `planID`, or throws `WatchSyncError.invalidComposition` if
    /// WorkoutKit's own static `supports*` pre-flight checks (§4 of the
    /// research log) reject any part of the composed workout.
    static func workoutPlan(for workout: Workout, planID: UUID) throws -> WorkoutPlan {
        let plan = try WatchCompositionPlanner.plan(for: workout)
        let composed = customWorkout(for: plan, activity: workout.activity)

        let failures = supportsFailures(for: composed)
        guard failures.isEmpty else {
            throw WatchSyncError.invalidComposition(reason: failures.joined(separator: "; "))
        }

        return WorkoutPlan(.custom(composed), id: planID)
    }

    // MARK: - IR -> CustomWorkout

    private static func customWorkout(for plan: WorkoutCompositionPlan, activity: WorkoutActivity) -> CustomWorkout {
        let (activityType, location) = hkActivity(for: activity)
        return CustomWorkout(
            activity: activityType,
            location: location,
            displayName: plan.displayName,
            warmup: plan.warmup.map(workoutStep),
            blocks: plan.blocks.map(intervalBlock),
            cooldown: plan.cooldown.map(workoutStep)
        )
    }

    private static func hkActivity(
        for activity: WorkoutActivity
    ) -> (HKWorkoutActivityType, HKWorkoutSessionLocationType) {
        switch activity {
        case .outdoorRun:
            return (.running, .outdoor)
        }
    }

    private static func intervalBlock(_ block: PlannedBlock) -> IntervalBlock {
        IntervalBlock(
            steps: block.steps.map(workoutKitIntervalStep),
            iterations: block.iterations
        )
    }

    // Explicitly `WorkoutKit.IntervalStep`: DomainKit also declares a public
    // `IntervalStep` struct (`WorkoutSegment.swift`), and both are visible
    // here since this file imports both modules — an unqualified
    // `IntervalStep` is ambiguous.
    private static func workoutKitIntervalStep(_ step: PlannedIntervalStep) -> WorkoutKit.IntervalStep {
        WorkoutKit.IntervalStep(intervalPurpose(for: step.purpose), step: workoutStep(step.step))
    }

    private static func intervalPurpose(for purpose: IntervalStepPurpose) -> WorkoutKit.IntervalStep.Purpose {
        switch purpose {
        case .work:
            return .work
        case .recovery:
            return .recovery
        }
    }

    private static func workoutStep(_ step: PlannedStep) -> WorkoutStep {
        WorkoutStep(goal: workoutGoal(step.goal), alert: step.alert.map(workoutAlert))
    }

    private static func workoutGoal(_ goal: Goal) -> WorkoutGoal {
        switch goal {
        case let .distance(meters):
            return .distance(meters, .meters)
        case let .duration(seconds):
            return .time(seconds, .seconds)
        case .open:
            return .open
        }
    }

    /// Maps an already-SI-unit `PlannedAlert` to a WorkoutKit alert, via the
    /// verified static factories on `WorkoutAlert` (RESEARCH-LOG 2026-07-06
    /// §3 + confirmed against the SDK interface directly for task 1.7):
    /// `.speed(_:unit:metric:)`, `.heartRate(_:unit:)`/`.heartRate(zone:)`,
    /// `.cadence(_:unit:)`. All of these take bare `Double`/`ClosedRange<Double>`
    /// values plus a `Foundation` unit, not `Measurement` — confirmed by
    /// reading `WorkoutKit.swiftinterface` directly, not just the research
    /// log's paraphrase.
    private static func workoutAlert(_ alert: PlannedAlert) -> any WorkoutAlert {
        switch alert {
        case let .paceRange(lower, upper):
            return .speed(lower...upper, unit: .metersPerSecond, metric: .current)
        case let .heartRateZone(zone):
            return .heartRate(zone: zone)
        case let .heartRateRange(lowerBPM, upperBPM):
            // `.countPerMinute` is declared as a static var on
            // `WorkoutAlertMetric` (not `UnitFrequency` itself, despite
            // returning one) per the SDK interface, so it must be qualified
            // explicitly rather than resolved via leading-dot syntax.
            return .heartRate(lowerBPM...upperBPM, unit: WorkoutAlertMetric.countPerMinute)
        case let .cadenceRange(lower, upper):
            return .cadence(lower...upper, unit: WorkoutAlertMetric.countPerMinute)
        }
    }

    // MARK: - `supports*` pre-flight

    /// Runs WorkoutKit's own static capability checks
    /// (`CustomWorkout.supportsActivity`/`supportsGoal`/`supportsAlert`,
    /// RESEARCH-LOG 2026-07-06 §4) against every goal/alert in `workout`,
    /// returning a human-readable failure per violation (empty = all
    /// checks passed). This is the "validate before Send" pre-flight
    /// `docs/ARCHITECTURE.md` §3.1/§7 calls for, distinct from the
    /// value-level trap guard already applied in `WatchCompositionPlanner`.
    private static func supportsFailures(for workout: CustomWorkout) -> [String] {
        guard CustomWorkout.supportsActivity(workout.activity) else {
            return ["activity \(workout.activity) is not supported"]
        }

        var failures: [String] = []
        if let warmup = workout.warmup {
            failures.append(contentsOf: stepFailures(warmup, label: "warmup", workout: workout))
        }
        for block in workout.blocks {
            for intervalStep in block.steps {
                let label = "\(intervalStep.purpose) step"
                failures.append(contentsOf: stepFailures(intervalStep.step, label: label, workout: workout))
            }
        }
        if let cooldown = workout.cooldown {
            failures.append(contentsOf: stepFailures(cooldown, label: "cooldown", workout: workout))
        }
        return failures
    }

    private static func stepFailures(_ step: WorkoutStep, label: String, workout: CustomWorkout) -> [String] {
        var failures: [String] = []
        if !CustomWorkout.supportsGoal(step.goal, activity: workout.activity, location: workout.location) {
            failures.append("\(label) goal is not supported")
        }
        if let alert = step.alert,
           !CustomWorkout.supportsAlert(alert, activity: workout.activity, location: workout.location) {
            failures.append("\(label) alert is not supported")
        }
        return failures
    }
}
#endif
