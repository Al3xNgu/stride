import DesignSystem
import DomainKit
import SwiftUI

/// A single milestone's full PR history: every stored record, current
/// record first, each row opening its source run via `onOpenRun`.
///
/// Lives inside `FeatureRecords` (not a separate feature module), so it uses
/// a plain `NavigationLink` from `RecordsView` rather than a closure hook —
/// the loose `onOpenRun(UUID)` closure is reserved for the one boundary that
/// genuinely crosses feature modules: jumping to `FeatureHistory`'s run
/// detail screen.
struct RecordHistoryView: View {
    let milestone: Milestone
    let history: [PersonalBest]
    let displayUnit: DisplayDistanceUnit
    let onOpenRun: (UUID) -> Void

    var body: some View {
        List {
            if history.isEmpty {
                Text("No record yet")
                    .foregroundStyle(Colors.secondaryText)
            }
            ForEach(history) { personalBest in
                Button {
                    onOpenRun(personalBest.completedRunID)
                } label: {
                    HStack {
                        Text(UnitFormatter.durationString(seconds: personalBest.elapsedSeconds))
                            .font(Typography.metricMedium)
                            .foregroundStyle(Colors.primaryText)
                        Spacer()
                        Text(Self.dateFormatter.string(from: personalBest.achievedAt))
                            .font(Typography.caption)
                            .foregroundStyle(Colors.secondaryText)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .navigationTitle(milestone.displayName)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }()
}
