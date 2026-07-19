import Testing
import Foundation
@testable import DomainKit

/// Coverage of `PersonalBestPolicy.qualifyingMilestones(for:among:)` and
/// `qualifies(run:milestone:)`: exact-distance matches, tolerance-band edges
/// (both directions), the multi-milestone "only the milestone(s) whose band
/// actually contains the distance" semantic, invalid/tombstoned runs, and
/// determinism.
///
/// Split from `PersonalBestPolicyEvaluationTests` (and the fake-repository
/// integration test) to keep each file's type body under SwiftLint's
/// `type_body_length` threshold, matching the existing
/// `ValidateWorkoutPolicy*Tests` split pattern.
@Suite("PersonalBestPolicy — qualification")
struct PersonalBestPolicyQualificationTests {
    private let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeRun(
        distanceMeters: Double,
        durationSeconds: TimeInterval = 1_500,
        isDeleted: Bool = false
    ) -> CompletedRun {
        CompletedRun(
            id: UUID(),
            date: referenceDate,
            distanceMeters: distanceMeters,
            durationSeconds: durationSeconds,
            source: "Apple Watch",
            isDeleted: isDeleted
        )
    }

    // MARK: - Exact distance

    @Test("Every MVP milestone qualifies for a run at exactly its nominal distance", arguments: Milestone.mvpPresets)
    func exactDistanceQualifies(_ milestone: Milestone) {
        let run = makeRun(distanceMeters: milestone.distanceMeters)
        #expect(PersonalBestPolicy.qualifies(run: run, milestone: milestone))
        #expect(PersonalBestPolicy.qualifyingMilestones(for: run, among: [milestone]) == [milestone])
    }

    // MARK: - Tolerance band edges
    //
    // Note: `milestone.distanceMeters ± milestone.tolerance` is not always
    // bit-exact in `Double` (e.g. `Milestone.halfMarathon.tolerance` is
    // `421.95`, a value with no exact binary representation), so a literal
    // "compute the edge by subtraction, then assert the reverse subtraction
    // recovers exactly `tolerance`" test is flaky by construction — it fails
    // on floating-point rounding, not on policy logic. These tests instead
    // use a 0.5 m margin, comfortably larger than any such rounding error,
    // to test genuinely-inside/genuinely-outside without relying on
    // bit-exact edge arithmetic. The literal `<=` boundary (bit-exact edge)
    // is separately pinned below using 5K/10K, whose tolerances (100 m,
    // 200 m) *are* exactly representable in `Double`.

    @Test("Comfortably inside the lower tolerance edge still qualifies", arguments: Milestone.mvpPresets)
    func lowerEdgeInclusiveQualifies(_ milestone: Milestone) {
        let run = makeRun(distanceMeters: milestone.distanceMeters - (milestone.tolerance - 0.5))
        #expect(PersonalBestPolicy.qualifies(run: run, milestone: milestone))
    }

    @Test("Comfortably outside the lower tolerance edge does not qualify", arguments: Milestone.mvpPresets)
    func justOutsideLowerEdgeDoesNotQualify(_ milestone: Milestone) {
        let run = makeRun(distanceMeters: milestone.distanceMeters - (milestone.tolerance + 0.5))
        #expect(!PersonalBestPolicy.qualifies(run: run, milestone: milestone))
    }

    @Test("Comfortably inside the upper tolerance edge still qualifies", arguments: Milestone.mvpPresets)
    func upperEdgeInclusiveQualifies(_ milestone: Milestone) {
        let run = makeRun(distanceMeters: milestone.distanceMeters + (milestone.tolerance - 0.5))
        #expect(PersonalBestPolicy.qualifies(run: run, milestone: milestone))
    }

    @Test("Exactly at the bit-exact lower tolerance edge still qualifies (5K and 10K only, per the note above)", arguments: [
        Milestone.fiveK, Milestone.tenK
    ])
    func exactLowerEdgeInclusiveQualifies(_ milestone: Milestone) {
        let run = makeRun(distanceMeters: milestone.distanceMeters - milestone.tolerance)
        #expect(PersonalBestPolicy.qualifies(run: run, milestone: milestone))
    }

    @Test("Exactly at the bit-exact upper tolerance edge still qualifies (5K and 10K only, per the note above)", arguments: [
        Milestone.fiveK, Milestone.tenK
    ])
    func exactUpperEdgeInclusiveQualifies(_ milestone: Milestone) {
        let run = makeRun(distanceMeters: milestone.distanceMeters + milestone.tolerance)
        #expect(PersonalBestPolicy.qualifies(run: run, milestone: milestone))
    }

    @Test("Comfortably outside the upper tolerance edge does not qualify", arguments: Milestone.mvpPresets)
    func justOutsideUpperEdgeDoesNotQualify(_ milestone: Milestone) {
        let run = makeRun(distanceMeters: milestone.distanceMeters + (milestone.tolerance + 0.5))
        #expect(!PersonalBestPolicy.qualifies(run: run, milestone: milestone))
    }

    // MARK: - Multi-milestone boundary semantics (flagged decision)

    @Test("A 10.1 km run qualifies for 10K only, not 5K, among the MVP presets")
    func tenPointOneKQualifiesForTenKOnly() {
        let run = makeRun(distanceMeters: 10_100)
        let qualifying = PersonalBestPolicy.qualifyingMilestones(for: run, among: Milestone.mvpPresets)
        #expect(qualifying == [.tenK])
    }

    @Test("An exact 5K run qualifies for 5K only, not 10K, among the MVP presets")
    func exactFiveKQualifiesForFiveKOnly() {
        let run = makeRun(distanceMeters: 5_000)
        let qualifying = PersonalBestPolicy.qualifyingMilestones(for: run, among: Milestone.mvpPresets)
        #expect(qualifying == [.fiveK])
    }

    @Test("A marathon-distance run does not qualify for 5K, 10K, or Half among the MVP presets")
    func marathonDoesNotQualifyForSmallerMilestones() {
        let run = makeRun(distanceMeters: Milestone.marathon.distanceMeters)
        let qualifying = PersonalBestPolicy.qualifyingMilestones(for: run, among: Milestone.mvpPresets)
        #expect(qualifying == [.marathon])
    }

    @Test("A run between two milestones' bands qualifies for neither")
    func runBetweenBandsQualifiesForNone() {
        // Roughly halfway between 5K (band ends ~5,100) and 10K (band starts ~9,800).
        let run = makeRun(distanceMeters: 7_500)
        let qualifying = PersonalBestPolicy.qualifyingMilestones(for: run, among: Milestone.mvpPresets)
        #expect(qualifying.isEmpty)
    }

    @Test("Overlapping tolerance bands (synthetic milestones) both qualify — the function does not assume a single match")
    func overlappingBandsBothQualify() {
        let near = Milestone(id: UUID(), distanceMeters: 5_000, tolerance: 600, displayName: "Near")
        let far = Milestone(id: UUID(), distanceMeters: 5_400, tolerance: 600, displayName: "Far")
        let run = makeRun(distanceMeters: 5_000)
        let qualifying = PersonalBestPolicy.qualifyingMilestones(for: run, among: [near, far])
        #expect(Set(qualifying.map(\.id)) == Set([near.id, far.id]))
    }

    // MARK: - Never qualifies: tombstoned / invalid runs

    @Test("A tombstoned (isDeleted) run never qualifies, even at an exact milestone distance")
    func tombstonedRunNeverQualifies() {
        let run = makeRun(distanceMeters: Milestone.fiveK.distanceMeters, isDeleted: true)
        #expect(PersonalBestPolicy.qualifyingMilestones(for: run).isEmpty)
        #expect(!PersonalBestPolicy.qualifies(run: run, milestone: .fiveK))
    }

    @Test("Zero distance never qualifies")
    func zeroDistanceNeverQualifies() {
        let run = makeRun(distanceMeters: 0)
        #expect(PersonalBestPolicy.qualifyingMilestones(for: run).isEmpty)
    }

    @Test("Negative distance never qualifies")
    func negativeDistanceNeverQualifies() {
        let run = makeRun(distanceMeters: -5_000)
        #expect(PersonalBestPolicy.qualifyingMilestones(for: run).isEmpty)
    }

    @Test("NaN distance never qualifies")
    func nanDistanceNeverQualifies() {
        let run = makeRun(distanceMeters: .nan)
        #expect(PersonalBestPolicy.qualifyingMilestones(for: run).isEmpty)
    }

    @Test("Infinite distance never qualifies")
    func infiniteDistanceNeverQualifies() {
        let run = makeRun(distanceMeters: .infinity)
        #expect(PersonalBestPolicy.qualifyingMilestones(for: run).isEmpty)
    }

    @Test("Zero duration never qualifies, even at an exact milestone distance")
    func zeroDurationNeverQualifies() {
        let run = makeRun(distanceMeters: Milestone.fiveK.distanceMeters, durationSeconds: 0)
        #expect(PersonalBestPolicy.qualifyingMilestones(for: run).isEmpty)
    }

    @Test("Negative duration never qualifies")
    func negativeDurationNeverQualifies() {
        let run = makeRun(distanceMeters: Milestone.fiveK.distanceMeters, durationSeconds: -1)
        #expect(PersonalBestPolicy.qualifyingMilestones(for: run).isEmpty)
    }

    @Test("NaN duration never qualifies")
    func nanDurationNeverQualifies() {
        let run = makeRun(distanceMeters: Milestone.fiveK.distanceMeters, durationSeconds: .nan)
        #expect(PersonalBestPolicy.qualifyingMilestones(for: run).isEmpty)
    }

    // MARK: - Determinism

    @Test("qualifyingMilestones(for:among:) is deterministic and order-preserving")
    func qualifyingMilestonesIsDeterministic() {
        let run = makeRun(distanceMeters: Milestone.tenK.distanceMeters)
        let first = PersonalBestPolicy.qualifyingMilestones(for: run)
        let second = PersonalBestPolicy.qualifyingMilestones(for: run)
        #expect(first == second)
        #expect(first == [.tenK])
    }
}
