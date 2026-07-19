import Testing
@testable import FeatureLibrary
import DomainKit

/// Exhaustive coverage of `SyncFailurePresenter`, proving every
/// `SyncFailureReason` case produces non-empty, reason-specific copy.
@Suite("SyncFailurePresenter")
struct SyncFailurePresenterTests {
    @Test("message(for:) is non-empty for every SyncFailureReason case", arguments: [
        SyncFailureReason.notAuthorized,
        .invalidComposition,
        .noPairedWatch,
        .transient(description: "network busy")
    ])
    func messagesAreNonEmpty(reason: SyncFailureReason) {
        #expect(!SyncFailurePresenter.message(for: reason).isEmpty)
    }

    @Test("the transient reason's description is included verbatim in its message")
    func transientMessageIncludesDescription() {
        let message = SyncFailurePresenter.message(for: .transient(description: "network busy"))
        #expect(message.contains("network busy"))
    }

    @Test("every SyncFailureReason case produces a distinct message")
    func messagesAreDistinctPerCase() {
        let reasons: [SyncFailureReason] = [.notAuthorized, .invalidComposition, .noPairedWatch, .transient(description: "x")]
        let messages = reasons.map(SyncFailurePresenter.message(for:))
        #expect(Set(messages).count == messages.count)
    }
}
