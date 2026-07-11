import Foundation
import DomainKit

/// Bidirectional mapping between `Workout` and `WorkoutModel` (+ its
/// `WorkoutSegmentModel` children).
///
/// `toModel`/`apply` always mint brand-new `WorkoutSegmentModel` rows for
/// the caller to insert/attach; callers that are updating an existing
/// `WorkoutModel` are responsible for deleting its previous segment rows
/// from the `ModelContext` first (a mapper has no `ModelContext` access, so
/// deletion is the repository's job — see `SwiftDataWorkoutRepository`).
public enum WorkoutMapper {
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    /// Builds a brand-new `WorkoutModel` (with freshly-encoded segment rows)
    /// from `workout`.
    public static func toModel(_ workout: Workout) throws -> WorkoutModel {
        let model = WorkoutModel(
            id: workout.id,
            name: workout.name,
            notes: workout.notes,
            activityRaw: workout.activity.rawValue,
            createdAt: workout.createdAt,
            updatedAt: workout.updatedAt,
            schemaVersion: workout.schemaVersion
        )
        model.segments = try segmentModels(for: workout.segments, workout: model)
        return model
    }

    /// Updates `model`'s scalar fields and replaces `model.segments` with
    /// freshly-encoded rows for `workout`. Does not touch `model.syncJobs` —
    /// sync jobs are saved independently via `SyncJobMapper`/`saveSyncJob`.
    public static func apply(_ workout: Workout, to model: WorkoutModel) throws {
        model.name = workout.name
        model.notes = workout.notes
        model.activityRaw = workout.activity.rawValue
        model.createdAt = workout.createdAt
        model.updatedAt = workout.updatedAt
        model.schemaVersion = workout.schemaVersion
        model.segments = try segmentModels(for: workout.segments, workout: model)
    }

    /// Maps `model` back to a domain `Workout`, decoding every segment row
    /// and restoring the original order via `WorkoutSegmentModel.order`.
    public static func toDomain(_ model: WorkoutModel) throws -> Workout {
        guard let activity = WorkoutActivity(rawValue: model.activityRaw) else {
            throw DataKitError.corruptedWorkout(
                workoutID: model.id,
                reason: "unrecognized activity raw value: \(model.activityRaw)"
            )
        }
        let segments = try model.segments
            .sorted { $0.order < $1.order }
            .map { try decodeSegment($0, workoutID: model.id) }
        return Workout(
            id: model.id,
            name: model.name,
            notes: model.notes,
            activity: activity,
            segments: segments,
            createdAt: model.createdAt,
            updatedAt: model.updatedAt,
            schemaVersion: model.schemaVersion
        )
    }

    private static func segmentModels(
        for segments: [WorkoutSegment],
        workout: WorkoutModel
    ) throws -> [WorkoutSegmentModel] {
        try segments.enumerated().map { order, segment in
            let data: Data
            do {
                data = try encoder.encode(segment)
            } catch {
                throw DataKitError.encodingFailed(reason: String(describing: error))
            }
            return WorkoutSegmentModel(id: segment.id, order: order, segmentData: data, workout: workout)
        }
    }

    private static func decodeSegment(_ model: WorkoutSegmentModel, workoutID: UUID) throws -> WorkoutSegment {
        do {
            return try decoder.decode(WorkoutSegment.self, from: model.segmentData)
        } catch {
            throw DataKitError.corruptedWorkout(workoutID: workoutID, reason: String(describing: error))
        }
    }
}
