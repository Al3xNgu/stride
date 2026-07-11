import Testing
import Foundation
import DomainKit
import TestSupport

/// `PersonalBest` CRUD, upsert-by-id identity, the deterministic
/// "current record" resolution contract documented on
/// `RunHistoryRepository.fetchPersonalBest(milestoneID:)`, and
/// `errorToThrow` injection for `FakeRunHistoryRepository`.
///
/// Split into its own suite (separate from `FakeRunHistoryRepositoryTests`)
/// to keep each file's type body under SwiftLint's `type_body_length`
/// threshold.
@Suite("FakeRunHistoryRepository — PersonalBest")
struct FakeRunHistoryPersonalBestTests {
    private func makePersonalBest(
        id: UUID = UUID(),
        milestoneID: UUID,
        elapsedSeconds: TimeInterval = 1_200,
        completedRunID: UUID = UUID(),
        achievedAt: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) -> PersonalBest {
        PersonalBest(
            id: id,
            milestoneID: milestoneID,
            elapsedSeconds: elapsedSeconds,
            completedRunID: completedRunID,
            achievedAt: achievedAt
        )
    }

    // MARK: - CRUD

    @Test("savePersonalBest(_:) then fetchPersonalBest(milestoneID:) round-trips")
    func savePersonalBestThenFetchRoundTrips() async throws {
        let repository = FakeRunHistoryRepository()
        let milestoneID = UUID()
        let personalBest = makePersonalBest(milestoneID: milestoneID)
        try await repository.savePersonalBest(personalBest)
        let fetched = try await repository.fetchPersonalBest(milestoneID: milestoneID)
        #expect(fetched == personalBest)
    }

    @Test("savePersonalBest(_:) with an existing id replaces rather than duplicating")
    func savePersonalBestUpsertsByID() async throws {
        let repository = FakeRunHistoryRepository()
        let id = UUID()
        let milestoneID = UUID()
        try await repository.savePersonalBest(
            makePersonalBest(id: id, milestoneID: milestoneID, elapsedSeconds: 1_300)
        )
        try await repository.savePersonalBest(
            makePersonalBest(id: id, milestoneID: milestoneID, elapsedSeconds: 1_200)
        )
        let all = try await repository.fetchPersonalBests()
        #expect(all.count == 1)
        #expect(all.first?.elapsedSeconds == 1_200)
    }

    @Test("fetchPersonalBest(milestoneID:) returns nil when no record has been set")
    func fetchPersonalBestReturnsNilWhenUnset() async throws {
        let repository = FakeRunHistoryRepository()
        let fetched = try await repository.fetchPersonalBest(milestoneID: UUID())
        #expect(fetched == nil)
    }

    @Test("deletePersonalBest(id:) removes the record")
    func deletePersonalBestRemovesRecord() async throws {
        let repository = FakeRunHistoryRepository()
        let milestoneID = UUID()
        let personalBest = makePersonalBest(milestoneID: milestoneID)
        try await repository.savePersonalBest(personalBest)
        try await repository.deletePersonalBest(id: personalBest.id)
        let fetched = try await repository.fetchPersonalBest(milestoneID: milestoneID)
        #expect(fetched == nil)
    }

    @Test("deletePersonalBest(id:) for an unknown id does not throw")
    func deletePersonalBestUnknownIDDoesNotThrow() async throws {
        let repository = FakeRunHistoryRepository()
        try await repository.deletePersonalBest(id: UUID())
    }

    // MARK: - Deterministic "current" resolution

    /// `PersonalBest` has no superseded flag — a caller can legally store two
    /// `PersonalBest`s that share the same `milestoneID` (e.g. a current
    /// record plus a superseded one). `fetchPersonalBests()` must still
    /// surface every record (so history/archive reads are not lossy), while
    /// `fetchPersonalBest(milestoneID:)` resolves deterministically to the
    /// port's documented "current" definition: lowest `elapsedSeconds` wins.
    @Test("fetchPersonalBests() surfaces every shared-milestone record; fetchPersonalBest resolves to the fastest")
    func fetchPersonalBestsSurfacesRecordsSharingAMilestone() async throws {
        let repository = FakeRunHistoryRepository()
        let milestoneID = UUID()
        let superseded = makePersonalBest(milestoneID: milestoneID, elapsedSeconds: 1_300)
        let current = makePersonalBest(milestoneID: milestoneID, elapsedSeconds: 1_200)
        try await repository.savePersonalBest(superseded)
        try await repository.savePersonalBest(current)

        let all = try await repository.fetchPersonalBests()
        #expect(Set(all.map(\.id)) == Set([superseded.id, current.id]))

        // The faster (lower elapsedSeconds) record is deterministically "current".
        let winner = try await repository.fetchPersonalBest(milestoneID: milestoneID)
        #expect(winner?.id == current.id)
    }

    @Test("fetchPersonalBest(milestoneID:) breaks an elapsedSeconds tie by the latest achievedAt")
    func fetchPersonalBestBreaksElapsedTiesByLatestAchievedAt() async throws {
        let repository = FakeRunHistoryRepository()
        let milestoneID = UUID()
        let older = makePersonalBest(
            milestoneID: milestoneID,
            elapsedSeconds: 1_200,
            achievedAt: Date(timeIntervalSince1970: 1_000)
        )
        let newer = makePersonalBest(
            milestoneID: milestoneID,
            elapsedSeconds: 1_200,
            achievedAt: Date(timeIntervalSince1970: 2_000)
        )
        try await repository.savePersonalBest(older)
        try await repository.savePersonalBest(newer)

        let winner = try await repository.fetchPersonalBest(milestoneID: milestoneID)
        #expect(winner?.id == newer.id)
    }

    @Test("fetchPersonalBest(milestoneID:) breaks a full tie by id.uuidString ascending")
    func fetchPersonalBestBreaksFullTiesByIDAscending() async throws {
        let repository = FakeRunHistoryRepository()
        let milestoneID = UUID()
        let achievedAt = Date(timeIntervalSince1970: 1_000)
        let lowerID = makePersonalBest(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001") ?? UUID(),
            milestoneID: milestoneID,
            elapsedSeconds: 1_200,
            achievedAt: achievedAt
        )
        let higherID = makePersonalBest(
            id: UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF") ?? UUID(),
            milestoneID: milestoneID,
            elapsedSeconds: 1_200,
            achievedAt: achievedAt
        )
        try await repository.savePersonalBest(higherID)
        try await repository.savePersonalBest(lowerID)

        let winner = try await repository.fetchPersonalBest(milestoneID: milestoneID)
        #expect(winner?.id == lowerID.id)
    }

    // MARK: - errorToThrow

    @Test("errorToThrow makes every PersonalBest-throwing method throw the injected error")
    func errorToThrowAffectsPersonalBestMethods() async {
        let repository = FakeRunHistoryRepository()
        let personalBest = makePersonalBest(milestoneID: UUID())
        repository.errorToThrow = RunHistoryRepositoryError.underlying("HK unavailable")

        await #expect(throws: RunHistoryRepositoryError.underlying("HK unavailable")) {
            try await repository.savePersonalBest(personalBest)
        }
        await #expect(throws: RunHistoryRepositoryError.underlying("HK unavailable")) {
            _ = try await repository.fetchPersonalBests()
        }
        await #expect(throws: RunHistoryRepositoryError.underlying("HK unavailable")) {
            _ = try await repository.fetchPersonalBest(milestoneID: UUID())
        }
        await #expect(throws: RunHistoryRepositoryError.underlying("HK unavailable")) {
            try await repository.deletePersonalBest(id: personalBest.id)
        }
    }

    @Test("Clearing errorToThrow restores normal PersonalBest behavior")
    func clearingErrorRestoresBehavior() async throws {
        let repository = FakeRunHistoryRepository()
        let milestoneID = UUID()
        let personalBest = makePersonalBest(milestoneID: milestoneID)
        repository.errorToThrow = RunHistoryRepositoryError.underlying("HK unavailable")
        repository.errorToThrow = nil

        try await repository.savePersonalBest(personalBest)
        let fetched = try await repository.fetchPersonalBest(milestoneID: milestoneID)
        #expect(fetched == personalBest)
    }
}
