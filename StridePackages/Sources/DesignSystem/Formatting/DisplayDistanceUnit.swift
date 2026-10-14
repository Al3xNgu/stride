import Foundation

/// The unit system used when displaying distance and pace values.
///
/// `DesignSystem` is a leaf UI module and, per CLAUDE.md rule 1, may not import
/// `DomainKit` — so it cannot reference `DomainKit.DistanceUnit` directly. This
/// type is a minimal, presentation-only mirror of that choice. Callers (feature
/// view models or the composition root) are responsible for mapping the
/// domain's `DistanceUnit` to this type at the presentation edge, e.g.:
///
/// ```swift
/// let displayUnit: DisplayDistanceUnit = preferences.distanceUnit == .kilometers
///     ? .kilometers
///     : .miles
/// ```
public enum DisplayDistanceUnit: String, Equatable, Hashable, Sendable, CaseIterable {
    /// Kilometers, for distance/pace display.
    case kilometers
    /// Miles, for distance/pace display.
    case miles

    /// The exact number of meters in one displayed distance unit.
    ///
    /// Keeping this conversion alongside the presentation-unit enum lets
    /// screens use the same authoritative boundary for formatting and for
    /// grouping persisted split segments into runner-facing laps.
    public var metersPerUnit: Double {
        switch self {
        case .kilometers:
            return 1_000
        case .miles:
            return 1_609.344
        }
    }
}
