import SwiftUI

/// Semantic colors for the app.
///
/// These lean on SwiftUI's built-in dynamic system colors (which already
/// adapt to light/dark mode and platform) rather than an asset catalog —
/// Swift packages need extra resource configuration for asset catalogs, and
/// a small running app doesn't yet need custom brand colors. `background`
/// and `surface` bridge to the platform's system background colors, since
/// SwiftUI has no cross-platform `Color` API for those.
public enum Colors {
    /// Primary text/foreground color.
    public static let primaryText = Color.primary
    /// Secondary (de-emphasized) text/foreground color.
    public static let secondaryText = Color.secondary
    /// The app's accent color (set in the app target's asset catalog).
    public static let accent = Color.accentColor
    /// Positive/success state (e.g. a completed workout, a new PR).
    public static let success = Color.green
    /// Cautionary state (e.g. an unsynced workout).
    public static let warning = Color.orange
    /// Destructive/error state (e.g. a failed sync, a validation error).
    public static let danger = Color.red

    /// The screen's base background color.
    public static let background = platformBackground

    /// A card/grouped-content background color, one step up from `background`.
    public static let surface = platformSurface

    private static var platformBackground: Color {
        #if os(iOS) || os(tvOS)
        Color(uiColor: .systemBackground)
        #elseif os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color.white
        #endif
    }

    private static var platformSurface: Color {
        #if os(iOS) || os(tvOS)
        Color(uiColor: .secondarySystemBackground)
        #elseif os(macOS)
        Color(nsColor: .controlBackgroundColor)
        #else
        Color.gray.opacity(0.1)
        #endif
    }
}
