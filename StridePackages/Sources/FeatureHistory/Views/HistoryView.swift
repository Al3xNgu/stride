import DesignSystem
import DomainKit
import SwiftUI

/// The run history screen: every non-tombstoned completed run, sectioned by
/// month, newest first.
///
/// Like `FeatureLibrary/Views/LibraryView.swift`, navigation to the detail
/// screen is a plain closure (`onOpenRun`), not a `NavigationLink` to a
/// concrete destination — `FeatureHistory` and the composition root (task
/// 1.16) decide how to push `RunDetailView`.
public struct HistoryView: View {
    @Bindable private var viewModel: HistoryViewModel
    private let displayUnit: DisplayDistanceUnit
    private let onOpenRun: (UUID) -> Void

    /// Creates the history screen.
    /// - Parameters:
    ///   - viewModel: The screen's state and mutations.
    ///   - displayUnit: The unit distance/pace values are shown in. A future
    ///     task wires this to `UserPreferences`; defaults to kilometers
    ///     (matching `LibraryView`/`BuilderView`).
    ///   - onOpenRun: Called with a run's id when the user taps its row.
    public init(
        viewModel: HistoryViewModel,
        displayUnit: DisplayDistanceUnit = .kilometers,
        onOpenRun: @escaping (UUID) -> Void = { _ in }
    ) {
        self.viewModel = viewModel
        self.displayUnit = displayUnit
        self.onOpenRun = onOpenRun
    }

    public var body: some View {
        List {
            if let loadError = viewModel.loadError {
                Section {
                    loadErrorView(loadError)
                }
            }

            if viewModel.isEmpty, !viewModel.isLoading {
                Text("No runs yet. Completed runs from Apple Watch will appear here.")
                    .foregroundStyle(Colors.secondaryText)
            }

            ForEach(viewModel.sections) { section in
                Section(header: Text(Self.monthTitle(for: section.monthStart))) {
                    ForEach(section.rows) { row in
                        Button {
                            onOpenRun(row.id)
                        } label: {
                            HistoryRowView(row: row, displayUnit: displayUnit)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .navigationTitle("History")
        .task {
            await viewModel.load()
        }
        .refreshable {
            await viewModel.load()
        }
    }

    @ViewBuilder
    private func loadErrorView(_ error: RunHistoryRepositoryError) -> some View {
        VStack(alignment: .leading, spacing: Spacing.extraSmall) {
            Label("Couldn't load history", systemImage: "exclamationmark.triangle")
                .foregroundStyle(Colors.danger)
            Text(message(for: error))
                .foregroundStyle(Colors.secondaryText)
            Button("Retry") {
                Task { await viewModel.load() }
            }
            .disabled(viewModel.isLoading)
        }
    }

    private func message(for error: RunHistoryRepositoryError) -> String {
        switch error {
        case .runNotFound:
            return "A run could not be found."
        case .personalBestNotFound:
            return "The run history store could not find a required record."
        case let .underlying(description):
            return "Couldn't load run history: \(description)"
        }
    }

    private static func monthTitle(for monthStart: Date) -> String {
        monthTitleFormatter.string(from: monthStart)
    }

    private static let monthTitleFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "LLLL yyyy"
        return formatter
    }()
}

#if DEBUG
#Preview("History") {
    NavigationStack {
        HistoryView(
            viewModel: HistoryViewModel(
                runHistoryRepository: PreviewFixtures.makeRunHistoryRepository(),
                workoutRepository: PreviewWorkoutRepository()
            )
        )
    }
}

#Preview("Empty history") {
    NavigationStack {
        HistoryView(
            viewModel: HistoryViewModel(
                runHistoryRepository: PreviewRunHistoryRepository(),
                workoutRepository: PreviewWorkoutRepository()
            )
        )
    }
}
#endif
