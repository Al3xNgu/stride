import Foundation
import TestSupport
import Testing
@testable import DomainKit

@Suite("RunIngestionCoordinator")
struct RunIngestionCoordinatorTests {
    private let anchorKey = "healthkit.running.workouts.v1"

    @Test("A successful batch commits its new anchor after domain persistence")
    func successCommitsAnchorAfterBatch() async throws {
        let harness = IngestCompletedRunsFixtures.makeHarness()
        let run = IngestCompletedRunsFixtures.makeRun()
        let source = FakeRunIngestionSource(
            result: RunIngestionFetchResult(
                batch: IngestionBatch(runs: [IngestedRun(run: run)]),
                newAnchor: Data([1, 2, 3])
            )
        )
        let anchors = FakeIngestionAnchorStore()
        let coordinator = RunIngestionCoordinator(
            source: source,
            anchorStore: anchors,
            ingest: harness.useCase,
            anchorKey: anchorKey,
            splitDistanceMeters: 1_000
        )

        _ = try await coordinator.ingestNow()

        #expect(source.receivedAnchors == [nil])
        #expect(anchors.anchorsByKey[anchorKey] == Data([1, 2, 3]))
        #expect(try await harness.runHistory.fetch(id: run.id) == run)
    }

    @Test("A domain persistence failure preserves the previous anchor for replay")
    func domainFailureDoesNotAdvanceAnchor() async throws {
        let harness = IngestCompletedRunsFixtures.makeHarness()
        let oldAnchor = Data([9])
        let newAnchor = Data([10])
        let source = FakeRunIngestionSource(
            result: RunIngestionFetchResult(
                batch: IngestionBatch(runs: [IngestedRun(run: IngestCompletedRunsFixtures.makeRun())]),
                newAnchor: newAnchor
            )
        )
        let anchors = FakeIngestionAnchorStore(anchorsByKey: [anchorKey: oldAnchor])
        let coordinator = RunIngestionCoordinator(
            source: source,
            anchorStore: anchors,
            ingest: harness.useCase,
            anchorKey: anchorKey,
            splitDistanceMeters: 1_000
        )
        harness.runHistory.errorToThrow = RunHistoryRepositoryError.underlying("write failed")

        await #expect(throws: RunHistoryRepositoryError.underlying("write failed")) {
            try await coordinator.ingestNow()
        }

        #expect(anchors.anchorsByKey[anchorKey] == oldAnchor)
        #expect(anchors.savedAnchors.isEmpty)

        harness.runHistory.errorToThrow = nil
        _ = try await coordinator.ingestNow()
        #expect(source.receivedAnchors == [oldAnchor, oldAnchor])
        #expect(anchors.anchorsByKey[anchorKey] == newAnchor)
    }

    @Test("Concurrent triggers each fetch from the latest committed cursor")
    func concurrentTriggersUseLatestCursor() async throws {
        let harness = IngestCompletedRunsFixtures.makeHarness()
        let source = FakeRunIngestionSource(
            result: RunIngestionFetchResult(batch: IngestionBatch(), newAnchor: Data([4]))
        )
        source.delayNanoseconds = 50_000_000
        let anchors = FakeIngestionAnchorStore()
        let coordinator = RunIngestionCoordinator(
            source: source,
            anchorStore: anchors,
            ingest: harness.useCase,
            anchorKey: anchorKey,
            splitDistanceMeters: 1_000
        )

        async let first = coordinator.ingestNow()
        async let second = coordinator.ingestNow()
        _ = try await (first, second)

        #expect(source.receivedAnchors == [nil, Data([4])])
        #expect(anchors.savedAnchors.count == 2)
    }
}
