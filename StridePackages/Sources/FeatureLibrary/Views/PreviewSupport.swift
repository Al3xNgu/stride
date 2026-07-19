#if DEBUG
import DomainKit
import Foundation

// MARK: - Preview-only port fakes

// `FeatureLibrary`'s production target may depend on `DomainKit` and
// `DesignSystem` only (never `TestSupport`, which is reserved for test
// targets per `Package.swift`), so `#Preview` providers in this module use
// these minimal, file-private stand-ins instead of `TestSupport`'s fakes —
// same pattern as `FeatureBuilder/Views/PreviewSupport.swift`.

/// A trivial in-memory `WorkoutRepository` for SwiftUI previews only.
final class PreviewWorkoutRepository: WorkoutRepository, @unchecked Sendable {
    private var workoutsByID: [UUID: Workout]
    private var syncJobsByID: [UUID: SyncJob]

    init(workouts: [Workout] = [], syncJobs: [SyncJob] = []) {
        workoutsByID = Dictionary(uniqueKeysWithValues: workouts.map { ($0.id, $0) })
        syncJobsByID = Dictionary(uniqueKeysWithValues: syncJobs.map { ($0.id, $0) })
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
        syncJobsByID = syncJobsByID.filter { $0.value.workoutID != id }
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

/// A trivial in-memory `WatchSyncService` for SwiftUI previews only. Always
/// supported/authorized and never fails, so previews show the happy path.
final class PreviewWatchSyncService: WatchSyncService, @unchecked Sendable {
    let isSupported = true
    let authorizationState: WatchAuthorizationState = .authorized
    let maxScheduledWorkoutCount = 50

    private var scheduled: [ScheduledWatchWorkout] = []

    func requestAuthorization() async -> WatchAuthorizationState {
        .authorized
    }

    func schedule(planID: UUID, workout: Workout, at date: Date?) async throws {
        scheduled.removeAll { $0.id == planID }
        scheduled.append(ScheduledWatchWorkout(id: planID, scheduledDate: date))
    }

    func remove(planID: UUID) async throws {
        scheduled.removeAll { $0.id == planID }
    }

    func fetchScheduledWorkouts() async throws -> [ScheduledWatchWorkout] {
        scheduled
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

/// Sample workouts + sync jobs used to populate library previews.
enum PreviewFixtures {
    static let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)

    static func sampleWorkout(name: String, now: Date = referenceDate) -> Workout {
        Workout(
            name: name,
            segments: [
                .step(SegmentStep(intent: .warmUp, goal: .duration(seconds: 600))),
                .step(SegmentStep(intent: .tempo, goal: .distance(meters: 5_000))),
                .step(SegmentStep(intent: .coolDown, goal: .duration(seconds: 300)))
            ],
            createdAt: now,
            updatedAt: now
        )
    }

    /// A repository pre-seeded with one workout in every notable badge state.
    static func makeRepository(now: Date = referenceDate) -> PreviewWorkoutRepository {
        let notSent = sampleWorkout(name: "5k Tempo")
        let synced = sampleWorkout(name: "5x1km Intervals")
        let failed = sampleWorkout(name: "Long Run")
        let stale = sampleWorkout(name: "Easy Recovery Jog")

        let syncedJob = SyncJob(
            workoutID: synced.id, state: .synced, createdAt: now, updatedAt: now, planIdentifier: UUID().uuidString
        )
        let failedJob = SyncJob(
            workoutID: failed.id, state: .failed(.noPairedWatch), createdAt: now, updatedAt: now
        )
        let staleJob = SyncJob(
            workoutID: stale.id, state: .stale, createdAt: now, updatedAt: now, planIdentifier: UUID().uuidString
        )

        return PreviewWorkoutRepository(
            workouts: [notSent, synced, failed, stale],
            syncJobs: [syncedJob, failedJob, staleJob]
        )
    }
}
#endif
