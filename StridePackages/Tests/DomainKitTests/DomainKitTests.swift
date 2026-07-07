import Testing
@testable import DomainKit

/// Trivial smoke test proving the `DomainKit` target and its test target
/// resolve and run under `swift test`. Real unit tests for entities,
/// use cases, and policies land in later tasks (0.3, 0.4, ...).
@Suite("DomainKit package skeleton")
struct DomainKitTests {
    @Test("Entities namespace marker exists and module compiles")
    func packageSkeletonCompiles() {
        #expect(Bool(true))
    }
}
