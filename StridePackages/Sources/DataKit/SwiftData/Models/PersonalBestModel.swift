import Foundation
import SwiftData

/// SwiftData persistence for a `PersonalBest` (`docs/ARCHITECTURE.md` §5/§9.4).
///
/// No relationships: `milestoneID` (a data-driven `Milestone` config value)
/// and `completedRunID` (a `CompletedRunModel` row) are both soft, id-only
/// references rather than ownership, matching the domain entity exactly —
/// `PersonalBest` supersession/history is a repository/policy concern, not
/// modeled here.
@Model
public final class PersonalBestModel {
    @Attribute(.unique) public var id: UUID
    public var milestoneID: UUID
    public var elapsedSeconds: TimeInterval
    public var completedRunID: UUID
    public var achievedAt: Date

    /// Creates a personal-best row.
    public init(
        id: UUID,
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
