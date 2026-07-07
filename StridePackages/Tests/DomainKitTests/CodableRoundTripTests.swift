import Testing
import Foundation
@testable import DomainKit

/// JSON round-trip coverage for every entity, with exhaustive coverage of
/// enum cases that carry associated values (Goal, Target, HeartRateTarget,
/// WorkoutSegment, SyncJobState/SyncFailureReason). This is load-bearing:
/// SwiftData mappers and workout export (Phase 2) depend on stable coding.
@Suite("Codable round-trips")
struct CodableRoundTripTests {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private func roundTrip<T: Codable & Equatable>(_ value: T) throws -> T {
        let data = try encoder.encode(value)
        return try decoder.decode(T.self, from: data)
    }

    // MARK: - SegmentIntent

    @Test("SegmentIntent round-trips for every case", arguments: [
        SegmentIntent.warmUp, .easy, .recovery, .tempo, .threshold, .work, .rest, .coolDown
    ])
    func segmentIntentRoundTrips(_ intent: SegmentIntent) throws {
        #expect(try roundTrip(intent) == intent)
    }

    // MARK: - Goal

    @Test("Goal.distance round-trips")
    func goalDistanceRoundTrips() throws {
        let goal = Goal.distance(meters: 5_000)
        #expect(try roundTrip(goal) == goal)
    }

    @Test("Goal.duration round-trips")
    func goalDurationRoundTrips() throws {
        let goal = Goal.duration(seconds: 1_800)
        #expect(try roundTrip(goal) == goal)
    }

    @Test("Goal.open round-trips")
    func goalOpenRoundTrips() throws {
        let goal = Goal.open
        #expect(try roundTrip(goal) == goal)
    }

    // MARK: - Target / HeartRateTarget

    @Test("Target.pace round-trips")
    func targetPaceRoundTrips() throws {
        let target = Target.pace(range: 0.25...0.30)
        #expect(try roundTrip(target) == target)
    }

    @Test("Target.heartRate(.zone) round-trips")
    func targetHeartRateZoneRoundTrips() throws {
        let target = Target.heartRate(.zone(3))
        #expect(try roundTrip(target) == target)
    }

    @Test("Target.heartRate(.range) round-trips")
    func targetHeartRateRangeRoundTrips() throws {
        let target = Target.heartRate(.range(140...160))
        #expect(try roundTrip(target) == target)
    }

    @Test("Target.cadence round-trips")
    func targetCadenceRoundTrips() throws {
        let target = Target.cadence(range: 170...180)
        #expect(try roundTrip(target) == target)
    }

    // MARK: - WorkoutSegment

    @Test("WorkoutSegment.step round-trips")
    func workoutSegmentStepRoundTrips() throws {
        let step = SegmentStep(intent: .tempo, goal: .distance(meters: 3_000), target: .pace(range: 0.2...0.25))
        let segment = WorkoutSegment.step(step)
        #expect(try roundTrip(segment) == segment)
    }

    @Test("WorkoutSegment.intervalBlock round-trips")
    func workoutSegmentIntervalBlockRoundTrips() throws {
        let work = IntervalStep(purpose: .work, step: SegmentStep(intent: .work, goal: .distance(meters: 400)))
        let recovery = IntervalStep(purpose: .recovery, step: SegmentStep(intent: .rest, goal: .duration(seconds: 90)))
        let segment = WorkoutSegment.intervalBlock(id: UUID(), steps: [work, recovery], repetitions: 6)
        #expect(try roundTrip(segment) == segment)
    }

    @Test("IntervalStep round-trips for both purposes", arguments: [
        IntervalStepPurpose.work, .recovery
    ])
    func intervalStepPurposeRoundTrips(_ purpose: IntervalStepPurpose) throws {
        let step = IntervalStep(purpose: purpose, step: SegmentStep(intent: .easy, goal: .open))
        #expect(try roundTrip(step) == step)
    }

    // MARK: - Workout

    @Test("Workout with empty segments round-trips")
    func workoutEmptyRoundTrips() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let workout = Workout(name: "Empty", createdAt: now, updatedAt: now)
        #expect(try roundTrip(workout) == workout)
    }

    @Test("Workout with mixed segments round-trips")
    func workoutMixedRoundTrips() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let warmUp = WorkoutSegment.step(SegmentStep(intent: .warmUp, goal: .duration(seconds: 600)))
        let block = WorkoutSegment.intervalBlock(
            steps: [
                IntervalStep(purpose: .work, step: SegmentStep(intent: .work, goal: .distance(meters: 400))),
                IntervalStep(purpose: .recovery, step: SegmentStep(intent: .rest, goal: .duration(seconds: 60)))
            ],
            repetitions: 8
        )
        let workout = Workout(
            name: "8x400",
            notes: "Track workout",
            segments: [warmUp, block],
            createdAt: now,
            updatedAt: now
        )
        #expect(try roundTrip(workout) == workout)
    }

    // MARK: - Milestone

    @Test("Milestone round-trips")
    func milestoneRoundTrips() throws {
        #expect(try roundTrip(Milestone.fiveK) == Milestone.fiveK)
    }

    // MARK: - PersonalBest

    @Test("PersonalBest round-trips")
    func personalBestRoundTrips() throws {
        let pb = PersonalBest(
            milestoneID: Milestone.fiveK.id,
            elapsedSeconds: 1_200,
            completedRunID: UUID(),
            achievedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        #expect(try roundTrip(pb) == pb)
    }

    // MARK: - CompletedRun / Split / HeartRateSummary

    @Test("CompletedRun round-trips with all optionals populated")
    func completedRunFullRoundTrips() throws {
        let run = CompletedRun(
            id: UUID(),
            date: Date(timeIntervalSince1970: 1_700_000_000),
            distanceMeters: 5_000,
            durationSeconds: 1_500,
            heartRate: HeartRateSummary(averageBPM: 150, maxBPM: 175),
            source: "Apple Watch",
            workoutID: UUID(),
            notes: "Felt good",
            isDeleted: false
        )
        #expect(try roundTrip(run) == run)
    }

    @Test("CompletedRun round-trips with all optionals nil")
    func completedRunMinimalRoundTrips() throws {
        let run = CompletedRun(
            id: UUID(),
            date: Date(timeIntervalSince1970: 1_700_000_000),
            distanceMeters: 0,
            durationSeconds: 0,
            source: "Stride"
        )
        #expect(try roundTrip(run) == run)
    }

    @Test("Split round-trips")
    func splitRoundTrips() throws {
        let split = Split(runID: UUID(), index: 0, distanceMeters: 1_000, durationSeconds: 300)
        #expect(try roundTrip(split) == split)
    }

    @Test("HeartRateSummary round-trips when both fields nil")
    func heartRateSummaryNilRoundTrips() throws {
        let summary = HeartRateSummary()
        #expect(try roundTrip(summary) == summary)
    }

    // MARK: - SyncJob / SyncJobState / SyncFailureReason (exhaustive)

    @Test("SyncJobState round-trips for every non-associated-value case", arguments: [
        SyncJobState.draft, .pending, .syncing, .synced, .abandoned, .completedRunLinked, .stale
    ])
    func syncJobStateSimpleCasesRoundTrip(_ state: SyncJobState) throws {
        #expect(try roundTrip(state) == state)
    }

    @Test("SyncJobState.failed round-trips for every SyncFailureReason case", arguments: [
        SyncFailureReason.notAuthorized,
        .invalidComposition,
        .noPairedWatch,
        .transient(description: "network unreachable")
    ])
    func syncJobStateFailedRoundTrips(_ reason: SyncFailureReason) throws {
        let state = SyncJobState.failed(reason)
        #expect(try roundTrip(state) == state)
    }

    @Test("SyncJob round-trips with full optionals populated")
    func syncJobFullRoundTrips() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let job = SyncJob(
            workoutID: UUID(),
            state: .failed(.transient(description: "timed out")),
            createdAt: now,
            updatedAt: now,
            planIdentifier: "plan-123",
            scheduledDate: now.addingTimeInterval(3_600),
            attemptCount: 2
        )
        #expect(try roundTrip(job) == job)
    }

    @Test("SyncJob round-trips with all optionals nil (draft state)")
    func syncJobMinimalRoundTrips() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let job = SyncJob(workoutID: UUID(), createdAt: now, updatedAt: now)
        #expect(try roundTrip(job) == job)
    }

    // MARK: - UserPreferences

    @Test("UserPreferences round-trips with defaults")
    func userPreferencesDefaultRoundTrips() throws {
        let prefs = UserPreferences()
        #expect(try roundTrip(prefs) == prefs)
    }

    @Test("UserPreferences round-trips with populated pace dictionary")
    func userPreferencesPopulatedRoundTrips() throws {
        let prefs = UserPreferences(
            distanceUnit: .kilometers,
            defaultPacesByIntent: [.easy: 0.35, .tempo: 0.28, .work: 0.22],
            hasCompletedOnboarding: true
        )
        #expect(try roundTrip(prefs) == prefs)
    }
}
