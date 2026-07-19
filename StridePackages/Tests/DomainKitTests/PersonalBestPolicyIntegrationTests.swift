import Testing
import Foundation
import TestSupport
@testable import DomainKit

/// An integration-flavored suite that exercises `PersonalBestPolicy`
/// alongside `FakeRunHistoryRepository`, confirming the interaction the
/// policy's doc comments assert but cannot prove in isolation: persisting a
/// `.newRecord`'s `PersonalBest` is sufficient for the repository's
/// documented "current" ordering (lowest `elapsedSeconds` wins) to surface
/// it — no separate "archive the old one" step is required, and the
/// superseded record remains in `fetchPersonalBests()` as history.
@Suite("PersonalBestPolicy — RunHistoryRepository ordering interaction")
struct PersonalBestPolicyIntegrationTests {
    private let milestone = Milestone.fiveK

    private func makeRun(durationSeconds: TimeInterval) -> CompletedRun {
        CompletedRun(
            id: UUID(),
            date: Date(timeIntervalSince1970: 1_700_000_000),
            distanceMeters: milestone.distanceMeters,
            durationSeconds: durationSeconds,
            source: "Apple Watch"
        )
    }

    @Test("Persisting a newRecord decision makes it the repository's current best, without touching the prior record")
    func newRecordBecomesCurrentUnderRepositoryOrdering() async throws {
        let repository = FakeRunHistoryRepository()

        // Seed a first-ever record at 1,300s.
        let firstRun = makeRun(durationSeconds: 1_300)
        let firstDecision = PersonalBestPolicy.evaluate(run: firstRun, milestone: milestone, currentBest: nil)
        guard case let .newRecord(firstBest) = firstDecision else {
            Issue.record("Expected the first-ever run to yield .newRecord")
            return
        }
        try await repository.savePersonalBest(firstBest)

        // A strictly faster second run at 1,200s.
        let secondRun = makeRun(durationSeconds: 1_200)
        let existingBest = try await repository.fetchPersonalBest(milestoneID: milestone.id)
        #expect(existingBest?.id == firstBest.id)

        let secondDecision = PersonalBestPolicy.evaluate(run: secondRun, milestone: milestone, currentBest: existingBest)
        guard case let .newRecord(secondBest) = secondDecision else {
            Issue.record("Expected the strictly faster run to yield .newRecord")
            return
        }
        try await repository.savePersonalBest(secondBest)

        // The faster record is now "current" purely by virtue of the
        // repository's ordering — no archive/flag step was performed.
        let current = try await repository.fetchPersonalBest(milestoneID: milestone.id)
        #expect(current?.id == secondBest.id)
        #expect(current?.elapsedSeconds == 1_200)

        // The superseded record remains stored, unmodified, as history.
        let all = try await repository.fetchPersonalBests()
        #expect(Set(all.map(\.id)) == Set([firstBest.id, secondBest.id]))
    }

    @Test("A tie decision is correctly not persisted, leaving the repository's current best unchanged")
    func tieDecisionLeavesRepositoryUnchanged() async throws {
        let repository = FakeRunHistoryRepository()
        let firstRun = makeRun(durationSeconds: 1_200)
        guard case let .newRecord(firstBest) = PersonalBestPolicy.evaluate(
            run: firstRun, milestone: milestone, currentBest: nil
        ) else {
            Issue.record("Expected the first-ever run to yield .newRecord")
            return
        }
        try await repository.savePersonalBest(firstBest)

        let tiedRun = makeRun(durationSeconds: 1_200)
        let existingBest = try await repository.fetchPersonalBest(milestoneID: milestone.id)
        let decision = PersonalBestPolicy.evaluate(run: tiedRun, milestone: milestone, currentBest: existingBest)
        #expect(decision == .tie(currentBest: firstBest))

        // Simulate the ingestion use case correctly declining to persist a tie.
        let current = try await repository.fetchPersonalBest(milestoneID: milestone.id)
        #expect(current?.id == firstBest.id)
        let all = try await repository.fetchPersonalBests()
        #expect(all.count == 1)
    }
}
