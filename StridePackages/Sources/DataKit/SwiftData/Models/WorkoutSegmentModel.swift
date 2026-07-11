import Foundation
import SwiftData

/// SwiftData persistence for one ordered element of a `Workout`'s segment
/// list (`docs/ARCHITECTURE.md` §5's `WorkoutSegment` sum type).
///
/// `WorkoutSegment` is a domain sum type (`.step` / `.intervalBlock`) whose
/// cases carry different nested associated values (`SegmentStep` vs.
/// `[IntervalStep]` + `repetitions`). Rather than flattening every case's
/// fields onto this model behind a discriminator column — which would let a
/// corrupt/partial row (e.g. `.step` fields set but `kind == "intervalBlock"`)
/// exist and force the mapper to guess or reject non-exhaustively — the
/// entire segment value is `Codable`-encoded into `segmentData` and decoded
/// back verbatim by `WorkoutMapper`. This keeps the mapper total (decoding
/// can only fail if the bytes themselves are corrupted, never because of an
/// invalid discriminator/field combination) and migration-friendly (a future
/// change to `WorkoutSegment`'s shape only needs `Codable` evolution, not a
/// SwiftData schema migration) — see task 1.2's summary for the full
/// rationale and the rejected alternative.
@Model
public final class WorkoutSegmentModel {
    /// Matches the domain `WorkoutSegment.id`.
    @Attribute(.unique) public var id: UUID
    /// Zero-based position within the owning workout's segment list.
    /// SwiftData to-many relationships are unordered, so order must be
    /// stored explicitly to preserve the domain's ordered `[WorkoutSegment]`.
    public var order: Int
    /// The entire `WorkoutSegment` value, JSON-encoded.
    public var segmentData: Data
    /// Inverse of `WorkoutModel.segments`; cascade-deleted with the workout.
    public var workout: WorkoutModel?

    /// Creates a segment row.
    public init(id: UUID, order: Int, segmentData: Data, workout: WorkoutModel? = nil) {
        self.id = id
        self.order = order
        self.segmentData = segmentData
        self.workout = workout
    }
}
