import DomainKit
import Foundation

/// An in-memory `WorkoutRepository` fake.
///
/// Backed by plain dictionaries keyed by id, with an injectable
/// `errorToThrow` that every method checks first (CLAUDE.md rule 5).
///
/// Not internally synchronized: intended for single-threaded test usage.
public final class FakeWorkoutRepository: WorkoutRepository, @unchecked Sendable {
    /// Backing storage for workouts, keyed by `Workout.id`.
    public var workoutsByID: [UUID: Workout]
    /// Backing storage for sync jobs, keyed by `SyncJob.id`.
    public var syncJobsByID: [UUID: SyncJob]
    /// When set, every call throws this error instead of succeeding.
    public var errorToThrow: Error?

    /// Creates a fake workout repository pre-seeded with `workouts` and
    /// `syncJobs`.
    public init(workouts: [Workout] = [], syncJobs: [SyncJob] = []) {
        self.workoutsByID = Dictionary(uniqueKeysWithValues: workouts.map { ($0.id, $0) })
        self.syncJobsByID = Dictionary(uniqueKeysWithValues: syncJobs.map { ($0.id, $0) })
    }

    public func save(_ workout: Workout) async throws {
        if let errorToThrow {
            throw errorToThrow
        }
        workoutsByID[workout.id] = workout
    }

    public func fetchAll() async throws -> [Workout] {
        if let errorToThrow {
            throw errorToThrow
        }
        return Array(workoutsByID.values)
    }

    public func fetch(id: UUID) async throws -> Workout? {
        if let errorToThrow {
            throw errorToThrow
        }
        return workoutsByID[id]
    }

    public func delete(id: UUID) async throws {
        if let errorToThrow {
            throw errorToThrow
        }
        workoutsByID.removeValue(forKey: id)
        syncJobsByID = syncJobsByID.filter { $0.value.workoutID != id }
    }

    public func saveSyncJob(_ syncJob: SyncJob) async throws {
        if let errorToThrow {
            throw errorToThrow
        }
        syncJobsByID[syncJob.id] = syncJob
    }

    public func fetchSyncJob(id: UUID) async throws -> SyncJob? {
        if let errorToThrow {
            throw errorToThrow
        }
        return syncJobsByID[id]
    }

    public func fetchSyncJobs(workoutID: UUID) async throws -> [SyncJob] {
        if let errorToThrow {
            throw errorToThrow
        }
        return syncJobsByID.values.filter { $0.workoutID == workoutID }
    }

    public func fetchLatestSyncJob(workoutID: UUID) async throws -> SyncJob? {
        if let errorToThrow {
            throw errorToThrow
        }
        return syncJobsByID.values
            .filter { $0.workoutID == workoutID }
            .max { $0.updatedAt < $1.updatedAt }
    }
}
