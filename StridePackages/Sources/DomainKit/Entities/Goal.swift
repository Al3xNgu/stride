import Foundation

/// The completion condition for a single workout step.
///
/// Per CLAUDE.md rule 4, distance is stored in meters and duration in
/// seconds; conversion to user-facing units (miles/km, mm:ss) happens only
/// at the presentation edge via `UnitFormatter`.
public enum Goal: Equatable, Hashable, Codable, Sendable {
    /// Complete the step after covering the given distance, in meters.
    case distance(meters: Double)
    /// Complete the step after the given duration, in seconds.
    case duration(seconds: TimeInterval)
    /// No automatic completion condition; the runner advances manually
    /// (WorkoutKit "open goal" / lap button).
    case open
}
