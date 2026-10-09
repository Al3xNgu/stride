import DataKit
import DomainKit
import Foundation
import Observation
import SwiftData
#if DEBUG
import TestSupport
#endif

/// The application's single dependency graph for production services.
@MainActor
@Observable
final class StrideAppContainer {
    let modelContainer: ModelContainer
    let workoutRepository: SwiftDataWorkoutRepository
    let runHistoryRepository: SwiftDataRunHistoryRepository
    let preferencesStore: any PreferencesStore
    let watchSyncService: any WatchSyncService
    let clock: any Clock
    let syncCoordinator: SyncCoordinator
    let healthSource: any HealthPermissionPriming
    let ingestionCoordinator: RunIngestionCoordinator?
    /// True only for the launch-argument composition used by the UI test target.
    let isUITesting: Bool
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
        isUITesting = false
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

    #if DEBUG
    convenience init(uiTesting: Bool) throws {
        if uiTesting {
            try self.init(uiTestingDependencies: ())
        } else {
            try self.init()
        }
    }

    /// This composition is reachable only through the UI-test launch argument.
    /// It deliberately keeps the persistence adapters real while replacing
    /// external services with the package's deterministic fakes.
    private init(uiTestingDependencies: Void) throws {
        isUITesting = true
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: WorkoutModel.self,
            WorkoutSegmentModel.self,
            SyncJobModel.self,
            CompletedRunModel.self,
            SplitModel.self,
            PersonalBestModel.self,
            HealthKitAnchorModel.self,
            configurations: configuration
        )
        modelContainer = container

        let workouts = SwiftDataWorkoutRepository(modelContainer: container)
        let runs = SwiftDataRunHistoryRepository(modelContainer: container)
        let preferences = FakePreferencesStore(
            storedPreferences: UserPreferences(hasCompletedOnboarding: true)
        )
        let watch = FakeWatchSyncService()
        let clock = FakeClock(currentDate: Date(timeIntervalSince1970: 0))

        workoutRepository = workouts
        runHistoryRepository = runs
        preferencesStore = preferences
        watchSyncService = watch
        self.clock = clock
        syncCoordinator = SyncCoordinator(repository: workouts, watchSyncService: watch, clock: clock)
        healthSource = FakeHealthPermissionPriming(status: .unnecessary)
        ingestionCoordinator = nil
    }
    #else
    convenience init(uiTesting _: Bool) throws {
        try self.init()
    }
    #endif

    /// Called synchronously during didFinishLaunching, even for background wakes.
    func observeAtLaunch() {
        guard !isUITesting else { return }
        do {
            try healthDelivery.observe()
        } catch {
            deliveryError = error
        }
    }

    /// Foreground refresh never prompts. Permission priming is a user action.
    func refresh(requestAccess: Bool = false) async {
        guard !isUITesting else {
            hasRequestedAccess = true
            return
        }
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
            guard let ingestionCoordinator else { return }
            _ = try await ingestionCoordinator.ingestNow()
            importedRunCount = try await runHistoryRepository.fetchAll().filter { !$0.isDeleted }.count
            ingestionRevision &+= 1
            ingestionError = nil
        } catch {
            ingestionError = error
        }
    }
}
