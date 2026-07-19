import Foundation

/// A pure, structural summary of a `Workout`'s planned totals.
///
/// Distance and duration are summed from every goal-bearing step, with
/// interval-block steps multiplied by their block's repetitions (per
/// `docs/ARCHITECTURE.md` §3.1: "interval blocks: work step + recovery
/// step... × N repetitions"). `.open` goals contribute nothing to either
/// total by definition (an open goal has no built-in completion distance or
/// time), but every open-goal step is still counted via
/// `openGoalStepCount` — so presentation can render an honest summary like
/// "5.2 km + 2 open segments" rather than silently dropping them from the
/// total (task 1.5 design notes).
public struct WorkoutSummary: Equatable, Hashable, Sendable {
    /// Sum of every distance goal's meters, with interval-block step
    /// distances multiplied by the block's repetitions.
    public let totalDistanceMeters: Double
    /// Sum of every duration goal's seconds, with interval-block step
    /// durations multiplied by the block's repetitions.
    public let totalDurationSeconds: TimeInterval
    /// Count of steps — top-level or nested inside an interval block —
    /// whose goal is `.open`. This is a count of *steps*, not counted per
    /// repetition: an open goal is a structural property of the step
    /// definition, not something that "happens more" each time a block
    /// repeats.
    public let openGoalStepCount: Int

    /// Creates a workout summary.
    public init(totalDistanceMeters: Double, totalDurationSeconds: TimeInterval, openGoalStepCount: Int) {
        self.totalDistanceMeters = totalDistanceMeters
        self.totalDurationSeconds = totalDurationSeconds
        self.openGoalStepCount = openGoalStepCount
    }

    /// Whether the workout has at least one open-goal step — a convenience
    /// for presentation's "should I show the open-segments annotation?"
    /// branch.
    public var hasOpenGoalSteps: Bool {
        openGoalStepCount > 0
    }
}

/// Computes planned totals (distance, duration) for a `Workout`.
///
/// `WorkoutSummaryPolicy` implements the "total-distance/duration summary"
/// half of the builder's live-validation responsibility described in
/// `docs/ARCHITECTURE.md` §3.1, running on every builder edit alongside
/// `ValidateWorkoutPolicy`. Like that policy, this type holds no state and
/// performs no I/O; it is a Policy per CLAUDE.md rule 7.
public enum WorkoutSummaryPolicy {
    /// Summarizes `workout`'s planned totals.
    ///
    /// - Returns: Total planned distance (meters) and duration (seconds)
    ///   across every segment, plus a count of open-goal steps. Values from
    ///   individual goals are summed as-is (this policy does not validate;
    ///   see `ValidateWorkoutPolicy` for that), so a malformed goal (e.g. a
    ///   negative or non-finite value) will propagate into the totals rather
    ///   than being silently skipped.
    public static func summarize(_ workout: Workout) -> WorkoutSummary {
        var totalDistance = 0.0
        var totalDuration = 0.0
        var openGoalStepCount = 0

        for segment in workout.segments {
            switch segment {
            case let .step(step):
                accumulate(
                    goal: step.goal,
                    repetitionMultiplier: 1,
                    totalDistance: &totalDistance,
                    totalDuration: &totalDuration,
                    openGoalStepCount: &openGoalStepCount
                )

            case let .intervalBlock(_, steps, repetitions):
                // `ValidateWorkoutPolicy` flags `repetitions < 1` as
                // invalid, but this policy runs live on every keystroke —
                // including transient invalid states — so it clamps rather
                // than producing a negative total.
                let multiplier = Double(max(0, repetitions))
                for intervalStep in steps {
                    accumulate(
                        goal: intervalStep.step.goal,
                        repetitionMultiplier: multiplier,
                        totalDistance: &totalDistance,
                        totalDuration: &totalDuration,
                        openGoalStepCount: &openGoalStepCount
                    )
                }
            }
        }

        return WorkoutSummary(
            totalDistanceMeters: totalDistance,
            totalDurationSeconds: totalDuration,
            openGoalStepCount: openGoalStepCount
        )
    }

    /// Folds a single step's goal into the running totals, per
    /// `repetitionMultiplier` (1 for a top-level step, the block's
    /// repetition count for a step nested in an interval block).
    private static func accumulate(
        goal: Goal,
        repetitionMultiplier: Double,
        totalDistance: inout Double,
        totalDuration: inout Double,
        openGoalStepCount: inout Int
    ) {
        switch goal {
        case let .distance(meters):
            totalDistance += meters * repetitionMultiplier
        case let .duration(seconds):
            totalDuration += seconds * repetitionMultiplier
        case .open:
            openGoalStepCount += 1
        }
    }
}
