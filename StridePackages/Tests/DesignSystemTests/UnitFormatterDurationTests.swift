import Testing
import Foundation
@testable import DesignSystem

/// Exhaustive coverage of `UnitFormatter`'s duration formatting: sub-minute,
/// minute-scale, and hour-carry cases, plus the 60-second rounding carry.
@Suite("UnitFormatter — duration")
struct UnitFormatterDurationTests {
    @Test("0 seconds formats as 0:00")
    func zeroSeconds() {
        #expect(UnitFormatter.durationString(seconds: 0) == "0:00")
    }

    @Test("45 seconds formats as 0:45")
    func subMinute() {
        #expect(UnitFormatter.durationString(seconds: 45) == "0:45")
    }

    @Test("2700 seconds formats as 45:00")
    func fortyFiveMinutes() {
        #expect(UnitFormatter.durationString(seconds: 2_700) == "45:00")
    }

    @Test("3750 seconds formats as 1:02:30 with an hour carry")
    func hourCarry() {
        #expect(UnitFormatter.durationString(seconds: 3_750) == "1:02:30")
    }

    @Test("3600 seconds formats as 1:00:00")
    func exactlyOneHour() {
        #expect(UnitFormatter.durationString(seconds: 3_600) == "1:00:00")
    }

    @Test("59.6 seconds carries to 1:00, never 0:60")
    func secondsCarryToMinute() {
        #expect(UnitFormatter.durationString(seconds: 59.6) == "1:00")
    }

    @Test("3599.6 seconds carries to 1:00:00, never 59:60")
    func minutesCarryToHour() {
        #expect(UnitFormatter.durationString(seconds: 3_599.6) == "1:00:00")
    }

    @Test("Negative duration renders the placeholder")
    func negativeDuration() {
        #expect(UnitFormatter.durationString(seconds: -1) == "--:--")
    }

    @Test("NaN duration renders the placeholder")
    func nanDuration() {
        #expect(UnitFormatter.durationString(seconds: .nan) == "--:--")
    }

    @Test("Infinite duration renders the placeholder", arguments: [Double.infinity, -Double.infinity])
    func infiniteDuration(_ value: Double) {
        #expect(UnitFormatter.durationString(seconds: value) == "--:--")
    }

    @Test("A finite duration too large for Int renders the placeholder instead of trapping")
    func absurdlyLargeFiniteDuration() {
        #expect(UnitFormatter.durationString(seconds: .greatestFiniteMagnitude) == "--:--")
    }

    @Test("Duration formatting is locale-invariant (hand-rolled integer math)")
    func durationIsLocaleInvariant() {
        let usString = UnitFormatter.durationString(seconds: 3_750, locale: Locale(identifier: "en_US"))
        let arString = UnitFormatter.durationString(seconds: 3_750, locale: Locale(identifier: "ar_SA"))
        #expect(usString == arString)
        #expect(usString == "1:02:30")
    }
}
