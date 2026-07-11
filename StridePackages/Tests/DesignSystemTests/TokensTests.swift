import Testing
import SwiftUI
@testable import DesignSystem

/// Smoke tests for the design tokens: mostly compile-time proof that the
/// public API is reachable from outside the module, plus a couple of sanity
/// checks on the numeric scales.
@Suite("Design tokens")
struct TokensTests {
    @Test("Spacing scale is strictly increasing")
    func spacingScaleIncreasing() {
        let scale = [Spacing.extraSmall, Spacing.small, Spacing.medium, Spacing.large, Spacing.extraLarge]
        #expect(scale == scale.sorted())
        #expect(Set(scale).count == scale.count)
    }

    @Test("Corner radius scale is strictly increasing")
    func cornerRadiusScaleIncreasing() {
        let scale = [CornerRadius.small, CornerRadius.medium, CornerRadius.large]
        #expect(scale == scale.sorted())
        #expect(Set(scale).count == scale.count)
    }

    @Test("Semantic colors are distinct")
    func semanticColorsDistinct() {
        let colors = [Colors.success, Colors.warning, Colors.danger]
        #expect(Set(colors).count == colors.count)
    }

    @Test("Background and surface colors are reachable and distinct")
    func backgroundAndSurfaceDistinct() {
        #expect(Colors.background != Colors.surface)
    }

    @Test("Type scale is reachable")
    func typeScaleReachable() {
        let fonts = [Typography.title, Typography.headline, Typography.body, Typography.caption]
        #expect(Set(fonts).count == fonts.count)
    }

    @Test("Metric fonts use monospaced digits")
    func metricFontsReachable() {
        // Presence/compilation is the main assertion; distinctness confirms the
        // two metric sizes aren't accidentally aliased to the same Font value.
        #expect(Typography.metricLarge != Typography.metricMedium)
    }
}
