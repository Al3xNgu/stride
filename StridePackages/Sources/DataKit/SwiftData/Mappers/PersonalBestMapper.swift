import Foundation
import DomainKit

/// Bidirectional mapping between `PersonalBest` and `PersonalBestModel`.
/// Total and non-throwing: every field is a plain primitive.
public enum PersonalBestMapper {
    /// Builds a brand-new `PersonalBestModel` from `personalBest`.
    public static func toModel(_ personalBest: PersonalBest) -> PersonalBestModel {
        PersonalBestModel(
            id: personalBest.id,
            milestoneID: personalBest.milestoneID,
            elapsedSeconds: personalBest.elapsedSeconds,
            completedRunID: personalBest.completedRunID,
            achievedAt: personalBest.achievedAt
        )
    }

    /// Updates `model`'s fields from `personalBest`.
    public static func apply(_ personalBest: PersonalBest, to model: PersonalBestModel) {
        model.milestoneID = personalBest.milestoneID
        model.elapsedSeconds = personalBest.elapsedSeconds
        model.completedRunID = personalBest.completedRunID
        model.achievedAt = personalBest.achievedAt
    }

    /// Maps `model` back to a domain `PersonalBest`.
    public static func toDomain(_ model: PersonalBestModel) -> PersonalBest {
        PersonalBest(
            id: model.id,
            milestoneID: model.milestoneID,
            elapsedSeconds: model.elapsedSeconds,
            completedRunID: model.completedRunID,
            achievedAt: model.achievedAt
        )
    }
}
