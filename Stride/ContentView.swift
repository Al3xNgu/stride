import DesignSystem
import DataKit
import DomainKit
import FeatureBuilder
import FeatureHistory
import FeatureLibrary
import FeatureRecords
import FeatureSettings
import SwiftUI

@MainActor
struct ContentView: View {
    let container: StrideAppContainer
    @Environment(\.scenePhase) private var scenePhase

    @State private var selectedTab: Tab = .library
    @State private var libraryPath: [LibraryRoute] = []
    @State private var historyPath: [UUID] = []
    @State private var isBootstrappingPreferences = true
    @State private var builderLoadFailure: BuilderLoadFailure?
    @State private var libraryViewModel: LibraryViewModel
    @State private var historyViewModel: HistoryViewModel
    @State private var recordsViewModel: RecordsViewModel
    @State private var settingsViewModel: SettingsViewModel

    init(container: StrideAppContainer) {
        self.container = container
        _libraryViewModel = State(initialValue: LibraryViewModel(
            workoutRepository: container.workoutRepository,
            syncCoordinator: container.syncCoordinator,
            clock: container.clock
        ))
        _historyViewModel = State(initialValue: HistoryViewModel(
            runHistoryRepository: container.runHistoryRepository,
            workoutRepository: container.workoutRepository
        ))
        _recordsViewModel = State(initialValue: RecordsViewModel(
            runHistoryRepository: container.runHistoryRepository,
            workoutRepository: container.workoutRepository
        ))
        _settingsViewModel = State(initialValue: SettingsViewModel(
            preferencesStore: container.preferencesStore,
            watchSyncService: container.watchSyncService,
            healthPermissionPriming: container.healthSource
        ))
    }

    var body: some View {
        Group {
            if isBootstrappingPreferences {
                ProgressView("Loading Stride…")
            } else if let loadError = settingsViewModel.loadError {
                preferencesRecoveryView(loadError)
            } else if settingsViewModel.preferences.hasCompletedOnboarding {
                TabView(selection: $selectedTab) {
                    libraryTab
                        .tabItem { Label("Library", systemImage: "books.vertical") }
                        .tag(Tab.library)

                    historyTab
                        .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
                        .tag(Tab.history)

                    recordsTab
                        .tabItem { Label("Records", systemImage: "medal") }
                        .tag(Tab.records)

                    settingsTab
                        .tabItem { Label("Settings", systemImage: "gearshape") }
                        .tag(Tab.settings)
                }
            } else {
                onboardingView
            }
        }
        .task {
            await bootstrapPreferences()
            await container.refresh()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task {
                    await settingsViewModel.load()
                    await container.refresh()
                }
            }
        }
        .onChange(of: selectedTab) { _, tab in
            Task {
                if tab == .history { await container.refresh() }
            }
        }
        .onChange(of: container.ingestionRevision) { _, _ in
            Task { await reloadRunSurfaces() }
        }
        .onChange(of: libraryPath) { oldPath, newPath in
            guard !oldPath.isEmpty, newPath.isEmpty else { return }
            Task { await libraryViewModel.load() }
        }
    }

    private var libraryTab: some View {
        NavigationStack(path: $libraryPath) {
            LibraryView(
                viewModel: libraryViewModel,
                displayUnit: displayUnit,
                onEditWorkout: { workoutID in openBuilder(workoutID: workoutID) },
                onNewWorkout: { libraryPath.append(.new) }
            )
            .navigationDestination(for: LibraryRoute.self) { route in
                BuilderDestinationView(
                    container: container,
                    workout: route.workout,
                    displayUnit: displayUnit
                )
            }
            .alert(item: $builderLoadFailure) { failure in
                Alert(
                    title: Text("Couldn't Open Workout"),
                    message: Text(builderLoadFailureMessage(failure.error)),
                    primaryButton: .default(Text("Retry")) {
                        openBuilder(workoutID: failure.workoutID)
                    },
                    secondaryButton: .cancel()
                )
            }
        }
    }

    private var historyTab: some View {
        NavigationStack(path: $historyPath) {
            HistoryView(
                viewModel: historyViewModel,
                displayUnit: displayUnit,
                onOpenRun: { historyPath.append($0) }
            )
            .safeAreaInset(edge: .bottom) { healthRefreshPrompt }
            .navigationDestination(for: UUID.self) { runID in
                RunDetailDestinationView(
                    container: container,
                    runID: runID,
                    displayUnit: displayUnit
                )
            }
        }
    }

    private var recordsTab: some View {
        NavigationStack {
            RecordsView(
                viewModel: recordsViewModel,
                displayUnit: displayUnit,
                onOpenRun: openRunFromRecords
            )
        }
    }

    private var settingsTab: some View {
        NavigationStack {
            SettingsView(viewModel: settingsViewModel)
        }
    }

    private var onboardingView: some View {
        ContentUnavailableView {
            Label("Welcome to Stride", systemImage: "figure.run")
        } description: {
            Text("Connect Health to import running workouts, distance, and heart rate into History and Records.")
        } actions: {
            Button("Connect Health") {
                Task { await completeOnboarding(requestAccess: true) }
            }
            .buttonStyle(.borderedProminent)
            .disabled(container.isRefreshing)

            Button("Continue Without Health") {
                Task { await completeOnboarding(requestAccess: false) }
            }
            .disabled(container.isRefreshing)

            if container.isRefreshing {
                ProgressView("Updating history…")
            }
            if container.ingestionError != nil {
                Text("Health access couldn't be checked. You can try again or review Settings.")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
            if let saveError = settingsViewModel.saveError {
                Text(preferencesErrorMessage(saveError))
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private func preferencesRecoveryView(_ error: PreferencesStoreError) -> some View {
        ContentUnavailableView {
            Label("Couldn't Load Preferences", systemImage: "exclamationmark.triangle")
        } description: {
            Text(preferencesErrorMessage(error))
        } actions: {
            Button("Reset Preferences to Defaults") {
                Task { await settingsViewModel.resetToDefaults() }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder
    private var healthRefreshPrompt: some View {
        if (container.importedRunCount ?? 0) == 0 {
            VStack(alignment: .leading, spacing: 8) {
                Text(
                    container.hasRequestedAccess
                        ? "No runs have been imported yet. Refresh after your Health request, "
                            + "or review Stride’s read access in the Health app."
                        : "Connect Health to ask for permission to import running workouts, distance, and heart rate."
                )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button(container.hasRequestedAccess ? "Refresh History" : "Connect Health") {
                    Task { await container.refresh(requestAccess: !container.hasRequestedAccess) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(container.isRefreshing)
                if container.isRefreshing { ProgressView("Updating history…") }
                if container.ingestionError != nil {
                    Text("History couldn’t be updated. Your saved runs are still available. Try again.")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
                if container.deliveryError != nil {
                    Text("Background updates are unavailable. Open Stride to refresh your history.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.bar)
        }
    }

    private var displayUnit: DisplayDistanceUnit {
        settingsViewModel.preferences.distanceUnit == .kilometers ? .kilometers : .miles
    }

    private func openBuilder(workoutID: UUID) {
        Task {
            do {
                guard let workout = try await container.workoutRepository.fetch(id: workoutID) else {
                    builderLoadFailure = BuilderLoadFailure(
                        workoutID: workoutID,
                        error: .workoutNotFound(id: workoutID)
                    )
                    return
                }
                libraryPath.append(.edit(workout))
            } catch let error as WorkoutRepositoryError {
                builderLoadFailure = BuilderLoadFailure(workoutID: workoutID, error: error)
            } catch {
                builderLoadFailure = BuilderLoadFailure(
                    workoutID: workoutID,
                    error: .underlying(String(describing: error))
                )
            }
        }
    }

    private func openRunFromRecords(_ runID: UUID) {
        selectedTab = .history
        historyPath = [runID]
    }

    private func completeOnboarding(requestAccess: Bool) async {
        if requestAccess {
            await container.refresh(requestAccess: true)
            guard container.hasRequestedAccess else { return }
        }
        await settingsViewModel.completeOnboarding()
    }

    private func reloadRunSurfaces() async {
        await historyViewModel.load()
        await recordsViewModel.load()
    }

    private func bootstrapPreferences() async {
        await settingsViewModel.load()
        isBootstrappingPreferences = false
    }

    private func builderLoadFailureMessage(_ error: WorkoutRepositoryError) -> String {
        switch error {
        case let .workoutNotFound(id):
            return "Workout \(id) could not be found."
        case .syncJobNotFound:
            return "A sync record could not be found."
        case let .underlying(description):
            return description
        }
    }

    private func preferencesErrorMessage(_ error: PreferencesStoreError) -> String {
        switch error {
        case let .underlying(description):
            return "Couldn't save onboarding: \(description)"
        }
    }

    private enum Tab: Hashable {
        case library
        case history
        case records
        case settings
    }

    private enum LibraryRoute: Hashable {
        case new
        case edit(Workout)

        var workout: Workout? {
            switch self {
            case .new:
                nil
            case let .edit(workout):
                workout
            }
        }
    }

    private struct BuilderLoadFailure: Identifiable {
        let workoutID: UUID
        let error: WorkoutRepositoryError

        var id: UUID { workoutID }
    }
}

@MainActor
private struct BuilderDestinationView: View {
    let container: StrideAppContainer
    let displayUnit: DisplayDistanceUnit
    @State private var viewModel: BuilderViewModel

    init(container: StrideAppContainer, workout: Workout?, displayUnit: DisplayDistanceUnit) {
        self.container = container
        self.displayUnit = displayUnit
        _viewModel = State(initialValue: BuilderViewModel(
            workoutRepository: container.workoutRepository,
            clock: container.clock,
            workout: workout
        ))
    }

    var body: some View {
        BuilderView(viewModel: viewModel, displayUnit: displayUnit)
    }
}

@MainActor
private struct RunDetailDestinationView: View {
    let displayUnit: DisplayDistanceUnit
    @State private var viewModel: RunDetailViewModel

    init(container: StrideAppContainer, runID: UUID, displayUnit: DisplayDistanceUnit) {
        self.displayUnit = displayUnit
        _viewModel = State(initialValue: RunDetailViewModel(
            runID: runID,
            runHistoryRepository: container.runHistoryRepository,
            workoutRepository: container.workoutRepository
        ))
    }

    var body: some View {
        RunDetailView(viewModel: viewModel, displayUnit: displayUnit)
    }
}
