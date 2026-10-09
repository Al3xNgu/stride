import Foundation
import SwiftData
import DomainKit

/// `WorkoutRepository` backed by SwiftData (`docs/ARCHITECTURE.md` §4/§9.4).
///
/// A `@ModelActor` per modern SwiftData concurrency practice: it owns and
/// serializes access to its own `ModelContext`, so a single instance is safe
/// to share across concurrent callers (the port requires `Sendable`, which
/// every actor satisfies). The macro synthesizes `modelExecutor`,
/// `modelContainer`, and an `init(modelContainer: ModelContainer)` — the
/// only way to construct this type is by injecting a `ModelContainer`
/// (CLAUDE.md rule 5: no singletons).
@ModelActor
public actor SwiftDataWorkoutRepository: WorkoutRepository {

    public func save(_ workout: Workout) async throws {
        try wrapping {
            if let existing = try fetchWorkoutModel(id: workout.id) {
                // Segments are fully replaced on every save (no per-segment
                // diffing): delete the old rows before the mapper creates
                // fresh ones, so replaced segments don't leak as orphans.
                for oldSegment in existing.segments {
                    modelContext.delete(oldSegment)
                }
                try WorkoutMapper.apply(workout, to: existing)
                for segment in existing.segments {
                    modelContext.insert(segment)
                }
            } else {
                let model = try WorkoutMapper.toModel(workout)
                modelContext.insert(model)
                for segment in model.segments {
                    modelContext.insert(segment)
                }
            }
            try modelContext.save()
        }
    }

    public func fetchAll() async throws -> [Workout] {
        try wrapping {
            try modelContext.fetch(FetchDescriptor<WorkoutModel>()).map(WorkoutMapper.toDomain)
        }
    }

    public func fetch(id: UUID) async throws -> Workout? {
        try wrapping {
            guard let model = try fetchWorkoutModel(id: id) else { return nil }
            return try WorkoutMapper.toDomain(model)
        }
    }

    public func delete(id: UUID) async throws {
        try wrapping {
            // Cascade-deletes every WorkoutSegmentModel and SyncJobModel for
            // this workout via the `.cascade` delete rules declared on
            // `WorkoutModel.segments`/`WorkoutModel.syncJobs`.
            guard let model = try fetchWorkoutModel(id: id) else { return }
            modelContext.delete(model)
            // The relationship cascade only reaches jobs linked via
            // `SyncJobModel.workout`. A job saved before its workout existed
            // has a nil relation, so sweep by the denormalized `workoutID`
            // too — the port contract promises no job survives its workout.
            let orphanDescriptor = FetchDescriptor<SyncJobModel>(
                predicate: #Predicate { $0.workoutID == id }
            )
            for orphan in try modelContext.fetch(orphanDescriptor) {
                modelContext.delete(orphan)
            }
            try modelContext.save()
        }
    }

    public func saveSyncJob(_ syncJob: SyncJob) async throws {
        try wrapping {
            if let existing = try fetchSyncJobModel(id: syncJob.id) {
                try SyncJobMapper.apply(syncJob, to: existing)
                // Keep the relationship in step with the denormalized
                // `workoutID` — a job saved before its workout existed gets
                // linked on its next save, so the `.cascade` rule reaches it.
                existing.workout = try fetchWorkoutModel(id: syncJob.workoutID)
            } else {
                let model = try SyncJobMapper.toModel(syncJob)
                model.workout = try fetchWorkoutModel(id: syncJob.workoutID)
                modelContext.insert(model)
            }
            try modelContext.save()
        }
    }

    public func fetchSyncJob(id: UUID) async throws -> SyncJob? {
        try wrapping {
            guard let model = try fetchSyncJobModel(id: id) else { return nil }
            return try SyncJobMapper.toDomain(model)
        }
    }

    public func fetchSyncJobs(workoutID: UUID) async throws -> [SyncJob] {
        try wrapping {
            let descriptor = FetchDescriptor<SyncJobModel>(
                predicate: #Predicate { $0.workoutID == workoutID }
            )
            return try modelContext.fetch(descriptor).map(SyncJobMapper.toDomain)
        }
    }

    public func fetchLatestSyncJob(workoutID: UUID) async throws -> SyncJob? {
        try wrapping {
            var descriptor = FetchDescriptor<SyncJobModel>(
                predicate: #Predicate { $0.workoutID == workoutID }
            )
            // Secondary key makes the winner deterministic when two jobs
            // share an `updatedAt` (the port contract only promises "max
            // updatedAt"; equal-instant ties fall to the newest-created).
            descriptor.sortBy = [
                SortDescriptor(\.updatedAt, order: .reverse),
                SortDescriptor(\.createdAt, order: .reverse)
            ]
            descriptor.fetchLimit = 1
            guard let model = try modelContext.fetch(descriptor).first else { return nil }
            return try SyncJobMapper.toDomain(model)
        }
    }

    // MARK: - Private helpers

    private func fetchWorkoutModel(id: UUID) throws -> WorkoutModel? {
        var descriptor = FetchDescriptor<WorkoutModel>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func fetchSyncJobModel(id: UUID) throws -> SyncJobModel? {
        var descriptor = FetchDescriptor<SyncJobModel>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    /// Runs `body`, translating any `DataKitError` (mapper decode failure)
    /// into `WorkoutRepositoryError.underlying`; passes an already-typed
    /// `WorkoutRepositoryError` through untouched; wraps every other error
    /// (SwiftData/Foundation) in `.underlying` too, so nothing above this
    /// repository ever observes a raw non-port error type.
    private func wrapping<T>(_ body: () throws -> T) throws -> T {
        modelContext.autosaveEnabled = false
        do {
            return try body()
        } catch let error as WorkoutRepositoryError {
            modelContext.rollback()
            throw error
        } catch let error as DataKitError {
            modelContext.rollback()
            throw WorkoutRepositoryError.underlying(error.description)
        } catch {
            modelContext.rollback()
            throw WorkoutRepositoryError.underlying(String(describing: error))
        }
    }
}
