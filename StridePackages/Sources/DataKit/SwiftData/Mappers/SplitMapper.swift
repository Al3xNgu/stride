import Foundation
import DomainKit

/// Bidirectional mapping between `Split` and `SplitModel`. Total and
/// non-throwing: every field is a plain primitive.
public enum SplitMapper {
    /// Builds a brand-new `SplitModel` from `split`. Does not set
    /// `model.run` — callers attach the owning `CompletedRunModel`.
    public static func toModel(_ split: Split) -> SplitModel {
        SplitModel(
            id: split.id,
            runID: split.runID,
            index: split.index,
            distanceMeters: split.distanceMeters,
            durationSeconds: split.durationSeconds
        )
    }

    /// Maps `model` back to a domain `Split`.
    public static func toDomain(_ model: SplitModel) -> Split {
        Split(
            id: model.id,
            runID: model.runID,
            index: model.index,
            distanceMeters: model.distanceMeters,
            durationSeconds: model.durationSeconds
        )
    }
}
