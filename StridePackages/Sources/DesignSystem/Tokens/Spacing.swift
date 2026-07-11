import CoreGraphics

/// The app's spacing scale, in points.
///
/// A small, fixed set of values keeps layout rhythm consistent across
/// features without inventing a full design language (task 1.6 scope).
public enum Spacing {
    /// 4pt — tight spacing between closely related elements (e.g. a label and its value).
    public static let extraSmall: CGFloat = 4
    /// 8pt — spacing within a compact group (e.g. stacked form rows).
    public static let small: CGFloat = 8
    /// 16pt — default spacing between sections of a screen.
    public static let medium: CGFloat = 16
    /// 24pt — spacing between major screen regions.
    public static let large: CGFloat = 24
    /// 32pt — spacing around a screen's outermost content.
    public static let extraLarge: CGFloat = 32
}
