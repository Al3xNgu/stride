import Testing
import Foundation
@testable import DesignSystem

/// Exhaustive coverage of `UnitFormatter`'s pace string formatting and its
/// inverse (minutes+seconds-per-unit -> seconds-per-meter), including the
/// 60-second rounding carry called out in task 1.6.
@Suite("UnitFormatter — pace")
struct UnitFormatterPaceTests {
    @Test("0.3 s/m formats as 5:00 /km")
    func kilometerPaceExample() {
        #expect(UnitFormatter.paceString(secondsPerMeter: 0.3, unit: .kilometers) == "5:00 /km")
    }

    @Test("0.3 s/m formats as 8:03 /mi")
    func milePaceExample() {
        #expect(UnitFormatter.paceString(secondsPerMeter: 0.3, unit: .miles) == "8:03 /mi")
    }

    @Test("Sub-minute paces render without a leading zero on minutes lost")
    func subMinutePace() {
        #expect(UnitFormatter.paceString(secondsPerMeter: 0.05, unit: .kilometers) == "0:50 /km")
    }

    @Test("299.6s (4:59.6) carries to 5:00, never 4:60")
    func carryAboveHalfSecond() {
        #expect(UnitFormatter.paceString(secondsPerMeter: 0.2996, unit: .kilometers) == "5:00 /km")
    }

    @Test("Exactly 299.5s rounds away from zero to 5:00")
    func carryAtExactHalfSecond() {
        #expect(UnitFormatter.paceString(secondsPerMeter: 0.2995, unit: .kilometers) == "5:00 /km")
    }

    @Test("299.4s rounds down to 4:59")
    func noCarryBelowHalfSecond() {
        #expect(UnitFormatter.paceString(secondsPerMeter: 0.2994, unit: .kilometers) == "4:59 /km")
    }

    @Test("Zero pace is invalid and renders the placeholder", arguments: [DisplayDistanceUnit.kilometers, .miles])
    func zeroPace(_ unit: DisplayDistanceUnit) {
        let suffix = unit == .kilometers ? "/km" : "/mi"
        #expect(UnitFormatter.paceString(secondsPerMeter: 0, unit: unit) == "--:-- \(suffix)")
    }

    @Test("Negative pace is invalid and renders the placeholder")
    func negativePace() {
        #expect(UnitFormatter.paceString(secondsPerMeter: -0.3, unit: .kilometers) == "--:-- /km")
    }

    @Test("NaN pace renders the placeholder")
    func nanPace() {
        #expect(UnitFormatter.paceString(secondsPerMeter: .nan, unit: .kilometers) == "--:-- /km")
    }

    @Test("Infinite pace renders the placeholder", arguments: [Double.infinity, -Double.infinity])
    func infinitePace(_ value: Double) {
        #expect(UnitFormatter.paceString(secondsPerMeter: value, unit: .kilometers) == "--:-- /km")
    }

    @Test("A finite pace too large for Int renders the placeholder instead of trapping")
    func absurdlyLargeFinitePace() {
        let result = UnitFormatter.paceString(secondsPerMeter: .greatestFiniteMagnitude, unit: .kilometers)
        #expect(result == "--:-- /km")
    }

    @Test("Pace formatting is locale-invariant (hand-rolled integer math, no digit localization)")
    func paceIsLocaleInvariant() {
        let usString = UnitFormatter.paceString(
            secondsPerMeter: 0.3,
            unit: .kilometers,
            locale: Locale(identifier: "en_US")
        )
        let arString = UnitFormatter.paceString(
            secondsPerMeter: 0.3,
            unit: .kilometers,
            locale: Locale(identifier: "ar_SA")
        )
        #expect(usString == arString)
        #expect(usString == "5:00 /km")
    }

    @Test("Exact minutes/seconds round-trip through secondsPerMeter for kilometers")
    func inverseRoundTripKilometers() {
        let pace = UnitFormatter.secondsPerMeter(minutes: 5, seconds: 0, unit: .kilometers)
        #expect(UnitFormatter.paceString(secondsPerMeter: pace, unit: .kilometers) == "5:00 /km")
    }

    @Test("Exact minutes/seconds round-trip through secondsPerMeter for miles")
    func inverseRoundTripMiles() {
        let pace = UnitFormatter.secondsPerMeter(minutes: 8, seconds: 3, unit: .miles)
        #expect(UnitFormatter.paceString(secondsPerMeter: pace, unit: .miles) == "8:03 /mi")
    }

    @Test("Negative minutes/seconds are clamped to zero, not negative")
    func inverseClampsNegativeInputs() {
        let clamped = UnitFormatter.secondsPerMeter(minutes: -5, seconds: -10, unit: .kilometers)
        #expect(clamped == 0)
    }

    @Test("secondsPerMeter does not require seconds < 60; totals fold correctly")
    func inverseFoldsOverflowSeconds() {
        let fromOverflow = UnitFormatter.secondsPerMeter(minutes: 4, seconds: 65, unit: .kilometers)
        let fromNormalized = UnitFormatter.secondsPerMeter(minutes: 5, seconds: 5, unit: .kilometers)
        #expect(fromOverflow == fromNormalized)
    }
}
