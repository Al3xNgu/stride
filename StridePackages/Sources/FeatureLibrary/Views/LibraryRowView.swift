import DesignSystem
import DomainKit
import SwiftUI

/// One row in `LibraryView`'s list: the workout's name, a planned-totals
/// summary (via `WorkoutSummaryPolicy` + `UnitFormatter`, matching
/// `FeatureBuilder`'s summary rendering), and its sync badge.
///
/// Tapping the badge while it is `.failed` calls `onShowFailureDetail` with
/// the failure reason, for the failure-reason detail alert `LibraryView`
/// owns — the row itself holds no presentation state.
struct LibraryRowView: View {
    let row: LibraryViewModel.Row
    let displayUnit: DisplayDistanceUnit
    let onShowFailureDetail: (SyncFailureReason) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.extraSmall) {
            HStack {
                Text(row.workout.name.isEmpty ? "Untitled Workout" : row.workout.name)
                    .font(Typography.headline)
                    .foregroundStyle(Colors.primaryText)
                Spacer()
                badge
            }
            Text(summaryText)
                .font(Typography.caption)
                .foregroundStyle(Colors.secondaryText)
        }
        .padding(.vertical, Spacing.extraSmall)
    }

    @ViewBuilder
    private var badge: some View {
        if case let .failed(reason) = row.badgeState {
            Button {
                onShowFailureDetail(reason)
            } label: {
                BadgeView(state: row.badgeState)
            }
            .buttonStyle(.plain)
        } else {
            BadgeView(state: row.badgeState)
        }
    }

    /// An honest, presentation-only rendering of the workout's planned
    /// totals, matching `BuilderView.summaryText`'s "distance + duration + N
    /// open segments" shape.
    private var summaryText: String {
        let summary = WorkoutSummaryPolicy.summarize(row.workout)
        var parts: [String] = []

        if summary.totalDistanceMeters > 0 {
            parts.append(UnitFormatter.distanceString(meters: summary.totalDistanceMeters, unit: displayUnit))
        }
        if summary.totalDurationSeconds > 0 {
            parts.append(UnitFormatter.durationString(seconds: summary.totalDurationSeconds))
        }
        if summary.hasOpenGoalSteps {
            let noun = summary.openGoalStepCount == 1 ? "segment" : "segments"
            parts.append("\(summary.openGoalStepCount) open \(noun)")
        }

        guard !parts.isEmpty else {
            return "No planned segments yet"
        }
        return parts.joined(separator: " + ")
    }
}
