import Testing
import Foundation
import DomainKit
import TestSupport

/// `FakePreferencesStore`'s load/save round trip, call recording, and
/// `errorToThrow` injection (CLAUDE.md rule 5).
@Suite("FakePreferencesStore")
struct FakePreferencesStoreTests {
    @Test("Default init loads UserPreferences() defaults")
    func defaultsLoadDefaultPreferences() async throws {
        let store = FakePreferencesStore()
        let loaded = try await store.load()
        #expect(loaded == UserPreferences())
    }

    @Test("load() returns the value the store was pre-seeded with")
    func loadReturnsSeededValue() async throws {
        let seeded = UserPreferences(distanceUnit: .kilometers, hasCompletedOnboarding: true)
        let store = FakePreferencesStore(storedPreferences: seeded)
        let loaded = try await store.load()
        #expect(loaded == seeded)
    }

    @Test("save(_:) then load() round-trips the new value")
    func saveThenLoadRoundTrips() async throws {
        let store = FakePreferencesStore()
        let updated = UserPreferences(distanceUnit: .kilometers)
        try await store.save(updated)
        let loaded = try await store.load()
        #expect(loaded == updated)
    }

    @Test("save(_:) replaces the previously-saved value, not accumulates")
    func saveReplacesPreviousValue() async throws {
        let store = FakePreferencesStore()
        try await store.save(UserPreferences(distanceUnit: .kilometers))
        try await store.save(UserPreferences(distanceUnit: .miles))
        let loaded = try await store.load()
        #expect(loaded.distanceUnit == .miles)
    }

    @Test("Every save(_:) call is recorded, in order")
    func savedPreferencesRecordsCallOrder() async throws {
        let store = FakePreferencesStore()
        let first = UserPreferences(distanceUnit: .kilometers)
        let second = UserPreferences(distanceUnit: .miles, hasCompletedOnboarding: true)
        try await store.save(first)
        try await store.save(second)
        #expect(store.savedPreferences == [first, second])
    }

    @Test("loadCallCount increments once per load() call")
    func loadCallCountIncrements() async throws {
        let store = FakePreferencesStore()
        _ = try await store.load()
        _ = try await store.load()
        _ = try await store.load()
        #expect(store.loadCallCount == 3)
    }

    @Test("errorToThrow makes load() throw the injected error")
    func errorToThrowMakesLoadThrow() async {
        let store = FakePreferencesStore()
        store.errorToThrow = PreferencesStoreError.underlying("disk full")
        await #expect(throws: PreferencesStoreError.underlying("disk full")) {
            _ = try await store.load()
        }
    }

    @Test("errorToThrow makes save(_:) throw and does not record the attempted value")
    func errorToThrowMakesSaveThrowWithoutRecording() async {
        let store = FakePreferencesStore()
        store.errorToThrow = PreferencesStoreError.underlying("disk full")
        await #expect(throws: PreferencesStoreError.underlying("disk full")) {
            try await store.save(UserPreferences(distanceUnit: .kilometers))
        }
        #expect(store.savedPreferences.isEmpty)
    }

    @Test("Clearing errorToThrow restores normal load()/save(_:) behavior")
    func clearingErrorRestoresBehavior() async throws {
        let store = FakePreferencesStore()
        store.errorToThrow = PreferencesStoreError.underlying("disk full")
        store.errorToThrow = nil
        let updated = UserPreferences(distanceUnit: .kilometers)
        try await store.save(updated)
        let loaded = try await store.load()
        #expect(loaded == updated)
    }
}
