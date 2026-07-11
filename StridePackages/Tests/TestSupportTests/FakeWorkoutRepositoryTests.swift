import Testing
import Foundation
import DomainKit
import TestSupport

/// CRUD round-trips, upsert-by-id identity, query behavior, and
/// `errorToThrow` injection for `FakeWorkoutRepository`.
@Suite("FakeWorkoutRepository")
struct FakeWorkoutRepositoryTests {
    private func makeWorkout(id: UUID = UUID(), name: String = "Easy Run") -> Workout {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        return Workout(id: id, name: name, createdAt: now, updatedAt: now)
    }

    private func makeSyncJob(
        id: UUID = UUID(),
        workoutID: UUID,
        state: SyncJobState = .draft,
        updatedAt: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) -> SyncJob {
        SyncJob(id: id, workoutID: workoutID, state: state, createdAt: updatedAt, updatedAt: updatedAt)
    }

    // MARK: - Workout CRUD

    @Test("save(_:) then fetch(id:) round-trips a workout")
    func saveThenFetchRoundTrips() async throws {
        let repository = FakeWorkoutRepository()
        let workout = makeWorkout()
        try await repository.save(workout)
        let fetched = try await repository.fetch(id: workout.id)
        #expect(fetched == workout)
    }

    @Test("fetch(id:) returns nil for an id that was never saved")
    func fetchUnknownIDReturnsNil() async throws {
        let repository = FakeWorkoutRepository()
        let fetched = try await repository.fetch(id: UUID())
        #expect(fetched == nil)
    }

    @Test("save(_:) with an existing id replaces (upserts) rather than duplicating")
    func saveUpsertsByID() async throws {
        let repository = FakeWorkoutRepository()
        let id = UUID()
        try await repository.save(makeWorkout(id: id, name: "Original"))
        try await repository.save(makeWorkout(id: id, name: "Renamed"))
        let all = try await repository.fetchAll()
        #expect(all.count == 1)
        #expect(all.first?.name == "Renamed")
    }

    @Test("fetchAll() returns every saved workout")
    func fetchAllReturnsEverySavedWorkout() async throws {
        let repository = FakeWorkoutRepository()
        let first = makeWorkout(name: "A")
        let second = makeWorkout(name: "B")
        try await repository.save(first)
        try await repository.save(second)
        let all = try await repository.fetchAll()
        #expect(Set(all.map(\.id)) == Set([first.id, second.id]))
    }

    @Test("delete(id:) removes a saved workout")
    func deleteRemovesWorkout() async throws {
        let repository = FakeWorkoutRepository()
        let workout = makeWorkout()
        try await repository.save(workout)
        try await repository.delete(id: workout.id)
        let fetched = try await repository.fetch(id: workout.id)
        #expect(fetched == nil)
    }

    @Test("delete(id:) for an id that was never saved does not throw")
    func deleteUnknownIDDoesNotThrow() async throws {
        let repository = FakeWorkoutRepository()
        try await repository.delete(id: UUID())
    }

    @Test("delete(id:) cascade-deletes every SyncJob recorded for that workout")
    func deleteCascadesSyncJobs() async throws {
        let repository = FakeWorkoutRepository()
        let workout = makeWorkout()
        try await repository.save(workout)
        try await repository.saveSyncJob(makeSyncJob(workoutID: workout.id))
        try await repository.saveSyncJob(makeSyncJob(workoutID: workout.id))

        try await repository.delete(id: workout.id)

        let jobs = try await repository.fetchSyncJobs(workoutID: workout.id)
        #expect(jobs.isEmpty)
    }

    @Test("delete(id:) does not affect SyncJobs belonging to a different workout")
    func deleteDoesNotCascadeUnrelatedWorkouts() async throws {
        let repository = FakeWorkoutRepository()
        let workoutA = makeWorkout()
        let workoutB = makeWorkout()
        try await repository.save(workoutA)
        try await repository.save(workoutB)
        let jobB = makeSyncJob(workoutID: workoutB.id)
        try await repository.saveSyncJob(makeSyncJob(workoutID: workoutA.id))
        try await repository.saveSyncJob(jobB)

        try await repository.delete(id: workoutA.id)

        let jobsForB = try await repository.fetchSyncJobs(workoutID: workoutB.id)
        #expect(jobsForB.map(\.id) == [jobB.id])
    }

    // MARK: - SyncJob CRUD

    @Test("saveSyncJob(_:) then fetchSyncJob(id:) round-trips a sync job")
    func saveSyncJobThenFetchRoundTrips() async throws {
        let repository = FakeWorkoutRepository()
        let job = makeSyncJob(workoutID: UUID())
        try await repository.saveSyncJob(job)
        let fetched = try await repository.fetchSyncJob(id: job.id)
        #expect(fetched == job)
    }

    @Test("saveSyncJob(_:) with an existing id replaces (upserts) rather than duplicating")
    func saveSyncJobUpsertsByID() async throws {
        let repository = FakeWorkoutRepository()
        let id = UUID()
        let workoutID = UUID()
        try await repository.saveSyncJob(makeSyncJob(id: id, workoutID: workoutID, state: .draft))
        try await repository.saveSyncJob(makeSyncJob(id: id, workoutID: workoutID, state: .pending))
        let jobs = try await repository.fetchSyncJobs(workoutID: workoutID)
        #expect(jobs.count == 1)
        #expect(jobs.first?.state == .pending)
    }

    @Test("fetchSyncJobs(workoutID:) only returns jobs for the given workout")
    func fetchSyncJobsFiltersByWorkoutID() async throws {
        let repository = FakeWorkoutRepository()
        let workoutA = UUID()
        let workoutB = UUID()
        let jobA = makeSyncJob(workoutID: workoutA)
        let jobB1 = makeSyncJob(workoutID: workoutB)
        let jobB2 = makeSyncJob(workoutID: workoutB)
        try await repository.saveSyncJob(jobA)
        try await repository.saveSyncJob(jobB1)
        try await repository.saveSyncJob(jobB2)

        let forA = try await repository.fetchSyncJobs(workoutID: workoutA)
        let forB = try await repository.fetchSyncJobs(workoutID: workoutB)
        #expect(forA.map(\.id) == [jobA.id])
        #expect(Set(forB.map(\.id)) == Set([jobB1.id, jobB2.id]))
    }

    @Test("fetchLatestSyncJob(workoutID:) returns nil when no job has ever been saved")
    func fetchLatestSyncJobReturnsNilWhenNone() async throws {
        let repository = FakeWorkoutRepository()
        let fetched = try await repository.fetchLatestSyncJob(workoutID: UUID())
        #expect(fetched == nil)
    }

    @Test("fetchLatestSyncJob(workoutID:) returns the job with the most recent updatedAt")
    func fetchLatestSyncJobReturnsMostRecentlyUpdated() async throws {
        let repository = FakeWorkoutRepository()
        let workoutID = UUID()
        let older = makeSyncJob(
            workoutID: workoutID,
            state: .draft,
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let newer = makeSyncJob(
            workoutID: workoutID,
            state: .synced,
            updatedAt: Date(timeIntervalSince1970: 200)
        )
        // Save out of chronological order to ensure the fake sorts by
        // updatedAt, not insertion order.
        try await repository.saveSyncJob(newer)
        try await repository.saveSyncJob(older)

        let latest = try await repository.fetchLatestSyncJob(workoutID: workoutID)
        #expect(latest?.id == newer.id)
    }

    // MARK: - errorToThrow

    @Test("errorToThrow makes every throwing method throw the injected error")
    func errorToThrowAffectsEveryMethod() async {
        let repository = FakeWorkoutRepository()
        let workout = makeWorkout()
        let job = makeSyncJob(workoutID: workout.id)
        repository.errorToThrow = WorkoutRepositoryError.underlying("db locked")

        await #expect(throws: WorkoutRepositoryError.underlying("db locked")) {
            try await repository.save(workout)
        }
        await #expect(throws: WorkoutRepositoryError.underlying("db locked")) {
            _ = try await repository.fetchAll()
        }
        await #expect(throws: WorkoutRepositoryError.underlying("db locked")) {
            _ = try await repository.fetch(id: workout.id)
        }
        await #expect(throws: WorkoutRepositoryError.underlying("db locked")) {
            try await repository.delete(id: workout.id)
        }
        await #expect(throws: WorkoutRepositoryError.underlying("db locked")) {
            try await repository.saveSyncJob(job)
        }
        await #expect(throws: WorkoutRepositoryError.underlying("db locked")) {
            _ = try await repository.fetchSyncJob(id: job.id)
        }
        await #expect(throws: WorkoutRepositoryError.underlying("db locked")) {
            _ = try await repository.fetchSyncJobs(workoutID: workout.id)
        }
        await #expect(throws: WorkoutRepositoryError.underlying("db locked")) {
            _ = try await repository.fetchLatestSyncJob(workoutID: workout.id)
        }
    }

    @Test("Clearing errorToThrow restores normal behavior")
    func clearingErrorRestoresBehavior() async throws {
        let repository = FakeWorkoutRepository()
        let workout = makeWorkout()
        repository.errorToThrow = WorkoutRepositoryError.underlying("db locked")
        repository.errorToThrow = nil

        try await repository.save(workout)
        let fetched = try await repository.fetch(id: workout.id)
        #expect(fetched == workout)
    }
}
