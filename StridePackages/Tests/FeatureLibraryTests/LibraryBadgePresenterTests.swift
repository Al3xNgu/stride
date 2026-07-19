import Testing
@testable import FeatureLibrary
import DomainKit

/// Exhaustive coverage of `LibraryBadgePresenter`'s label/symbol mapping,
/// proving every `BadgeState` case produces distinct, non-empty copy.
@Suite("LibraryBadgePresenter")
struct LibraryBadgePresenterTests {
    private static let allStates: [BadgeState] = [
        .notSynced, .pending, .syncing, .synced, .stale,
        .failed(.noPairedWatch), .abandoned, .completedRunLinked
    ]

    @Test("label(for:) is non-empty for every BadgeState case", arguments: allStates)
    func labelsAreNonEmpty(state: BadgeState) {
        #expect(!LibraryBadgePresenter.label(for: state).isEmpty)
    }

    @Test("systemImageName(for:) is non-empty for every BadgeState case", arguments: allStates)
    func symbolNamesAreNonEmpty(state: BadgeState) {
        #expect(!LibraryBadgePresenter.systemImageName(for: state).isEmpty)
    }

    @Test("every BadgeState case produces a distinct label")
    func labelsAreDistinctPerCase() {
        let labels = Self.allStates.map(LibraryBadgePresenter.label(for:))
        #expect(Set(labels).count == labels.count)
    }
}
