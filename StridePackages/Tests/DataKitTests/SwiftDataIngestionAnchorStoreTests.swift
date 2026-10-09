import Foundation
import SwiftData
import Testing
@testable import DataKit

@Suite("SwiftDataIngestionAnchorStore")
struct SwiftDataIngestionAnchorStoreTests {
    private let key = "healthkit.running.workouts.v1"

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: HealthKitAnchorModel.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    @Test("A missing anchor loads as nil")
    func missingAnchorIsNil() async throws {
        let store = SwiftDataIngestionAnchorStore(modelContainer: try makeContainer())
        #expect(try await store.loadAnchor(for: key) == nil)
    }

    @Test("Saving an anchor replaces the cursor for its key")
    func saveReplacesByKey() async throws {
        let store = SwiftDataIngestionAnchorStore(modelContainer: try makeContainer())
        try await store.saveAnchor(Data([1]), for: key)
        try await store.saveAnchor(Data([2, 3]), for: key)

        #expect(try await store.loadAnchor(for: key) == Data([2, 3]))
    }

    @Test("Cursors for different keys remain independent")
    func keysAreIndependent() async throws {
        let store = SwiftDataIngestionAnchorStore(modelContainer: try makeContainer())
        try await store.saveAnchor(Data([1]), for: key)
        try await store.saveAnchor(Data([2]), for: "healthkit.other.v1")

        #expect(try await store.loadAnchor(for: key) == Data([1]))
        #expect(try await store.loadAnchor(for: "healthkit.other.v1") == Data([2]))
    }

    @Test("Reopening a disk store retains the latest opaque cursor and independent keys")
    func diskReopenRetainsLatestCursor() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("anchors.store")
        let expected = Data([0, 255, 13, 42, 0])
        do {
            let container = try ModelContainer(
                for: HealthKitAnchorModel.self, configurations: ModelConfiguration(url: url)
            )
            let store = SwiftDataIngestionAnchorStore(modelContainer: container)
            try await store.saveAnchor(Data([1]), for: key)
            try await store.saveAnchor(expected, for: key)
            try await store.saveAnchor(Data(), for: "empty.cursor")
        }
        let reopened = try ModelContainer(
            for: HealthKitAnchorModel.self, configurations: ModelConfiguration(url: url)
        )
        let store = SwiftDataIngestionAnchorStore(modelContainer: reopened)
        #expect(try await store.loadAnchor(for: key) == expected)
        #expect(try await store.loadAnchor(for: "empty.cursor") == Data())
        #expect(try await store.loadAnchor(for: "missing.cursor") == nil)
    }
}
