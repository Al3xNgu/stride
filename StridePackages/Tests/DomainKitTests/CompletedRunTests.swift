import Testing
import Foundation
@testable import DomainKit

/// Arithmetic and edge-value coverage for `CompletedRun.averagePace`, plus
/// the entity's "dumb data holder" contract (it should store whatever it's
/// given, including zero/negative values — validation is a separate task).
@Suite("CompletedRun.averagePace")
struct CompletedRunTests {
    private func makeRun(distanceMeters: Double, durationSeconds: TimeInterval) -> CompletedRun {
        CompletedRun(
            id: UUID(),
            date: Date(timeIntervalSince1970: 1_700_000_000),
            distanceMeters: distanceMeters,
            durationSeconds: durationSeconds,
            source: "Apple Watch"
        )
    }

    @Test("5000m in 1500s yields 0.3 seconds-per-meter")
    func standardPaceArithmetic() {
        let run = makeRun(distanceMeters: 5_000, durationSeconds: 1_500)
        #expect(run.averagePace == 0.3)
    }

    @Test("10000m in 3000s yields 0.3 seconds-per-meter")
    func tenKPaceArithmetic() {
        let run = makeRun(distanceMeters: 10_000, durationSeconds: 3_000)
        #expect(run.averagePace == 0.3)
    }

    /// FINDING (pinned, not a bug): `averagePace` explicitly guards
    /// `distanceMeters > 0` (CompletedRun.swift) and returns `nil` for a
    /// zero-distance run rather than producing `.infinity` or `NaN`. This is
    /// the correct behavior per CLAUDE.md's "no silently swallowed errors"
    /// spirit — pinning it here so a future refactor can't silently
    /// regress to unchecked division.
    @Test("Zero-distance run yields nil average pace, not infinity or NaN")
    func zeroDistanceYieldsNil() {
        let run = makeRun(distanceMeters: 0, durationSeconds: 600)
        #expect(run.averagePace == nil)
    }

    @Test("Zero-distance and zero-duration run yields nil, not NaN")
    func zeroDistanceZeroDurationYieldsNil() {
        let run = makeRun(distanceMeters: 0, durationSeconds: 0)
        #expect(run.averagePace == nil)
    }

    /// Behavior pin: the guard is `distanceMeters > 0`, which also correctly
    /// excludes negative distances (a negative value is not `> 0`), so a
    /// negative-distance run yields `nil` rather than a nonsensical negative
    /// pace. Confirmed by reading the guard, not assumed.
    @Test("Negative distance also yields nil average pace (guard is > 0, not == 0)")
    func negativeDistanceYieldsNil() {
        let run = makeRun(distanceMeters: -1_000, durationSeconds: 300)
        #expect(run.averagePace == nil)
    }

    @Test("Zero duration with positive distance yields zero pace (instantaneous, not nil)")
    func zeroDurationYieldsZeroPace() {
        let run = makeRun(distanceMeters: 1_000, durationSeconds: 0)
        #expect(run.averagePace == 0)
    }

    // MARK: - Entities are dumb: they store what they're given.

    @Test("CompletedRun stores negative duration without crashing (validation is not this layer's job)")
    func storesNegativeDurationVerbatim() {
        let run = makeRun(distanceMeters: 5_000, durationSeconds: -100)
        #expect(run.durationSeconds == -100)
    }

    @Test("CompletedRun.isDeleted defaults to false and is settable to true (tombstone)")
    func isDeletedTombstoneFlag() {
        var run = makeRun(distanceMeters: 5_000, durationSeconds: 1_500)
        #expect(run.isDeleted == false)
        run.isDeleted = true
        #expect(run.isDeleted == true)
    }
}
