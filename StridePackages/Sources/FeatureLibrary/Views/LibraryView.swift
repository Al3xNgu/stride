import DesignSystem
import DomainKit
import SwiftUI

/// The workout library screen: every saved workout with its sync badge,
/// send-to-watch / schedule-by-date / retry actions, and delete.
///
/// Navigation to the builder (new/edit) is intentionally *not* a
/// `NavigationLink` to a concrete destination view: `FeatureLibrary` may not
/// import `FeatureBuilder` (CLAUDE.md rule 1 — feature modules don't import
/// each other), so this view only reports taps via `onEditWorkout`/
/// `onNewWorkout` closures. The composition root (task 1.16) wires these to
/// push/present the real builder screen.
public struct LibraryView: View {
    @Bindable private var viewModel: LibraryViewModel
    @Environment(\.scenePhase) private var scenePhase

    private let displayUnit: DisplayDistanceUnit
    private let onEditWorkout: (UUID) -> Void
    private let onNewWorkout: () -> Void

    @State private var scheduleTarget: ScheduleTarget?
    @State private var failureDetail: FailureDetail?

    /// Creates the library screen.
    /// - Parameters:
    ///   - viewModel: The screen's state and mutations.
    ///   - displayUnit: The unit distance previews are shown in. A future
    ///     task wires this to `UserPreferences`; the MVP library defaults to
    ///     kilometers (matching `BuilderView`).
    ///   - onEditWorkout: Called with a workout's id when the user taps its
    ///     row.
    ///   - onNewWorkout: Called when the user taps the "New" toolbar button.
    public init(
        viewModel: LibraryViewModel,
        displayUnit: DisplayDistanceUnit = .kilometers,
        onEditWorkout: @escaping (UUID) -> Void = { _ in },
        onNewWorkout: @escaping () -> Void = {}
    ) {
        self.viewModel = viewModel
        self.displayUnit = displayUnit
        self.onEditWorkout = onEditWorkout
        self.onNewWorkout = onNewWorkout
    }

    public var body: some View {
        List {
            if viewModel.rows.isEmpty, !viewModel.isLoading {
                Text("No workouts yet. Tap \"New\" to build one.")
                    .foregroundStyle(Colors.secondaryText)
            }

            ForEach(viewModel.rows) { row in
                Button {
                    onEditWorkout(row.workout.id)
                } label: {
                    HStack {
                        LibraryRowView(row: row, displayUnit: displayUnit) { reason in
                            failureDetail = FailureDetail(reason: reason)
                        }
                        if viewModel.isSending(workoutID: row.workout.id) {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        Task { await viewModel.delete(workoutID: row.workout.id) }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .swipeActions(edge: .leading) {
                    Button {
                        scheduleTarget = ScheduleTarget(workoutID: row.workout.id, workoutName: row.workout.name)
                    } label: {
                        Label("Send", systemImage: "applewatch")
                    }
                    .tint(Colors.accent)
                    .disabled(viewModel.isSending(workoutID: row.workout.id))
                }
                .contextMenu {
                    contextMenuItems(for: row)
                }
            }
        }
        .navigationTitle("Library")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    onNewWorkout()
                } label: {
                    Label("New", systemImage: "plus")
                }
                .accessibilityIdentifier("library.newWorkout")
            }
        }
        .task {
            await viewModel.reconcileOnForeground()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task { await viewModel.reconcileOnForeground() }
        }
        .sheet(item: $scheduleTarget) { target in
            ScheduleSheetView(
                workoutName: target.workoutName,
                now: viewModel.now,
                onSendNow: {
                    scheduleTarget = nil
                    Task { await viewModel.sendToWatch(workoutID: target.workoutID) }
                },
                onSchedule: { date in
                    scheduleTarget = nil
                    Task { await viewModel.scheduleForDate(workoutID: target.workoutID, date: date) }
                },
                onCancel: {
                    scheduleTarget = nil
                }
            )
        }
        .alert(item: $failureDetail) { detail in
            Alert(title: Text("Send Failed"), message: Text(SyncFailurePresenter.message(for: detail.reason)))
        }
        .alert(
            "Couldn't Complete That Action",
            isPresented: Binding(
                get: { viewModel.sendError != nil },
                set: { isPresented in if !isPresented { viewModel.clearSendError() } }
            )
        ) {
            Button("OK") { viewModel.clearSendError() }
        } message: {
            if let sendError = viewModel.sendError {
                Text(LibrarySendErrorPresenter.message(for: sendError))
            }
        }
    }

    @ViewBuilder
    private func contextMenuItems(for row: LibraryViewModel.Row) -> some View {
        Button {
            Task { await viewModel.sendToWatch(workoutID: row.workout.id) }
        } label: {
            Label("Send to Watch Now", systemImage: "applewatch")
        }
        .accessibilityIdentifier("library.sendToWatchNow")
        Button {
            scheduleTarget = ScheduleTarget(workoutID: row.workout.id, workoutName: row.workout.name)
        } label: {
            Label("Schedule…", systemImage: "calendar")
        }
        if isRetryable(row.badgeState) {
            Button {
                Task { await viewModel.retryFailed(workoutID: row.workout.id) }
            } label: {
                Label("Retry", systemImage: "arrow.clockwise")
            }
        }
        Button(role: .destructive) {
            Task { await viewModel.delete(workoutID: row.workout.id) }
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    private func isRetryable(_ state: BadgeState) -> Bool {
        switch state {
        case .failed, .abandoned:
            return true
        case .notSynced, .pending, .syncing, .synced, .stale, .completedRunLinked:
            return false
        }
    }
}

/// Identifies which row's schedule sheet is presented.
private struct ScheduleTarget: Identifiable {
    let workoutID: UUID
    let workoutName: String
    var id: UUID { workoutID }
}

/// Identifies the failure reason currently shown in the detail alert.
private struct FailureDetail: Identifiable {
    let id = UUID()
    let reason: SyncFailureReason
}

#if DEBUG
#Preview("Library") {
    let repository = PreviewFixtures.makeRepository()
    NavigationStack {
        LibraryView(
            viewModel: LibraryViewModel(
                workoutRepository: repository,
                syncCoordinator: SyncCoordinator(
                    repository: repository,
                    watchSyncService: PreviewWatchSyncService(),
                    clock: PreviewClock()
                ),
                clock: PreviewClock()
            )
        )
    }
}

#Preview("Empty library") {
    let repository = PreviewWorkoutRepository()
    NavigationStack {
        LibraryView(
            viewModel: LibraryViewModel(
                workoutRepository: repository,
                syncCoordinator: SyncCoordinator(
                    repository: repository,
                    watchSyncService: PreviewWatchSyncService(),
                    clock: PreviewClock()
                ),
                clock: PreviewClock()
            )
        )
    }
}
#endif
