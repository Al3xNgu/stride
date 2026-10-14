import Testing
import Foundation
@testable import DesignSystem

/// Exhaustive coverage of `UnitFormatter`'s long-distance and short-segment
/// distance formatting, including the meters/kilometers threshold rule.
@Suite("UnitFormatter — distance")
struct UnitFormatterDistanceTests {
    @Test("Display units expose exact meter conversions")
    func displayUnitMeterConversions() {
        #expect(DisplayDistanceUnit.kilometers.metersPerUnit == 1_000)
        #expect(DisplayDistanceUnit.miles.metersPerUnit == 1_609.344)
    }

    @Test("5000m formats as 5.00 km by default")
    func kilometersDefaultDecimals() {
        #expect(UnitFormatter.distanceString(meters: 5_000, unit: .kilometers) == "5.00 km")
    }

    @Test("5000m formats as 3.11 mi by default")
    func milesDefaultDecimals() {
        #expect(UnitFormatter.distanceString(meters: 5_000, unit: .miles) == "3.11 mi")
    }

    @Test("decimals: 0 renders no fraction digits")
    func zeroDecimals() {
        #expect(UnitFormatter.distanceString(meters: 5_000, unit: .kilometers, decimals: 0) == "5 km")
    }

    @Test("decimals: 1 renders one fraction digit")
    func oneDecimal() {
        #expect(UnitFormatter.distanceString(meters: 5_000, unit: .kilometers, decimals: 1) == "5.0 km")
    }

    @Test("Negative decimals are clamped to zero rather than crashing")
    func negativeDecimalsClamp() {
        #expect(UnitFormatter.distanceString(meters: 5_000, unit: .kilometers, decimals: -3) == "5 km")
    }

    @Test("Negative meters render the placeholder", arguments: [DisplayDistanceUnit.kilometers, .miles])
    func negativeMeters(_ unit: DisplayDistanceUnit) {
        let suffix = unit == .kilometers ? "km" : "mi"
        #expect(UnitFormatter.distanceString(meters: -1, unit: unit) == "-- \(suffix)")
    }

    @Test("NaN meters render the placeholder")
    func nanMeters() {
        #expect(UnitFormatter.distanceString(meters: .nan, unit: .kilometers) == "-- km")
    }

    @Test("Infinite meters render the placeholder", arguments: [Double.infinity, -Double.infinity])
    func infiniteMeters(_ value: Double) {
        #expect(UnitFormatter.distanceString(meters: value, unit: .kilometers) == "-- km")
    }

    @Test("German locale uses a comma decimal separator")
    func germanLocaleUsesComma() {
        let result = UnitFormatter.distanceString(
            meters: 5_000,
            unit: .kilometers,
            locale: Locale(identifier: "de_DE")
        )
        #expect(result == "5,00 km")
    }

    @Test("US locale uses a period decimal separator")
    func usLocaleUsesPeriod() {
        let result = UnitFormatter.distanceString(
            meters: 5_000,
            unit: .kilometers,
            locale: Locale(identifier: "en_US")
        )
        #expect(result == "5.00 km")
    }

    // MARK: - Segment distance (meters-below-threshold rule)

    @Test("400m segment renders as whole meters, not a fractional km/mi value")
    func shortSegmentRendersMeters() {
        #expect(UnitFormatter.segmentDistanceString(meters: 400, unit: .kilometers) == "400 m")
        #expect(UnitFormatter.segmentDistanceString(meters: 400, unit: .miles) == "400 m")
    }

    @Test("999m (just under the 1,000m threshold) still renders as meters")
    func justUnderThresholdRendersMeters() {
        #expect(UnitFormatter.segmentDistanceString(meters: 999, unit: .kilometers) == "999 m")
    }

    @Test("1000m (at the threshold) falls back to the long-distance formatter")
    func atThresholdFallsBackToDistanceString() {
        #expect(UnitFormatter.segmentDistanceString(meters: 1_000, unit: .kilometers) == "1.00 km")
    }

    @Test("1500m in miles falls back to the long-distance formatter")
    func aboveThresholdMiles() {
        #expect(UnitFormatter.segmentDistanceString(meters: 1_500, unit: .miles) == "0.93 mi")
    }

    @Test("999.6m stays in the meters branch and rounds to 1,000 m (threshold checked before rounding)")
    func justUnderThresholdRoundsWithinMetersBranch() {
        let result = UnitFormatter.segmentDistanceString(
            meters: 999.6, unit: .kilometers, locale: Locale(identifier: "en_US")
        )
        #expect(result == "1,000 m")
    }

    @Test("Negative segment meters render the placeholder")
    func negativeSegmentMeters() {
        #expect(UnitFormatter.segmentDistanceString(meters: -1, unit: .kilometers) == "-- m")
    }

    @Test("NaN segment meters render the placeholder")
    func nanSegmentMeters() {
        #expect(UnitFormatter.segmentDistanceString(meters: .nan, unit: .kilometers) == "-- m")
    }

    @Test("Infinite segment meters render the placeholder")
    func infiniteSegmentMeters() {
        #expect(UnitFormatter.segmentDistanceString(meters: .infinity, unit: .kilometers) == "-- m")
    }
}
