import DomainKit
import Foundation
import TestSupport
import Testing

@Suite("Run ingestion recovery")
struct RunIngestionRecoveryTests {
    @Test("Source failure keeps the cursor and permits a subsequent retry")
    func sourceFailure() async throws {
        let harness = IngestCompletedRunsFixtures.makeHarness()
        let source = FakeRunIngestionSource(result: .init(batch: IngestionBatch(), newAnchor: Data([2])))
        let anchors = FakeIngestionAnchorStore(anchorsByKey: ["runs": Data([1])])
        let coordinator = RunIngestionCoordinator(
            source: source, anchorStore: anchors, ingest: harness.useCase,
            anchorKey: "runs", splitDistanceMeters: 1_000
        )
        source.errorToThrow = RunIngestionSourceError.underlying("fetch failed")
        await #expect(throws: RunIngestionSourceError.self) { try await coordinator.ingestNow() }
        #expect(anchors.savedAnchors.isEmpty)
        source.errorToThrow = nil
        try await coordinator.ingestNow()
        #expect(source.receivedAnchors == [Data([1]), Data([1])])
        #expect(anchors.anchorsByKey["runs"] == Data([2]))
    }

    @Test("Cursor save failure replays persisted runs without duplicating records")
    func cursorFailure() async throws {
        let harness = IngestCompletedRunsFixtures.makeHarness()
        let run = IngestCompletedRunsFixtures.makeRun()
        let source = FakeRunIngestionSource(result: .init(
            batch: IngestionBatch(runs: [IngestedRun(run: run)]), newAnchor: Data([2])
        ))
        let anchors = FakeIngestionAnchorStore(anchorsByKey: ["runs": Data([1])])
        let coordinator = RunIngestionCoordinator(
            source: source, anchorStore: anchors, ingest: harness.useCase,
            anchorKey: "runs", splitDistanceMeters: 1_000
        )
        anchors.saveError = IngestionAnchorStoreError.underlying("disk full")
        await #expect(throws: IngestionAnchorStoreError.self) { try await coordinator.ingestNow() }
        #expect(harness.runHistory.runsByID[run.id] == run)
        let records = harness.runHistory.personalBestsByID
        #expect(!records.isEmpty)
        #expect(anchors.anchorsByKey["runs"] == Data([1]))
        anchors.saveError = nil
        try await coordinator.ingestNow()
        #expect(source.receivedAnchors == [Data([1]), Data([1])])
        #expect(harness.runHistory.personalBestsByID == records)
    }

    @Test("Deletion-only batches tombstone runs before the cursor commits")
    func deletionBatch() async throws {
        let run = IngestCompletedRunsFixtures.makeRun()
        let harness = IngestCompletedRunsFixtures.makeHarness(runHistory: FakeRunHistoryRepository(runs: [run]))
        let source = FakeRunIngestionSource(result: .init(
            batch: IngestionBatch(deletedRunIDs: [run.id]), newAnchor: Data([2])
        ))
        let anchors = FakeIngestionAnchorStore()
        let coordinator = RunIngestionCoordinator(
            source: source, anchorStore: anchors, ingest: harness.useCase,
            anchorKey: "runs", splitDistanceMeters: 1_000
        )
        try await coordinator.ingestNow()
        #expect(harness.runHistory.runsByID[run.id]?.isDeleted == true)
        #expect(anchors.anchorsByKey["runs"] == Data([2]))
    }
}
