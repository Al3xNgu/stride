import DomainKit
import Foundation

/// An in-memory, controllable `Clock` fake for deterministic tests.
///
/// `now()` returns a settable date that only moves when a test explicitly
/// calls `advance(by:)`, rather than depending on wall-clock time
/// (CLAUDE.md rule 5 — every `DomainKit/Ports` protocol ships a
/// `TestSupport` fake in the same PR).
///
/// Not internally synchronized: intended for single-threaded test usage,
/// like every other fake in this module.
public final class FakeClock: Clock, @unchecked Sendable {
    /// The date `now()` currently returns.
    public var currentDate: Date

    /// Creates a fake clock pinned at `currentDate`.
    public init(currentDate: Date = Date(timeIntervalSince1970: 0)) {
        self.currentDate = currentDate
    }

    public func now() -> Date {
        currentDate
    }

    /// Advances the fake clock forward by `seconds` (negative values move it
    /// backward).
    public func advance(by seconds: TimeInterval) {
        currentDate = currentDate.addingTimeInterval(seconds)
    }
}
