import DataKit
import DomainKit
import Observation
import SwiftData

/// The application's single dependency graph for production services.
@MainActor
@Observable
final class StrideAppContainer {
    let modelContainer: ModelContainer
    let workoutRepository: SwiftDataWorkoutRepository
    let runHistoryRepository: SwiftDataRunHistoryRepository
    let preferencesStore: UserDefaultsPreferencesStore
    let watchSyncService: WorkoutKitSyncService
    let clock: SystemClock
    let syncCoordinator: SyncCoordinator
    let healthSource: HealthKitRunHistoryRepository
    let ingestionCoordinator: RunIngestionCoordinator
    var ingestionError: Error?
    var deliveryError: Error?
    var isRefreshing = false
    var hasRequestedAccess = false
    var importedRunCount: Int?
    /// Changes after a successful import so feature view models can reload.
    var ingestionRevision = 0
    @ObservationIgnored private lazy var healthDelivery = HealthKitRunBackgroundDelivery { [weak self] error in
        await self?.receiveUpdate(error)
    }

    init() throws {
        let container = try ModelContainer(
            for: WorkoutModel.self,
            WorkoutSegmentModel.self,
            SyncJobModel.self,
            CompletedRunModel.self,
            SplitModel.self,
            PersonalBestModel.self,
            HealthKitAnchorModel.self
        )
        modelContainer = container

        let workouts = SwiftDataWorkoutRepository(modelContainer: container)
        let runs = SwiftDataRunHistoryRepository(modelContainer: container)
        let health = HealthKitRunHistoryRepository()
        let preferences = UserDefaultsPreferencesStore()
        let watch = WorkoutKitSyncService()
        let clock = SystemClock()
        let sync = SyncCoordinator(repository: workouts, watchSyncService: watch, clock: clock)
        let ingest = IngestCompletedRunsUseCase(
            runHistoryRepository: runs,
            workoutRepository: workouts,
            syncCoordinator: sync
        )
        let anchors = SwiftDataIngestionAnchorStore(modelContainer: container)
        let coordinator = RunIngestionCoordinator(
            source: health,
            anchorStore: anchors,
            ingest: ingest,
            anchorKey: "healthkit.running.workouts.v1",
            splitDistanceMeters: SplitDerivation.kilometerMeters
        )
        workoutRepository = workouts
        runHistoryRepository = runs
        preferencesStore = preferences
        watchSyncService = watch
        self.clock = clock
        syncCoordinator = sync
        healthSource = health
        ingestionCoordinator = coordinator
    }

    /// Called synchronously during didFinishLaunching, even for background wakes.
    func observeAtLaunch() {
        do {
            try healthDelivery.observe()
        } catch {
            deliveryError = error
        }
    }

    /// Foreground refresh never prompts. Permission priming is a user action.
    func refresh(requestAccess: Bool = false) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            if requestAccess { _ = try await healthSource.requestAccess() }
            hasRequestedAccess = try await healthSource.status == .unnecessary
            guard hasRequestedAccess else { return }
        } catch {
            ingestionError = error
            return
        }
        do {
            try await healthDelivery.start()
            deliveryError = nil
        } catch {
            deliveryError = error
        }
        // Background registration failure must not block foreground recovery.
        await receiveUpdate(nil)
    }

    private func receiveUpdate(_ observerError: RunIngestionDeliveryError?) async {
        if let observerError {
            deliveryError = observerError
            return
        }
        do {
            _ = try await ingestionCoordinator.ingestNow()
            importedRunCount = try await runHistoryRepository.fetchAll().filter { !$0.isDeleted }.count
            ingestionRevision &+= 1
            ingestionError = nil
        } catch {
            ingestionError = error
        }
    }
}
