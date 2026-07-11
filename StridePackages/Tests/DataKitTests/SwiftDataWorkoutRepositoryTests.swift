import Testing
import Foundation
import SwiftData
import DomainKit
@testable import DataKit

/// CRUD round-trips, upsert-by-id identity, cascade-delete, and
/// `fetchLatestSyncJob` ordering for `SwiftDataWorkoutRepository`, backed by
/// an in-memory (`isStoredInMemoryOnly: true`) `ModelContainer` per test.
@Suite("SwiftDataWorkoutRepository")
struct SwiftDataWorkoutRepositoryTests {
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

    private func makeWorkout(
        id: UUID = UUID(),
        name: String = "Easy Run",
        segments: [WorkoutSegment] = []
    ) -> Workout {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        return Workout(id: id, name: name, segments: segments, createdAt: now, updatedAt: now)
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

    // MARK: - Workout CRUD

    @Test("save(_:) then fetch(id:) round-trips a workout")
    func saveThenFetchRoundTrips() async throws {
        let repository = try makeRepository()
        let workout = makeWorkout()
        try await repository.save(workout)
        let fetched = try await repository.fetch(id: workout.id)
        #expect(fetched == workout)
    }

    @Test("fetch(id:) returns nil for an id that was never saved")
    func fetchUnknownIDReturnsNil() async throws {
        let repository = try makeRepository()
        let fetched = try await repository.fetch(id: UUID())
        #expect(fetched == nil)
    }

    @Test("save(_:) with an existing id replaces (upserts) rather than duplicating")
    func saveUpsertsByID() async throws {
        let repository = try makeRepository()
        let id = UUID()
        try await repository.save(makeWorkout(id: id, name: "Original"))
        try await repository.save(makeWorkout(id: id, name: "Renamed"))
        let all = try await repository.fetchAll()
        #expect(all.count == 1)
        #expect(all.first?.name == "Renamed")
    }

    @Test("save(_:) persists segments including an interval block, round-tripping in order")
    func saveRoundTripsSegments() async throws {
        let repository = try makeRepository()
        let warmUp = WorkoutSegment.step(SegmentStep(intent: .warmUp, goal: .duration(seconds: 600)))
        let block = WorkoutSegment.intervalBlock(
            steps: [
                IntervalStep(
                    purpose: .work,
                    step: SegmentStep(intent: .work, goal: .distance(meters: 400), target: .pace(range: 0.2...0.25))
                ),
                IntervalStep(purpose: .recovery, step: SegmentStep(intent: .rest, goal: .duration(seconds: 60)))
            ],
            repetitions: 8
        )
        let workout = makeWorkout(segments: [warmUp, block])
        try await repository.save(workout)
        let fetched = try await repository.fetch(id: workout.id)
        #expect(fetched?.segments == [warmUp, block])
    }

    @Test("save(_:) then fetch(id:) preserves the order of five mixed segments")
    func saveRoundTripsFiveSegmentsInOrder() async throws {
        let repository = try makeRepository()
        let segments: [WorkoutSegment] = [
            .step(SegmentStep(intent: .warmUp, goal: .duration(seconds: 600))),
            .step(SegmentStep(intent: .easy, goal: .distance(meters: 1_000))),
            .intervalBlock(
                steps: [IntervalStep(purpose: .work, step: SegmentStep(intent: .work, goal: .duration(seconds: 120)))],
                repetitions: 6
            ),
            .step(SegmentStep(intent: .tempo, goal: .distance(meters: 2_000))),
            .step(SegmentStep(intent: .coolDown, goal: .duration(seconds: 300)))
        ]
        let workout = makeWorkout(segments: segments)
        try await repository.save(workout)
        let fetched = try await repository.fetch(id: workout.id)
        #expect(fetched?.segments == segments)
    }

    @Test("save(_:) replacing segments does not leak orphaned segment rows")
    func saveReplacesSegmentsWithoutLeaking() async throws {
        let repository = try makeRepository()
        let id = UUID()
        let first = makeWorkout(id: id, segments: [.step(SegmentStep(intent: .easy, goal: .open))])
        try await repository.save(first)
        let second = makeWorkout(
            id: id,
            segments: [
                .step(SegmentStep(intent: .tempo, goal: .distance(meters: 2_000))),
                .step(SegmentStep(intent: .coolDown, goal: .duration(seconds: 300)))
            ]
        )
        try await repository.save(second)
        let fetched = try await repository.fetch(id: id)
        #expect(fetched?.segments == second.segments)
    }

    @Test("delete(id:) removes the workout")
    func deleteRemovesWorkout() async throws {
        let repository = try makeRepository()
        let workout = makeWorkout()
        try await repository.save(workout)
        try await repository.delete(id: workout.id)
        let fetched = try await repository.fetch(id: workout.id)
        #expect(fetched == nil)
    }

    @Test("delete(id:) for an unknown id is a no-op, not an error")
    func deleteUnknownIDIsNoOp() async throws {
        let repository = try makeRepository()
        try await repository.delete(id: UUID())
    }

    @Test("delete(id:) cascade-deletes every SyncJob recorded for that workout")
    func deleteCascadesSyncJobs() async throws {
        let repository = try makeRepository()
        let workout = makeWorkout()
        try await repository.save(workout)
        let job1 = makeSyncJob(workoutID: workout.id)
        let job2 = makeSyncJob(workoutID: workout.id)
        try await repository.saveSyncJob(job1)
        try await repository.saveSyncJob(job2)

        try await repository.delete(id: workout.id)

        let fetchedJob1 = try await repository.fetchSyncJob(id: job1.id)
        let fetchedJob2 = try await repository.fetchSyncJob(id: job2.id)
        #expect(fetchedJob1 == nil)
        #expect(fetchedJob2 == nil)
        let remaining = try await repository.fetchSyncJobs(workoutID: workout.id)
        #expect(remaining.isEmpty)
    }

    @Test("delete(id:) for workout A leaves workout B's own sync jobs intact")
    func deleteDoesNotCascadeAcrossUnrelatedWorkouts() async throws {
        let repository = try makeRepository()
        let workoutA = makeWorkout(name: "A")
        let workoutB = makeWorkout(name: "B")
        try await repository.save(workoutA)
        try await repository.save(workoutB)
        let jobA = makeSyncJob(workoutID: workoutA.id)
        let jobB = makeSyncJob(workoutID: workoutB.id)
        try await repository.saveSyncJob(jobA)
        try await repository.saveSyncJob(jobB)

        try await repository.delete(id: workoutA.id)

        let fetchedA = try await repository.fetch(id: workoutA.id)
        let fetchedB = try await repository.fetch(id: workoutB.id)
        #expect(fetchedA == nil)
        #expect(fetchedB == workoutB)
        let jobsForB = try await repository.fetchSyncJobs(workoutID: workoutB.id)
        #expect(jobsForB == [jobB])
        let fetchedJobA = try await repository.fetchSyncJob(id: jobA.id)
        #expect(fetchedJobA == nil)
    }

    // SyncJob CRUD / query tests live in SwiftDataWorkoutRepositorySyncJobTests
    // (split file, type_body_length). The cascade tests above stay here because
    // they exercise workout deletion.

    @Test("re-saving a workout with identical segment ids but an edited goal persists the edit")
    func resaveWithStableSegmentIDsPersistsEdits() async throws {
        let repository = try makeRepository()
        let workoutID = UUID()
        let stepID = UUID()
        // Same SegmentStep id across both saves: the replace-segments path
        // deletes and re-inserts a row with the same `.unique` id inside one
        // save() — the classic unique-constraint trap this test pins down.
        let original = makeWorkout(
            id: workoutID,
            segments: [.step(SegmentStep(id: stepID, intent: .tempo, goal: .distance(meters: 2_000)))]
        )
        try await repository.save(original)
        let edited = makeWorkout(
            id: workoutID,
            segments: [.step(SegmentStep(id: stepID, intent: .tempo, goal: .distance(meters: 3_000)))]
        )
        try await repository.save(edited)

        let fetched = try await repository.fetch(id: workoutID)
        #expect(fetched?.segments == edited.segments)
        let all = try await repository.fetchAll()
        #expect(all.count == 1)
    }

    @Test("re-saving with stable segment ids also works against an on-disk store")
    func resaveWithStableSegmentIDsPersistsEditsOnDisk() async throws {
        // The in-memory store historically tolerates delete+insert of the
        // same `.unique` id within one save() in cases where the on-disk
        // SQLite store throws a unique-constraint error — so this pattern
        // must be pinned against a real file-backed container too.
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("stride-resave-test-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: storeURL) }
        let container = try ModelContainer(
            for: WorkoutModel.self,
            WorkoutSegmentModel.self,
            SyncJobModel.self,
            CompletedRunModel.self,
            SplitModel.self,
            PersonalBestModel.self,
            configurations: ModelConfiguration(url: storeURL)
        )
        let repository = SwiftDataWorkoutRepository(modelContainer: container)

        let workoutID = UUID()
        let stepID = UUID()
        let original = makeWorkout(
            id: workoutID,
            segments: [.step(SegmentStep(id: stepID, intent: .tempo, goal: .distance(meters: 2_000)))]
        )
        try await repository.save(original)
        let edited = makeWorkout(
            id: workoutID,
            segments: [.step(SegmentStep(id: stepID, intent: .tempo, goal: .distance(meters: 3_000)))]
        )
        try await repository.save(edited)

        let fetched = try await repository.fetch(id: workoutID)
        #expect(fetched?.segments == edited.segments)
    }

    // MARK: - Concurrency sanity

    @Test("a burst of interleaved saves and fetches across many workouts completes without crashing or losing data")
    func concurrentSavesAndFetchesRemainConsistent() async throws {
        let repository = try makeRepository()
        let ids = (0..<20).map { _ in UUID() }

        await withTaskGroup(of: Void.self) { group in
            for id in ids {
                group.addTask {
                    try? await repository.save(self.makeWorkout(id: id, name: "Workout \(id)"))
                }
                group.addTask {
                    _ = try? await repository.fetch(id: id)
                }
                group.addTask {
                    _ = try? await repository.fetchAll()
                }
            }
        }

        let all = try await repository.fetchAll()
        #expect(all.count == ids.count)
        #expect(Set(all.map(\.id)) == Set(ids))
    }
}
