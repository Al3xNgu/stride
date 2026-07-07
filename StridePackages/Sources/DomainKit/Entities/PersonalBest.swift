import Foundation

/// A stored personal record for a given `Milestone`.
///
/// Computed and persisted incrementally on ingestion rather than derived on
/// the fly, because computing a PR requires scanning full run history
/// (`docs/ARCHITECTURE.md` §5). `PersonalBest` represents a single record;
/// supersession (archiving a previous best when a new one is set) is a
/// repository/policy concern and is out of scope for this entity — it only
/// needs to carry the fields necessary to represent one record in a
/// superseded-records history.
public struct PersonalBest: Identifiable, Equatable, Hashable, Codable, Sendable {
    /// Stable identity of this record.
    public let id: UUID
    /// The milestone this record was set for.
    public var milestoneID: UUID
    /// Elapsed time for the milestone distance, in seconds.
    public var elapsedSeconds: TimeInterval
    /// The completed run that achieved this record.
    public var completedRunID: UUID
    /// When this record was achieved.
    public var achievedAt: Date

    /// Creates a personal best record.
    public init(
        id: UUID = UUID(),
        milestoneID: UUID,
        elapsedSeconds: TimeInterval,
        completedRunID: UUID,
        achievedAt: Date
    ) {
        self.id = id
        self.milestoneID = milestoneID
        self.elapsedSeconds = elapsedSeconds
        self.completedRunID = completedRunID
        self.achievedAt = achievedAt
    }
}
