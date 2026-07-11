import SwiftUI

/// The app's type scale.
///
/// `metricLarge`/`metricMedium` use monospaced digits so pace/duration/distance
/// values (formatted by `UnitFormatter`) don't visually jitter as digits change
/// — important for splits tables and in-progress workout displays.
public enum Typography {
    /// A screen's primary title.
    public static let title = Font.title.weight(.bold)
    /// A section header.
    public static let headline = Font.headline
    /// Default body text.
    public static let body = Font.body
    /// De-emphasized supporting text.
    public static let caption = Font.caption

    /// A large, prominent metric (e.g. a live pace or the workout total time).
    public static let metricLarge = Font.system(.largeTitle, design: .rounded).monospacedDigit()
    /// A smaller metric, e.g. a row in a splits table.
    public static let metricMedium = Font.system(.body, design: .rounded).monospacedDigit()
}
