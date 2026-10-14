import Testing
import Foundation
import DomainKit
import TestSupport

/// CRUD round-trips, upsert-by-id identity, tombstone semantics, date-range
/// queries, splits persistence, and `errorToThrow` injection for
/// `FakeRunHistoryRepository`'s `CompletedRun`/`Split` surface.
///
/// `PersonalBest` coverage lives in a separate suite
/// (`FakeRunHistoryRepositoryPersonalBestTests`) to keep each file's type
/// body under SwiftLint's `type_body_length` threshold.
@Suite("FakeRunHistoryRepository")
struct FakeRunHistoryRepositoryTests {
    private func makeRun(
        id: UUID = UUID(),
        date: Date = Date(timeIntervalSince1970: 1_700_000_000),
        isDeleted: Bool = false
    ) -> CompletedRun {
        CompletedRun(
            id: id,
            date: date,
            distanceMeters: 5_000,
            durationSeconds: 1_500,
            source: "Apple Watch",
            isDeleted: isDeleted
        )
    }

    private func makeSplit(
        id: UUID = UUID(),
        runID: UUID,
        index: Int,
        distanceMeters: Double = 1_000,
        durationSeconds: TimeInterval = 300
    ) -> Split {
        Split(id: id, runID: runID, index: index, distanceMeters: distanceMeters, durationSeconds: durationSeconds)
    }

    // MARK: - CompletedRun CRUD

    @Test("upsert(_:) then fetch(id:) round-trips a run")
    func upsertThenFetchRoundTrips() async throws {
        let repository = FakeRunHistoryRepository()
        let run = makeRun()
        try await repository.upsert(run)
        let fetched = try await repository.fetch(id: run.id)
        #expect(fetched == run)
    }

    @Test("upsert(_:) with an existing id replaces rather than duplicating (HK UUID idempotency)")
    func upsertReplacesByID() async throws {
        let repository = FakeRunHistoryRepository()
        let id = UUID()
        try await repository.upsert(makeRun(id: id, date: Date(timeIntervalSince1970: 100)))
        try await repository.upsert(makeRun(id: id, date: Date(timeIntervalSince1970: 200)))
        let all = try await repository.fetchAll()
        #expect(all.count == 1)
        #expect(all.first?.date == Date(timeIntervalSince1970: 200))
    }

    @Test("fetch(id:) returns nil for an id that was never upserted")
    func fetchUnknownIDReturnsNil() async throws {
        let repository = FakeRunHistoryRepository()
        let fetched = try await repository.fetch(id: UUID())
        #expect(fetched == nil)
    }

    @Test("fetchAll() includes both tombstoned and non-tombstoned runs")
    func fetchAllIncludesTombstonedRuns() async throws {
        let repository = FakeRunHistoryRepository()
        let live = makeRun()
        let tombstoned = makeRun(isDeleted: true)
        try await repository.upsert(live)
        try await repository.upsert(tombstoned)
        let all = try await repository.fetchAll()
        #expect(Set(all.map(\.id)) == Set([live.id, tombstoned.id]))
    }

    // MARK: - Date-range query

    @Test("fetch(from:to:) includes runs exactly at both range boundaries")
    func fetchDateRangeIsInclusiveOfBoundaries() async throws {
        let repository = FakeRunHistoryRepository()
        let start = Date(timeIntervalSince1970: 1_000)
        let end = Date(timeIntervalSince1970: 2_000)
        let atStart = makeRun(date: start)
        let atEnd = makeRun(date: end)
        try await repository.upsert(atStart)
        try await repository.upsert(atEnd)

        let results = try await repository.fetch(from: start, to: end)
        #expect(Set(results.map(\.id)) == Set([atStart.id, atEnd.id]))
    }

    @Test("fetch(from:to:) excludes runs outside the range")
    func fetchDateRangeExcludesOutsideRuns() async throws {
        let repository = FakeRunHistoryRepository()
        let start = Date(timeIntervalSince1970: 1_000)
        let end = Date(timeIntervalSince1970: 2_000)
        let before = makeRun(date: Date(timeIntervalSince1970: 999))
        let after = makeRun(date: Date(timeIntervalSince1970: 2_001))
        let inside = makeRun(date: Date(timeIntervalSince1970: 1_500))
        try await repository.upsert(before)
        try await repository.upsert(after)
        try await repository.upsert(inside)

        let results = try await repository.fetch(from: start, to: end)
        #expect(results.map(\.id) == [inside.id])
    }

    // MARK: - Tombstone semantics

    @Test("markDeleted(id:) flags isDeleted but keeps the projection fetchable")
    func markDeletedFlagsButKeepsProjection() async throws {
        let repository = FakeRunHistoryRepository()
        let run = makeRun()
        try await repository.upsert(run)
        try await repository.markDeleted(id: run.id)
        let fetched = try await repository.fetch(id: run.id)
        #expect(fetched?.isDeleted == true)
        #expect(fetched?.id == run.id)
    }

    @Test("markDeleted(id:) for an unknown id throws runNotFound")
    func markDeletedUnknownIDThrows() async {
        let repository = FakeRunHistoryRepository()
        let missingID = UUID()
        await #expect(throws: RunHistoryRepositoryError.runNotFound(id: missingID)) {
            try await repository.markDeleted(id: missingID)
        }
    }

    // MARK: - Splits

    @Test("saveSplits(_:for:) then fetchSplits(runID:) round-trips, ordered by index")
    func saveSplitsThenFetchRoundTrips() async throws {
        let repository = FakeRunHistoryRepository()
        let runID = UUID()
        let splitTwo = makeSplit(runID: runID, index: 1)
        let splitOne = makeSplit(runID: runID, index: 0)
        // Save out of index order to ensure the fake sorts by index, not
        // insertion order.
        try await repository.saveSplits([splitTwo, splitOne], for: runID)

        let fetched = try await repository.fetchSplits(runID: runID)
        #expect(fetched == [splitOne, splitTwo])
    }

    @Test("saveSplits(_:for:) replaces the previously-saved splits for that run")
    func saveSplitsReplacesOnResave() async throws {
        let repository = FakeRunHistoryRepository()
        let runID = UUID()
        try await repository.saveSplits([makeSplit(runID: runID, index: 0)], for: runID)
        let replacement = [makeSplit(runID: runID, index: 0), makeSplit(runID: runID, index: 1)]
        try await repository.saveSplits(replacement, for: runID)

        let fetched = try await repository.fetchSplits(runID: runID)
        #expect(fetched == replacement)
    }

    @Test("fetchSplits(runID:) returns an empty array for a runID with no saved splits")
    func fetchSplitsReturnsEmptyForUnknownRunID() async throws {
        let repository = FakeRunHistoryRepository()
        let fetched = try await repository.fetchSplits(runID: UUID())
        #expect(fetched.isEmpty)
    }

    @Test("splitFetchError affects only fetchSplits(runID:)")
    func splitFetchErrorDoesNotAffectOtherRepositoryCalls() async throws {
        let repository = FakeRunHistoryRepository()
        let run = makeRun()
        try await repository.upsert(run)
        repository.splitFetchError = RunHistoryRepositoryError.underlying("Split store unavailable")

        #expect(try await repository.fetch(id: run.id) == run)
        await #expect(throws: RunHistoryRepositoryError.underlying("Split store unavailable")) {
            _ = try await repository.fetchSplits(runID: run.id)
        }
    }

    @Test("saveSplits(_:for:) for one run does not affect another run's splits")
    func saveSplitsIsolatedPerRun() async throws {
        let repository = FakeRunHistoryRepository()
        let runA = UUID()
        let runB = UUID()
        try await repository.saveSplits([makeSplit(runID: runA, index: 0)], for: runA)
        try await repository.saveSplits([makeSplit(runID: runB, index: 0)], for: runB)

        let fetchedA = try await repository.fetchSplits(runID: runA)
        let fetchedB = try await repository.fetchSplits(runID: runB)
        #expect(fetchedA.map(\.runID) == [runA])
        #expect(fetchedB.map(\.runID) == [runB])
    }

    // MARK: - errorToThrow

    @Test("errorToThrow makes every run/split-throwing method throw the injected error")
    func errorToThrowAffectsRunAndSplitMethods() async {
        let repository = FakeRunHistoryRepository()
        let run = makeRun()
        repository.errorToThrow = RunHistoryRepositoryError.underlying("HK unavailable")

        await #expect(throws: RunHistoryRepositoryError.underlying("HK unavailable")) {
            try await repository.upsert(run)
        }
        await #expect(throws: RunHistoryRepositoryError.underlying("HK unavailable")) {
            _ = try await repository.fetchAll()
        }
        await #expect(throws: RunHistoryRepositoryError.underlying("HK unavailable")) {
            _ = try await repository.fetch(id: run.id)
        }
        await #expect(throws: RunHistoryRepositoryError.underlying("HK unavailable")) {
            _ = try await repository.fetch(from: .distantPast, to: .distantFuture)
        }
        await #expect(throws: RunHistoryRepositoryError.underlying("HK unavailable")) {
            try await repository.markDeleted(id: run.id)
        }
        await #expect(throws: RunHistoryRepositoryError.underlying("HK unavailable")) {
            try await repository.saveSplits([makeSplit(runID: run.id, index: 0)], for: run.id)
        }
        await #expect(throws: RunHistoryRepositoryError.underlying("HK unavailable")) {
            _ = try await repository.fetchSplits(runID: run.id)
        }
    }

    @Test("Clearing errorToThrow restores normal behavior")
    func clearingErrorRestoresBehavior() async throws {
        let repository = FakeRunHistoryRepository()
        let run = makeRun()
        repository.errorToThrow = RunHistoryRepositoryError.underlying("HK unavailable")
        repository.errorToThrow = nil

        try await repository.upsert(run)
        let fetched = try await repository.fetch(id: run.id)
        #expect(fetched == run)
    }
}
