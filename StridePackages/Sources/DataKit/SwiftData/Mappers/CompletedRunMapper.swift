import Foundation
import DomainKit

/// Bidirectional mapping between `CompletedRun` and `CompletedRunModel`.
///
/// Unlike `WorkoutMapper`/`SyncJobMapper`, this mapper is total and
/// non-throwing: `CompletedRun`'s only nested type, `HeartRateSummary`, is a
/// plain two-optional-`Double` struct with no sum-type ambiguity to protect
/// against, so its fields are flattened directly onto `CompletedRunModel`.
public enum CompletedRunMapper {
    /// Builds a brand-new `CompletedRunModel` from `run`.
    public static func toModel(_ run: CompletedRun) -> CompletedRunModel {
        CompletedRunModel(
            id: run.id,
            date: run.date,
            distanceMeters: run.distanceMeters,
            durationSeconds: run.durationSeconds,
            averageBPM: run.heartRate.averageBPM,
            maxBPM: run.heartRate.maxBPM,
            source: run.source,
            workoutID: run.workoutID,
            notes: run.notes,
            isDeleted: run.isDeleted
        )
    }

    /// Updates `model`'s fields from `run`. Does not touch `model.splits`.
    public static func apply(_ run: CompletedRun, to model: CompletedRunModel) {
        model.date = run.date
        model.distanceMeters = run.distanceMeters
        model.durationSeconds = run.durationSeconds
        model.averageBPM = run.heartRate.averageBPM
        model.maxBPM = run.heartRate.maxBPM
        model.source = run.source
        model.workoutID = run.workoutID
        model.notes = run.notes
        model.deletedFlag = run.isDeleted
    }

    /// Maps `model` back to a domain `CompletedRun`.
    public static func toDomain(_ model: CompletedRunModel) -> CompletedRun {
        CompletedRun(
            id: model.id,
            date: model.date,
            distanceMeters: model.distanceMeters,
            durationSeconds: model.durationSeconds,
            heartRate: HeartRateSummary(averageBPM: model.averageBPM, maxBPM: model.maxBPM),
            source: model.source,
            workoutID: model.workoutID,
            notes: model.notes,
            isDeleted: model.deletedFlag
        )
    }
}
