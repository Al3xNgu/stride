import Foundation
import SwiftData

/// SwiftData persistence for a `Split` (`docs/ARCHITECTURE.md` §5/§9.4).
@Model
public final class SplitModel {
    @Attribute(.unique) public var id: UUID
    /// Denormalized copy of the owning run's id, for querying without a
    /// relationship traversal.
    public var runID: UUID
    /// Zero-based position of this split within the run.
    public var index: Int
    public var distanceMeters: Double
    public var durationSeconds: TimeInterval
    /// Inverse of `CompletedRunModel.splits`; cascade-deleted with the run.
    public var run: CompletedRunModel?

    /// Creates a split row.
    public init(
        id: UUID,
        runID: UUID,
        index: Int,
        distanceMeters: Double,
        durationSeconds: TimeInterval,
        run: CompletedRunModel? = nil
    ) {
        self.id = id
        self.runID = runID
        self.index = index
        self.distanceMeters = distanceMeters
        self.durationSeconds = durationSeconds
        self.run = run
    }
}
