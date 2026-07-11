import Testing
import Foundation
import DomainKit
@testable import DataKit

/// Domain -> model -> domain round-trip coverage for `CompletedRunMapper`,
/// `SplitMapper`, and `PersonalBestMapper` — all three are total and
/// non-throwing, so these suites only assert equality, not error paths.
@Suite("CompletedRunMapper")
struct CompletedRunMapperTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("toModel then toDomain round-trips with all optionals populated")
    func fullRunRoundTrips() {
        let run = CompletedRun(
            id: UUID(),
            date: now,
            distanceMeters: 5_000,
            durationSeconds: 1_500,
            heartRate: HeartRateSummary(averageBPM: 150, maxBPM: 175),
            source: "Apple Watch",
            workoutID: UUID(),
            notes: "Felt good",
            isDeleted: false
        )
        let model = CompletedRunMapper.toModel(run)
        let decoded = CompletedRunMapper.toDomain(model)
        #expect(decoded == run)
    }

    @Test("toModel then toDomain round-trips with all optionals nil")
    func minimalRunRoundTrips() {
        let run = CompletedRun(id: UUID(), date: now, distanceMeters: 0, durationSeconds: 0, source: "Stride")
        let model = CompletedRunMapper.toModel(run)
        let decoded = CompletedRunMapper.toDomain(model)
        #expect(decoded == run)
    }

    @Test("toModel then toDomain round-trips a tombstoned run")
    func tombstonedRunRoundTrips() {
        let run = CompletedRun(
            id: UUID(), date: now, distanceMeters: 5_000, durationSeconds: 1_500,
            source: "Apple Watch", isDeleted: true
        )
        let model = CompletedRunMapper.toModel(run)
        let decoded = CompletedRunMapper.toDomain(model)
        #expect(decoded == run)
    }

    @Test("apply(_:to:) updates an existing model's fields")
    func applyUpdatesExistingModel() {
        let original = CompletedRun(id: UUID(), date: now, distanceMeters: 5_000, durationSeconds: 1_500, source: "Apple Watch")
        let model = CompletedRunMapper.toModel(original)
        let updated = CompletedRun(
            id: original.id,
            date: now.addingTimeInterval(60),
            distanceMeters: 10_000,
            durationSeconds: 3_000,
            heartRate: HeartRateSummary(averageBPM: 140, maxBPM: 170),
            source: "Stride",
            workoutID: UUID(),
            notes: "Updated",
            isDeleted: true
        )
        CompletedRunMapper.apply(updated, to: model)
        let decoded = CompletedRunMapper.toDomain(model)
        #expect(decoded == updated)
    }
}

@Suite("SplitMapper")
struct SplitMapperTests {
    @Test("toModel then toDomain round-trips")
    func splitRoundTrips() {
        let split = Split(runID: UUID(), index: 2, distanceMeters: 1_000, durationSeconds: 300)
        let model = SplitMapper.toModel(split)
        let decoded = SplitMapper.toDomain(model)
        #expect(decoded == split)
    }
}

@Suite("PersonalBestMapper")
struct PersonalBestMapperTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("toModel then toDomain round-trips")
    func personalBestRoundTrips() {
        let personalBest = PersonalBest(
            milestoneID: Milestone.fiveK.id,
            elapsedSeconds: 1_200,
            completedRunID: UUID(),
            achievedAt: now
        )
        let model = PersonalBestMapper.toModel(personalBest)
        let decoded = PersonalBestMapper.toDomain(model)
        #expect(decoded == personalBest)
    }

    @Test("apply(_:to:) updates an existing model's fields")
    func applyUpdatesExistingModel() {
        let original = PersonalBest(milestoneID: Milestone.fiveK.id, elapsedSeconds: 1_200, completedRunID: UUID(), achievedAt: now)
        let model = PersonalBestMapper.toModel(original)
        let updated = PersonalBest(
            id: original.id,
            milestoneID: Milestone.tenK.id,
            elapsedSeconds: 2_400,
            completedRunID: UUID(),
            achievedAt: now.addingTimeInterval(60)
        )
        PersonalBestMapper.apply(updated, to: model)
        let decoded = PersonalBestMapper.toDomain(model)
        #expect(decoded == updated)
    }
}
