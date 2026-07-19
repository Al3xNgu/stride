import DesignSystem
import SwiftUI

/// A small, colored label rendering a workout row's `BadgeState`.
struct BadgeView: View {
    let state: BadgeState

    var body: some View {
        Label(LibraryBadgePresenter.label(for: state), systemImage: LibraryBadgePresenter.systemImageName(for: state))
            .font(Typography.caption)
            .foregroundStyle(color)
    }

    private var color: Color {
        switch state {
        case .notSynced:
            return Colors.secondaryText
        case .pending, .syncing:
            return Colors.accent
        case .synced, .completedRunLinked:
            return Colors.success
        case .stale:
            return Colors.warning
        case .failed, .abandoned:
            return Colors.danger
        }
    }
}

#if DEBUG
#Preview {
    VStack(alignment: .leading, spacing: Spacing.small) {
        BadgeView(state: .notSynced)
        BadgeView(state: .pending)
        BadgeView(state: .syncing)
        BadgeView(state: .synced)
        BadgeView(state: .stale)
        BadgeView(state: .failed(.noPairedWatch))
        BadgeView(state: .abandoned)
        BadgeView(state: .completedRunLinked)
    }
    .padding()
}
#endif
