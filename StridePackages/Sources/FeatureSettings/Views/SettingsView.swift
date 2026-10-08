import DomainKit
import SwiftUI

/// The settings screen for display units and system permission access.
///
/// Permission state is intentionally rendered as explanatory copy with an
/// explicit action. HealthKit does not reveal whether read access was denied,
/// so the Health row says that access was requested rather than claiming that
/// it was granted. The view model owns all effects and is injected by the
/// composition root; this feature never imports DataKit or a system
/// permission framework.
public struct SettingsView: View {
    @Bindable private var viewModel: SettingsViewModel
    @Environment(\.scenePhase) private var scenePhase

    /// Creates a settings screen backed by `viewModel`.
    public init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        Form {
            unitsSection
            watchSection
            healthSection
            recoverySection
        }
        .navigationTitle("Settings")
        .task {
            await viewModel.load()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task { await viewModel.load() }
        }
    }

    private var unitsSection: some View {
        Section {
            Picker("Distance and pace", selection: distanceUnitBinding) {
                Text("Miles").tag(DistanceUnit.miles)
                Text("Kilometers").tag(DistanceUnit.kilometers)
            }
            .pickerStyle(.segmented)
            .disabled(viewModel.isLoading)

            if viewModel.isLoading {
                ProgressView("Loading preferences…")
            }

            if let saveError = viewModel.saveError {
                Label(preferencesErrorMessage(saveError), systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Units")
        } footer: {
            Text("Distances and pace alerts use this unit throughout Stride.")
        }
    }

    private var watchSection: some View {
        Section {
            if viewModel.isWatchSupported {
                permissionRow(
                    PermissionRowConfiguration(
                        title: "Apple Watch",
                        status: WatchAuthorizationPresenter.statusLabel(for: viewModel.watchAuthorizationState),
                        detail: WatchAuthorizationPresenter.detail(for: viewModel.watchAuthorizationState),
                        isRequesting: viewModel.isRequestingWatchAuthorization,
                        actionTitle: "Request Access",
                        actionAvailable: WatchAuthorizationPresenter.canRequestAuthorization(
                            for: viewModel.watchAuthorizationState
                        ),
                        action: { Task { await viewModel.requestWatchAuthorization() } }
                    )
                )
            } else {
                Label("Apple Watch unavailable", systemImage: "applewatch.slash")
                Text("A paired Apple Watch is required to schedule workouts.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Workout Scheduling")
        } footer: {
            Text("Stride schedules workouts in Apple's Workout app on your paired watch.")
        }
    }

    private var healthSection: some View {
        Section {
            permissionRow(
                PermissionRowConfiguration(
                    title: "Health run history",
                    status: HealthPermissionPresenter.statusLabel(for: viewModel.healthPermissionStatus),
                    detail: HealthPermissionPresenter.detail(for: viewModel.healthPermissionStatus),
                    isRequesting: viewModel.isRequestingHealthPermission,
                    actionTitle: "Grant Access",
                    actionAvailable: HealthPermissionPresenter.canRequestAccess(
                        for: viewModel.healthPermissionStatus
                    ),
                    action: { Task { await viewModel.requestHealthPermission() } }
                )
            )

            if let error = viewModel.healthPermissionError {
                Label(HealthPermissionPresenter.errorMessage(for: error), systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Health")
        } footer: {
            Text("Stride reads runs, distance, and heart rate to build History and Records.")
        }
    }

    @ViewBuilder
    private func permissionRow(_ configuration: PermissionRowConfiguration) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(configuration.title)
                    Spacer(minLength: 8)
                    Text(configuration.status)
                        .foregroundStyle(.secondary)
                }
                Text(configuration.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if configuration.isRequesting {
                ProgressView()
                    .controlSize(.small)
            }
        }

        if configuration.actionAvailable {
            Button(configuration.actionTitle, action: configuration.action)
                .disabled(configuration.isRequesting)
        }
    }

    @ViewBuilder
    private var recoverySection: some View {
        if let loadError = viewModel.loadError {
            Section {
                Label(preferencesErrorMessage(loadError), systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                Button("Reset Preferences to Defaults") {
                    Task { await viewModel.resetToDefaults() }
                }
                .disabled(viewModel.isLoading)
            } header: {
                Text("Preferences Recovery")
            } footer: {
                Text("Resetting replaces the unreadable saved preferences with Stride's defaults.")
            }
        }
    }

    private var distanceUnitBinding: Binding<DistanceUnit> {
        Binding(
            get: { viewModel.preferences.distanceUnit },
            set: { unit in
                guard unit != viewModel.preferences.distanceUnit else { return }
                Task { await viewModel.setDistanceUnit(unit) }
            }
        )
    }

    private func preferencesErrorMessage(_ error: PreferencesStoreError) -> String {
        switch error {
        case let .underlying(description):
            return description
        }
    }
}

private struct PermissionRowConfiguration {
    let title: String
    let status: String
    let detail: String
    let isRequesting: Bool
    let actionTitle: String
    let actionAvailable: Bool
    let action: () -> Void
}

#if DEBUG
#Preview("Settings") {
    NavigationStack {
        SettingsView(
            viewModel: SettingsViewModel(
                preferencesStore: PreviewPreferencesStore(),
                watchSyncService: PreviewWatchService(),
                healthPermissionPriming: PreviewHealthPermissionPriming()
            )
        )
    }
}

private final class PreviewPreferencesStore: PreferencesStore, @unchecked Sendable {
    private var value = UserPreferences()

    func load() async throws -> UserPreferences { value }

    func save(_ preferences: UserPreferences) async throws {
        value = preferences
    }
}

private final class PreviewWatchService: WatchSyncService, @unchecked Sendable {
    var isSupported: Bool { get async { true } }
    var authorizationState: WatchAuthorizationState { get async { .authorized } }
    var maxScheduledWorkoutCount: Int { get async { 50 } }
    func requestAuthorization() async -> WatchAuthorizationState { .authorized }
    func schedule(planID: UUID, workout: Workout, at date: Date?) async throws {}
    func remove(planID: UUID) async throws {}
    func fetchScheduledWorkouts() async throws -> [ScheduledWatchWorkout] { [] }
}

private final class PreviewHealthPermissionPriming: HealthPermissionPriming, @unchecked Sendable {
    var status: HealthPermissionStatus { get async throws { .shouldRequest } }
    func requestAccess() async throws -> HealthPermissionStatus { .unnecessary }
}
#endif
