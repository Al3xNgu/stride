import DomainKit
import Foundation

/// An in-memory `PreferencesStore` fake.
///
/// Starts pre-loaded with `storedPreferences` (defaulting to
/// `UserPreferences()`), records every saved value in `savedPreferences` for
/// call-order assertions, and can be made to fail via `errorToThrow`
/// (CLAUDE.md rule 5).
///
/// Not internally synchronized: intended for single-threaded test usage.
public final class FakePreferencesStore: PreferencesStore, @unchecked Sendable {
    /// The value `load()` currently returns.
    public var storedPreferences: UserPreferences
    /// When set, every call throws this error instead of succeeding.
    public var errorToThrow: Error?
    /// Number of times `load()` has been called.
    public private(set) var loadCallCount = 0
    /// Every value passed to `save(_:)`, in call order.
    public private(set) var savedPreferences: [UserPreferences] = []

    /// Creates a fake preferences store pre-loaded with `storedPreferences`.
    public init(storedPreferences: UserPreferences = UserPreferences()) {
        self.storedPreferences = storedPreferences
    }

    public func load() async throws -> UserPreferences {
        loadCallCount += 1
        if let errorToThrow {
            throw errorToThrow
        }
        return storedPreferences
    }

    public func save(_ preferences: UserPreferences) async throws {
        if let errorToThrow {
            throw errorToThrow
        }
        storedPreferences = preferences
        savedPreferences.append(preferences)
    }
}
