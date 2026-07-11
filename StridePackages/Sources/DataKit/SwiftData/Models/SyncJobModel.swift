import Foundation
import SwiftData

/// SwiftData persistence for a `SyncJob` (`docs/ARCHITECTURE.md` §5/§7/§9.4).
///
/// `SyncJobState` carries associated values in its `.failed(SyncFailureReason)`
/// case, so — matching `WorkoutSegmentModel`'s rationale — the whole state is
/// `Codable`-encoded into `stateData` rather than flattened behind a
/// discriminator column, keeping the mapper total.
@Model
public final class SyncJobModel {
    @Attribute(.unique) public var id: UUID
    /// Denormalized copy of the owning workout's id, so sync jobs can be
    /// queried by `workoutID` (e.g. `fetchSyncJobs`/`fetchLatestSyncJob`)
    /// without a relationship traversal/join.
    public var workoutID: UUID
    /// The entire `SyncJobState` value, JSON-encoded.
    public var stateData: Data
    public var createdAt: Date
    public var updatedAt: Date
    public var planIdentifier: String?
    public var scheduledDate: Date?
    public var attemptCount: Int
    /// Inverse of `WorkoutModel.syncJobs`; cascade-deleted with the workout.
    public var workout: WorkoutModel?

    /// Creates a sync job row.
    public init(
        id: UUID,
        workoutID: UUID,
        stateData: Data,
        createdAt: Date,
        updatedAt: Date,
        planIdentifier: String? = nil,
        scheduledDate: Date? = nil,
        attemptCount: Int,
        workout: WorkoutModel? = nil
    ) {
        self.id = id
        self.workoutID = workoutID
        self.stateData = stateData
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.planIdentifier = planIdentifier
        self.scheduledDate = scheduledDate
        self.attemptCount = attemptCount
        self.workout = workout
    }
}
