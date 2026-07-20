import DomainKit
import Foundation

/// Pure `[DistanceSeriesPoint]` -> `[Split]` derivation.
///
/// This type has no HealthKit dependency (only `DomainKit` + `Foundation`),
/// matching the WatchSync module's "pure planner core, thin framework layer"
/// precedent (`WatchCompositionPlanner`, task 1.7) so the split math is fully
/// unit-testable via `swift test` on macOS, independent of whether HealthKit
/// data is available on the machine running the tests.
///
/// HARDWARE-VERIFY: real Apple Watch outdoor-run distance-series granularity
/// is unconfirmed (`docs/RESEARCH-LOG.md` 2026-07-19 Task 1.10 §4 /
/// hardware-verify item 1) — this calculator is written to integrate
/// arbitrary interval sizes and gaps between samples rather than assume any
/// particular sampling cadence.
public enum SplitDerivation {
    /// One kilometer, in meters — a convenience for the common per-km split
    /// distance.
    public static let kilometerMeters: Double = 1_000
    /// One statute mile, in meters — a convenience for the per-mile split
    /// distance (the international mile: 1_609.344 m).
    public static let mileMeters: Double = 1_609.344

    /// Derives ordered, zero-based-indexed `Split`s for `runID` from a
    /// cumulative-distance `series`, cutting a new split every
    /// `splitDistanceMeters` of covered ground.
    ///
    /// Semantics, all chosen to keep this function total (never throws,
    /// never traps, always returns — CLAUDE.md's "no force-unwraps... errors
    /// are typed and surfaced, not swallowed" extends here to "malformed
    /// input degrades gracefully, it does not crash"):
    /// - **Empty series** -> `[]`.
    /// - **Single sample** covering more than one split's worth of distance
    ///   -> multiple splits are cut within that one sample, via linear
    ///   interpolation of the crossing time inside the sample's
    ///   `startDate...endDate`.
    /// - **Exact split-distance crossing** (a sample's accumulated distance
    ///   lands exactly on a `splitDistanceMeters` boundary) -> the crossing
    ///   time is that sample's own `endDate` (interpolation fraction `1.0`),
    ///   not fudged forward into the next sample.
    /// - **Interpolated crossings** (the boundary falls partway through a
    ///   sample's interval) -> crossing time = `startDate` + `duration *
    ///   (neededMeters / sampleDeltaMeters)`, assuming constant pace across
    ///   that one sample's interval (the only assumption HealthKit's
    ///   summary-per-interval shape allows).
    /// - **Partial final split**: `Split` (`DomainKit/Entities/CompletedRun.swift`)
    ///   has no "is this split complete" flag — a shorter `distanceMeters`
    ///   on the *last* split IS the partial-split representation. Any
    ///   leftover distance after the last full split boundary becomes one
    ///   trailing `Split` with `distanceMeters` = the leftover (< `splitDistanceMeters`)
    ///   and `durationSeconds` = time from the last boundary to the final
    ///   sample's `endDate`. No trailing split is emitted when the total
    ///   distance divides the split distance exactly (leftover == 0).
    /// - **Non-monotonic / negative / non-finite deltas** (e.g. a GPS
    ///   correction that reduces reported distance) -> clamped to zero
    ///   distance for that sample; the sample is skipped entirely (it can
    ///   never trigger a crossing) rather than moving cumulative distance
    ///   backwards.
    /// - **Duplicate/zero-duration timestamps** (`startDate == endDate`) ->
    ///   handled without division-by-zero: the interpolation fraction
    ///   divides by the sample's *distance* delta, never its duration: a
    ///   zero-duration sample with positive delta simply crosses
    ///   instantaneously at `startDate`.
    /// - **Pauses (gaps between samples)**: HealthKit's series query only
    ///   yields samples for periods it has data; a real-world pause/tunnel
    ///   gap shows up as an absence of samples between two `dateInterval`s,
    ///   not as an explicit "paused" marker. This function has no way to
    ///   detect that gap was a pause versus a genuinely slow/stationary
    ///   period, so it makes no special case for it: the elapsed wall-clock
    ///   time of a gap is folded into whichever split is "in progress" when
    ///   the *next* sample with positive delta arrives (i.e. paused time
    ///   inflates that split's `durationSeconds`, exactly as it would if the
    ///   runner had genuinely stood still while GPS kept ticking). This
    ///   mirrors `docs/ARCHITECTURE.md` §11 risk 3's documented split-accuracy
    ///   risk and is a deliberate, simple choice rather than an attempt to
    ///   infer pause boundaries from distance data alone.
    public static func deriveSplits(
        from series: [DistanceSeriesPoint],
        runID: UUID,
        splitDistanceMeters: Double
    ) -> [Split] {
        guard splitDistanceMeters.isFinite, splitDistanceMeters > 0 else { return [] }

        let orderedSeries = series.sorted { $0.startDate < $1.startDate }
        guard let first = orderedSeries.first else { return [] }

        var splits: [Split] = []
        var splitIndex = 0
        var cumulativeMeters = 0.0
        var lastBoundaryDate = first.startDate

        for point in orderedSeries {
            let intervalStart = point.startDate
            // Clamp: never let a corrupt/reordered end date precede the start.
            let intervalEnd = max(point.endDate, intervalStart)
            let intervalDuration = intervalEnd.timeIntervalSince(intervalStart)
            // Clamp non-monotonic/negative/non-finite deltas to zero rather
            // than letting cumulative distance move backwards or crash.
            let delta = (point.deltaMeters.isFinite && point.deltaMeters > 0) ? point.deltaMeters : 0
            guard delta > 0 else { continue }

            // Fixed for the whole point: every crossing's fraction is measured
            // from this point's cumulative distance at its own start, never
            // from a boundary reached partway through -- multiple crossings
            // within a single large sample must each be positioned relative
            // to the same interval, not compound off one another.
            let pointStartCumulative = cumulativeMeters
            let endCumulative = pointStartCumulative + delta
            var nextBoundary = Double(splitIndex + 1) * splitDistanceMeters

            while nextBoundary <= endCumulative {
                let fraction = (nextBoundary - pointStartCumulative) / delta
                let crossingDate = intervalStart.addingTimeInterval(intervalDuration * fraction)
                let duration = max(0, crossingDate.timeIntervalSince(lastBoundaryDate))
                splits.append(
                    Split(
                        runID: runID,
                        index: splitIndex,
                        distanceMeters: splitDistanceMeters,
                        durationSeconds: duration
                    )
                )
                lastBoundaryDate = crossingDate
                splitIndex += 1
                nextBoundary = Double(splitIndex + 1) * splitDistanceMeters
            }

            cumulativeMeters = endCumulative
        }

        let leftoverMeters = cumulativeMeters - Double(splitIndex) * splitDistanceMeters
        if leftoverMeters > 0, let last = orderedSeries.last {
            let endDate = max(last.endDate, lastBoundaryDate)
            let duration = max(0, endDate.timeIntervalSince(lastBoundaryDate))
            splits.append(
                Split(
                    runID: runID,
                    index: splitIndex,
                    distanceMeters: leftoverMeters,
                    durationSeconds: duration
                )
            )
        }

        return splits
    }
}
