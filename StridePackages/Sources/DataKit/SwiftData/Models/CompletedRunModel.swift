import Foundation
import SwiftData

/// SwiftData persistence for a `CompletedRun` projection
/// (`docs/ARCHITECTURE.md` §5/§8/§9.4: "CompletedRun projections, splits,
/// PRs, HK anchors" — cache/derived, rebuildable from HealthKit).
@Model
public final class CompletedRunModel {
    /// Matches the source `HKWorkout`'s UUID, per the domain entity.
    @Attribute(.unique) public var id: UUID
    public var date: Date
    public var distanceMeters: Double
    public var durationSeconds: TimeInterval
    /// Flattened `HeartRateSummary.averageBPM` — a simple two-optional-Double
    /// struct, stored directly rather than `Codable`-encoded since there is
    /// no sum-type ambiguity to protect against.
    public var averageBPM: Double?
    /// Flattened `HeartRateSummary.maxBPM`.
    public var maxBPM: Double?
    public var source: String
    /// Soft, nullable link back to an authored `WorkoutModel`'s id.
    public var workoutID: UUID?
    public var notes: String?
    public var isDeleted: Bool

    @Relationship(deleteRule: .cascade, inverse: \SplitModel.run)
    public var splits: [SplitModel]

    /// Creates a completed-run row.
    public init(
        id: UUID,
        date: Date,
        distanceMeters: Double,
        durationSeconds: TimeInterval,
        averageBPM: Double? = nil,
        maxBPM: Double? = nil,
        source: String,
        workoutID: UUID? = nil,
        notes: String? = nil,
        isDeleted: Bool = false,
        splits: [SplitModel] = []
    ) {
        self.id = id
        self.date = date
        self.distanceMeters = distanceMeters
        self.durationSeconds = durationSeconds
        self.averageBPM = averageBPM
        self.maxBPM = maxBPM
        self.source = source
        self.workoutID = workoutID
        self.notes = notes
        self.isDeleted = isDeleted
        self.splits = splits
    }
}
