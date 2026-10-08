import DesignSystem
import DomainKit
import SwiftUI

/// The run detail screen: summary header, splits table, and heart-rate
/// summary for a single completed run.
public struct RunDetailView: View {
    @Bindable private var viewModel: RunDetailViewModel
    private let displayUnit: DisplayDistanceUnit

    /// Creates the run detail screen.
    /// - Parameters:
    ///   - viewModel: The screen's state and mutations, already constructed
    ///     with the target run's id.
    ///   - displayUnit: The unit distance/pace values are shown in. Defaults
    ///     to kilometers (matching `HistoryView`).
    public init(viewModel: RunDetailViewModel, displayUnit: DisplayDistanceUnit = .kilometers) {
        self.viewModel = viewModel
        self.displayUnit = displayUnit
    }

    public var body: some View {
        List {
            if let loadError = viewModel.loadError {
                Section {
                    loadErrorView(loadError)
                }
            }

            if let run = viewModel.run {
                Section {
                    summaryHeader(for: run)
                }
                if !viewModel.splitRows.isEmpty {
                    Section("Splits") {
                        ForEach(viewModel.splitRows) { splitRow in
                            splitRowView(splitRow)
                        }
                    }
                }
                if run.heartRate.averageBPM != nil || run.heartRate.maxBPM != nil {
                    Section("Heart Rate") {
                        heartRateRow(for: run)
                    }
                }
            } else if viewModel.loadError != nil {
                Text("This run couldn't be loaded.")
                    .foregroundStyle(Colors.secondaryText)
            }
        }
        .navigationTitle("Run Detail")
        .task {
            await viewModel.load()
        }
    }

    @ViewBuilder
    private func loadErrorView(_ error: RunHistoryRepositoryError) -> some View {
        VStack(alignment: .leading, spacing: Spacing.extraSmall) {
            Label("Couldn't load run details", systemImage: "exclamationmark.triangle")
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
            return "This run is no longer available."
        case .personalBestNotFound:
            return "A required record could not be found."
        case let .underlying(description):
            return "Couldn't load run details: \(description)"
        }
    }

    @ViewBuilder
    private func summaryHeader(for run: CompletedRun) -> some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            Text(UnitFormatter.distanceString(meters: run.distanceMeters, unit: displayUnit))
                .font(Typography.metricLarge)
            HStack {
                Text(UnitFormatter.durationString(seconds: run.durationSeconds))
                if let pace = run.averagePace {
                    Text(UnitFormatter.paceString(secondsPerMeter: pace, unit: displayUnit))
                }
            }
            .font(Typography.metricMedium)
            .foregroundStyle(Colors.secondaryText)
            if let workoutName = viewModel.attributedWorkoutName {
                Text("From \(workoutName)")
                    .font(Typography.caption)
                    .foregroundStyle(Colors.secondaryText)
            }
        }
        .padding(.vertical, Spacing.small)
    }

    @ViewBuilder
    private func splitRowView(_ splitRow: RunDetailViewModel.SplitRow) -> some View {
        HStack {
            Text("\(splitRow.index + 1)")
                .foregroundStyle(Colors.secondaryText)
            Spacer()
            Text(UnitFormatter.distanceString(meters: splitRow.distanceMeters, unit: displayUnit, decimals: 1))
            Spacer()
            Text(UnitFormatter.durationString(seconds: splitRow.durationSeconds))
            Spacer()
            if let pace = splitRow.paceSecondsPerMeter {
                Text(UnitFormatter.paceString(secondsPerMeter: pace, unit: displayUnit))
            }
        }
        .font(Typography.metricMedium)
    }

    @ViewBuilder
    private func heartRateRow(for run: CompletedRun) -> some View {
        HStack {
            if let averageBPM = run.heartRate.averageBPM {
                labeledMetric("Avg", value: "\(Int(averageBPM.rounded())) bpm")
            }
            Spacer()
            if let maxBPM = run.heartRate.maxBPM {
                labeledMetric("Max", value: "\(Int(maxBPM.rounded())) bpm")
            }
        }
    }

    @ViewBuilder
    private func labeledMetric(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.extraSmall) {
            Text(label)
                .font(Typography.caption)
                .foregroundStyle(Colors.secondaryText)
            Text(value)
                .font(Typography.metricMedium)
        }
    }
}

#if DEBUG
#Preview("Run Detail") {
    let harness = PreviewFixtures.makeDetailHarness()
    NavigationStack {
        RunDetailView(
            viewModel: RunDetailViewModel(
                runID: harness.runID,
                runHistoryRepository: harness.runHistoryRepository,
                workoutRepository: harness.workoutRepository
            )
        )
    }
}
#endif
