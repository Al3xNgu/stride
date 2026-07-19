import DomainKit

/// Maps `ValidationRule`/`ValidationIssue` into runner-facing copy.
///
/// `ValidateWorkoutPolicy` deliberately keeps display copy out of
/// `ValidationRule` (see its doc comment) so presentation stays a
/// feature-layer concern; this is that mapping. The switch over
/// `ValidationRule` is exhaustive and intentionally has no `default:` case,
/// so adding a new rule in `DomainKit` fails this file's compilation instead
/// of silently rendering a blank row here.
enum ValidationMessagePresenter {
    /// A human-readable message for `issue`'s rule, ignoring its locator
    /// (callers that need locator context already know it from where they
    /// looked the issue up — e.g. a specific segment row).
    static func message(for issue: ValidationIssue) -> String {
        message(for: issue.rule)
    }

    /// A human-readable message for `rule`.
    static func message(for rule: ValidationRule) -> String {
        switch rule {
        case .workoutHasNoSegments:
            return "Add at least one segment to this workout."

        case .workoutNameEmpty:
            return "Give this workout a name."

        case let .intervalBlockRepetitionsNotPositive(repetitions):
            return "This interval block repeats \(repetitions) time(s); it needs at least 1 repetition."

        case .intervalBlockHasNoSteps:
            return "This interval block has no steps; add a work step (and usually a recovery step)."

        case .goalDistanceNotPositive:
            return "This step's distance goal must be greater than zero."

        case .goalDurationNotPositive:
            return "This step's duration goal must be greater than zero."

        case .paceRangeNotPositive:
            return "This step's pace target must be a valid, positive range."

        case .heartRateRangeNotPositive:
            return "This step's heart-rate range target must be a valid, positive range."

        case let .heartRateZoneOutOfBounds(zone):
            return "Heart-rate zone \(zone) is out of range; choose a zone between 1 and 5."

        case .cadenceRangeNotPositive:
            return "This step's cadence target must be a valid, positive range."
        }
    }
}
