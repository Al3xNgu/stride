#if DEBUG
import DomainKit
import Foundation

// MARK: - Preview-only port fakes

// `FeatureHistory`'s production target may depend on `DomainKit` and
// `DesignSystem` only (never `TestSupport`, which is reserved for test
// targets per `Package.swift`), so `#Preview` providers in this module use
// these minimal, file-private stand-ins instead of `TestSupport`'s fakes —
// same pattern as `FeatureLibrary/Views/PreviewSupport.swift`.

/// A trivial in-memory `RunHistoryRepository` for SwiftUI previews only.
final class PreviewRunHistoryRepository: RunHistoryRepository, @unchecked Sendable {
    private var runsByID: [UUID: CompletedRun]
    private var splitsByRunID: [UUID: [Split]]
    private var personalBestsByID: [UUID: PersonalBest] = [:]

    init(runs: [CompletedRun] = [], splitsByRunID: [UUID: [Split]] = [:]) {
        runsByID = Dictionary(uniqueKeysWithValues: runs.map { ($0.id, $0) })
        self.splitsByRunID = splitsByRunID
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
        personalBestsByID.values.first { $0.milestoneID == milestoneID }
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

/// Sample runs, splits, and workouts used to populate history previews.
enum PreviewFixtures {
    static let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)

    struct DetailHarness {
        let runID: UUID
        let runHistoryRepository: PreviewRunHistoryRepository
        let workoutRepository: PreviewWorkoutRepository
    }

    static func sampleRun(id: UUID = UUID(), daysAgo: Int, workoutID: UUID? = nil) -> CompletedRun {
        CompletedRun(
            id: id,
            date: referenceDate.addingTimeInterval(-Double(daysAgo) * 86_400),
            distanceMeters: 5_000,
            durationSeconds: 1_500,
            heartRate: HeartRateSummary(averageBPM: 150, maxBPM: 172),
            source: "Apple Watch",
            workoutID: workoutID
        )
    }

    /// A repository pre-seeded with a recent run and an older, different-month run.
    static func makeRunHistoryRepository() -> PreviewRunHistoryRepository {
        let recent = sampleRun(daysAgo: 1)
        let older = sampleRun(daysAgo: 40)
        return PreviewRunHistoryRepository(runs: [recent, older])
    }

    /// A repository/id pair with one fully-populated run (splits + HR +
    /// attribution) for the `RunDetailView` preview.
    static func makeDetailHarness() -> DetailHarness {
        let workout = Workout(name: "5k Tempo", createdAt: referenceDate, updatedAt: referenceDate)
        let run = sampleRun(daysAgo: 1, workoutID: workout.id)
        let splits = (0..<5).map { index in
            Split(runID: run.id, index: index, distanceMeters: 1_000, durationSeconds: 300)
        }
        let runHistoryRepository = PreviewRunHistoryRepository(runs: [run], splitsByRunID: [run.id: splits])
        let workoutRepository = PreviewWorkoutRepository(workouts: [workout])
        return DetailHarness(
            runID: run.id,
            runHistoryRepository: runHistoryRepository,
            workoutRepository: workoutRepository
        )
    }
}
#endif
