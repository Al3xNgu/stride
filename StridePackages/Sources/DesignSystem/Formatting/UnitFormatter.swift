import Foundation

/// Converts and formats domain measurements for display.
///
/// Per CLAUDE.md rule 4, `DomainKit` and every layer beneath it store distance
/// in meters, time in seconds, and pace in seconds-per-meter. `UnitFormatter`
/// is the *only* place that conversion to a runner-facing unit (km/mi,
/// `"5:00 /km"`, `"45:00"`) is allowed to happen — it is pure, stateless, and
/// has no dependency on `DomainKit` (see `DisplayDistanceUnit`).
///
/// All formatting functions accept an injectable `Locale` (defaulting to
/// `.current`) so callers — and tests — can pin deterministic output.
public enum UnitFormatter {
    /// Placeholder shown for pace/duration values that cannot be formatted
    /// (zero, negative, `NaN`, or infinite input).
    private static let timePlaceholder = "--:--"

    /// Placeholder shown for distance values that cannot be formatted.
    private static let distancePlaceholder = "--"

    // MARK: - Pace

    /// Formats a pace, given in seconds-per-meter, as `"5:00 /km"` or `"7:59 /mi"`.
    ///
    /// - Parameters:
    ///   - secondsPerMeter: The domain's internal pace representation.
    ///   - unit: The display unit (kilometers or miles).
    ///   - locale: Reserved for future numeral localization; the minutes/seconds
    ///     portion is hand-rolled with explicit integer math (see note below)
    ///     and is intentionally locale-invariant. Defaults to `.current`.
    /// - Returns: A string of the form `"M:SS /unit"`, or a placeholder
    ///   (`"--:-- /unit"`) if `secondsPerMeter` is zero, negative, `NaN`, or infinite.
    ///
    /// No stock `Foundation` formatter produces `"M:SS /unit"` pace strings, so
    /// this hand-rolls the conversion with integer math on the *total* rounded
    /// seconds — never by rounding minutes and seconds independently — so a
    /// carry like 4:59.6 correctly becomes `"5:00"` rather than the invalid `"4:60"`.
    public static func paceString(
        secondsPerMeter: Double,
        unit: DisplayDistanceUnit,
        locale: Locale = .current
    ) -> String {
        guard secondsPerMeter.isFinite, secondsPerMeter > 0 else {
            return "\(timePlaceholder) \(paceUnitSuffix(unit))"
        }

        let totalSecondsPerUnit = secondsPerMeter * metersPerUnit(unit)
        // The upper bound also guards `Int(_:)`, which traps (rather than
        // saturating) on finite doubles beyond Int.max.
        guard totalSecondsPerUnit.isFinite, totalSecondsPerUnit < Double(Int.max) else {
            return "\(timePlaceholder) \(paceUnitSuffix(unit))"
        }

        let roundedTotalSeconds = Int(totalSecondsPerUnit.rounded())
        guard roundedTotalSeconds >= 0 else {
            return "\(timePlaceholder) \(paceUnitSuffix(unit))"
        }

        let minutes = roundedTotalSeconds / 60
        let seconds = roundedTotalSeconds % 60
        return "\(minutes):\(twoDigits(seconds)) \(paceUnitSuffix(unit))"
    }

    /// Converts a pace expressed as minutes and seconds per unit distance into
    /// seconds-per-meter, the domain's internal representation (CLAUDE.md rule 4).
    ///
    /// Intended for pace-input UI (task 1.4), where a runner picks minutes and
    /// seconds per kilometer or mile with a wheel/stepper control.
    ///
    /// - Parameters:
    ///   - minutes: Whole minutes per unit distance. Negative values are clamped to zero.
    ///   - seconds: Seconds per unit distance. Not required to be `< 60` — any
    ///     non-negative value is folded into the total; negative values are clamped to zero.
    ///   - unit: The unit the minutes/seconds are expressed per.
    /// - Returns: The equivalent pace in seconds-per-meter.
    public static func secondsPerMeter(minutes: Int, seconds: Int, unit: DisplayDistanceUnit) -> Double {
        let clampedMinutes = max(0, minutes)
        let clampedSeconds = max(0, seconds)
        let totalSecondsPerUnit = Double(clampedMinutes * 60 + clampedSeconds)
        return totalSecondsPerUnit / metersPerUnit(unit)
    }

    // MARK: - Distance

    /// Formats a distance, given in meters, as a localized decimal string in the
    /// requested unit, e.g. `"5.00 km"` or `"3.11 mi"`.
    ///
    /// - Parameters:
    ///   - meters: The distance in meters (the domain's internal representation).
    ///   - unit: The display unit (kilometers or miles).
    ///   - decimals: Number of fraction digits to show. Defaults to `2`. Negative
    ///     values are clamped to `0`.
    ///   - locale: Locale used for the decimal separator (and digit grouping, for
    ///     very long distances). Defaults to `.current`.
    /// - Returns: A localized `"<value> <unit>"` string, or a placeholder
    ///   (`"-- <unit>"`) if `meters` is negative, `NaN`, or infinite.
    public static func distanceString(
        meters: Double,
        unit: DisplayDistanceUnit,
        decimals: Int = 2,
        locale: Locale = .current
    ) -> String {
        guard meters.isFinite, meters >= 0 else {
            return "\(distancePlaceholder) \(distanceUnitSuffix(unit))"
        }

        let convertedValue = meters / metersPerUnit(unit)
        let formatter = decimalFormatter(fractionDigits: max(0, decimals), locale: locale)
        let numberString = formatter.string(from: NSNumber(value: convertedValue)) ?? distancePlaceholder
        return "\(numberString) \(distanceUnitSuffix(unit))"
    }

    /// Formats a distance for short interval/segment goals, e.g. `"400 m"`.
    ///
    /// Distances under 1,000 meters are shown as whole meters, since
    /// sub-kilometer training segments (400 m, 800 m repeats) are conventionally
    /// specified and displayed in round meter counts regardless of the runner's
    /// preferred long-distance unit — converting a 400 m repeat to `"0.25 mi"`
    /// would be both unfamiliar and imprecise for that use case. Distances at or
    /// above 1,000 meters fall back to `distanceString(meters:unit:decimals:locale:)`.
    ///
    /// - Parameters:
    ///   - meters: The distance in meters.
    ///   - unit: The display unit used only when `meters >= 1,000`.
    ///   - locale: Locale used for the decimal separator/grouping. Defaults to `.current`.
    /// - Returns: `"<meters> m"` below the 1,000 m threshold, otherwise a
    ///   localized distance string, or a placeholder (`"-- m"`) if `meters` is
    ///   negative, `NaN`, or infinite.
    ///
    /// The threshold is checked *before* rounding, so a value like 999.6
    /// renders as `"1,000 m"` (locale grouping applies; not `"1.00 km"`) —
    /// acceptable because segment goals are entered as whole meter counts;
    /// fractional near-threshold values don't occur in practice.
    public static func segmentDistanceString(
        meters: Double,
        unit: DisplayDistanceUnit,
        locale: Locale = .current
    ) -> String {
        guard meters.isFinite, meters >= 0 else {
            return "\(distancePlaceholder) m"
        }

        guard meters < 1_000 else {
            return distanceString(meters: meters, unit: unit, locale: locale)
        }

        let formatter = decimalFormatter(fractionDigits: 0, locale: locale)
        let numberString = formatter.string(from: NSNumber(value: meters.rounded())) ?? distancePlaceholder
        return "\(numberString) m"
    }

    // MARK: - Duration

    /// Formats a duration, given in seconds, as `"0:45"`, `"45:00"`, or
    /// `"1:02:30"` (hours only shown, and carried, when the duration is an
    /// hour or longer).
    ///
    /// - Parameters:
    ///   - seconds: The duration in seconds (the domain's internal representation).
    ///   - locale: Reserved for future numeral localization; like pace, the
    ///     colon-separated components are hand-rolled integer math and are
    ///     intentionally locale-invariant. Defaults to `.current`.
    /// - Returns: A `"M:SS"` or `"H:MM:SS"` string, or a placeholder (`"--:--"`)
    ///   if `seconds` is negative, `NaN`, or infinite.
    public static func durationString(seconds: Double, locale: Locale = .current) -> String {
        // The upper bound also guards `Int(_:)`, which traps (rather than
        // saturating) on finite doubles beyond Int.max.
        guard seconds.isFinite, seconds >= 0, seconds < Double(Int.max) else {
            return timePlaceholder
        }

        let totalSeconds = Int(seconds.rounded())
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let secs = totalSeconds % 60

        guard hours > 0 else {
            return "\(minutes):\(twoDigits(secs))"
        }
        return "\(hours):\(twoDigits(minutes)):\(twoDigits(secs))"
    }

    // MARK: - Private helpers

    private static func metersPerUnit(_ unit: DisplayDistanceUnit) -> Double {
        switch unit {
        case .kilometers:
            return 1_000
        case .miles:
            return 1_609.344
        }
    }

    private static func paceUnitSuffix(_ unit: DisplayDistanceUnit) -> String {
        switch unit {
        case .kilometers:
            return "/km"
        case .miles:
            return "/mi"
        }
    }

    private static func distanceUnitSuffix(_ unit: DisplayDistanceUnit) -> String {
        switch unit {
        case .kilometers:
            return "km"
        case .miles:
            return "mi"
        }
    }

    private static func decimalFormatter(fractionDigits: Int, locale: Locale) -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = fractionDigits
        formatter.maximumFractionDigits = fractionDigits
        formatter.roundingMode = .halfUp
        return formatter
    }

    private static func twoDigits(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }
}
