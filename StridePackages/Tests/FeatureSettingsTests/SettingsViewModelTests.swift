import DomainKit
import Foundation
import Testing
@testable import FeatureSettings
import TestSupport

/// Tests the settings screen's state transitions against the domain fakes and
/// the feature-owned permission seam. No HealthKit or WatchKit entitlement is
/// needed to exercise these flows.
@MainActor
@Suite("SettingsViewModel")
struct SettingsViewModelTests {
    @Test("load refreshes preferences and both permission surfaces")
    func loadRefreshesAllState() async {
        let preferences = UserPreferences(
            distanceUnit: .kilometers,
            defaultPacesByIntent: [.easy: 0.004],
            hasCompletedOnboarding: true
        )
        let store = FakePreferencesStore(storedPreferences: preferences)
        let watch = FakeWatchSyncService(isSupported: true, authorizationState: .denied)
        let health = FakeHealthPermissionPriming(status: .unnecessary)
        let viewModel = makeViewModel(store: store, watch: watch, health: health)

        await viewModel.load()

        #expect(viewModel.preferences == preferences)
        #expect(viewModel.isWatchSupported)
        #expect(viewModel.watchAuthorizationState == .denied)
        #expect(viewModel.healthPermissionStatus == .unnecessary)
        #expect(viewModel.loadError == nil)
        #expect(!viewModel.isLoading)
    }

    @Test("changing units persists the new unit and preserves the other preferences")
    func changingUnitsPreservesDefaults() async {
        let preferences = UserPreferences(
            distanceUnit: .miles,
            defaultPacesByIntent: [.tempo: 0.0035],
            hasCompletedOnboarding: true
        )
        let store = FakePreferencesStore(storedPreferences: preferences)
        let viewModel = makeViewModel(
            store: store,
            watch: FakeWatchSyncService(),
            health: FakeHealthPermissionPriming()
        )
        await viewModel.load()

        await viewModel.setDistanceUnit(.kilometers)

        #expect(viewModel.preferences.distanceUnit == .kilometers)
        #expect(viewModel.preferences.defaultPacesByIntent == preferences.defaultPacesByIntent)
        #expect(viewModel.preferences.hasCompletedOnboarding)
        #expect(store.savedPreferences.last == UserPreferences(
            distanceUnit: .kilometers,
            defaultPacesByIntent: preferences.defaultPacesByIntent,
            hasCompletedOnboarding: true
        ))
    }

    @Test("a failed Health request is typed, visible, and leaves the last status intact")
    func healthRequestErrorIsSurfaced() async {
        let health = FakeHealthPermissionPriming(status: .shouldRequest)
        health.errorToThrow = HealthPermissionPrimingError.unavailable
        let viewModel = makeViewModel(
            store: FakePreferencesStore(),
            watch: FakeWatchSyncService(),
            health: health
        )
        await viewModel.load()

        await viewModel.requestHealthPermission()

        #expect(viewModel.healthPermissionStatus == .shouldRequest)
        #expect(viewModel.healthPermissionError == .unavailable)
        #expect(!viewModel.isRequestingHealthPermission)

        health.errorToThrow = nil
        health.result = .unnecessary
        await viewModel.requestHealthPermission()

        #expect(viewModel.healthPermissionStatus == .unnecessary)
        #expect(viewModel.healthPermissionError == nil)
    }

    @Test("a failed Health status check is typed and does not replace the last status")
    func healthStatusErrorIsSurfaced() async {
        let health = FakeHealthPermissionPriming(status: .unnecessary)
        health.statusErrorToThrow = HealthPermissionPrimingError.underlying("status unavailable")
        let viewModel = makeViewModel(
            store: FakePreferencesStore(),
            watch: FakeWatchSyncService(),
            health: health
        )

        await viewModel.load()

        #expect(viewModel.healthPermissionStatus == .unknown)
        #expect(viewModel.healthPermissionError == .underlying("status unavailable"))

        health.statusErrorToThrow = nil
        await viewModel.load()
        #expect(viewModel.healthPermissionStatus == .unnecessary)
        #expect(viewModel.healthPermissionError == nil)
    }

    @Test("duplicate Health requests while the first is in flight are ignored")
    func duplicateHealthRequestsAreIgnored() async {
        let health = FakeHealthPermissionPriming(status: .shouldRequest)
        health.result = .unnecessary
        health.delayNanoseconds = 100_000_000
        let viewModel = makeViewModel(
            store: FakePreferencesStore(),
            watch: FakeWatchSyncService(),
            health: health
        )
        await viewModel.load()

        let first = Task { @MainActor in
            await viewModel.requestHealthPermission()
        }
        try? await Task.sleep(nanoseconds: 10_000_000)
        await viewModel.requestHealthPermission()
        await first.value

        #expect(health.requestCallCount == 1)
        #expect(viewModel.healthPermissionStatus == .unnecessary)
    }

    @Test("duplicate Watch requests while the first is in flight are ignored")
    func duplicateWatchRequestsAreIgnored() async {
        let watch = BlockingWatchService()
        let viewModel = makeViewModel(
            store: FakePreferencesStore(),
            watch: watch,
            health: FakeHealthPermissionPriming()
        )
        await viewModel.load()

        let first = Task { @MainActor in
            await viewModel.requestWatchAuthorization()
        }
        try? await Task.sleep(nanoseconds: 10_000_000)
        await viewModel.requestWatchAuthorization()
        await first.value

        #expect(watch.requestCallCount == 1)
        #expect(viewModel.watchAuthorizationState == .authorized)
    }

    @Test("Watch permission does not request when scheduling is unsupported")
    func unsupportedWatchDoesNotRequest() async {
        let watch = FakeWatchSyncService(isSupported: false, authorizationState: .notDetermined)
        let viewModel = makeViewModel(
            store: FakePreferencesStore(),
            watch: watch,
            health: FakeHealthPermissionPriming()
        )
        await viewModel.load()

        await viewModel.requestWatchAuthorization()

        #expect(watch.requestAuthorizationCallCount == 0)
        #expect(viewModel.watchAuthorizationState == .notDetermined)
    }

    private func makeViewModel(
        store: PreferencesStore,
        watch: WatchSyncService,
        health: HealthPermissionPriming
    ) -> SettingsViewModel {
        SettingsViewModel(
            preferencesStore: store,
            watchSyncService: watch,
            healthPermissionPriming: health
        )
    }
}

private final class FakeHealthPermissionPriming: HealthPermissionPriming, @unchecked Sendable {
    var statusValue: HealthPermissionStatus
    var result: HealthPermissionStatus
    var statusErrorToThrow: Error?
    var errorToThrow: Error?
    var delayNanoseconds: UInt64 = 0
    private(set) var requestCallCount = 0

    init(status: HealthPermissionStatus = .shouldRequest) {
        statusValue = status
        result = status
    }

    var status: HealthPermissionStatus {
        get async throws {
            if let statusErrorToThrow {
                throw statusErrorToThrow
            }
            return statusValue
        }
    }

    func requestAccess() async throws -> HealthPermissionStatus {
        requestCallCount += 1
        if delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }
        if let errorToThrow {
            throw errorToThrow
        }
        statusValue = result
        return result
    }
}

private final class BlockingWatchService: WatchSyncService, @unchecked Sendable {
    let isSupported = true
    var authorizationState: WatchAuthorizationState = .notDetermined
    let maxScheduledWorkoutCount = 50
    private(set) var requestCallCount = 0

    func requestAuthorization() async -> WatchAuthorizationState {
        requestCallCount += 1
        try? await Task.sleep(nanoseconds: 100_000_000)
        authorizationState = .authorized
        return .authorized
    }

    func schedule(planID: UUID, workout: Workout, at date: Date?) async throws {}
    func remove(planID: UUID) async throws {}
    func fetchScheduledWorkouts() async throws -> [ScheduledWatchWorkout] { [] }
}
