/// Namespace marker for the `DesignSystem` module.
///
/// This is a leaf UI module (`docs/ARCHITECTURE.md` §4): it has no dependency
/// on `DomainKit`, `DataKit`, or any Apple framework beyond SwiftUI/Foundation.
/// See `Formatting/UnitFormatter.swift` for the presentation-edge unit
/// conversion required by CLAUDE.md rule 4, and `Tokens/` for the spacing,
/// corner radius, color, and type-scale tokens shared by feature modules.
/// Reusable SwiftUI components and previews will be added here in a later task.
public enum DesignSystem {}
