import DesignSystem
import SwiftUI

/// One row in `HistoryView`'s list: a completed run's date, distance,
/// duration, average pace, and attributed workout name (if any).
struct HistoryRowView: View {
    let row: HistoryViewModel.Row
    let displayUnit: DisplayDistanceUnit

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.extraSmall) {
            HStack {
                Text(Self.dateFormatter.string(from: row.date))
                    .font(Typography.headline)
                    .foregroundStyle(Colors.primaryText)
                Spacer()
                Text(UnitFormatter.distanceString(meters: row.distanceMeters, unit: displayUnit))
                    .font(Typography.metricMedium)
                    .foregroundStyle(Colors.primaryText)
            }
            HStack {
                Text(UnitFormatter.durationString(seconds: row.durationSeconds))
                if let pace = row.averagePaceSecondsPerMeter {
                    Text(UnitFormatter.paceString(secondsPerMeter: pace, unit: displayUnit))
                }
                Spacer()
                if let workoutName = row.attributedWorkoutName {
                    Text(workoutName)
                        .lineLimit(1)
                }
            }
            .font(Typography.caption)
            .foregroundStyle(Colors.secondaryText)
        }
        .padding(.vertical, Spacing.extraSmall)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }()
}
