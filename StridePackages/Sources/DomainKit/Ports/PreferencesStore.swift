import Foundation

/// A typed error surfaced by a `PreferencesStore` implementation.
///
/// Kept intentionally small: the `UserDefaults`-backed adapter
/// (`docs/ARCHITECTURE.md` §9.4) has almost no failure modes of its own, so
/// every unexpected failure collapses into `.underlying` with a
/// human-readable description rather than inventing speculative cases.
public enum PreferencesStoreError: Error, Equatable, Hashable, Sendable {
    /// An unexpected underlying failure, with a human-readable description.
    case underlying(String)
}

/// Reads and writes the single `UserPreferences` value.
///
/// Abstracts the `UserDefaults` adapter described in
/// `docs/ARCHITECTURE.md` §4/§9.4 behind a protocol so DomainKit never
/// imports `Foundation.UserDefaults`-adjacent APIs directly, and so features
/// can be tested against `TestSupport`'s `FakePreferencesStore` without a
/// real `UserDefaults` suite.
public protocol PreferencesStore: Sendable {
    /// Loads the current preferences, or `UserPreferences()` defaults if
    /// none have been saved yet.
    func load() async throws -> UserPreferences

    /// Persists `preferences`, replacing any previously-saved value.
    func save(_ preferences: UserPreferences) async throws
}
