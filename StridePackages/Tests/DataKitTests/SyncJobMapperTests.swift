import Testing
import Foundation
import DomainKit
@testable import DataKit

/// Domain -> model -> domain round-trip coverage for `SyncJobMapper`,
/// exhaustive over every `SyncJobState` (including every `SyncFailureReason`).
@Suite("SyncJobMapper")
struct SyncJobMapperTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeSyncJob(state: SyncJobState) -> SyncJob {
        SyncJob(
            workoutID: UUID(),
            state: state,
            createdAt: now,
            updatedAt: now,
            planIdentifier: "plan-123",
            scheduledDate: now.addingTimeInterval(3_600),
            attemptCount: 2
        )
    }

    @Test(
        "toModel then toDomain round-trips every non-associated-value SyncJobState",
        arguments: [SyncJobState.draft, .pending, .syncing, .synced, .abandoned, .completedRunLinked, .stale]
    )
    func simpleStatesRoundTrip(_ state: SyncJobState) throws {
        let syncJob = makeSyncJob(state: state)
        let model = try SyncJobMapper.toModel(syncJob)
        let decoded = try SyncJobMapper.toDomain(model)
        #expect(decoded == syncJob)
    }

    @Test(
        "toModel then toDomain round-trips .failed for every SyncFailureReason",
        arguments: [
            SyncFailureReason.notAuthorized,
            .invalidComposition,
            .noPairedWatch,
            .transient(description: "network unreachable")
        ]
    )
    func failedStatesRoundTrip(_ reason: SyncFailureReason) throws {
        let syncJob = makeSyncJob(state: .failed(reason))
        let model = try SyncJobMapper.toModel(syncJob)
        let decoded = try SyncJobMapper.toDomain(model)
        #expect(decoded == syncJob)
    }

    @Test("toModel then toDomain round-trips a job with all optionals nil")
    func minimalJobRoundTrips() throws {
        let syncJob = SyncJob(workoutID: UUID(), createdAt: now, updatedAt: now)
        let model = try SyncJobMapper.toModel(syncJob)
        let decoded = try SyncJobMapper.toDomain(model)
        #expect(decoded == syncJob)
    }

    @Test("apply(_:to:) updates an existing model's state and scalar fields")
    func applyUpdatesExistingModel() throws {
        let original = makeSyncJob(state: .draft)
        let model = try SyncJobMapper.toModel(original)
        let updated = SyncJob(
            id: original.id,
            workoutID: original.workoutID,
            state: .synced,
            createdAt: original.createdAt,
            updatedAt: now.addingTimeInterval(60),
            planIdentifier: "plan-456",
            scheduledDate: nil,
            attemptCount: 3
        )
        try SyncJobMapper.apply(updated, to: model)
        let decoded = try SyncJobMapper.toDomain(model)
        #expect(decoded == updated)
    }

    @Test("toDomain throws DataKitError.corruptedSyncState for corrupted state bytes")
    func corruptedStateBytesThrows() throws {
        let syncJob = makeSyncJob(state: .draft)
        let model = try SyncJobMapper.toModel(syncJob)
        model.stateData = Data("not json".utf8)
        #expect(throws: DataKitError.self) {
            try SyncJobMapper.toDomain(model)
        }
    }

    @Test("toDomain throws DataKitError.corruptedSyncState for empty state bytes")
    func emptyStateBytesThrows() throws {
        let syncJob = makeSyncJob(state: .draft)
        let model = try SyncJobMapper.toModel(syncJob)
        model.stateData = Data()
        #expect(throws: DataKitError.self) {
            try SyncJobMapper.toDomain(model)
        }
    }

    @Test("toDomain throws DataKitError.corruptedSyncState for a valid-JSON-but-unrecognized state case")
    func unrecognizedStateCaseThrows() throws {
        let syncJob = makeSyncJob(state: .draft)
        let model = try SyncJobMapper.toModel(syncJob)
        model.stateData = Data(#"{"notARealState": {}}"#.utf8)
        #expect(throws: DataKitError.self) {
            try SyncJobMapper.toDomain(model)
        }
    }

    @Test("toModel then toDomain round-trips a .transient failure reason with an empty description")
    func transientEmptyDescriptionRoundTrips() throws {
        let syncJob = makeSyncJob(state: .failed(.transient(description: "")))
        let model = try SyncJobMapper.toModel(syncJob)
        let decoded = try SyncJobMapper.toDomain(model)
        #expect(decoded == syncJob)
    }

    @Test("toModel then toDomain round-trips a .transient failure reason with unicode/emoji in its description")
    func transientUnicodeDescriptionRoundTrips() throws {
        let syncJob = makeSyncJob(state: .failed(.transient(description: "Wi-Fi timed out 🔌⌚️ — réessayer? 日本語")))
        let model = try SyncJobMapper.toModel(syncJob)
        let decoded = try SyncJobMapper.toDomain(model)
        #expect(decoded == syncJob)
    }

    @Test("toModel then toDomain round-trips extreme attemptCount and scheduledDate values")
    func extremeAttemptCountAndScheduledDateRoundTrip() throws {
        let syncJob = SyncJob(
            workoutID: UUID(),
            state: .pending,
            createdAt: now,
            updatedAt: now,
            scheduledDate: Date(timeIntervalSince1970: -1_000_000_000),
            attemptCount: Int.max
        )
        let model = try SyncJobMapper.toModel(syncJob)
        let decoded = try SyncJobMapper.toDomain(model)
        #expect(decoded == syncJob)
    }
}
