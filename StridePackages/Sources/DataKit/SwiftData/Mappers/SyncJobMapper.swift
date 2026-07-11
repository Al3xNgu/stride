import Foundation
import DomainKit

/// Bidirectional mapping between `SyncJob` and `SyncJobModel`.
public enum SyncJobMapper {
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    /// Builds a brand-new `SyncJobModel` from `syncJob`. Does not set
    /// `model.workout` — callers attach the owning `WorkoutModel` themselves
    /// (a mapper has no `ModelContext`/fetch access).
    public static func toModel(_ syncJob: SyncJob) throws -> SyncJobModel {
        SyncJobModel(
            id: syncJob.id,
            workoutID: syncJob.workoutID,
            stateData: try encodeState(syncJob.state),
            createdAt: syncJob.createdAt,
            updatedAt: syncJob.updatedAt,
            planIdentifier: syncJob.planIdentifier,
            scheduledDate: syncJob.scheduledDate,
            attemptCount: syncJob.attemptCount
        )
    }

    /// Updates `model`'s fields from `syncJob`. Does not touch
    /// `model.workout`.
    public static func apply(_ syncJob: SyncJob, to model: SyncJobModel) throws {
        model.workoutID = syncJob.workoutID
        model.stateData = try encodeState(syncJob.state)
        model.createdAt = syncJob.createdAt
        model.updatedAt = syncJob.updatedAt
        model.planIdentifier = syncJob.planIdentifier
        model.scheduledDate = syncJob.scheduledDate
        model.attemptCount = syncJob.attemptCount
    }

    /// Maps `model` back to a domain `SyncJob`, decoding its persisted state.
    public static func toDomain(_ model: SyncJobModel) throws -> SyncJob {
        let state: SyncJobState
        do {
            state = try decoder.decode(SyncJobState.self, from: model.stateData)
        } catch {
            throw DataKitError.corruptedSyncState(syncJobID: model.id, reason: String(describing: error))
        }
        return SyncJob(
            id: model.id,
            workoutID: model.workoutID,
            state: state,
            createdAt: model.createdAt,
            updatedAt: model.updatedAt,
            planIdentifier: model.planIdentifier,
            scheduledDate: model.scheduledDate,
            attemptCount: model.attemptCount
        )
    }

    private static func encodeState(_ state: SyncJobState) throws -> Data {
        do {
            return try encoder.encode(state)
        } catch {
            throw DataKitError.encodingFailed(reason: String(describing: error))
        }
    }
}
