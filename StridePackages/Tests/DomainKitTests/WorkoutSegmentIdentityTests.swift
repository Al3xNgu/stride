import Testing
import Foundation
@testable import DomainKit

/// Identity- and equality-coherence tests for `WorkoutSegment`/`SegmentStep`/
/// `IntervalStep`. These are value types with compiler-synthesized
/// `Equatable`/`Hashable` conformances, so equality compares *all* stored
/// fields (including `id`), not just the `Identifiable.id` computed property.
/// This suite pins that behavior precisely, since it's easy to assume
/// "same content" implies "==" when id participates too.
@Suite("WorkoutSegment identity and equality coherence")
struct WorkoutSegmentIdentityTests {
    @Test("SegmentStep id is stable across mutation of unrelated fields")
    func segmentStepIdStableAcrossMutation() {
        var step = SegmentStep(intent: .easy, goal: .distance(meters: 1_000))
        let originalID = step.id
        step.intent = .tempo
        step.goal = .duration(seconds: 600)
        step.target = .pace(range: 0.2...0.25)
        #expect(step.id == originalID)
    }

    @Test("IntervalStep id is stable across mutation of its wrapped step")
    func intervalStepIdStableAcrossMutation() {
        var interval = IntervalStep(purpose: .work, step: SegmentStep(intent: .work, goal: .distance(meters: 400)))
        let originalID = interval.id
        interval.step.goal = .duration(seconds: 120)
        interval.purpose = .recovery
        #expect(interval.id == originalID)
    }

    @Test("intervalBlock factory produces distinct ids per call")
    func intervalBlockFactoryProducesDistinctIDs() {
        let steps = [IntervalStep(purpose: .work, step: SegmentStep(intent: .work, goal: .open))]
        let first = WorkoutSegment.intervalBlock(steps: steps, repetitions: 4)
        let second = WorkoutSegment.intervalBlock(steps: steps, repetitions: 4)
        #expect(first.id != second.id)
    }

    @Test("intervalBlock id is stable per instance across copies")
    func intervalBlockIDStablePerInstance() {
        let original = WorkoutSegment.intervalBlock(
            steps: [IntervalStep(purpose: .work, step: SegmentStep(intent: .work, goal: .open))],
            repetitions: 4
        )
        let copy = original
        #expect(copy.id == original.id)
    }

    // MARK: - Equatable semantics: id participates in `==`

    /// FINDING (behavior pin, not a bug per se, but a sharp edge worth
    /// flagging to the reviewer): `WorkoutSegment`'s `Equatable` conformance
    /// is compiler-synthesized over ALL associated values, including the
    /// explicit `id: UUID` stored in `.intervalBlock`. This means two
    /// `.intervalBlock` segments with byte-identical steps/repetitions but
    /// different ids (e.g. produced by the `intervalBlock(steps:repetitions:)`
    /// factory called twice with identical arguments) are NOT equal, even
    /// though they are "the same content." This is consistent with
    /// `SegmentStep`/`IntervalStep` (whose `id` is also a plain stored
    /// property participating in synthesized `Equatable`), so the semantics
    /// are at least uniform across the three id-bearing types. If content-only
    /// equality is ever needed (e.g. for dedup/diffing in the WorkoutKit
    /// mapper), a dedicated comparison will be needed — synthesized `==`
    /// will not provide it.
    @Test("Two intervalBlocks with identical content but different ids are NOT equal (id participates in ==)")
    func intervalBlocksWithDifferentIDsAreNotEqual() {
        let steps = [IntervalStep(purpose: .work, step: SegmentStep(intent: .work, goal: .distance(meters: 400)))]
        let first = WorkoutSegment.intervalBlock(id: UUID(), steps: steps, repetitions: 6)
        let second = WorkoutSegment.intervalBlock(id: UUID(), steps: steps, repetitions: 6)
        #expect(first.id != second.id)
        #expect(first != second)
    }

    @Test("Two intervalBlocks with the same explicit id and same content ARE equal")
    func intervalBlocksWithSameIDAndContentAreEqual() {
        let sharedID = UUID()
        let steps = [IntervalStep(purpose: .work, step: SegmentStep(intent: .work, goal: .distance(meters: 400)))]
        let first = WorkoutSegment.intervalBlock(id: sharedID, steps: steps, repetitions: 6)
        let second = WorkoutSegment.intervalBlock(id: sharedID, steps: steps, repetitions: 6)
        #expect(first == second)
    }

    @Test("Two SegmentSteps with identical content but different ids are NOT equal")
    func segmentStepsWithDifferentIDsAreNotEqual() {
        let first = SegmentStep(intent: .easy, goal: .distance(meters: 1_000))
        let second = SegmentStep(intent: .easy, goal: .distance(meters: 1_000))
        #expect(first.id != second.id)
        #expect(first != second)
    }

    @Test("Two SegmentSteps with same explicit id and content are equal, and hash equal")
    func segmentStepsWithSameIDAreEqualAndHashEqual() {
        let sharedID = UUID()
        let first = SegmentStep(id: sharedID, intent: .easy, goal: .distance(meters: 1_000))
        let second = SegmentStep(id: sharedID, intent: .easy, goal: .distance(meters: 1_000))
        #expect(first == second)
        #expect(first.hashValue == second.hashValue)
    }

    @Test(".step and .intervalBlock with unrelated content are never equal across cases")
    func differentCasesAreNeverEqual() {
        let step = WorkoutSegment.step(SegmentStep(intent: .easy, goal: .open))
        let block = WorkoutSegment.intervalBlock(
            steps: [IntervalStep(purpose: .work, step: SegmentStep(intent: .work, goal: .open))],
            repetitions: 1
        )
        #expect(step != block)
    }

    @Test("WorkoutSegment.id dispatches to the wrapped step's id for .step")
    func workoutSegmentIDDispatchesForStep() {
        let step = SegmentStep(intent: .coolDown, goal: .open)
        let segment = WorkoutSegment.step(step)
        #expect(segment.id == step.id)
    }

    @Test("WorkoutSegment.id dispatches to the block's own id for .intervalBlock")
    func workoutSegmentIDDispatchesForIntervalBlock() {
        let blockID = UUID()
        let segment = WorkoutSegment.intervalBlock(
            id: blockID,
            steps: [IntervalStep(purpose: .work, step: SegmentStep(intent: .work, goal: .open))],
            repetitions: 2
        )
        #expect(segment.id == blockID)
    }
}
