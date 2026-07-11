import CoreGraphics

/// The app's corner radius scale, in points.
public enum CornerRadius {
    /// 8pt — small controls (chips, badges).
    public static let small: CGFloat = 8
    /// 12pt — default card/button radius.
    public static let medium: CGFloat = 12
    /// 20pt — large containers (sheets, prominent cards).
    public static let large: CGFloat = 20
}
