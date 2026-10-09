import DomainKit
import Foundation
import SwiftData

/// SwiftData-backed durable storage for opaque ingestion cursors.
@ModelActor
public actor SwiftDataIngestionAnchorStore: IngestionAnchorStore {
    public func loadAnchor(for key: String) async throws -> Data? {
        modelContext.autosaveEnabled = false
        do {
            var descriptor = FetchDescriptor<HealthKitAnchorModel>(
                predicate: #Predicate { $0.key == key }
            )
            descriptor.fetchLimit = 1
            return try modelContext.fetch(descriptor).first?.anchorData
        } catch {
            modelContext.rollback()
            throw IngestionAnchorStoreError.underlying(String(describing: error))
        }
    }

    public func saveAnchor(_ anchor: Data, for key: String) async throws {
        modelContext.autosaveEnabled = false
        do {
            var descriptor = FetchDescriptor<HealthKitAnchorModel>(
                predicate: #Predicate { $0.key == key }
            )
            descriptor.fetchLimit = 1
            if let existing = try modelContext.fetch(descriptor).first {
                existing.anchorData = anchor
                existing.updatedAt = Date()
            } else {
                modelContext.insert(HealthKitAnchorModel(key: key, anchorData: anchor))
            }
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw IngestionAnchorStoreError.underlying(String(describing: error))
        }
    }
}
