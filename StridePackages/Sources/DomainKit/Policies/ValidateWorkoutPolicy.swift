import Foundation

/// A stable pointer to the offending element within a `Workout`, so
/// presentation code can anchor an inline error without string parsing.
///
/// A locator is either the workout itself, a top-level segment, or a step
/// nested inside an interval block (identified by both the block's id and
/// the inner step's id, since inner steps are not addressable on their own).
public enum ValidationLocator: Equatable, Hashable, Sendable {
    /// The violation applies to the workout as a whole (e.g. its name or
    /// the fact that it has no segments).
    case workout
    /// The violation applies to a top-level segment, identified by the
    /// segment's own `id` (see `WorkoutSegment.id`).
    case segment(id: UUID)
    /// The violation applies to a step nested inside an interval block,
    /// identified by the block's id and the inner step's own id.
    case intervalStep(blockID: UUID, stepID: UUID)
}

/// The specific structural rule a `ValidationIssue` reports as violated.
///
/// Cases carry just enough payload to let presentation code render a
/// message; display copy itself is a presentation-layer concern and is
/// deliberately not baked in here (CLAUDE.md rule 4, task 0.4 design notes).
public enum ValidationRule: Equatable, Hashable, Sendable {
    /// The workout has no segments at all.
    case workoutHasNoSegments
    /// The workout's name is empty after trimming whitespace/newlines.
    case workoutNameEmpty
    /// An interval block has fewer than 1 repetition.
    case intervalBlockRepetitionsNotPositive(repetitions: Int)
    /// An interval block has no steps.
    case intervalBlockHasNoSteps
    /// A distance goal's meters are not strictly positive.
    case goalDistanceNotPositive(meters: Double)
    /// A duration goal's seconds are not strictly positive.
    case goalDurationNotPositive(seconds: TimeInterval)
    /// A pace target's range lower bound is not strictly positive
    /// (0 s/m is an infinitely fast, meaningless pace).
    case paceLowerBoundNotPositive(lowerBound: Double)
    /// A heart-rate range target's bounds are not strictly positive.
    case heartRateRangeNotPositive(lowerBound: Double, upperBound: Double)
    /// A heart-rate zone target is outside Apple's 1...5 five-zone model.
    case heartRateZoneOutOfBounds(zone: Int)
    /// A cadence target's range bounds are not strictly positive.
    case cadenceRangeNotPositive(lowerBound: Double, upperBound: Double)
}

/// A single validation violation found in a `Workout`, paired with a
/// locator identifying where it occurred.
public struct ValidationIssue: Equatable, Hashable, Sendable {
    /// Which rule was violated.
    public let rule: ValidationRule
    /// Where in the workout the violation occurred.
    public let locator: ValidationLocator

    /// Creates a validation issue.
    public init(rule: ValidationRule, locator: ValidationLocator) {
        self.rule = rule
        self.locator = locator
    }
}

/// Pure structural validation rules for a `Workout`.
///
/// `ValidateWorkoutPolicy` implements the "Structural rules... unit
/// normalization" responsibility assigned to `ValidateWorkout` in
/// `docs/ARCHITECTURE.md` §6, and runs both live (on every builder edit) and
/// pre-flight (before "Send to Watch") per §7. It reports every violation
/// found rather than stopping at the first one, so the builder UI (§3.1)
/// can surface all inline errors at once.
///
/// This type holds no state and performs no I/O; it is a Policy per
/// CLAUDE.md rule 7.
public enum ValidateWorkoutPolicy {
    /// Validates a workout, returning every violation found.
    ///
    /// An empty array means the workout is structurally valid. Order of
    /// issues follows segment order, then rule-check order within a segment.
    public static func validate(_ workout: Workout) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []

        if workout.segments.isEmpty {
            issues.append(ValidationIssue(rule: .workoutHasNoSegments, locator: .workout))
        }
        if workout.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(ValidationIssue(rule: .workoutNameEmpty, locator: .workout))
        }

        for segment in workout.segments {
            issues.append(contentsOf: validate(segment: segment))
        }

        return issues
    }

    /// Convenience: whether a workout has zero validation issues.
    public static func isValid(_ workout: Workout) -> Bool {
        validate(workout).isEmpty
    }

    private static func validate(segment: WorkoutSegment) -> [ValidationIssue] {
        switch segment {
        case let .step(step):
            return validate(step: step, locator: .segment(id: step.id))

        case let .intervalBlock(id, steps, repetitions):
            var issues: [ValidationIssue] = []
            if repetitions < 1 {
                issues.append(
                    ValidationIssue(
                        rule: .intervalBlockRepetitionsNotPositive(repetitions: repetitions),
                        locator: .segment(id: id)
                    )
                )
            }
            if steps.isEmpty {
                issues.append(ValidationIssue(rule: .intervalBlockHasNoSteps, locator: .segment(id: id)))
            }
            for intervalStep in steps {
                let locator = ValidationLocator.intervalStep(blockID: id, stepID: intervalStep.step.id)
                issues.append(contentsOf: validate(step: intervalStep.step, locator: locator))
            }
            return issues
        }
    }

    private static func validate(step: SegmentStep, locator: ValidationLocator) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        issues.append(contentsOf: validate(goal: step.goal, locator: locator))
        if let target = step.target {
            issues.append(contentsOf: validate(target: target, locator: locator))
        }
        return issues
    }

    private static func validate(goal: Goal, locator: ValidationLocator) -> [ValidationIssue] {
        switch goal {
        case let .distance(meters):
            if !isPositiveFinite(meters) {
                return [ValidationIssue(rule: .goalDistanceNotPositive(meters: meters), locator: locator)]
            }
            return []

        case let .duration(seconds):
            if !isPositiveFinite(seconds) {
                return [ValidationIssue(rule: .goalDurationNotPositive(seconds: seconds), locator: locator)]
            }
            return []

        case .open:
            return []
        }
    }

    private static func validate(target: Target, locator: ValidationLocator) -> [ValidationIssue] {
        switch target {
        case let .pace(range):
            // ClosedRange<Double> cannot represent an inverted range (lower
            // > upper traps at construction), so only the bounds' finiteness
            // and positivity need checking here. An infinite upper bound is
            // just as meaningless as a non-positive lower bound (an
            // "infinitely slow" pace), so both bounds must be finite; no
            // other upper sanity bound is enforced, per task 0.4 design notes
            // (no arbitrary limits).
            if !isPositiveFinite(range.lowerBound) || !range.upperBound.isFinite {
                return [ValidationIssue(rule: .paceLowerBoundNotPositive(lowerBound: range.lowerBound), locator: locator)]
            }
            return []

        case let .heartRate(heartRateTarget):
            switch heartRateTarget {
            case let .zone(zone):
                if !(1...5).contains(zone) {
                    return [ValidationIssue(rule: .heartRateZoneOutOfBounds(zone: zone), locator: locator)]
                }
                return []

            case let .range(range):
                if !isPositiveFinite(range.lowerBound) || !range.upperBound.isFinite {
                    return [
                        ValidationIssue(
                            rule: .heartRateRangeNotPositive(lowerBound: range.lowerBound, upperBound: range.upperBound),
                            locator: locator
                        )
                    ]
                }
                return []
            }

        case let .cadence(range):
            if !isPositiveFinite(range.lowerBound) || !range.upperBound.isFinite {
                return [
                    ValidationIssue(
                        rule: .cadenceRangeNotPositive(lowerBound: range.lowerBound, upperBound: range.upperBound),
                        locator: locator
                    )
                ]
            }
            return []
        }
    }

    /// Whether `value` is both finite and strictly positive.
    ///
    /// `value <= 0` is a poor proxy for "not positive" on its own: `NaN`
    /// compares `false` against every relational operator (so a NaN goal or
    /// bound would silently pass), and `+.infinity` is also `> 0` yet is an
    /// operationally meaningless goal or range bound. This helper is the
    /// single source of truth for "positive" throughout this policy.
    private static func isPositiveFinite(_ value: Double) -> Bool {
        value.isFinite && value > 0
    }
}
