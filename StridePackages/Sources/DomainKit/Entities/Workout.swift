import Foundation

/// The physical activity and location a `Workout` is authored for.
///
/// Modeled as an enum with a single `.outdoorRun` case for the MVP so
/// indoor running (and other activities) can land later without changing
/// every call site that switches on activity.
public enum WorkoutActivity: String, Equatable, Hashable, Codable, Sendable {
    /// An outdoor running workout (the only MVP case).
    case outdoorRun
}

/// A user-authored workout template.
///
/// `Workout` is the asset a user's library is built from: authored intent
/// that must survive independently of both the Apple Watch and HealthKit
/// (see `docs/ARCHITECTURE.md` §5). It owns an ordered list of segments and
/// is the input to validation, persistence, and the WorkoutKit mapper.
public struct Workout: Identifiable, Equatable, Hashable, Codable, Sendable {
    /// Stable identity, used as the persistence key and for soft-linking
    /// from `CompletedRun`.
    public let id: UUID
    /// User-facing name, e.g. "5x1km Intervals".
    public var name: String
    /// Free-form user notes.
    public var notes: String
    /// The activity/location this workout is authored for.
    public var activity: WorkoutActivity
    /// Ordered segments that make up the workout.
    public var segments: [WorkoutSegment]
    /// When the workout was first created.
    public var createdAt: Date
    /// When the workout was last modified.
    public var updatedAt: Date
    /// Schema version of this workout's structure, for migration support.
    public var schemaVersion: Int

    /// Creates a workout.
    public init(
        id: UUID = UUID(),
        name: String,
        notes: String = "",
        activity: WorkoutActivity = .outdoorRun,
        segments: [WorkoutSegment] = [],
        createdAt: Date,
        updatedAt: Date,
        schemaVersion: Int = 1
    ) {
        self.id = id
        self.name = name
        self.notes = notes
        self.activity = activity
        self.segments = segments
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.schemaVersion = schemaVersion
    }
}
