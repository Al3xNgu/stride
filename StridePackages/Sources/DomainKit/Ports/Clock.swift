import Foundation

/// An abstraction over "the current time", so domain and use-case logic that
/// needs `Date()` is deterministically testable (CLAUDE.md rule 5 — all
/// non-pure access goes through a `DomainKit/Ports` protocol with a
/// `DataKit` implementation and a `TestSupport` fake).
///
/// Named `Clock` (matching `docs/TASKBOARD.md`) rather than `DateProvider`:
/// this declares a distinct type in `DomainKit`'s own module namespace, so it
/// does not conflict with the standard library's `Clock` protocol (which has
/// associated `Instant`/`Duration` types and is not used anywhere in this
/// module) — Swift resolves the unqualified name `Clock` to this module's
/// own declaration for every call site within `DomainKit` and its clients.
public protocol Clock: Sendable {
    /// The current date/time.
    func now() -> Date
}
