import Testing
import Foundation
@testable import DomainKit
import TestSupport

/// Coverage of `IngestCompletedRunsUseCase`'s personal-best recalculation:
/// new record / tie / slower-no-op, in-batch same-milestone ordering,
/// multi-milestone runs, non-qualifying runs, the tombstoned-PR-source
/// semantics (the subtle case — see `IngestCompletedRunsUseCase.execute(_:)`'s
/// doc comment), and one end-to-end combined-batch test.
@Suite("IngestCompletedRunsUseCase — personal bests")
struct IngestCompletedRunsPersonalBestTests {
    private typealias Fixtures = IngestCompletedRunsFixtures

    @Test("A qualifying run with no prior record persists a new PersonalBest")
    func newPersonalBestIsPersisted() async throws {
        let harness = Fixtures.makeHarness()
        let run = Fixtures.makeRun(durationSeconds: 1_200)

        let report = try await harness.useCase.execute(IngestionBatch(runs: [IngestedRun(run: run)]))

        #expect(report.newPersonalBests.count == 1)
        let best = try #require(await harness.runHistory.fetchPersonalBest(milestoneID: Milestone.fiveK.id))
        #expect(best.completedRunID == run.id)
        #expect(best.elapsedSeconds == 1_200)
    }

    @Test("A tie against the current best is not persisted")
    func tieIsNotPersisted() async throws {
        let harness = Fixtures.makeHarness()
        let first = Fixtures.makeRun(durationSeconds: 1_200)
        _ = try await harness.useCase.execute(IngestionBatch(runs: [IngestedRun(run: first)]))

        let secondRun = Fixtures.makeRun(durationSeconds: 1_200)
        let report = try await harness.useCase.execute(IngestionBatch(runs: [IngestedRun(run: secondRun)]))

        #expect(report.newPersonalBests.isEmpty)
        let best = try #require(await harness.runHistory.fetchPersonalBest(milestoneID: Milestone.fiveK.id))
        #expect(best.completedRunID == first.id, "the original record remains current on a tie")
    }

    @Test("A slower run against the current best is not persisted")
    func slowerRunIsNotPersisted() async throws {
        let harness = Fixtures.makeHarness()
        let fastRun = Fixtures.makeRun(durationSeconds: 1_100)
        _ = try await harness.useCase.execute(IngestionBatch(runs: [IngestedRun(run: fastRun)]))

        let slowRun = Fixtures.makeRun(durationSeconds: 1_300)
        let report = try await harness.useCase.execute(IngestionBatch(runs: [IngestedRun(run: slowRun)]))

        #expect(report.newPersonalBests.isEmpty)
        let best = try #require(await harness.runHistory.fetchPersonalBest(milestoneID: Milestone.fiveK.id))
        #expect(best.completedRunID == fastRun.id)
    }

    @Test("A strictly faster run supersedes the current best by becoming the new current record")
    func fasterRunSupersedesCurrentBest() async throws {
        let harness = Fixtures.makeHarness()
        let slower = Fixtures.makeRun(durationSeconds: 1_200)
        _ = try await harness.useCase.execute(IngestionBatch(runs: [IngestedRun(run: slower)]))

        let faster = Fixtures.makeRun(durationSeconds: 1_100)
        let report = try await harness.useCase.execute(IngestionBatch(runs: [IngestedRun(run: faster)]))

        #expect(report.newPersonalBests.count == 1)
        let best = try #require(await harness.runHistory.fetchPersonalBest(milestoneID: Milestone.fiveK.id))
        #expect(best.completedRunID == faster.id)
    }

    @Test("Two qualifying runs for the same milestone within one batch are compared against each other in order")
    func twoRunsSameMilestoneWithinOneBatch() async throws {
        let harness = Fixtures.makeHarness()
        let slower = Fixtures.makeRun(durationSeconds: 1_200)
        let faster = Fixtures.makeRun(durationSeconds: 1_100)

        let report = try await harness.useCase.execute(
            IngestionBatch(runs: [IngestedRun(run: slower), IngestedRun(run: faster)])
        )

        #expect(report.newPersonalBests.count == 2, "both the first-ever record and the subsequent improvement")
        let best = try #require(await harness.runHistory.fetchPersonalBest(milestoneID: Milestone.fiveK.id))
        #expect(best.completedRunID == faster.id)
    }

    @Test("A run qualifying for multiple milestones sets a PR for each")
    func multiMilestoneRunSetsMultipleRecords() async throws {
        // A run whose distance sits inside BOTH overlapping milestone bands —
        // constructed directly so this test doesn't depend on the MVP
        // presets' real (widely-spaced) distances.
        let milestoneA = Milestone(id: UUID(), distanceMeters: 5_000, tolerance: 500, displayName: "A")
        let milestoneB = Milestone(id: UUID(), distanceMeters: 5_100, tolerance: 500, displayName: "B")
        let harness = Fixtures.makeHarness(milestones: [milestoneA, milestoneB])
        let run = Fixtures.makeRun(distanceMeters: 5_050, durationSeconds: 1_200)

        let report = try await harness.useCase.execute(IngestionBatch(runs: [IngestedRun(run: run)]))

        #expect(report.newPersonalBests.count == 2)
        #expect(try await harness.runHistory.fetchPersonalBest(milestoneID: milestoneA.id)?.completedRunID == run.id)
        #expect(try await harness.runHistory.fetchPersonalBest(milestoneID: milestoneB.id)?.completedRunID == run.id)
    }

    @Test("A non-qualifying run (outside every milestone band) sets no records")
    func nonQualifyingRunSetsNoRecords() async throws {
        let harness = Fixtures.makeHarness()
        let run = Fixtures.makeRun(distanceMeters: 7_000, durationSeconds: 1_800)

        let report = try await harness.useCase.execute(IngestionBatch(runs: [IngestedRun(run: run)]))

        #expect(report.newPersonalBests.isEmpty)
        #expect(try await harness.runHistory.fetchPersonalBests().isEmpty)
    }

    // MARK: - Tombstoned-PR-source semantics (the subtle case)

    @Test("Tombstoning the current PR-source run leaves its PersonalBest untouched and still current")
    func tombstoningPRSourceRunLeavesRecordUntouched() async throws {
        let harness = Fixtures.makeHarness()
        let prRun = Fixtures.makeRun(durationSeconds: 1_100)
        _ = try await harness.useCase.execute(IngestionBatch(runs: [IngestedRun(run: prRun)]))
        let originalBest = try #require(await harness.runHistory.fetchPersonalBest(milestoneID: Milestone.fiveK.id))

        let report = try await harness.useCase.execute(IngestionBatch(deletedRunIDs: [prRun.id]))

        #expect(report.tombstonedRunIDs == [prRun.id])
        #expect(report.newPersonalBests.isEmpty, "tombstoning never manufactures a recalculated record")
        let stillCurrent = try #require(await harness.runHistory.fetchPersonalBest(milestoneID: Milestone.fiveK.id))
        #expect(stillCurrent == originalBest, "the record is retained, unchanged, still referencing the tombstoned run")
        #expect(harness.runHistory.runsByID[prRun.id]?.isDeleted == true)
    }

    @Test("After tombstoning the PR-source run, a subsequent slower run still does not supersede it")
    func tombstonedPRSourceStillBlocksASlowerSubsequentRun() async throws {
        let harness = Fixtures.makeHarness()
        let prRun = Fixtures.makeRun(durationSeconds: 1_100)
        _ = try await harness.useCase.execute(IngestionBatch(runs: [IngestedRun(run: prRun)]))
        _ = try await harness.useCase.execute(IngestionBatch(deletedRunIDs: [prRun.id]))

        let slowerRun = Fixtures.makeRun(durationSeconds: 1_200)
        let report = try await harness.useCase.execute(IngestionBatch(runs: [IngestedRun(run: slowerRun)]))

        #expect(report.newPersonalBests.isEmpty)
        let best = try #require(await harness.runHistory.fetchPersonalBest(milestoneID: Milestone.fiveK.id))
        #expect(best.completedRunID == prRun.id, "the tombstoned run's record still wins on elapsed time")
    }

    @Test("After tombstoning the PR-source run, a strictly faster subsequent run does supersede it")
    func fasterRunAfterTombstoneStillSupersedes() async throws {
        let harness = Fixtures.makeHarness()
        let prRun = Fixtures.makeRun(durationSeconds: 1_100)
        _ = try await harness.useCase.execute(IngestionBatch(runs: [IngestedRun(run: prRun)]))
        _ = try await harness.useCase.execute(IngestionBatch(deletedRunIDs: [prRun.id]))

        let fasterRun = Fixtures.makeRun(durationSeconds: 1_000)
        let report = try await harness.useCase.execute(IngestionBatch(runs: [IngestedRun(run: fasterRun)]))

        #expect(report.newPersonalBests.count == 1)
        let best = try #require(await harness.runHistory.fetchPersonalBest(milestoneID: Milestone.fiveK.id))
        #expect(best.completedRunID == fasterRun.id)
    }

    // MARK: - Combined batch (upsert + tombstone + attribution + PR recalc)

    @Test("A single batch applies upsert, attribution, and PR recalculation together")
    func combinedBatchAppliesEverything() async throws {
        let harness = Fixtures.makeHarness()
        let workoutID = try await Fixtures.seedSyncedJob(in: harness.workouts, scheduledDate: Fixtures.referenceDate)
        let run = Fixtures.makeRun(date: Fixtures.referenceDate, durationSeconds: 1_200)
        let split = Fixtures.makeSplit(runID: run.id, index: 0)

        let report = try await harness.useCase.execute(IngestionBatch(runs: [IngestedRun(run: run, splits: [split])]))

        #expect(report.upsertedRunIDs == [run.id])
        #expect(report.attributedRunIDs[run.id] == workoutID)
        #expect(report.newPersonalBests.count == 1)
        #expect(harness.runHistory.runsByID[run.id]?.workoutID == workoutID)
        #expect(try await harness.runHistory.fetchSplits(runID: run.id) == [split])
    }
}
