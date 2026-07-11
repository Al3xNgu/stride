import Testing
import Foundation
import SwiftData
import DomainKit
@testable import DataKit

/// SyncJob CRUD, filtering, and `fetchLatestSyncJob` ordering for
/// `SwiftDataWorkoutRepository` (split from
/// `SwiftDataWorkoutRepositoryTests` to respect `type_body_length`), backed
/// by an in-memory `ModelContainer` per test.
@Suite("SwiftDataWorkoutRepository — SyncJobs")
struct SwiftDataWorkoutRepositorySyncJobTests {
    private func makeRepository() throws -> SwiftDataWorkoutRepository {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: WorkoutModel.self,
            WorkoutSegmentModel.self,
            SyncJobModel.self,
            CompletedRunModel.self,
            SplitModel.self,
            PersonalBestModel.self,
            configurations: configuration
        )
        return SwiftDataWorkoutRepository(modelContainer: container)
    }

    private func makeWorkout(id: UUID = UUID(), name: String = "Easy Run") -> Workout {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        return Workout(id: id, name: name, segments: [], createdAt: now, updatedAt: now)
    }

    private func makeSyncJob(
        id: UUID = UUID(),
        workoutID: UUID,
        state: SyncJobState = .draft,
        updatedAt: Date = Date(timeIntervalSince1970: 1_700_000_000),
        createdAt: Date? = nil
    ) -> SyncJob {
        SyncJob(id: id, workoutID: workoutID, state: state, createdAt: createdAt ?? updatedAt, updatedAt: updatedAt)
    }

    @Test("saveSyncJob(_:) then fetchSyncJob(id:) round-trips")
    func saveSyncJobThenFetchRoundTrips() async throws {
        let repository = try makeRepository()
        let workout = makeWorkout()
        try await repository.save(workout)
        let job = makeSyncJob(workoutID: workout.id, state: .failed(.transient(description: "timed out")))
        try await repository.saveSyncJob(job)
        let fetched = try await repository.fetchSyncJob(id: job.id)
        #expect(fetched == job)
    }

    @Test("fetchSyncJob(id:) returns nil for an id that was never saved")
    func fetchSyncJobUnknownIDReturnsNil() async throws {
        let repository = try makeRepository()
        let fetched = try await repository.fetchSyncJob(id: UUID())
        #expect(fetched == nil)
    }

    @Test("saveSyncJob(_:) with an existing id replaces rather than duplicating")
    func saveSyncJobUpsertsByID() async throws {
        let repository = try makeRepository()
        let workout = makeWorkout()
        try await repository.save(workout)
        let id = UUID()
        try await repository.saveSyncJob(makeSyncJob(id: id, workoutID: workout.id, state: .draft))
        try await repository.saveSyncJob(makeSyncJob(id: id, workoutID: workout.id, state: .synced))
        let jobs = try await repository.fetchSyncJobs(workoutID: workout.id)
        #expect(jobs.count == 1)
        #expect(jobs.first?.state == .synced)
    }

    @Test("saveSyncJob(_:) succeeds even when no workout exists yet for workoutID")
    func saveSyncJobWithoutWorkoutSucceeds() async throws {
        let repository = try makeRepository()
        let job = makeSyncJob(workoutID: UUID())
        try await repository.saveSyncJob(job)
        let fetched = try await repository.fetchSyncJob(id: job.id)
        #expect(fetched == job)
    }

    @Test("fetchSyncJobs(workoutID:) returns only jobs for that workout")
    func fetchSyncJobsFiltersByWorkoutID() async throws {
        let repository = try makeRepository()
        let workoutA = makeWorkout()
        let workoutB = makeWorkout()
        try await repository.save(workoutA)
        try await repository.save(workoutB)
        let jobA = makeSyncJob(workoutID: workoutA.id)
        let jobB = makeSyncJob(workoutID: workoutB.id)
        try await repository.saveSyncJob(jobA)
        try await repository.saveSyncJob(jobB)
        let jobsForA = try await repository.fetchSyncJobs(workoutID: workoutA.id)
        #expect(jobsForA == [jobA])
    }

    @Test("fetchLatestSyncJob(workoutID:) returns the job with the greatest updatedAt")
    func fetchLatestSyncJobOrdersByUpdatedAt() async throws {
        let repository = try makeRepository()
        let workout = makeWorkout()
        try await repository.save(workout)
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let older = makeSyncJob(workoutID: workout.id, state: .pending, updatedAt: base)
        let newer = makeSyncJob(workoutID: workout.id, state: .synced, updatedAt: base.addingTimeInterval(3_600))
        try await repository.saveSyncJob(older)
        try await repository.saveSyncJob(newer)
        let latest = try await repository.fetchLatestSyncJob(workoutID: workout.id)
        #expect(latest == newer)
    }

    @Test("fetchLatestSyncJob(workoutID:) returns nil when the workout has never been synced")
    func fetchLatestSyncJobReturnsNilWhenNeverSynced() async throws {
        let repository = try makeRepository()
        let workout = makeWorkout()
        try await repository.save(workout)
        let latest = try await repository.fetchLatestSyncJob(workoutID: workout.id)
        #expect(latest == nil)
    }

    @Test("fetchLatestSyncJob(workoutID:) picks the max updatedAt regardless of insertion order")
    func fetchLatestSyncJobIgnoresInsertionOrder() async throws {
        let repository = try makeRepository()
        let workout = makeWorkout()
        try await repository.save(workout)
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        // Deliberately insert out of chronological order: the middle-aged
        // job first, then the truly-latest job, then the oldest job last —
        // so a bug that returns "last inserted" or "first inserted" instead
        // of "max updatedAt" would be caught.
        let middle = makeSyncJob(workoutID: workout.id, state: .pending, updatedAt: base.addingTimeInterval(3_600))
        let latestJob = makeSyncJob(workoutID: workout.id, state: .synced, updatedAt: base.addingTimeInterval(7_200))
        let oldest = makeSyncJob(workoutID: workout.id, state: .draft, updatedAt: base)
        try await repository.saveSyncJob(middle)
        try await repository.saveSyncJob(latestJob)
        try await repository.saveSyncJob(oldest)

        let latest = try await repository.fetchLatestSyncJob(workoutID: workout.id)
        #expect(latest == latestJob)
    }

    @Test("fetchLatestSyncJob(workoutID:) breaks equal-updatedAt ties by newest createdAt, deterministically")
    func fetchLatestSyncJobBreaksTiesByCreatedAt() async throws {
        let repository = try makeRepository()
        let workout = makeWorkout()
        try await repository.save(workout)
        let sharedUpdatedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let olderCreation = makeSyncJob(
            workoutID: workout.id, state: .pending,
            updatedAt: sharedUpdatedAt, createdAt: sharedUpdatedAt.addingTimeInterval(-7_200)
        )
        let newerCreation = makeSyncJob(
            workoutID: workout.id, state: .synced,
            updatedAt: sharedUpdatedAt, createdAt: sharedUpdatedAt.addingTimeInterval(-3_600)
        )
        // Insert the expected winner first so "last inserted wins" can't
        // masquerade as a correct tie-break.
        try await repository.saveSyncJob(newerCreation)
        try await repository.saveSyncJob(olderCreation)

        let latest = try await repository.fetchLatestSyncJob(workoutID: workout.id)
        #expect(latest == newerCreation)
    }

    @Test("delete(id:) removes a job that was saved before its workout existed (nil relation)")
    func deleteSweepsJobsSavedBeforeTheirWorkout() async throws {
        let repository = try makeRepository()
        let workoutID = UUID()
        // Job first: SyncJobModel.workout stays nil, so the relationship
        // cascade alone can't reach it — the denormalized sweep must.
        let orphan = makeSyncJob(workoutID: workoutID)
        try await repository.saveSyncJob(orphan)
        try await repository.save(makeWorkout(id: workoutID))

        try await repository.delete(id: workoutID)

        let fetched = try await repository.fetchSyncJob(id: orphan.id)
        #expect(fetched == nil)
        let remaining = try await repository.fetchSyncJobs(workoutID: workoutID)
        #expect(remaining.isEmpty)
    }
}
