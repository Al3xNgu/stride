import Testing
import Foundation
import DomainKit
@testable import DataKit

/// Shared fixtures for `CompletedRunProjector` test suites.
enum CompletedRunProjectorFixtures {
    static let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)
    static let workoutUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000002") ?? UUID()

    static func input(
        totalDistanceMeters: Double = 5_000,
        totalDurationSeconds: TimeInterval = 1_500,
        averageHeartRateBPM: Double? = 150,
        maxHeartRateBPM: Double? = 175,
        sourceName: String = "Apple Watch"
    ) -> HealthKitRunProjectionInput {
        HealthKitRunProjectionInput(
            workoutUUID: workoutUUID,
            startDate: referenceDate,
            totalDistanceMeters: totalDistanceMeters,
            totalDurationSeconds: totalDurationSeconds,
            averageHeartRateBPM: averageHeartRateBPM,
            maxHeartRateBPM: maxHeartRateBPM,
            sourceName: sourceName
        )
    }
}

@Suite("CompletedRunProjector — field mapping")
struct CompletedRunProjectorFieldMappingTests {
    private typealias Fixtures = CompletedRunProjectorFixtures

    @Test("Every field maps straight through for well-formed input")
    func happyPathMapping() {
        let run = CompletedRunProjector.project(Fixtures.input())
        #expect(run.id == Fixtures.workoutUUID)
        #expect(run.date == Fixtures.referenceDate)
        #expect(run.distanceMeters == 5_000)
        #expect(run.durationSeconds == 1_500)
        #expect(run.heartRate.averageBPM == 150)
        #expect(run.heartRate.maxBPM == 175)
        #expect(run.source == "Apple Watch")
    }

    @Test("A freshly-projected run is always unattributed, undeleted, and note-free")
    func freshProjectionDefaults() {
        let run = CompletedRunProjector.project(Fixtures.input())
        #expect(run.workoutID == nil)
        #expect(run.notes == nil)
        #expect(run.isDeleted == false)
    }

    @Test("Missing heart-rate statistics project as nil, not zero")
    func missingHeartRateIsNil() {
        let run = CompletedRunProjector.project(
            Fixtures.input(averageHeartRateBPM: nil, maxHeartRateBPM: nil)
        )
        #expect(run.heartRate.averageBPM == nil)
        #expect(run.heartRate.maxBPM == nil)
    }
}

@Suite("CompletedRunProjector — sanitization of malformed HealthKit statistics")
struct CompletedRunProjectorSanitizationTests {
    private typealias Fixtures = CompletedRunProjectorFixtures

    @Test("Negative distance/duration are clamped to zero, never surfaced negative")
    func negativeValuesClampedToZero() {
        let run = CompletedRunProjector.project(
            Fixtures.input(totalDistanceMeters: -100, totalDurationSeconds: -50)
        )
        #expect(run.distanceMeters == 0)
        #expect(run.durationSeconds == 0)
    }

    @Test("Non-finite distance/duration are clamped to zero rather than propagating NaN/Infinity")
    func nonFiniteValuesClampedToZero() {
        let run = CompletedRunProjector.project(
            Fixtures.input(totalDistanceMeters: .nan, totalDurationSeconds: .infinity)
        )
        #expect(run.distanceMeters == 0)
        #expect(run.durationSeconds == 0)
    }

    @Test("Zero distance is preserved (not treated as an error) and averagePace is nil")
    func zeroDistancePreserved() {
        let run = CompletedRunProjector.project(Fixtures.input(totalDistanceMeters: 0))
        #expect(run.distanceMeters == 0)
        #expect(run.averagePace == nil)
    }

    @Test("Non-positive or non-finite heart-rate values are dropped to nil, not clamped to zero")
    func invalidHeartRateDroppedToNil() {
        let run = CompletedRunProjector.project(
            Fixtures.input(averageHeartRateBPM: -10, maxHeartRateBPM: .nan)
        )
        #expect(run.heartRate.averageBPM == nil)
        #expect(run.heartRate.maxBPM == nil)
    }
}
