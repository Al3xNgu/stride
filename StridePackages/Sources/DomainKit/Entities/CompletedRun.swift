import Foundation

/// A per-km/mi split derived from a `CompletedRun`'s cumulative distance
/// samples.
///
/// `Split` is modeled as a standalone type carrying its own `runID` rather
/// than a nested array on `CompletedRun`, so splits can be fetched/derived
/// independently (e.g. lazily, or recomputed without rewriting the whole
/// run projection) while still being unambiguously owned by one run.
public struct Split: Identifiable, Equatable, Hashable, Codable, Sendable {
    /// Stable identity of this split.
    public let id: UUID
    /// The `CompletedRun` this split belongs to.
    public var runID: UUID
    /// Zero-based position of this split within the run.
    public var index: Int
    /// Distance covered by this split, in meters.
    public var distanceMeters: Double
    /// Time elapsed for this split, in seconds.
    public var durationSeconds: TimeInterval

    /// Creates a split.
    public init(
        id: UUID = UUID(),
        runID: UUID,
        index: Int,
        distanceMeters: Double,
        durationSeconds: TimeInterval
    ) {
        self.id = id
        self.runID = runID
        self.index = index
        self.distanceMeters = distanceMeters
        self.durationSeconds = durationSeconds
    }
}

/// A heart-rate summary for a completed run, when HealthKit provides one.
public struct HeartRateSummary: Equatable, Hashable, Codable, Sendable {
    /// Average heart rate in beats per minute, if available.
    public var averageBPM: Double?
    /// Maximum heart rate in beats per minute, if available.
    public var maxBPM: Double?

    /// Creates a heart-rate summary.
    public init(averageBPM: Double? = nil, maxBPM: Double? = nil) {
        self.averageBPM = averageBPM
        self.maxBPM = maxBPM
    }
}

/// A local, offline-first projection of an `HKWorkout`.
///
/// `CompletedRun` exists so History and Records screens work instantly and
/// offline; HealthKit remains the source of truth and this projection is
/// rebuildable at any time via idempotent ingestion keyed by the source
/// `HKWorkout`'s UUID (`docs/ARCHITECTURE.md` §5/§8). `workoutID` is a soft,
/// nullable link back to an authored `Workout` — a run can exist without a
/// Stride workout, and a workout can exist without ever being run.
public struct CompletedRun: Identifiable, Equatable, Hashable, Codable, Sendable {
    /// Identity keyed by the source `HKWorkout`'s UUID.
    public let id: UUID
    /// The date the run occurred.
    public var date: Date
    /// Total distance covered, in meters.
    public var distanceMeters: Double
    /// Total duration, in seconds.
    public var durationSeconds: TimeInterval
    /// Heart-rate summary, when available from HealthKit.
    public var heartRate: HeartRateSummary
    /// Source app/device name, e.g. "Apple Watch" or "Stride".
    public var source: String
    /// Soft link to the authored `Workout` this run was attributed to, if
    /// any. `nil` means unattributed or attribution has not run yet.
    public var workoutID: UUID?
    /// Optional user-entered notes for this run.
    public var notes: String?
    /// Whether this projection has been tombstoned because the source
    /// `HKWorkout` was deleted from HealthKit (`docs/ARCHITECTURE.md` §8).
    /// The projection is retained (rather than removed outright) so
    /// dependent records, such as a `PersonalBest` referencing it, remain
    /// explainable.
    public var isDeleted: Bool

    /// Average pace, in seconds-per-meter (CLAUDE.md rule 4), derived from
    /// `durationSeconds` / `distanceMeters`. `nil` when distance is zero,
    /// to avoid a division-by-zero / infinite pace.
    public var averagePace: Double? {
        guard distanceMeters > 0 else { return nil }
        return durationSeconds / distanceMeters
    }

    /// Creates a completed run projection.
    public init(
        id: UUID,
        date: Date,
        distanceMeters: Double,
        durationSeconds: TimeInterval,
        heartRate: HeartRateSummary = HeartRateSummary(),
        source: String,
        workoutID: UUID? = nil,
        notes: String? = nil,
        isDeleted: Bool = false
    ) {
        self.id = id
        self.date = date
        self.distanceMeters = distanceMeters
        self.durationSeconds = durationSeconds
        self.heartRate = heartRate
        self.source = source
        self.workoutID = workoutID
        self.notes = notes
        self.isDeleted = isDeleted
    }
}
