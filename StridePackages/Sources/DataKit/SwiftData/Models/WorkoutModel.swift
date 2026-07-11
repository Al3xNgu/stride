import Foundation
import SwiftData

/// SwiftData persistence for a `Workout` (`docs/ARCHITECTURE.md` §5/§9.4:
/// "Workout definitions, segments" and "SyncJobs + WorkoutKit plan IDs" both
/// live in SwiftData).
///
/// Both relationships cascade-delete with the workout: §5 documents
/// `Workout -> WorkoutSegment` as composition ("segments have no life
/// outside a workout"), and the `WorkoutRepository` port contract requires
/// `delete(id:)` to cascade-delete every `SyncJob` recorded for the workout
/// (`Workout -> SyncJob` is one-to-many history, also owned).
@Model
public final class WorkoutModel {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var notes: String
    /// Raw value of the domain `WorkoutActivity` enum.
    public var activityRaw: String
    public var createdAt: Date
    public var updatedAt: Date
    public var schemaVersion: Int

    @Relationship(deleteRule: .cascade, inverse: \WorkoutSegmentModel.workout)
    public var segments: [WorkoutSegmentModel]

    @Relationship(deleteRule: .cascade, inverse: \SyncJobModel.workout)
    public var syncJobs: [SyncJobModel]

    /// Creates a workout row.
    public init(
        id: UUID,
        name: String,
        notes: String,
        activityRaw: String,
        createdAt: Date,
        updatedAt: Date,
        schemaVersion: Int,
        segments: [WorkoutSegmentModel] = [],
        syncJobs: [SyncJobModel] = []
    ) {
        self.id = id
        self.name = name
        self.notes = notes
        self.activityRaw = activityRaw
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.schemaVersion = schemaVersion
        self.segments = segments
        self.syncJobs = syncJobs
    }
}
