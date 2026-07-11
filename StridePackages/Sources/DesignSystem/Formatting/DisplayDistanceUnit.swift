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
}
