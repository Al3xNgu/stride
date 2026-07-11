import DomainKit
import Foundation

/// `PreferencesStore` backed by `UserDefaults` (`docs/ARCHITECTURE.md` §9.4:
/// "Units, default paces, flags, onboarding state → UserDefaults... Tiny,
/// non-relational, no migration needs").
///
/// Persists the entire `UserPreferences` value as a single JSON-encoded blob
/// under one namespaced key (``preferencesKey``), rather than exploding it
/// into one `UserDefaults` key per field. A single blob is the simplest
/// migration story available: `UserPreferences` already supplies its own
/// per-field defaults via its designated initializer, so evolving the entity
/// (adding a field) is a `DomainKit`-only concern — this adapter never needs
/// per-key migration logic.
///
/// `UserDefaults` is injected (default `.standard`) rather than hardcoded
/// inside each method. `docs/ARCHITECTURE.md` §10 calls out an App Group
/// container as a day-one decision only for the *SwiftData* store (to serve
/// a future widget extension); it does not mandate one for these
/// `UserDefaults`-backed preferences. Making the suite injectable here
/// future-proofs that path anyway at negligible cost: a caller that later
/// needs widget access simply passes `UserDefaults(suiteName:)` in. Wiring
/// the actual App Group suite name happens at the composition root
/// (task 1.16), never inside this type.
///
/// `@unchecked Sendable` is sound: every stored property is an immutable
/// `let`; `UserDefaults` is documented thread-safe; the shared JSON coders
/// are never mutated after init and build only call-local state during
/// encode/decode, so concurrent `load`/`save` calls share no mutable state.
public final class UserDefaultsPreferencesStore: PreferencesStore, @unchecked Sendable {
    /// The `UserDefaults` key under which the encoded `UserPreferences` blob
    /// is stored.
    public static let preferencesKey = "stride.userPreferences"

    private let userDefaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    /// Creates a store backed by `userDefaults` (defaults to `.standard`).
    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    /// Loads the current preferences, or `UserPreferences()` defaults if
    /// nothing has been saved yet under ``preferencesKey``.
    ///
    /// The port contract is silent on corrupted persisted data; per
    /// CLAUDE.md rule 6 ("errors are typed and surfaced, not swallowed") this
    /// surfaces `PreferencesStoreError.underlying` rather than silently
    /// resetting the user's saved preferences to defaults.
    public func load() async throws -> UserPreferences {
        guard let data = userDefaults.data(forKey: Self.preferencesKey) else {
            return UserPreferences()
        }
        do {
            return try decoder.decode(UserPreferences.self, from: data)
        } catch {
            throw PreferencesStoreError.underlying(
                "Corrupted UserPreferences data at key \"\(Self.preferencesKey)\": \(error)"
            )
        }
    }

    /// Persists `preferences` as a single JSON blob, replacing any
    /// previously-saved value.
    ///
    /// Encoding can fail in practice: `defaultPacesByIntent` stores bare
    /// `Double` seconds-per-meter values, and `JSONEncoder`'s default
    /// non-conforming-float strategy throws for NaN/Infinity — so this stays
    /// a throwing call rather than a force-try.
    public func save(_ preferences: UserPreferences) async throws {
        do {
            let data = try encoder.encode(preferences)
            userDefaults.set(data, forKey: Self.preferencesKey)
        } catch {
            throw PreferencesStoreError.underlying(
                "Failed to encode UserPreferences for persistence: \(error)"
            )
        }
    }
}
