#if DEBUG
import DomainKit
import Foundation

// MARK: - Preview-only port fakes

// `FeatureBuilder`'s production target may depend on `DomainKit` and
// `DesignSystem` only (never `TestSupport`, which is reserved for test
// targets per `Package.swift`), so `#Preview` providers in this module use
// these minimal, file-private stand-ins instead of `TestSupport`'s fakes.

/// A trivial in-memory `WorkoutRepository` for SwiftUI previews only.
final class PreviewWorkoutRepository: WorkoutRepository, @unchecked Sendable {
    private var workoutsByID: [UUID: Workout] = [:]
    private var syncJobsByID: [UUID: SyncJob] = [:]

    init(workouts: [Workout] = []) {
        workoutsByID = Dictionary(uniqueKeysWithValues: workouts.map { ($0.id, $0) })
    }

    func save(_ workout: Workout) async throws {
        workoutsByID[workout.id] = workout
    }

    func fetchAll() async throws -> [Workout] {
        Array(workoutsByID.values)
    }

    func fetch(id: UUID) async throws -> Workout? {
        workoutsByID[id]
    }

    func delete(id: UUID) async throws {
        workoutsByID.removeValue(forKey: id)
    }

    func saveSyncJob(_ syncJob: SyncJob) async throws {
        syncJobsByID[syncJob.id] = syncJob
    }

    func fetchSyncJob(id: UUID) async throws -> SyncJob? {
        syncJobsByID[id]
    }

    func fetchSyncJobs(workoutID: UUID) async throws -> [SyncJob] {
        syncJobsByID.values.filter { $0.workoutID == workoutID }
    }

    func fetchLatestSyncJob(workoutID: UUID) async throws -> SyncJob? {
        syncJobsByID.values
            .filter { $0.workoutID == workoutID }
            .max { $0.updatedAt < $1.updatedAt }
    }
}

/// A trivial fixed-date `Clock` for SwiftUI previews only.
final class PreviewClock: Clock, @unchecked Sendable {
    private let date: Date

    init(date: Date = Date(timeIntervalSince1970: 1_700_000_000)) {
        self.date = date
    }

    func now() -> Date {
        date
    }
}

/// A sample workout used to populate builder previews.
enum PreviewFixtures {
    static func sampleWorkout(id: UUID = UUID(), now: Date = Date(timeIntervalSince1970: 1_700_000_000)) -> Workout {
        Workout(
            id: id,
            name: "5x1km Intervals",
            segments: [
                .step(SegmentStep(intent: .warmUp, goal: .duration(seconds: 600))),
                .intervalBlock(
                    steps: [
                        IntervalStep(
                            purpose: .work,
                            step: SegmentStep(
                                intent: .work,
                                goal: .distance(meters: 1_000),
                                target: .pace(range: 0.2...0.22)
                            )
                        ),
                        IntervalStep(
                            purpose: .recovery,
                            step: SegmentStep(intent: .recovery, goal: .duration(seconds: 120))
                        )
                    ],
                    repetitions: 5
                ),
                .step(SegmentStep(intent: .coolDown, goal: .duration(seconds: 600)))
            ],
            createdAt: now,
            updatedAt: now
        )
    }
}

#endif
