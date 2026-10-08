import DesignSystem
import DomainKit
import SwiftUI

/// One row on `RecordsView`'s board: a milestone's display name plus its
/// current record's time/pace, or an empty-slot message when no record has
/// been set yet.
struct RecordsRowView: View {
    let entry: RecordsViewModel.BoardEntry
    let displayUnit: DisplayDistanceUnit

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.extraSmall) {
            Text(entry.milestone.displayName)
                .font(Typography.headline)
                .foregroundStyle(Colors.primaryText)

            if let personalBest = entry.personalBest {
                HStack {
                    Text(UnitFormatter.durationString(seconds: personalBest.elapsedSeconds))
                        .font(Typography.metricMedium)
                    Text(
                        UnitFormatter.paceString(
                            secondsPerMeter: paceSecondsPerMeter(personalBest),
                            unit: displayUnit
                        )
                    )
                    .font(Typography.caption)
                    .foregroundStyle(Colors.secondaryText)
                }
                if let workoutName = entry.sourceWorkoutName {
                    Text(workoutName)
                        .font(Typography.caption)
                        .foregroundStyle(Colors.secondaryText)
                        .lineLimit(1)
                }
            } else {
                Text("No record yet")
                    .font(Typography.body)
                    .foregroundStyle(Colors.secondaryText)
            }
        }
        .padding(.vertical, Spacing.extraSmall)
    }

    /// The milestone-distance pace implied by `personalBest.elapsedSeconds`,
    /// in seconds-per-meter (CLAUDE.md rule 4) — `PersonalBest` stores only
    /// elapsed time, so pace is derived here from the milestone's known
    /// distance rather than stored redundantly.
    private func paceSecondsPerMeter(_ personalBest: PersonalBest) -> Double {
        guard entry.milestone.distanceMeters > 0 else { return 0 }
        return personalBest.elapsedSeconds / entry.milestone.distanceMeters
    }
}
