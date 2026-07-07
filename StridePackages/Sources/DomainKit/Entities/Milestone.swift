import Foundation

/// A data-driven personal-record distance configuration.
///
/// Modeling milestones as data (rather than a fixed enum of distances)
/// means adding a new milestone, e.g. "50K", is a one-line config change,
/// not a refactor (`docs/ARCHITECTURE.md` §3.5). `tolerance` is stored per
/// milestone because the acceptable GPS-overshoot tolerance is
/// distance-dependent (§8: ~1-2% for 5K).
public struct Milestone: Identifiable, Equatable, Hashable, Codable, Sendable {
    /// Stable identity, also used as a stable lookup key across app versions.
    public let id: UUID
    /// The nominal race distance, in meters.
    public var distanceMeters: Double
    /// Acceptable absolute deviation from `distanceMeters`, in meters, for a
    /// completed run to be considered a candidate for this milestone.
    public var tolerance: Double
    /// User-facing display name, e.g. "5K".
    public var displayName: String

    /// Creates a milestone.
    public init(
        id: UUID,
        distanceMeters: Double,
        tolerance: Double,
        displayName: String
    ) {
        self.id = id
        self.distanceMeters = distanceMeters
        self.tolerance = tolerance
        self.displayName = displayName
    }
}

extension Milestone {
    /// The 1 mile milestone (1609.344 meters), ~1-2% tolerance.
    public static let oneMile = Milestone(
        id: UUID(uuidString: "9E3F0A2B-1C1E-4E9C-8E10-000000000001") ?? UUID(),
        distanceMeters: 1609.344,
        tolerance: 1609.344 * 0.02,
        displayName: "1 Mile"
    )

    /// The 5K milestone (5000 meters), ~1-2% tolerance.
    public static let fiveK = Milestone(
        id: UUID(uuidString: "9E3F0A2B-1C1E-4E9C-8E10-000000000002") ?? UUID(),
        distanceMeters: 5_000,
        tolerance: 5_000 * 0.02,
        displayName: "5K"
    )

    /// The 10K milestone (10000 meters), ~1-2% tolerance.
    public static let tenK = Milestone(
        id: UUID(uuidString: "9E3F0A2B-1C1E-4E9C-8E10-000000000003") ?? UUID(),
        distanceMeters: 10_000,
        tolerance: 10_000 * 0.02,
        displayName: "10K"
    )

    /// The half marathon milestone (21097.5 meters), ~1-2% tolerance.
    public static let halfMarathon = Milestone(
        id: UUID(uuidString: "9E3F0A2B-1C1E-4E9C-8E10-000000000004") ?? UUID(),
        distanceMeters: 21_097.5,
        tolerance: 21_097.5 * 0.02,
        displayName: "Half Marathon"
    )

    /// The marathon milestone (42195 meters), ~1-2% tolerance.
    public static let marathon = Milestone(
        id: UUID(uuidString: "9E3F0A2B-1C1E-4E9C-8E10-000000000005") ?? UUID(),
        distanceMeters: 42_195,
        tolerance: 42_195 * 0.02,
        displayName: "Marathon"
    )

    /// All MVP milestone presets, in ascending distance order.
    public static let mvpPresets: [Milestone] = [
        .oneMile, .fiveK, .tenK, .halfMarathon, .marathon
    ]
}
