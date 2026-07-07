import Foundation

/// The runner's preferred display unit system.
public enum DistanceUnit: String, Equatable, Hashable, Codable, Sendable {
    /// Miles, for distance/pace display.
    case miles
    /// Kilometers, for distance/pace display.
    case kilometers
}

/// User-configurable settings and defaults.
///
/// Kept as a single, mostly-flat value so every feature doesn't grow its
/// own settings tendrils (`docs/ARCHITECTURE.md` §5). Default paces are
/// stored per `SegmentIntent` in seconds-per-meter (CLAUDE.md rule 4) so the
/// builder can pre-fill sensible pace targets for a newly-added step.
public struct UserPreferences: Equatable, Hashable, Codable, Sendable {
    /// Preferred distance/pace display unit.
    public var distanceUnit: DistanceUnit
    /// Default pace, in seconds-per-meter, keyed by segment intent, used to
    /// pre-fill the builder's target for a new step of that intent.
    public var defaultPacesByIntent: [SegmentIntent: Double]
    /// Whether the user has completed the onboarding/permission-priming flow.
    public var hasCompletedOnboarding: Bool

    /// Creates user preferences.
    public init(
        distanceUnit: DistanceUnit = .miles,
        defaultPacesByIntent: [SegmentIntent: Double] = [:],
        hasCompletedOnboarding: Bool = false
    ) {
        self.distanceUnit = distanceUnit
        self.defaultPacesByIntent = defaultPacesByIntent
        self.hasCompletedOnboarding = hasCompletedOnboarding
    }
}
