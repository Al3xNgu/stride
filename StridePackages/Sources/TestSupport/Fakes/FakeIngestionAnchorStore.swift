import DomainKit
import Foundation

/// In-memory durable cursor fake for ingestion-coordinator tests.
public final class FakeIngestionAnchorStore: IngestionAnchorStore, @unchecked Sendable {
    /// Stored cursors by source/query key.
    public var anchorsByKey: [String: Data]
    /// Optional failure injected into load/save operations.
    public var errorToThrow: Error?
    /// Optional failure applying only to cursor writes.
    public var saveError: Error?
    /// Every committed cursor, in order.
    public private(set) var savedAnchors: [(key: String, data: Data)] = []

    /// Creates a store with optional seed data.
    public init(anchorsByKey: [String: Data] = [:]) {
        self.anchorsByKey = anchorsByKey
    }

    public func loadAnchor(for key: String) async throws -> Data? {
        if let errorToThrow {
            throw errorToThrow
        }
        return anchorsByKey[key]
    }

    public func saveAnchor(_ anchor: Data, for key: String) async throws {
        if let saveError { throw saveError }
        if let errorToThrow {
            throw errorToThrow
        }
        anchorsByKey[key] = anchor
        savedAnchors.append((key: key, data: anchor))
    }
}
