import Testing
import Foundation
@testable import DomainKit
import TestSupport

/// Core `IngestCompletedRunsUseCase.execute(_:)` coverage: the empty-batch
/// no-op, idempotent upsert (incl. split replace semantics), and tombstone
/// flows (known/already-deleted/unknown). Attribution and personal-best
/// recalculation coverage live in their own suites — see
/// `IngestCompletedRunsFixtures`'s doc comment.
@Suite("IngestCompletedRunsUseCase")
struct IngestCompletedRunsUseCaseTests {
    private typealias Fixtures = IngestCompletedRunsFixtures

    // MARK: - Empty batch

    @Test("An empty batch is a total no-op")
    func emptyBatchIsNoOp() async throws {
        let harness = Fixtures.makeHarness()
        let report = try await harness.useCase.execute(IngestionBatch())

        #expect(report == IngestionReport())
        #expect(harness.runHistory.runsByID.isEmpty)
        #expect(harness.workouts.syncJobsByID.isEmpty)
    }

    // MARK: - Idempotent upsert

    @Test("Re-ingesting the same batch twice is a no-op the second time")
    func reingestingSameBatchIsIdempotent() async throws {
        let harness = Fixtures.makeHarness()
        let run = Fixtures.makeRun()
        let batch = IngestionBatch(runs: [IngestedRun(run: run, splits: [Fixtures.makeSplit(runID: run.id, index: 0)])])

        let first = try await harness.useCase.execute(batch)
        let stateAfterFirst = harness.runHistory.runsByID
        let splitsAfterFirst = harness.runHistory.splitsByRunID
        let bestsAfterFirst = harness.runHistory.personalBestsByID

        let second = try await harness.useCase.execute(batch)

        #expect(harness.runHistory.runsByID == stateAfterFirst)
        #expect(harness.runHistory.splitsByRunID == splitsAfterFirst)
        #expect(harness.runHistory.personalBestsByID == bestsAfterFirst)
        #expect(first.upsertedRunIDs == second.upsertedRunIDs)
        #expect(second.newPersonalBests.isEmpty, "second ingestion must not mint a duplicate PR (tie, not newRecord)")
    }

    @Test("Upsert replaces changed fields for an existing run id")
    func upsertUpdatesChangedRun() async throws {
        let harness = Fixtures.makeHarness()
        let runID = UUID()
        let original = Fixtures.makeRun(id: runID, durationSeconds: 1_300)
        _ = try await harness.useCase.execute(IngestionBatch(runs: [IngestedRun(run: original)]))

        let updated = Fixtures.makeRun(id: runID, durationSeconds: 1_250)
        _ = try await harness.useCase.execute(IngestionBatch(runs: [IngestedRun(run: updated)]))

        let stored = try #require(harness.runHistory.runsByID[runID])
        #expect(stored.durationSeconds == 1_250)
    }

    @Test("Splits are replaced, not appended, on re-ingestion")
    func splitsAreReplacedNotAppended() async throws {
        let harness = Fixtures.makeHarness()
        let run = Fixtures.makeRun()
        let firstSplits = [Fixtures.makeSplit(runID: run.id, index: 0), Fixtures.makeSplit(runID: run.id, index: 1)]
        _ = try await harness.useCase.execute(IngestionBatch(runs: [IngestedRun(run: run, splits: firstSplits)]))

        let secondSplits = [Fixtures.makeSplit(runID: run.id, index: 0)]
        _ = try await harness.useCase.execute(IngestionBatch(runs: [IngestedRun(run: run, splits: secondSplits)]))

        let stored = try await harness.runHistory.fetchSplits(runID: run.id)
        #expect(stored.count == 1)
    }

    // MARK: - Tombstones

    @Test("A known run id is tombstoned via markDeleted")
    func tombstoneKnownRun() async throws {
        let harness = Fixtures.makeHarness()
        let run = Fixtures.makeRun()
        _ = try await harness.useCase.execute(IngestionBatch(runs: [IngestedRun(run: run)]))

        let report = try await harness.useCase.execute(IngestionBatch(deletedRunIDs: [run.id]))

        #expect(report.tombstonedRunIDs == [run.id])
        #expect(report.skippedUnknownDeletionIDs.isEmpty)
        let stored = try #require(harness.runHistory.runsByID[run.id])
        #expect(stored.isDeleted)
    }

    @Test("An already-deleted run id is tolerated (idempotent tombstone)")
    func tombstoneAlreadyDeletedRunIsTolerated() async throws {
        let harness = Fixtures.makeHarness()
        let run = Fixtures.makeRun()
        _ = try await harness.useCase.execute(IngestionBatch(runs: [IngestedRun(run: run)]))
        _ = try await harness.useCase.execute(IngestionBatch(deletedRunIDs: [run.id]))

        let secondReport = try await harness.useCase.execute(IngestionBatch(deletedRunIDs: [run.id]))

        #expect(secondReport.tombstonedRunIDs == [run.id])
        #expect(secondReport.skippedUnknownDeletionIDs.isEmpty)
        #expect(harness.runHistory.runsByID[run.id]?.isDeleted == true)
    }

    @Test("An unknown deleted run id is skipped, not thrown, and the batch still applies")
    func unknownDeletedRunIDIsSkipped() async throws {
        let harness = Fixtures.makeHarness()
        let unknownID = UUID()
        let run = Fixtures.makeRun()

        let report = try await harness.useCase.execute(
            IngestionBatch(runs: [IngestedRun(run: run)], deletedRunIDs: [unknownID])
        )

        #expect(report.skippedUnknownDeletionIDs == [unknownID])
        #expect(report.tombstonedRunIDs.isEmpty)
        #expect(report.upsertedRunIDs == [run.id])
        #expect(harness.runHistory.runsByID[run.id] != nil)
    }

    @Test("A non-runNotFound error from markDeleted propagates and aborts the batch")
    func nonRunNotFoundDeletionErrorPropagates() async throws {
        let harness = Fixtures.makeHarness()
        harness.runHistory.errorToThrow = RunHistoryRepositoryError.underlying("boom")

        await #expect(throws: RunHistoryRepositoryError.underlying("boom")) {
            try await harness.useCase.execute(IngestionBatch(deletedRunIDs: [UUID()]))
        }
    }

    // MARK: - Duplicate run id within one batch

    @Test("The same run id appearing twice within one batch is deduped to its final state")
    func duplicateRunIDWithinBatchIsDeduped() async throws {
        let harness = Fixtures.makeHarness()
        let runID = UUID()
        let first = Fixtures.makeRun(id: runID, durationSeconds: 1_300)
        let second = Fixtures.makeRun(id: runID, durationSeconds: 1_100)

        let report = try await harness.useCase.execute(
            IngestionBatch(runs: [IngestedRun(run: first), IngestedRun(run: second)])
        )

        // Deduped: one entry in the processing order, not two.
        #expect(report.upsertedRunIDs == [runID])
        // Final stored state reflects the LAST occurrence, not the first.
        #expect(harness.runHistory.runsByID[runID]?.durationSeconds == 1_100)
        // PR recalculation ran once, against the final (faster) state — not
        // once per raw batch entry (which would double-count the same run).
        #expect(report.newPersonalBests.count == 1)
        let best = try #require(await harness.runHistory.fetchPersonalBest(milestoneID: Milestone.fiveK.id))
        #expect(best.elapsedSeconds == 1_100)
    }
}
