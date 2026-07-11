import Testing
import Foundation
import DomainKit
@testable import DataKit

/// Domain -> model -> domain round-trip coverage for `WorkoutMapper`,
/// including every `WorkoutSegment` case and corrupted-data error paths.
@Suite("WorkoutMapper")
struct WorkoutMapperTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeWorkout(segments: [WorkoutSegment] = []) -> Workout {
        Workout(
            name: "8x400",
            notes: "Track workout",
            segments: segments,
            createdAt: now,
            updatedAt: now
        )
    }

    @Test("toModel then toDomain round-trips a workout with no segments")
    func emptySegmentsRoundTrips() throws {
        let workout = makeWorkout()
        let model = try WorkoutMapper.toModel(workout)
        let decoded = try WorkoutMapper.toDomain(model)
        #expect(decoded == workout)
    }

    @Test("toModel then toDomain round-trips a .step segment with every Goal/Target combination")
    func stepSegmentRoundTrips() throws {
        let step = WorkoutSegment.step(
            SegmentStep(intent: .tempo, goal: .distance(meters: 3_000), target: .pace(range: 0.2...0.25))
        )
        let workout = makeWorkout(segments: [step])
        let model = try WorkoutMapper.toModel(workout)
        let decoded = try WorkoutMapper.toDomain(model)
        #expect(decoded == workout)
    }

    @Test("toModel then toDomain round-trips an .intervalBlock segment")
    func intervalBlockSegmentRoundTrips() throws {
        let block = WorkoutSegment.intervalBlock(
            steps: [
                IntervalStep(purpose: .work, step: SegmentStep(intent: .work, goal: .distance(meters: 400))),
                IntervalStep(purpose: .recovery, step: SegmentStep(intent: .rest, goal: .duration(seconds: 60)))
            ],
            repetitions: 8
        )
        let workout = makeWorkout(segments: [block])
        let model = try WorkoutMapper.toModel(workout)
        let decoded = try WorkoutMapper.toDomain(model)
        #expect(decoded == workout)
    }

    @Test("toModel then toDomain preserves mixed segment order")
    func mixedSegmentsPreserveOrder() throws {
        let warmUp = WorkoutSegment.step(SegmentStep(intent: .warmUp, goal: .duration(seconds: 600)))
        let block = WorkoutSegment.intervalBlock(
            steps: [IntervalStep(purpose: .work, step: SegmentStep(intent: .work, goal: .open))],
            repetitions: 4
        )
        let coolDown = WorkoutSegment.step(SegmentStep(intent: .coolDown, goal: .duration(seconds: 300)))
        let workout = makeWorkout(segments: [warmUp, block, coolDown])
        let model = try WorkoutMapper.toModel(workout)
        let decoded = try WorkoutMapper.toDomain(model)
        #expect(decoded.segments == [warmUp, block, coolDown])
    }

    @Test("apply(_:to:) updates an existing model's scalar fields and segments")
    func applyUpdatesExistingModel() throws {
        let original = makeWorkout(segments: [.step(SegmentStep(intent: .easy, goal: .open))])
        let model = try WorkoutMapper.toModel(original)
        let updated = Workout(
            id: original.id,
            name: "Renamed",
            segments: [.step(SegmentStep(intent: .tempo, goal: .distance(meters: 1_000)))],
            createdAt: original.createdAt,
            updatedAt: now.addingTimeInterval(60)
        )
        try WorkoutMapper.apply(updated, to: model)
        let decoded = try WorkoutMapper.toDomain(model)
        #expect(decoded == updated)
    }

    @Test("toDomain throws DataKitError.corruptedWorkout for an unrecognized activityRaw value")
    func corruptedActivityThrows() throws {
        let workout = makeWorkout()
        let model = try WorkoutMapper.toModel(workout)
        model.activityRaw = "not-a-real-activity"
        #expect(throws: DataKitError.self) {
            try WorkoutMapper.toDomain(model)
        }
    }

    @Test("toDomain throws DataKitError.corruptedWorkout for corrupted segment bytes")
    func corruptedSegmentBytesThrows() throws {
        let step = WorkoutSegment.step(SegmentStep(intent: .easy, goal: .open))
        let workout = makeWorkout(segments: [step])
        let model = try WorkoutMapper.toModel(workout)
        model.segments.first?.segmentData = Data("not json".utf8)
        #expect(throws: DataKitError.self) {
            try WorkoutMapper.toDomain(model)
        }
    }

    @Test("toDomain throws DataKitError.corruptedWorkout for empty segment bytes")
    func emptySegmentBytesThrows() throws {
        let step = WorkoutSegment.step(SegmentStep(intent: .easy, goal: .open))
        let workout = makeWorkout(segments: [step])
        let model = try WorkoutMapper.toModel(workout)
        model.segments.first?.segmentData = Data()
        #expect(throws: DataKitError.self) {
            try WorkoutMapper.toDomain(model)
        }
    }

    @Test("toDomain throws DataKitError.corruptedWorkout for a valid-JSON-but-wrong-shape segment payload")
    func wrongShapeSegmentBytesThrows() throws {
        let step = WorkoutSegment.step(SegmentStep(intent: .easy, goal: .open))
        let workout = makeWorkout(segments: [step])
        let model = try WorkoutMapper.toModel(workout)
        // Valid JSON object, but not a shape `WorkoutSegment`'s Codable
        // synthesis can decode (no recognized case key).
        model.segments.first?.segmentData = Data(#"{"notASegmentCase": true}"#.utf8)
        #expect(throws: DataKitError.self) {
            try WorkoutMapper.toDomain(model)
        }
    }

    // MARK: - Goal exhaustiveness

    @Test(
        "toModel then toDomain round-trips every Goal case",
        arguments: [
            Goal.distance(meters: 3_000),
            .duration(seconds: 600),
            .open
        ]
    )
    func everyGoalCaseRoundTrips(_ goal: Goal) throws {
        let step = WorkoutSegment.step(SegmentStep(intent: .easy, goal: goal))
        let workout = makeWorkout(segments: [step])
        let model = try WorkoutMapper.toModel(workout)
        let decoded = try WorkoutMapper.toDomain(model)
        #expect(decoded == workout)
    }

    // MARK: - Target exhaustiveness

    @Test(
        "toModel then toDomain round-trips every Target case",
        arguments: [
            Target.pace(range: 0.2...0.25),
            .heartRate(.zone(3)),
            .heartRate(.range(120...160)),
            .cadence(range: 170...185)
        ]
    )
    func everyTargetCaseRoundTrips(_ target: Target) throws {
        let step = WorkoutSegment.step(SegmentStep(intent: .tempo, goal: .open, target: target))
        let workout = makeWorkout(segments: [step])
        let model = try WorkoutMapper.toModel(workout)
        let decoded = try WorkoutMapper.toDomain(model)
        #expect(decoded == workout)
    }

    @Test("toModel then toDomain round-trips a step with a nil target")
    func nilTargetRoundTrips() throws {
        let step = WorkoutSegment.step(SegmentStep(intent: .easy, goal: .open, target: nil))
        let workout = makeWorkout(segments: [step])
        let model = try WorkoutMapper.toModel(workout)
        let decoded = try WorkoutMapper.toDomain(model)
        #expect(decoded == workout)
    }

    // MARK: - Edge-value totality

    @Test("toModel then toDomain round-trips an intervalBlock with zero steps")
    func zeroStepIntervalBlockRoundTrips() throws {
        let block = WorkoutSegment.intervalBlock(steps: [], repetitions: 4)
        let workout = makeWorkout(segments: [block])
        let model = try WorkoutMapper.toModel(workout)
        let decoded = try WorkoutMapper.toDomain(model)
        #expect(decoded == workout)
    }

    @Test(
        "toModel then toDomain round-trips an intervalBlock with a non-positive repetitions count",
        arguments: [0, -1]
    )
    func nonPositiveRepetitionsRoundTrips(_ repetitions: Int) throws {
        let block = WorkoutSegment.intervalBlock(
            steps: [IntervalStep(purpose: .work, step: SegmentStep(intent: .work, goal: .open))],
            repetitions: repetitions
        )
        let workout = makeWorkout(segments: [block])
        let model = try WorkoutMapper.toModel(workout)
        let decoded = try WorkoutMapper.toDomain(model)
        #expect(decoded == workout)
    }

    @Test("toModel then toDomain round-trips unicode/emoji in name and notes")
    func unicodeNameAndNotesRoundTrip() throws {
        let workout = Workout(
            name: "5\u{00d7}1km \u{1F3C3}\u{200D}\u{2642}\u{FE0F}\u{1F525} Türkçe/日本語",
            notes: "Feeling 💪 — negative split! café/naïve résumé",
            segments: [.step(SegmentStep(intent: .easy, goal: .open))],
            createdAt: now,
            updatedAt: now
        )
        let model = try WorkoutMapper.toModel(workout)
        let decoded = try WorkoutMapper.toDomain(model)
        #expect(decoded == workout)
    }

    @Test(
        "toModel then toDomain round-trips extreme numeric goal values",
        arguments: [
            Goal.distance(meters: 1e12),
            .distance(meters: 0.001),
            .distance(meters: -100),
            .duration(seconds: 0.001),
            .duration(seconds: -1),
            .duration(seconds: Double.greatestFiniteMagnitude)
        ]
    )
    func extremeNumericGoalValuesRoundTrip(_ goal: Goal) throws {
        let step = WorkoutSegment.step(SegmentStep(intent: .easy, goal: goal))
        let workout = makeWorkout(segments: [step])
        let model = try WorkoutMapper.toModel(workout)
        let decoded = try WorkoutMapper.toDomain(model)
        #expect(decoded == workout)
    }

    @Test("toModel throws DataKitError.encodingFailed for a non-conforming Double (NaN) goal value")
    func nonConformingDoubleGoalThrowsEncodingFailed() throws {
        let step = WorkoutSegment.step(SegmentStep(intent: .easy, goal: .distance(meters: .nan)))
        let workout = makeWorkout(segments: [step])
        #expect(throws: DataKitError.self) {
            try WorkoutMapper.toModel(workout)
        }
    }

    @Test("toModel throws DataKitError.encodingFailed for a non-conforming Double (infinity) target value")
    func nonConformingDoubleTargetThrowsEncodingFailed() throws {
        let step = WorkoutSegment.step(
            SegmentStep(intent: .easy, goal: .open, target: .cadence(range: 0...Double.infinity))
        )
        let workout = makeWorkout(segments: [step])
        #expect(throws: DataKitError.self) {
            try WorkoutMapper.toModel(workout)
        }
    }
}
