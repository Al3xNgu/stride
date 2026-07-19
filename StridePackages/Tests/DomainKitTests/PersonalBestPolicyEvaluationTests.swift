import Testing
import Foundation
@testable import DomainKit

/// Coverage of `PersonalBestPolicy.evaluate(run:milestone:currentBest:)`:
/// first-ever record, strictly-faster supersede, tie → not a new record,
/// slower → no change, the defensive ineligible-run re-check, decision
/// payload correctness (ids, `achievedAt`), and determinism.
@Suite("PersonalBestPolicy — evaluation")
struct PersonalBestPolicyEvaluationTests {
    private let runDate = Date(timeIntervalSince1970: 1_700_000_000)
    private let priorAchievedAt = Date(timeIntervalSince1970: 1_600_000_000)

    private func makeRun(
        distanceMeters: Double = Milestone.fiveK.distanceMeters,
        durationSeconds: TimeInterval,
        isDeleted: Bool = false
    ) -> CompletedRun {
        CompletedRun(
            id: UUID(),
            date: runDate,
            distanceMeters: distanceMeters,
            durationSeconds: durationSeconds,
            source: "Apple Watch",
            isDeleted: isDeleted
        )
    }

    private func makeCurrentBest(elapsedSeconds: TimeInterval) -> PersonalBest {
        PersonalBest(
            milestoneID: Milestone.fiveK.id,
            elapsedSeconds: elapsedSeconds,
            completedRunID: UUID(),
            achievedAt: priorAchievedAt
        )
    }

    // MARK: - First-ever record

    @Test("No existing best yields a newRecord decision")
    func noExistingBestYieldsNewRecord() {
        let run = makeRun(durationSeconds: 1_200)
        let decision = PersonalBestPolicy.evaluate(run: run, milestone: .fiveK, currentBest: nil)

        guard case let .newRecord(personalBest) = decision else {
            Issue.record("Expected .newRecord, got \(decision)")
            return
        }
        #expect(personalBest.elapsedSeconds == 1_200)
    }

    // MARK: - Strictly faster supersede

    @Test("A strictly faster run yields a newRecord decision")
    func strictlyFasterYieldsNewRecord() {
        let run = makeRun(durationSeconds: 1_190)
        let currentBest = makeCurrentBest(elapsedSeconds: 1_200)
        let decision = PersonalBestPolicy.evaluate(run: run, milestone: .fiveK, currentBest: currentBest)

        guard case let .newRecord(personalBest) = decision else {
            Issue.record("Expected .newRecord, got \(decision)")
            return
        }
        #expect(personalBest.elapsedSeconds == 1_190)
    }

    // MARK: - Tie

    @Test("An exactly tied run yields a tie decision, not a new record")
    func tieYieldsTieDecision() {
        let run = makeRun(durationSeconds: 1_200)
        let currentBest = makeCurrentBest(elapsedSeconds: 1_200)
        let decision = PersonalBestPolicy.evaluate(run: run, milestone: .fiveK, currentBest: currentBest)

        #expect(decision == .tie(currentBest: currentBest))
    }

    // MARK: - Slower

    @Test("A strictly slower run yields noChange, echoing the current best")
    func slowerYieldsNoChange() {
        let run = makeRun(durationSeconds: 1_210)
        let currentBest = makeCurrentBest(elapsedSeconds: 1_200)
        let decision = PersonalBestPolicy.evaluate(run: run, milestone: .fiveK, currentBest: currentBest)

        #expect(decision == .noChange(currentBest: currentBest))
    }

    // MARK: - Defensive ineligible-run re-check

    @Test("A tombstoned run yields noChange even though it would otherwise be a new record")
    func tombstonedRunYieldsNoChangeEvenIfFaster() {
        let run = makeRun(durationSeconds: 1, isDeleted: true)
        let decision = PersonalBestPolicy.evaluate(run: run, milestone: .fiveK, currentBest: nil)
        #expect(decision == .noChange(currentBest: nil))
    }

    @Test("A tombstoned run yields noChange echoing the existing current best, not dropping it")
    func tombstonedRunEchoesExistingCurrentBest() {
        let run = makeRun(durationSeconds: 1, isDeleted: true)
        let currentBest = makeCurrentBest(elapsedSeconds: 1_200)
        let decision = PersonalBestPolicy.evaluate(run: run, milestone: .fiveK, currentBest: currentBest)
        #expect(decision == .noChange(currentBest: currentBest))
    }

    @Test("A zero-distance run yields noChange even though duration alone would be a new record")
    func zeroDistanceRunYieldsNoChange() {
        let run = makeRun(distanceMeters: 0, durationSeconds: 1)
        let decision = PersonalBestPolicy.evaluate(run: run, milestone: .fiveK, currentBest: nil)
        #expect(decision == .noChange(currentBest: nil))
    }

    @Test("A NaN-duration run yields noChange rather than crashing or fabricating a record")
    func nanDurationRunYieldsNoChange() {
        let run = makeRun(durationSeconds: .nan)
        let decision = PersonalBestPolicy.evaluate(run: run, milestone: .fiveK, currentBest: nil)
        #expect(decision == .noChange(currentBest: nil))
    }

    @Test("A negative-duration run yields noChange")
    func negativeDurationRunYieldsNoChange() {
        let run = makeRun(durationSeconds: -100)
        let currentBest = makeCurrentBest(elapsedSeconds: 1_200)
        let decision = PersonalBestPolicy.evaluate(run: run, milestone: .fiveK, currentBest: currentBest)
        #expect(decision == .noChange(currentBest: currentBest))
    }

    // MARK: - Decision payload correctness

    @Test("A newRecord's PersonalBest carries the milestone id, run's duration/id, and run's date")
    func newRecordPayloadIsCorrect() {
        let run = makeRun(durationSeconds: 1_234)
        let decision = PersonalBestPolicy.evaluate(run: run, milestone: .fiveK, currentBest: nil)

        guard case let .newRecord(personalBest) = decision else {
            Issue.record("Expected .newRecord, got \(decision)")
            return
        }
        #expect(personalBest.milestoneID == Milestone.fiveK.id)
        #expect(personalBest.elapsedSeconds == run.durationSeconds)
        #expect(personalBest.completedRunID == run.id)
        #expect(personalBest.achievedAt == run.date)
    }

    @Test("Each newRecord decision generates a fresh, distinct id")
    func newRecordGeneratesFreshID() {
        let run = makeRun(durationSeconds: 1_200)
        guard
            case let .newRecord(first) = PersonalBestPolicy.evaluate(run: run, milestone: .fiveK, currentBest: nil),
            case let .newRecord(second) = PersonalBestPolicy.evaluate(run: run, milestone: .fiveK, currentBest: nil)
        else {
            Issue.record("Expected both evaluations to yield .newRecord")
            return
        }
        #expect(first.id != second.id)
    }

    // MARK: - Determinism (aside from the intentionally-fresh id)

    @Test("evaluate is deterministic: same inputs yield the same decision kind and payload, aside from id")
    func evaluateIsDeterministicAsideFromID() {
        let run = makeRun(durationSeconds: 1_190)
        let currentBest = makeCurrentBest(elapsedSeconds: 1_200)

        let first = PersonalBestPolicy.evaluate(run: run, milestone: .fiveK, currentBest: currentBest)
        let second = PersonalBestPolicy.evaluate(run: run, milestone: .fiveK, currentBest: currentBest)

        guard
            case let .newRecord(firstBest) = first,
            case let .newRecord(secondBest) = second
        else {
            Issue.record("Expected both evaluations to yield .newRecord")
            return
        }
        #expect(firstBest.milestoneID == secondBest.milestoneID)
        #expect(firstBest.elapsedSeconds == secondBest.elapsedSeconds)
        #expect(firstBest.completedRunID == secondBest.completedRunID)
        #expect(firstBest.achievedAt == secondBest.achievedAt)
    }

    @Test("evaluate is deterministic for a noChange decision")
    func evaluateIsDeterministicForNoChange() {
        let run = makeRun(durationSeconds: 1_210)
        let currentBest = makeCurrentBest(elapsedSeconds: 1_200)

        let first = PersonalBestPolicy.evaluate(run: run, milestone: .fiveK, currentBest: currentBest)
        let second = PersonalBestPolicy.evaluate(run: run, milestone: .fiveK, currentBest: currentBest)
        #expect(first == second)
    }

    @Test("evaluate refuses a distance-mismatched milestone — a marathon run never mints a 5K record")
    func evaluateRefusesMismatchedMilestone() {
        // Well outside 5K's band; without the full qualification re-check
        // this would fabricate a 5K "PR" out of a marathon's total duration.
        let marathonRun = makeRun(distanceMeters: 42_195, durationSeconds: 14_400)

        let decision = PersonalBestPolicy.evaluate(run: marathonRun, milestone: .fiveK, currentBest: nil)

        #expect(decision == .noChange(currentBest: nil))
    }
}
