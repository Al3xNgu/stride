import Testing
import Foundation
import DomainKit
@testable import DataKit

/// `UserDefaultsPreferencesStore`'s load/save round trip, missing-data
/// defaults, and corrupted-data error surfacing.
///
/// Each test uses its own uniquely-named suite (never `.standard`) and
/// removes that suite's persistent domain on teardown, so the suite is
/// created and destroyed hermetically per test.
@Suite("UserDefaultsPreferencesStore")
struct UserDefaultsPreferencesStoreTests {
    /// Creates an isolated `UserDefaults` suite for a single test, along
    /// with a teardown closure that must be called to leave no trace.
    private func makeIsolatedDefaults() -> (defaults: UserDefaults, suiteName: String) {
        let suiteName = "com.stride.tests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Failed to create UserDefaults suite \(suiteName)")
            return (UserDefaults.standard, suiteName)
        }
        return (defaults, suiteName)
    }

    private func removeIsolatedDefaults(_ defaults: UserDefaults, suiteName: String) {
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test("load() with nothing persisted returns UserPreferences() defaults")
    func loadWithNothingPersistedReturnsDefaults() async throws {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { removeIsolatedDefaults(defaults, suiteName: suiteName) }
        let store = UserDefaultsPreferencesStore(userDefaults: defaults)

        let loaded = try await store.load()

        #expect(loaded == UserPreferences())
    }

    @Test("save(_:) then load() round-trips a non-default value")
    func saveThenLoadRoundTrips() async throws {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { removeIsolatedDefaults(defaults, suiteName: suiteName) }
        let store = UserDefaultsPreferencesStore(userDefaults: defaults)
        let preferences = UserPreferences(
            distanceUnit: .kilometers,
            defaultPacesByIntent: [.tempo: 0.25, .easy: 0.35],
            hasCompletedOnboarding: true
        )

        try await store.save(preferences)
        let loaded = try await store.load()

        #expect(loaded == preferences)
    }

    @Test("save(_:) replaces the previously-saved value, not accumulates")
    func saveReplacesPreviousValue() async throws {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { removeIsolatedDefaults(defaults, suiteName: suiteName) }
        let store = UserDefaultsPreferencesStore(userDefaults: defaults)

        try await store.save(UserPreferences(distanceUnit: .kilometers))
        try await store.save(UserPreferences(distanceUnit: .miles))
        let loaded = try await store.load()

        #expect(loaded.distanceUnit == .miles)
    }

    @Test("load() throws PreferencesStoreError.underlying when the persisted blob is corrupted")
    func corruptedDataThrowsTypedError() async throws {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { removeIsolatedDefaults(defaults, suiteName: suiteName) }
        defaults.set(Data("not json".utf8), forKey: UserDefaultsPreferencesStore.preferencesKey)
        let store = UserDefaultsPreferencesStore(userDefaults: defaults)

        await #expect(throws: PreferencesStoreError.self) {
            _ = try await store.load()
        }
    }

    @Test("load() throws PreferencesStoreError.underlying for valid-JSON-but-wrong-shape data")
    func wrongShapeDataThrowsTypedError() async throws {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { removeIsolatedDefaults(defaults, suiteName: suiteName) }
        defaults.set(Data(#"{"notARealField": 1}"#.utf8), forKey: UserDefaultsPreferencesStore.preferencesKey)
        let store = UserDefaultsPreferencesStore(userDefaults: defaults)

        await #expect(throws: PreferencesStoreError.self) {
            _ = try await store.load()
        }
    }

    @Test("Corrupted data does not get silently reset to defaults on load()")
    func corruptedDataIsNotSilentlyReset() async throws {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { removeIsolatedDefaults(defaults, suiteName: suiteName) }
        let corrupted = Data("not json".utf8)
        defaults.set(corrupted, forKey: UserDefaultsPreferencesStore.preferencesKey)
        let store = UserDefaultsPreferencesStore(userDefaults: defaults)

        _ = try? await store.load()

        #expect(defaults.data(forKey: UserDefaultsPreferencesStore.preferencesKey) == corrupted)
    }

    @Test("A saved blob survives a store reinit over the same suite (on-disk format stability)")
    func savedBlobSurvivesStoreReinit() async throws {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { removeIsolatedDefaults(defaults, suiteName: suiteName) }
        let preferences = UserPreferences(
            distanceUnit: .kilometers,
            defaultPacesByIntent: [.tempo: 0.25],
            hasCompletedOnboarding: true
        )
        try await UserDefaultsPreferencesStore(userDefaults: defaults).save(preferences)

        // A brand-new store instance (fresh coders) over the same suite must
        // read the same value — locks in the persisted format for 1.16.
        let reloaded = try await UserDefaultsPreferencesStore(userDefaults: defaults).load()

        #expect(reloaded == preferences)
    }

    @Test("Different suites are isolated from one another")
    func differentSuitesAreIsolated() async throws {
        let (defaultsA, suiteA) = makeIsolatedDefaults()
        defer { removeIsolatedDefaults(defaultsA, suiteName: suiteA) }
        let (defaultsB, suiteB) = makeIsolatedDefaults()
        defer { removeIsolatedDefaults(defaultsB, suiteName: suiteB) }
        let storeA = UserDefaultsPreferencesStore(userDefaults: defaultsA)
        let storeB = UserDefaultsPreferencesStore(userDefaults: defaultsB)

        try await storeA.save(UserPreferences(distanceUnit: .kilometers))

        let loadedB = try await storeB.load()
        #expect(loadedB == UserPreferences())
    }
}
