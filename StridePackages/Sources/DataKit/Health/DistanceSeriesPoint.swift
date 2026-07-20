import Foundation

/// One raw entry from HealthKit's cumulative-distance series query for a
/// single running workout.
///
/// This is the platform-independent input `SplitDerivation` consumes. It is
/// deliberately shaped as a *delta over an interval* rather than an
/// already-cumulative running total: per `docs/RESEARCH-LOG.md` 2026-07-19
/// Task 1.10 §4, `HKQuantitySeriesSampleQueryDescriptor` yields
/// `Result { quantity, dateInterval, sample }` entries that must be
/// "accumulate[d]... vs. dateInterval" to build a running distance — the
/// query does not hand back pre-summed cumulative values.
public struct DistanceSeriesPoint: Equatable, Hashable, Sendable {
    /// Start of the interval this delta was recorded over.
    public var startDate: Date
    /// End of the interval this delta was recorded over. May equal
    /// `startDate` (an instantaneous/duplicate-timestamp sample) — callers
    /// must not assume a strictly positive duration.
    public var endDate: Date
    /// Distance covered during `startDate...endDate`, in meters. May be
    /// negative or non-finite for corrupt/non-monotonic HealthKit data;
    /// `SplitDerivation` clamps rather than trusting this at face value.
    public var deltaMeters: Double

    /// Creates a distance series point.
    public init(startDate: Date, endDate: Date, deltaMeters: Double) {
        self.startDate = startDate
        self.endDate = endDate
        self.deltaMeters = deltaMeters
    }
}
