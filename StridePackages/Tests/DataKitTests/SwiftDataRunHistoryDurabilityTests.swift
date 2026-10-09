import DomainKit
import Foundation
import SwiftData
import Testing
@testable import DataKit

@Suite("SwiftDataRunHistoryRepository — disk durability")
struct SwiftDataRunHistoryDurabilityTests {
    private func makeContainer(url: URL, allowsSave: Bool = true) throws -> ModelContainer {
        try ModelContainer(
            for: CompletedRunModel.self, SplitModel.self, PersonalBestModel.self,
            configurations: ModelConfiguration(url: url, allowsSave: allowsSave)
        )
    }

    @Test("Reopening retains updated projections, stable-ID split replacements, tombstones and PR history")
    func diskReopenRetainsUpdatedRecords() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("history.store")
        var run = CompletedRun(
            id: UUID(), date: Date(timeIntervalSince1970: 1_700_000_000), distanceMeters: 5_000,
            durationSeconds: 1_500, source: "Apple Watch"
        )
        let other = CompletedRun(
            id: UUID(), date: run.date, distanceMeters: 1_000, durationSeconds: 400, source: "Other"
        )
        var first = Split(runID: run.id, index: 0, distanceMeters: 1_000, durationSeconds: 300)
        let removed = Split(runID: run.id, index: 1, distanceMeters: 1_000, durationSeconds: 305)
        let unrelated = Split(runID: other.id, index: 0, distanceMeters: 1_000, durationSeconds: 400)
        var best = PersonalBest(
            milestoneID: UUID(), elapsedSeconds: 1_500, completedRunID: run.id, achievedAt: run.date
        )
        do {
            let repository = SwiftDataRunHistoryRepository(modelContainer: try makeContainer(url: url))
            try await repository.upsert(run)
            try await repository.upsert(other)
            try await repository.saveSplits([removed, first], for: run.id)
            try await repository.saveSplits([unrelated], for: other.id)
            try await repository.savePersonalBest(best)
            run.notes = "Retained after restart"
            run.durationSeconds = 1_450
            try await repository.upsert(run)
            first.durationSeconds = 290
            try await repository.saveSplits([first], for: run.id)
            try await repository.saveSplits([first], for: run.id)
            best.elapsedSeconds = 1_450
            try await repository.savePersonalBest(best)
            try await repository.markDeleted(id: run.id)
        }
        let repository = SwiftDataRunHistoryRepository(modelContainer: try makeContainer(url: url))
        run.isDeleted = true
        #expect(try await repository.fetch(id: run.id) == run)
        #expect(try await repository.fetchAll().count == 2)
        #expect(try await repository.fetchSplits(runID: run.id) == [first])
        #expect(try await repository.fetchSplits(runID: other.id) == [unrelated])
        #expect(try await repository.fetchPersonalBests() == [best])
        try await repository.saveSplits([], for: run.id)
        #expect(try await repository.fetchSplits(runID: run.id).isEmpty)
        #expect(try await repository.fetchSplits(runID: other.id) == [unrelated])
    }
}
