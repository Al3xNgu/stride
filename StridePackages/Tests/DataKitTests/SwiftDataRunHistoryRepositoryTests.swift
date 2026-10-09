import DomainKit
import Foundation
import SwiftData
import Testing
@testable import DataKit

@Suite("SwiftDataRunHistoryRepository")
struct SwiftDataRunHistoryRepositoryTests {
    private func makeRepository() throws -> SwiftDataRunHistoryRepository {
        let container = try ModelContainer(
            for: CompletedRunModel.self,
            SplitModel.self,
            PersonalBestModel.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return SwiftDataRunHistoryRepository(modelContainer: container)
    }

    private func makeRun(id: UUID = UUID(), date: Date = Date(timeIntervalSince1970: 1_700_000_000)) -> CompletedRun {
        CompletedRun(
            id: id,
            date: date,
            distanceMeters: 5_000,
            durationSeconds: 1_500,
            source: "Apple Watch"
        )
    }

    @Test("Upsert and fetch round-trip a completed run")
    func runRoundTrip() async throws {
        let repository = try makeRepository()
        let run = makeRun()

        try await repository.upsert(run)

        #expect(try await repository.fetch(id: run.id) == run)
    }

    @Test("Upsert replaces an existing projection and tombstones preserve the row")
    func upsertAndTombstone() async throws {
        let repository = try makeRepository()
        let run = makeRun()
        try await repository.upsert(run)
        var updated = run
        updated.durationSeconds = 1_450
        try await repository.upsert(updated)
        try await repository.markDeleted(id: run.id)

        let stored = try #require(await repository.fetch(id: run.id))
        #expect(stored.durationSeconds == 1_450)
        #expect(stored.isDeleted)
        try await repository.markDeleted(id: run.id)
        #expect(try await repository.fetchAll() == [stored])
    }

    @Test("Unknown run fetch is nil and tombstoning it throws runNotFound")
    func unknownRunContracts() async throws {
        let repository = try makeRepository()
        let id = UUID()
        #expect(try await repository.fetch(id: id) == nil)
        #expect(try await repository.fetchSplits(runID: id).isEmpty)
        await #expect(throws: RunHistoryRepositoryError.runNotFound(id: id)) {
            try await repository.markDeleted(id: id)
        }
    }

    @Test("Date queries include both boundaries and tombstones but exclude outside runs")
    func inclusiveDateRangeIncludesTombstones() async throws {
        let repository = try makeRepository()
        let runs = (0...4).map { makeRun(date: Date(timeIntervalSince1970: Double($0))) }
        for run in runs { try await repository.upsert(run) }
        try await repository.markDeleted(id: runs[2].id)
        let result = try await repository.fetch(from: runs[1].date, to: runs[3].date)
        #expect(Set(result.map(\.id)) == Set(runs[1...3].map(\.id)))
        #expect(result.first(where: { $0.id == runs[2].id })?.isDeleted == true)
        #expect(try await repository.fetch(from: runs[1].date, to: runs[1].date) == [runs[1]])
        #expect(try await repository.fetch(from: runs[3].date, to: runs[1].date).isEmpty)
        #expect(try await repository.fetchAll().count == 5)
    }

    @Test("Saving splits replaces prior splits and orders by index")
    func splitReplacement() async throws {
        let repository = try makeRepository()
        let run = makeRun()
        try await repository.upsert(run)
        let first = Split(runID: run.id, index: 0, distanceMeters: 1_000, durationSeconds: 300)
        let second = Split(runID: run.id, index: 1, distanceMeters: 1_000, durationSeconds: 290)
        try await repository.saveSplits([second, first], for: run.id)
        try await repository.saveSplits([first], for: run.id)

        #expect(try await repository.fetchSplits(runID: run.id) == [first])
    }

    @Test("Current personal best uses the documented deterministic ordering")
    func currentPersonalBestOrdering() async throws {
        let repository = try makeRepository()
        let milestoneID = UUID()
        let runID = UUID()
        let achievedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let slower = PersonalBest(
            id: UUID(),
            milestoneID: milestoneID,
            elapsedSeconds: 300,
            completedRunID: runID,
            achievedAt: achievedAt
        )
        let faster = PersonalBest(
            id: UUID(),
            milestoneID: milestoneID,
            elapsedSeconds: 299,
            completedRunID: runID,
            achievedAt: achievedAt
        )
        try await repository.savePersonalBest(slower)
        try await repository.savePersonalBest(faster)

        #expect(try await repository.fetchPersonalBest(milestoneID: milestoneID) == faster)
    }

    @Test("Personal best ties use latest date then ascending UUID and deletion exposes history")
    func personalBestTiesAndDeletion() async throws {
        let repository = try makeRepository()
        let milestoneID = UUID()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let lowID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let highID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
        let preferred = PersonalBest(
            id: lowID, milestoneID: milestoneID, elapsedSeconds: 300,
            completedRunID: UUID(), achievedAt: date
        )
        let tied = PersonalBest(
            id: highID, milestoneID: milestoneID, elapsedSeconds: 300,
            completedRunID: UUID(), achievedAt: date
        )
        var older = preferred
        older.achievedAt = date.addingTimeInterval(-1)
        try await repository.savePersonalBest(older)
        try await repository.savePersonalBest(tied)
        #expect(try await repository.fetchPersonalBest(milestoneID: milestoneID) == tied)
        try await repository.savePersonalBest(preferred)
        #expect(try await repository.fetchPersonalBest(milestoneID: milestoneID) == preferred)
        #expect(try await repository.fetchPersonalBests().count == 2)
        #expect(try await repository.fetchPersonalBest(milestoneID: UUID()) == nil)
        try await repository.deletePersonalBest(id: preferred.id)
        #expect(try await repository.fetchPersonalBest(milestoneID: milestoneID) == tied)
        try await repository.deletePersonalBest(id: preferred.id)
        try await repository.deletePersonalBest(id: tied.id)
        #expect(try await repository.fetchPersonalBest(milestoneID: milestoneID) == nil)
        #expect(try await repository.fetchPersonalBests().isEmpty)
    }
}
