#if DEBUG
import DomainKit
import Foundation

// MARK: - Preview-only port fakes

// `FeatureRecords`'s production target may depend on `DomainKit` and
// `DesignSystem` only (never `TestSupport`, which is reserved for test
// targets per `Package.swift`), so `#Preview` providers in this module use
// this minimal, file-private stand-in instead of `TestSupport`'s fakes —
// same pattern as `FeatureLibrary/Views/PreviewSupport.swift`.

/// A trivial in-memory `RunHistoryRepository` for SwiftUI previews only.
final class PreviewRunHistoryRepository: RunHistoryRepository, @unchecked Sendable {
    private var runsByID: [UUID: CompletedRun]
    private var splitsByRunID: [UUID: [Split]] = [:]
    private var personalBestsByID: [UUID: PersonalBest]

    init(runs: [CompletedRun] = [], personalBests: [PersonalBest] = []) {
        runsByID = Dictionary(uniqueKeysWithValues: runs.map { ($0.id, $0) })
        personalBestsByID = Dictionary(uniqueKeysWithValues: personalBests.map { ($0.id, $0) })
    }

    func upsert(_ run: CompletedRun) async throws {
        runsByID[run.id] = run
    }

    func fetchAll() async throws -> [CompletedRun] {
        Array(runsByID.values)
    }

    func fetch(id: UUID) async throws -> CompletedRun? {
        runsByID[id]
    }

    func fetch(from startDate: Date, to endDate: Date) async throws -> [CompletedRun] {
        runsByID.values.filter { (startDate...endDate).contains($0.date) }
    }

    func markDeleted(id: UUID) async throws {
        guard var run = runsByID[id] else { return }
        run.isDeleted = true
        runsByID[id] = run
    }

    func saveSplits(_ splits: [Split], for runID: UUID) async throws {
        splitsByRunID[runID] = splits
    }

    func fetchSplits(runID: UUID) async throws -> [Split] {
        (splitsByRunID[runID] ?? []).sorted { $0.index < $1.index }
    }

    func savePersonalBest(_ personalBest: PersonalBest) async throws {
        personalBestsByID[personalBest.id] = personalBest
    }

    func fetchPersonalBests() async throws -> [PersonalBest] {
        Array(personalBestsByID.values)
    }

    func fetchPersonalBest(milestoneID: UUID) async throws -> PersonalBest? {
        personalBestsByID.values
            .filter { $0.milestoneID == milestoneID }
            .min { $0.elapsedSeconds < $1.elapsedSeconds }
    }

    func deletePersonalBest(id: UUID) async throws {
        personalBestsByID.removeValue(forKey: id)
    }
}

/// A trivial in-memory `WorkoutRepository` for SwiftUI previews only.
final class PreviewWorkoutRepository: WorkoutRepository, @unchecked Sendable {
    private var workoutsByID: [UUID: Workout]

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

    func saveSyncJob(_ syncJob: SyncJob) async throws {}

    func fetchSyncJob(id: UUID) async throws -> SyncJob? {
        nil
    }

    func fetchSyncJobs(workoutID: UUID) async throws -> [SyncJob] {
        []
    }

    func fetchLatestSyncJob(workoutID: UUID) async throws -> SyncJob? {
        nil
    }
}

/// Sample runs and personal bests used to populate records previews.
enum PreviewFixtures {
    static let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)

    /// A repository pre-seeded with a current 5K record (and empty slots for
    /// every other MVP milestone).
    static func makeRunHistoryRepository() -> PreviewRunHistoryRepository {
        let run = CompletedRun(
            id: UUID(),
            date: referenceDate,
            distanceMeters: 5_000,
            durationSeconds: 1_320,
            source: "Apple Watch"
        )
        let personalBest = PersonalBest(
            milestoneID: Milestone.fiveK.id,
            elapsedSeconds: 1_320,
            completedRunID: run.id,
            achievedAt: referenceDate
        )
        return PreviewRunHistoryRepository(runs: [run], personalBests: [personalBest])
    }
}
#endif
