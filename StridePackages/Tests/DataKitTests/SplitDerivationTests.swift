import Testing
import Foundation
import DomainKit
@testable import DataKit

/// Shared fixtures for `SplitDerivation` test suites.
enum SplitDerivationFixtures {
    static let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)
    static let runID = UUID(uuidString: "00000000-0000-0000-0000-000000000001") ?? UUID()

    /// A point starting `offset` seconds after `referenceDate`, running for
    /// `duration` seconds and covering `meters`.
    static func point(offset: TimeInterval, duration: TimeInterval, meters: Double) -> DistanceSeriesPoint {
        DistanceSeriesPoint(
            startDate: referenceDate.addingTimeInterval(offset),
            endDate: referenceDate.addingTimeInterval(offset + duration),
            deltaMeters: meters
        )
    }
}

@Suite("SplitDerivation — empty/single-sample edge cases")
struct SplitDerivationEmptyTests {
    private typealias Fixtures = SplitDerivationFixtures

    @Test("Empty series produces no splits")
    func emptySeries() {
        let splits = SplitDerivation.deriveSplits(
            from: [],
            runID: Fixtures.runID,
            splitDistanceMeters: SplitDerivation.kilometerMeters
        )
        #expect(splits.isEmpty)
    }

    @Test("Non-finite/non-positive split distance produces no splits rather than looping or crashing")
    func invalidSplitDistance() {
        let series = [Fixtures.point(offset: 0, duration: 300, meters: 1_000)]
        #expect(SplitDerivation.deriveSplits(from: series, runID: Fixtures.runID, splitDistanceMeters: 0).isEmpty)
        #expect(SplitDerivation.deriveSplits(from: series, runID: Fixtures.runID, splitDistanceMeters: -1).isEmpty)
        #expect(
            SplitDerivation.deriveSplits(
                from: series,
                runID: Fixtures.runID,
                splitDistanceMeters: .nan
            ).isEmpty
        )
    }

    @Test("Single sample under one split distance yields one partial split, no full split")
    func singleSampleUnderSplitDistance() {
        let series = [Fixtures.point(offset: 0, duration: 300, meters: 500)]
        let splits = SplitDerivation.deriveSplits(
            from: series,
            runID: Fixtures.runID,
            splitDistanceMeters: SplitDerivation.kilometerMeters
        )
        #expect(splits.count == 1)
        #expect(splits[0].index == 0)
        #expect(splits[0].distanceMeters == 500)
        #expect(splits[0].durationSeconds == 300)
    }

    @Test("Single sample spanning multiple split distances cuts multiple splits plus a partial remainder")
    func singleSampleMultipleSplits() {
        // 2500m over 1000s at (assumed) constant pace: km0 at t=400, km1 at
        // t=800, partial 500m split remaining at t=1000.
        let series = [Fixtures.point(offset: 0, duration: 1_000, meters: 2_500)]
        let splits = SplitDerivation.deriveSplits(
            from: series,
            runID: Fixtures.runID,
            splitDistanceMeters: SplitDerivation.kilometerMeters
        )
        #expect(splits.count == 3)
        #expect(splits[0].index == 0)
        #expect(splits[0].distanceMeters == 1_000)
        #expect(splits[0].durationSeconds == 400)
        #expect(splits[1].index == 1)
        #expect(splits[1].distanceMeters == 1_000)
        #expect(splits[1].durationSeconds == 400)
        #expect(splits[2].index == 2)
        #expect(splits[2].distanceMeters == 500)
        #expect(splits[2].durationSeconds == 200)
    }
}

@Suite("SplitDerivation — exact and interpolated crossings across multiple samples")
struct SplitDerivationCrossingTests {
    private typealias Fixtures = SplitDerivationFixtures

    @Test("Exact-km crossing lands the split boundary at the sample's own end date")
    func exactCrossing() {
        let series = [
            Fixtures.point(offset: 0, duration: 300, meters: 1_000),
            Fixtures.point(offset: 300, duration: 200, meters: 500)
        ]
        let splits = SplitDerivation.deriveSplits(
            from: series,
            runID: Fixtures.runID,
            splitDistanceMeters: SplitDerivation.kilometerMeters
        )
        #expect(splits.count == 2)
        #expect(splits[0].distanceMeters == 1_000)
        #expect(splits[0].durationSeconds == 300)
        #expect(splits[1].distanceMeters == 500)
        #expect(splits[1].durationSeconds == 200)
    }

    @Test("Interpolated crossing lands partway through a sample proportional to distance fraction")
    func interpolatedCrossing() {
        // km0 crosses partway through the second sample: 600m needed of this
        // sample's 800m, over its 400s duration -> +300s.
        let series = [
            Fixtures.point(offset: 0, duration: 200, meters: 400),
            Fixtures.point(offset: 200, duration: 400, meters: 800)
        ]
        let splits = SplitDerivation.deriveSplits(
            from: series,
            runID: Fixtures.runID,
            splitDistanceMeters: SplitDerivation.kilometerMeters
        )
        #expect(splits.count == 2)
        #expect(splits[0].distanceMeters == 1_000)
        #expect(splits[0].durationSeconds == 500)
        #expect(splits[1].distanceMeters == 200)
        #expect(splits[1].durationSeconds == 100)
    }

    @Test("Per-mile parameterization uses the mile distance constant, not km")
    func perMileParameterization() {
        let miles = [Fixtures.point(offset: 0, duration: 1_609, meters: SplitDerivation.mileMeters)]
        let splits = SplitDerivation.deriveSplits(
            from: miles,
            runID: Fixtures.runID,
            splitDistanceMeters: SplitDerivation.mileMeters
        )
        #expect(splits.count == 1)
        #expect(splits[0].distanceMeters == SplitDerivation.mileMeters)
        #expect(splits[0].durationSeconds == 1_609)
    }
}

@Suite("SplitDerivation — malformed input never crashes")
struct SplitDerivationMalformedInputTests {
    private typealias Fixtures = SplitDerivationFixtures

    @Test("Non-monotonic (negative delta) samples are clamped to zero distance, never reversing cumulative total")
    func nonMonotonicSampleClamped() {
        let series = [
            Fixtures.point(offset: 0, duration: 300, meters: 900),
            Fixtures.point(offset: 300, duration: 100, meters: -400),
            Fixtures.point(offset: 400, duration: 200, meters: 300)
        ]
        let splits = SplitDerivation.deriveSplits(
            from: series,
            runID: Fixtures.runID,
            splitDistanceMeters: SplitDerivation.kilometerMeters
        )
        // Total real distance: 900 + 0 (clamped) + 300 = 1200m -> one full
        // split + a 200m partial, never a crash or a negative cumulative.
        #expect(splits.count == 2)
        #expect(splits[0].distanceMeters == 1_000)
        #expect(splits[1].distanceMeters == 200)
    }

    @Test("Non-finite delta (NaN) is clamped to zero rather than propagating NaN")
    func nonFiniteDeltaClamped() {
        let series = [
            Fixtures.point(offset: 0, duration: 300, meters: .nan),
            Fixtures.point(offset: 300, duration: 300, meters: 500)
        ]
        let splits = SplitDerivation.deriveSplits(
            from: series,
            runID: Fixtures.runID,
            splitDistanceMeters: SplitDerivation.kilometerMeters
        )
        #expect(splits.count == 1)
        #expect(splits[0].distanceMeters == 500)
        #expect(splits[0].durationSeconds.isFinite)
    }

    @Test("Duplicate/zero-duration timestamps do not divide by zero and cross instantaneously")
    func duplicateTimestampsHandled() {
        let series = [
            Fixtures.point(offset: 0, duration: 0, meters: 1_000),
            Fixtures.point(offset: 0, duration: 100, meters: 200)
        ]
        let splits = SplitDerivation.deriveSplits(
            from: series,
            runID: Fixtures.runID,
            splitDistanceMeters: SplitDerivation.kilometerMeters
        )
        #expect(splits.count == 2)
        #expect(splits[0].distanceMeters == 1_000)
        #expect(splits[0].durationSeconds == 0)
        #expect(splits[1].distanceMeters == 200)
        #expect(splits[1].durationSeconds == 100)
    }

    @Test("Out-of-order samples are sorted by startDate before derivation")
    func outOfOrderSamplesSorted() {
        let series = [
            Fixtures.point(offset: 300, duration: 200, meters: 500),
            Fixtures.point(offset: 0, duration: 300, meters: 1_000)
        ]
        let splits = SplitDerivation.deriveSplits(
            from: series,
            runID: Fixtures.runID,
            splitDistanceMeters: SplitDerivation.kilometerMeters
        )
        #expect(splits.count == 2)
        #expect(splits[0].distanceMeters == 1_000)
        #expect(splits[0].durationSeconds == 300)
        #expect(splits[1].distanceMeters == 500)
        #expect(splits[1].durationSeconds == 200)
    }
}

@Suite("SplitDerivation — pause-gap semantics")
struct SplitDerivationPauseGapTests {
    private typealias Fixtures = SplitDerivationFixtures

    @Test("A wall-clock gap between samples (no data during a pause) inflates the split in progress when data resumes")
    func pauseGapFoldedIntoInProgressSplit() {
        // First sample reaches 800m at t=300 (no crossing yet). Then a
        // 500-second gap with no samples (simulating a pause/tunnel), after
        // which a new sample resumes and crosses 1000m. The chosen semantics
        // (documented on `SplitDerivation.deriveSplits`): the gap's elapsed
        // wall-clock time counts toward whichever split was in progress when
        // distance data resumes, since there is no explicit pause signal in
        // the distance series alone.
        let series = [
            Fixtures.point(offset: 0, duration: 300, meters: 800),
            Fixtures.point(offset: 800, duration: 100, meters: 200)
        ]
        let splits = SplitDerivation.deriveSplits(
            from: series,
            runID: Fixtures.runID,
            splitDistanceMeters: SplitDerivation.kilometerMeters
        )
        #expect(splits.count == 1)
        #expect(splits[0].distanceMeters == 1_000)
        // Crossing lands at the second sample's own end date (t=900, since
        // its full 200m exactly completes the km): 900s elapsed since run
        // start (t=0), even though only 300s + 100s = 400s of that was spent
        // actually covering distance — the remaining 500s (t=300...800, no
        // samples) is the pause gap, folded into this split's duration
        // rather than excluded.
        #expect(splits[0].durationSeconds == 900)
    }
}

@Suite("SplitDerivation — runID/index bookkeeping")
struct SplitDerivationBookkeepingTests {
    private typealias Fixtures = SplitDerivationFixtures

    @Test("Every derived split carries the supplied runID and zero-based ascending index")
    func runIDAndIndexAssigned() {
        let series = [Fixtures.point(offset: 0, duration: 900, meters: 2_000)]
        let splits = SplitDerivation.deriveSplits(
            from: series,
            runID: Fixtures.runID,
            splitDistanceMeters: SplitDerivation.kilometerMeters
        )
        #expect(splits.count == 2)
        for (offset, split) in splits.enumerated() {
            #expect(split.runID == Fixtures.runID)
            #expect(split.index == offset)
        }
    }
}
