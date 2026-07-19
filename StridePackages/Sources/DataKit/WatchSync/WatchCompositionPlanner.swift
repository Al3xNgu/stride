import DomainKit
import Foundation

/// A single alert/guidance value, expressed in SI units, ready to be handed
/// to a WorkoutKit alert factory.
///
/// Kept separate from `WorkoutKitCompositionMapper`'s WorkoutKit-specific
/// translation (task 1.7) so the value math — in particular the pace
/// inversion below — is exercised by `swift test` on macOS, where
/// `WorkoutKit` does not exist (CLAUDE.md rule 2; RESEARCH-LOG 2026-07-10
/// Task 0.6 §4).
public enum PlannedAlert: Equatable, Hashable, Sendable {
    /// A pace range converted to a speed range in meters-per-second.
    ///
    /// WorkoutKit has no dedicated pace alert type — pace is modeled as
    /// speed (`docs/RESEARCH-LOG.md` 2026-07-06 §3: "There is NO 'PaceAlert'
    /// type — pace is modeled as speed"). Stride stores pace as
    /// seconds-per-meter (CLAUDE.md rule 4) with the *lower* bound being the
    /// *faster* pace; speed is the reciprocal of pace, and reciprocal is a
    /// monotonically-decreasing function, so the bounds swap on conversion —
    /// the faster (smaller) seconds-per-meter bound becomes the *higher*
    /// meters-per-second bound, and vice versa.
    case paceRange(lowerMetersPerSecond: Double, upperMetersPerSecond: Double)
    /// A named heart-rate zone (Apple's five-zone model, per
    /// `ValidateWorkoutPolicy`).
    case heartRateZone(Int)
    /// An explicit heart-rate range, in beats per minute.
    case heartRateRange(lowerBPM: Double, upperBPM: Double)
    /// A cadence range, in steps per minute.
    case cadenceRange(lowerStepsPerMinute: Double, upperStepsPerMinute: Double)
}

/// A single step, with its goal already confirmed finite/positive (or
/// `.open`) and its target (if any) translated into a `PlannedAlert`.
public struct PlannedStep: Equatable, Hashable, Sendable {
    /// The step's runner-facing intent, carried through unchanged — the
    /// WorkoutKit translation layer uses this to pick an `IntervalStep`
    /// purpose for steps that aren't part of a domain interval block (see
    /// `WatchCompositionPlanner.purpose(for:)`).
    public var intent: SegmentIntent
    /// The step's completion goal (meters/seconds/open) — reused from
    /// DomainKit as-is since `Goal` is already SI-unit and WorkoutKit-free.
    public var goal: Goal
    /// The step's in-run alert, if any, already converted to SI units.
    public var alert: PlannedAlert?
}

/// A single step inside a planned interval block, tagged with its role.
public struct PlannedIntervalStep: Equatable, Hashable, Sendable {
    /// Whether this step is the work bout or the recovery bout. Reuses
    /// `IntervalStepPurpose` directly: its two cases (`work`/`recovery`) are
    /// a verbatim 1:1 match for WorkoutKit's `IntervalStep.Purpose`
    /// (RESEARCH-LOG 2026-07-06 §1), so no separate IR enum is needed.
    public var purpose: IntervalStepPurpose
    /// The step itself.
    public var step: PlannedStep
}

/// A repeating block of one or more planned steps.
public struct PlannedBlock: Equatable, Hashable, Sendable {
    /// The block's steps, in order.
    public var steps: [PlannedIntervalStep]
    /// Number of times the block repeats (WorkoutKit's `IntervalBlock.iterations`).
    public var iterations: Int
}

/// The platform-independent intermediate representation of a domain
/// `Workout`, ready for translation into a WorkoutKit `CustomWorkout`.
///
/// Producing this IR is the sole responsibility of `WatchCompositionPlanner`;
/// translating it into WorkoutKit types is `WorkoutKitCompositionMapper`'s
/// job (guarded by `#if canImport(WorkoutKit)` since WorkoutKit doesn't exist
/// on macOS, where `swift test` runs — see that file's doc comment).
public struct WorkoutCompositionPlan: Equatable, Hashable, Sendable {
    /// The workout's display name, carried through to `CustomWorkout.displayName`.
    public var displayName: String
    /// The leading warm-up step, if the workout's first top-level segment
    /// was a single `.warmUp`-intent step.
    public var warmup: PlannedStep?
    /// Every other top-level segment, each expressed as a `PlannedBlock`
    /// (a lone step becomes a 1-iteration, 1-step block).
    public var blocks: [PlannedBlock]
    /// The trailing cool-down step, if the workout's last remaining
    /// top-level segment was a single `.coolDown`-intent step.
    public var cooldown: PlannedStep?
}

/// Pure domain `Workout` -> `WorkoutCompositionPlan` planner.
///
/// This type has no WorkoutKit dependency (only `DomainKit` + `Foundation`)
/// so it is fully unit-testable on macOS via `swift test` (CLAUDE.md rule 2;
/// task 1.7 structuring requirement). It is also the mapper's *only* trap
/// guard against WorkoutKit's `CustomWorkout.init` runtime precondition
/// (`Fatal error: requiresNonZeroValue` on any goal value <= 0 — a process
/// kill, not a catchable error, per RESEARCH-LOG's 2026-07-10 "spike crash
/// root-caused" entry): every numeric value that reaches
/// `WorkoutCompositionPlan` has already been confirmed finite and positive
/// here, independently of (and in addition to) `ValidateWorkoutPolicy`, so a
/// bug in that policy alone cannot cause a trap downstream.
public enum WatchCompositionPlanner {
    /// Builds a `WorkoutCompositionPlan` from `workout`, or throws a typed
    /// `WatchSyncError` if the workout is structurally invalid or contains
    /// any non-finite/non-positive goal or target value.
    ///
    /// This function is total: every reachable input either produces a plan
    /// or throws — it never traps.
    public static func plan(for workout: Workout) throws -> WorkoutCompositionPlan {
        let issues = ValidateWorkoutPolicy.validate(workout)
        guard issues.isEmpty else {
            throw WatchSyncError.invalidComposition(reason: describe(issues))
        }
        // Defense in depth: `ValidateWorkoutPolicy` already rejects
        // non-positive/non-finite values above, but a trap is unrecoverable,
        // so every step is re-checked independently right before it's
        // placed into the IR (see `plannedStep(from:)` below).
        guard !workout.segments.isEmpty else {
            throw WatchSyncError.invalidComposition(reason: "workout has no segments")
        }

        var remaining = workout.segments[...]

        var warmup: PlannedStep?
        if case let .step(step)? = remaining.first, step.intent == .warmUp {
            warmup = try plannedStep(from: step)
            remaining.removeFirst()
        }

        var cooldown: PlannedStep?
        if case let .step(step)? = remaining.last, step.intent == .coolDown {
            cooldown = try plannedStep(from: step)
            remaining.removeLast()
        }

        let blocks = try remaining.map { try plannedBlock(from: $0) }

        return WorkoutCompositionPlan(
            displayName: workout.name,
            warmup: warmup,
            blocks: blocks,
            cooldown: cooldown
        )
    }

    // MARK: - Segment -> block

    private static func plannedBlock(from segment: WorkoutSegment) throws -> PlannedBlock {
        switch segment {
        case let .step(step):
            // A lone top-level step (that wasn't consumed as warmup/cooldown
            // above — e.g. a second warm-up-intent step, or any non-interval
            // easy/tempo/threshold/rest step) becomes a 1-iteration block
            // with a single interval step, per task 1.7's mapping contract.
            let planned = try plannedStep(from: step)
            let intervalStep = PlannedIntervalStep(purpose: purpose(for: step.intent), step: planned)
            return PlannedBlock(steps: [intervalStep], iterations: 1)

        case let .intervalBlock(_, steps, repetitions):
            let plannedSteps = try steps.map { intervalStep -> PlannedIntervalStep in
                PlannedIntervalStep(
                    purpose: intervalStep.purpose,
                    step: try plannedStep(from: intervalStep.step)
                )
            }
            return PlannedBlock(steps: plannedSteps, iterations: repetitions)
        }
    }

    /// Maps a single top-level step's intent to a WorkoutKit interval
    /// purpose. WorkoutKit's `IntervalStep.Purpose` only has two cases
    /// (`work`/`recovery`), so the eight domain intents collapse: the two
    /// explicitly rest-like intents (`recovery`, `rest`) map to `.recovery`;
    /// every other intent (`easy`, `tempo`, `threshold`, `work`, and any
    /// `warmUp`/`coolDown` step not special-cased above) maps to `.work`,
    /// matching how a runner would actually experience that effort within
    /// the block.
    private static func purpose(for intent: SegmentIntent) -> IntervalStepPurpose {
        switch intent {
        case .recovery, .rest:
            return .recovery
        case .warmUp, .easy, .tempo, .threshold, .work, .coolDown:
            return .work
        }
    }

    // MARK: - Step -> planned step

    private static func plannedStep(from step: SegmentStep) throws -> PlannedStep {
        try requireComposable(step.goal)
        let alert = try step.target.map(plannedAlert)
        return PlannedStep(intent: step.intent, goal: step.goal, alert: alert)
    }

    private static func plannedAlert(from target: Target) throws -> PlannedAlert {
        switch target {
        case let .pace(range):
            try requirePositiveFinite(range.lowerBound, describing: "pace range lower bound (s/m)")
            try requirePositiveFinite(range.upperBound, describing: "pace range upper bound (s/m)")
            // Bounds swap: faster pace (smaller s/m) -> higher speed (m/s).
            let fasterSpeed = 1 / range.lowerBound
            let slowerSpeed = 1 / range.upperBound
            return .paceRange(lowerMetersPerSecond: slowerSpeed, upperMetersPerSecond: fasterSpeed)

        case let .heartRate(heartRateTarget):
            switch heartRateTarget {
            case let .zone(zone):
                // Re-guarded independently of ValidateWorkoutPolicy, like
                // every other value: zone bounds are an assumption
                // (RESEARCH-LOG 2026-07-06 note), so keep the planner's
                // "policy bug alone cannot reach WorkoutKit" claim true.
                guard (1...5).contains(zone) else {
                    throw WatchSyncError.invalidComposition(
                        reason: "heart-rate zone \(zone) outside Apple's 1-5 zone model"
                    )
                }
                return .heartRateZone(zone)
            case let .range(range):
                try requirePositiveFinite(range.lowerBound, describing: "heart-rate range lower bound (bpm)")
                try requirePositiveFinite(range.upperBound, describing: "heart-rate range upper bound (bpm)")
                return .heartRateRange(lowerBPM: range.lowerBound, upperBPM: range.upperBound)
            }

        case let .cadence(range):
            try requirePositiveFinite(range.lowerBound, describing: "cadence range lower bound (steps/min)")
            try requirePositiveFinite(range.upperBound, describing: "cadence range upper bound (steps/min)")
            return .cadenceRange(lowerStepsPerMinute: range.lowerBound, upperStepsPerMinute: range.upperBound)
        }
    }

    // MARK: - Trap guard

    /// The trap guard: a `Goal` must be `.open` or carry a finite,
    /// strictly-positive value before it is allowed anywhere near
    /// `CustomWorkout.init`/`WorkoutStep.init` (RESEARCH-LOG 2026-07-10).
    private static func requireComposable(_ goal: Goal) throws {
        switch goal {
        case let .distance(meters):
            try requirePositiveFinite(meters, describing: "distance goal (meters)")
        case let .duration(seconds):
            try requirePositiveFinite(seconds, describing: "duration goal (seconds)")
        case .open:
            break
        }
    }

    /// Whether `value` is both finite and strictly positive, throwing a
    /// typed `WatchSyncError` if not. Mirrors `ValidateWorkoutPolicy`'s own
    /// `isPositiveFinite` reasoning (NaN compares `false` to every
    /// relational operator; `+.infinity` is `> 0` yet operationally
    /// meaningless) but is intentionally re-implemented here rather than
    /// shared, so this guard keeps working even if that policy changes.
    private static func requirePositiveFinite(_ value: Double, describing context: String) throws {
        guard value.isFinite, value > 0 else {
            throw WatchSyncError.invalidComposition(reason: "\(context) must be finite and > 0, got \(value)")
        }
    }

    private static func describe(_ issues: [ValidationIssue]) -> String {
        issues.map { "\($0.rule) at \($0.locator)" }.joined(separator: "; ")
    }
}
