import DesignSystem
import DomainKit
import SwiftUI

/// The personal-records board: one entry per MVP milestone, each pushing to
/// its full PR history, with a loose `onOpenRun` hook for jumping to a
/// record's source run in `FeatureHistory` — same pattern as
/// `FeatureLibrary/Views/LibraryView.swift`'s `onEditWorkout`.
public struct RecordsView: View {
    @Bindable private var viewModel: RecordsViewModel
    private let displayUnit: DisplayDistanceUnit
    private let onOpenRun: (UUID) -> Void

    /// Creates the records screen.
    /// - Parameters:
    ///   - viewModel: The screen's state and mutations.
    ///   - displayUnit: The unit pace values are shown in. Defaults to
    ///     kilometers (matching `HistoryView`/`LibraryView`).
    ///   - onOpenRun: Called with a `CompletedRun.id` when the user taps a
    ///     record's source run in its history. Navigation stays loose here —
    ///     the composition root (task 1.16) wires this to push
    ///     `FeatureHistory`'s `RunDetailView`.
    public init(
        viewModel: RecordsViewModel,
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

            ForEach(viewModel.board) { entry in
                NavigationLink {
                    RecordHistoryView(
                        milestone: entry.milestone,
                        history: viewModel.history(for: entry.milestone.id),
                        displayUnit: displayUnit,
                        onOpenRun: onOpenRun
                    )
                } label: {
                    RecordsRowView(entry: entry, displayUnit: displayUnit)
                }
            }
        }
        .navigationTitle("Records")
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
            Label("Couldn't load records", systemImage: "exclamationmark.triangle")
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
            return "A source run could not be found."
        case .personalBestNotFound:
            return "A personal record could not be found."
        case let .underlying(description):
            return "Couldn't load records: \(description)"
        }
    }
}

#if DEBUG
#Preview("Records") {
    NavigationStack {
        RecordsView(
            viewModel: RecordsViewModel(runHistoryRepository: PreviewFixtures.makeRunHistoryRepository())
        )
    }
}

#Preview("Empty records") {
    NavigationStack {
        RecordsView(
            viewModel: RecordsViewModel(runHistoryRepository: PreviewRunHistoryRepository())
        )
    }
}
#endif
