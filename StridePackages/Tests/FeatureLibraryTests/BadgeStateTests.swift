import Testing
import Foundation
@testable import FeatureLibrary
import DomainKit

/// Exhaustive coverage of `BadgeState.from(_:)`'s mapping from every
/// `SyncJobState` case (and `nil`).
@Suite("BadgeState")
struct BadgeStateTests {
    private let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)

    private func job(_ state: SyncJobState) -> SyncJob {
        SyncJob(workoutID: UUID(), state: state, createdAt: referenceDate, updatedAt: referenceDate)
    }

    @Test("nil job maps to .notSynced")
    func nilJobMapsToNotSynced() {
        #expect(BadgeState.from(nil) == .notSynced)
    }

    @Test("every SyncJobState case maps to its corresponding BadgeState case", arguments: [
        (SyncJobState.draft, BadgeState.notSynced),
        (SyncJobState.pending, BadgeState.pending),
        (SyncJobState.syncing, BadgeState.syncing),
        (SyncJobState.synced, BadgeState.synced),
        (SyncJobState.stale, BadgeState.stale),
        (SyncJobState.abandoned, BadgeState.abandoned),
        (SyncJobState.completedRunLinked, BadgeState.completedRunLinked)
    ])
    func mapsEveryState(state: SyncJobState, expected: BadgeState) {
        #expect(BadgeState.from(job(state)) == expected)
    }

    @Test("every SyncFailureReason is wrapped, unmodified, into .failed", arguments: [
        SyncFailureReason.notAuthorized,
        .invalidComposition,
        .noPairedWatch,
        .transient(description: "busy")
    ])
    func mapsFailureReasons(reason: SyncFailureReason) {
        #expect(BadgeState.from(job(.failed(reason))) == .failed(reason))
    }
}
