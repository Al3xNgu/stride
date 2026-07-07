import Testing
import Foundation
@testable import DomainKit

/// `SyncJobState` transitions per `docs/ARCHITECTURE.md` §7:
///
/// ```
/// draft -> pending -> syncing -> synced -> (completedRunLinked | stale)
///                        |
///                        +-> failed -> pending (retry) | abandoned
/// ```
///
/// NOTE: at the entity layer (task 0.3 scope), `SyncJobState` is a plain
/// enum with no transition-guarding logic of its own — the state machine's
/// *legality rules* belong to a future `SyncCoordinator`/use case (task
/// 1.x). This suite therefore documents the state shape itself (mutability,
/// equality, every state reachable, "illegal" transitions are not rejected
/// at this layer because nothing enforces them yet) and flags that gap as a
/// design-smell for the orchestrator rather than inventing enforcement here.
@Suite("SyncJob state machine (entity-level shape)")
struct SyncJobStateMachineTests {
    private func makeJob(state: SyncJobState = .draft) -> SyncJob {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        return SyncJob(workoutID: UUID(), state: state, createdAt: now, updatedAt: now)
    }

    @Test("A freshly-created SyncJob defaults to .draft")
    func defaultsToDraft() {
        let job = makeJob()
        #expect(job.state == .draft)
    }

    @Test("state is a mutable var and can be advanced along the documented happy path")
    func happyPathIsSettable() {
        var job = makeJob()
        job.state = .pending
        #expect(job.state == .pending)
        job.state = .syncing
        #expect(job.state == .syncing)
        job.state = .synced
        #expect(job.state == .synced)
        job.state = .completedRunLinked
        #expect(job.state == .completedRunLinked)
    }

    @Test("synced can transition to stale (edit-after-sync)")
    func syncedCanGoStale() {
        var job = makeJob(state: .synced)
        job.state = .stale
        #expect(job.state == .stale)
    }

    @Test("syncing can transition to failed with any SyncFailureReason", arguments: [
        SyncFailureReason.notAuthorized,
        .invalidComposition,
        .noPairedWatch,
        .transient(description: "busy")
    ])
    func syncingCanFail(_ reason: SyncFailureReason) {
        var job = makeJob(state: .syncing)
        job.state = .failed(reason)
        #expect(job.state == .failed(reason))
    }

    @Test("failed can transition back to pending (retry) or abandoned")
    func failedCanRetryOrBeAbandoned() {
        var retried = makeJob(state: .failed(.transient(description: "timeout")))
        retried.state = .pending
        #expect(retried.state == .pending)

        var abandoned = makeJob(state: .failed(.notAuthorized))
        abandoned.state = .abandoned
        #expect(abandoned.state == .abandoned)
    }

    /// FINDING / design smell: nothing at the entity layer prevents an
    /// "illegal" transition such as `.draft` -> `.completedRunLinked`
    /// directly, or `.abandoned` -> `.syncing`. `SyncJobState` is a plain
    /// data enum; transition legality is presumably meant to live in a
    /// `SyncCoordinator` (per ARCHITECTURE.md §6) that does not exist yet.
    /// This test pins CURRENT (permissive) behavior so it is visible, not
    /// silently assumed, and flags the gap in the summary for the
    /// orchestrator to schedule the state-machine-enforcing use case.
    @Test("Entity layer does NOT reject illegal transitions (no guard exists yet — design smell)")
    func illegalTransitionsAreNotRejectedAtEntityLevel() {
        var job = makeJob(state: .draft)
        job.state = .completedRunLinked // skips pending/syncing/synced entirely
        #expect(job.state == .completedRunLinked)

        var abandonedJob = makeJob(state: .abandoned)
        abandonedJob.state = .syncing // resurrecting an abandoned job
        #expect(abandonedJob.state == .syncing)
    }

    @Test("Equal states with equal failure reasons compare equal")
    func equalFailedStatesAreEqual() {
        let first = SyncJobState.failed(.transient(description: "x"))
        let second = SyncJobState.failed(.transient(description: "x"))
        #expect(first == second)
    }

    @Test("failed states with different transient descriptions are NOT equal")
    func differentTransientDescriptionsAreNotEqual() {
        let first = SyncJobState.failed(.transient(description: "x"))
        let second = SyncJobState.failed(.transient(description: "y"))
        #expect(first != second)
    }

    @Test("failed states with different reason cases are NOT equal")
    func differentFailureReasonCasesAreNotEqual() {
        #expect(SyncJobState.failed(.notAuthorized) != SyncJobState.failed(.noPairedWatch))
    }

    @Test("SyncJob attemptCount defaults to zero and is mutable")
    func attemptCountDefaultsToZero() {
        var job = makeJob()
        #expect(job.attemptCount == 0)
        job.attemptCount += 1
        #expect(job.attemptCount == 1)
    }

    @Test("SyncJob planIdentifier and scheduledDate default to nil")
    func optionalFieldsDefaultNil() {
        let job = makeJob()
        #expect(job.planIdentifier == nil)
        #expect(job.scheduledDate == nil)
    }
}
