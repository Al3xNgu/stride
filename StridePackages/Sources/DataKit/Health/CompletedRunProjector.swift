import DomainKit
import Foundation

/// Plain-value input to `CompletedRunProjector`, already extracted from an
/// `HKWorkout`'s statistics — this type has no HealthKit dependency itself,
/// so the projection mapping is fully unit-testable via `swift test`.
public struct HealthKitRunProjectionInput: Equatable, Hashable, Sendable {
    /// The source `HKWorkout`'s stable identity — becomes `CompletedRun.id`.
    public var workoutUUID: UUID
    /// The workout's start date — becomes `CompletedRun.date`.
    public var startDate: Date
    /// Total distance, in meters, from `HKWorkout.statisticsForType`'s
    /// `sumQuantity()` for the distance-walking-running type.
    public var totalDistanceMeters: Double
    /// Total duration, in seconds (`HKWorkout.duration`).
    public var totalDurationSeconds: TimeInterval
    /// Average heart rate in bpm, from `statisticsForType`'s
    /// `averageQuantity()` for the heart-rate type, if HealthKit has any.
    public var averageHeartRateBPM: Double?
    /// Maximum heart rate in bpm, from `statisticsForType`'s
    /// `maximumQuantity()`, if HealthKit has any.
    public var maxHeartRateBPM: Double?
    /// The recording source's display name (`HKSourceRevision.source.name`),
    /// e.g. "Apple Watch".
    public var sourceName: String

    /// Creates a projection input.
    public init(
        workoutUUID: UUID,
        startDate: Date,
        totalDistanceMeters: Double,
        totalDurationSeconds: TimeInterval,
        averageHeartRateBPM: Double? = nil,
        maxHeartRateBPM: Double? = nil,
        sourceName: String
    ) {
        self.workoutUUID = workoutUUID
        self.startDate = startDate
        self.totalDistanceMeters = totalDistanceMeters
        self.totalDurationSeconds = totalDurationSeconds
        self.averageHeartRateBPM = averageHeartRateBPM
        self.maxHeartRateBPM = maxHeartRateBPM
        self.sourceName = sourceName
    }
}

/// Pure `HealthKitRunProjectionInput` -> `CompletedRun` projection.
///
/// Kept separate from the HealthKit-reading code (`HealthKitRunHistoryRepository`)
/// so the field mapping — and its defensive sanitization of whatever
/// HealthKit hands back — is exercised by `swift test` independent of
/// HealthKit availability, mirroring `SplitDerivation`'s pure-core shape.
public enum CompletedRunProjector {
    /// Projects `input` into a `CompletedRun`. Always freshly-attributed
    /// (`workoutID: nil`), not deleted, and without notes — attribution,
    /// user notes, and tombstoning are `IngestCompletedRunsUseCase`/
    /// `RunHistoryRepository` concerns (task 1.12), not this adapter's.
    public static func project(_ input: HealthKitRunProjectionInput) -> CompletedRun {
        CompletedRun(
            id: input.workoutUUID,
            date: input.startDate,
            distanceMeters: sanitizedNonNegative(input.totalDistanceMeters),
            durationSeconds: sanitizedNonNegative(input.totalDurationSeconds),
            heartRate: HeartRateSummary(
                averageBPM: sanitizedPositive(input.averageHeartRateBPM),
                maxBPM: sanitizedPositive(input.maxHeartRateBPM)
            ),
            source: input.sourceName,
            workoutID: nil,
            notes: nil,
            isDeleted: false
        )
    }

    /// Clamps a distance/duration value to zero when it is negative or
    /// non-finite (NaN/Infinity), never letting corrupt HealthKit statistics
    /// produce a negative or unusable `CompletedRun` field.
    private static func sanitizedNonNegative(_ value: Double) -> Double {
        guard value.isFinite, value >= 0 else { return 0 }
        return value
    }

    /// Drops a heart-rate value entirely (rather than clamping) when it is
    /// non-positive or non-finite — an absent/invalid HR statistic should
    /// read as "no data" (`nil`), matching `HeartRateSummary`'s own optional
    /// fields, not as a bogus zero.
    private static func sanitizedPositive(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value > 0 else { return nil }
        return value
    }
}
