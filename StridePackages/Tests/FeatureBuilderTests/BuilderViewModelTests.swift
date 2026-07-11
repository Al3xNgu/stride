import Testing
import Foundation
@testable import FeatureBuilder
import DomainKit
import TestSupport

/// Coverage of `BuilderViewModel`'s segment-list mutations, persistence, and
/// validation-issue surfacing against `TestSupport`'s in-memory fakes.
///
/// Edge cases (mutation degenerate indices, save/load failure semantics,
/// clock-vs-wall-clock stamping) live in `BuilderViewModelAdversarialTests`.
@MainActor
@Suite("BuilderViewModel")
struct BuilderViewModelTests {
    private typealias Fixtures = BuilderViewModelFixtures
    private let referenceDate = Fixtures.referenceDate

    private func makeViewModel(
        workouts: [Workout] = [],
        workout: Workout? = nil
    ) -> Fixtures.Harness {
        Fixtures.makeViewModel(workouts: workouts, workout: workout)
    }

    // MARK: - New workout defaults

    @Test("A new workout starts unnamed with no segments, stamped by the clock")
    func newWorkoutDefaults() {
        let viewModel = makeViewModel().viewModel
        #expect(viewModel.name == "")
        #expect(viewModel.segments.isEmpty)
        #expect(viewModel.workout.createdAt == referenceDate)
        #expect(viewModel.workout.updatedAt == referenceDate)
    }

    // MARK: - addSegment

    @Test("addSegment(.warmUp) appends an open-goal warm-up step")
    func addSingleIntentSegment() {
        let viewModel = makeViewModel().viewModel
        viewModel.addSegment(.warmUp)
        #expect(viewModel.segments.count == 1)
        guard case let .step(step) = viewModel.segments[0] else {
            Issue.record("Expected a .step segment")
            return
        }
        #expect(step.intent == .warmUp)
        #expect(step.goal == .open)
        #expect(step.target == nil)
    }

    @Test("addSegment(.intervalBlock) appends a valid starter work/recovery block")
    func addIntervalBlockSegment() {
        let viewModel = makeViewModel().viewModel
        viewModel.name = "Interval Day"
        viewModel.addSegment(.intervalBlock)
        #expect(viewModel.segments.count == 1)
        guard case let .intervalBlock(_, steps, repetitions) = viewModel.segments[0] else {
            Issue.record("Expected an .intervalBlock segment")
            return
        }
        #expect(repetitions > 0)
        #expect(steps.contains { $0.purpose == .work })
        #expect(steps.contains { $0.purpose == .recovery })
        #expect(ValidateWorkoutPolicy.validate(viewModel.workout).isEmpty)
    }

    @Test("Segments append in the order added")
    func addSegmentAppendsInOrder() {
        let viewModel = makeViewModel().viewModel
        viewModel.addSegment(.warmUp)
        viewModel.addSegment(.tempo)
        viewModel.addSegment(.coolDown)
        let intents = viewModel.segments.compactMap { segment -> SegmentIntent? in
            guard case let .step(step) = segment else { return nil }
            return step.intent
        }
        #expect(intents == [.warmUp, .tempo, .coolDown])
    }

    // MARK: - moveSegments

    @Test("moveSegments reorders the segment list")
    func moveSegmentsReorders() {
        let viewModel = makeViewModel().viewModel
        viewModel.addSegment(.warmUp)
        viewModel.addSegment(.tempo)
        viewModel.addSegment(.coolDown)

        viewModel.moveSegments(fromOffsets: IndexSet(integer: 2), toOffset: 0)

        let intents = viewModel.segments.compactMap { segment -> SegmentIntent? in
            guard case let .step(step) = segment else { return nil }
            return step.intent
        }
        #expect(intents == [.coolDown, .warmUp, .tempo])
    }

    // MARK: - replaceSegment

    @Test("replaceSegment(id:with:) swaps in the edited segment at the same position")
    func replaceSegmentSwapsInPlace() {
        let viewModel = makeViewModel().viewModel
        viewModel.addSegment(.warmUp)
        viewModel.addSegment(.tempo)
        let targetID = viewModel.segments[1].id

        let updated = SegmentStep(id: targetID, intent: .tempo, goal: .distance(meters: 5_000))
        viewModel.replaceSegment(id: targetID, with: .step(updated))

        #expect(viewModel.segments.count == 2)
        guard case let .step(step) = viewModel.segments[1] else {
            Issue.record("Expected a .step segment")
            return
        }
        #expect(step.goal == .distance(meters: 5_000))
    }

    @Test("replaceSegment(id:with:) no-ops for an unknown id")
    func replaceSegmentUnknownIDNoOps() {
        let viewModel = makeViewModel().viewModel
        viewModel.addSegment(.warmUp)
        let before = viewModel.segments

        viewModel.replaceSegment(id: UUID(), with: .step(SegmentStep(intent: .easy, goal: .open)))

        #expect(viewModel.segments == before)
    }

    // MARK: - duplicateSegment

    @Test("duplicateSegment inserts a copy directly after the original with a fresh id")
    func duplicateSegmentFreshID() {
        let viewModel = makeViewModel().viewModel
        viewModel.addSegment(.tempo)
        let originalID = viewModel.segments[0].id

        viewModel.duplicateSegment(id: originalID)

        #expect(viewModel.segments.count == 2)
        #expect(viewModel.segments[0].id == originalID)
        #expect(viewModel.segments[1].id != originalID)

        guard case let .step(original) = viewModel.segments[0], case let .step(copy) = viewModel.segments[1] else {
            Issue.record("Expected .step segments")
            return
        }
        #expect(copy.id != original.id)
        #expect(copy.intent == original.intent)
        #expect(copy.goal == original.goal)
    }

    @Test("duplicateSegment on an interval block generates fresh ids for the block and every interval step")
    func duplicateIntervalBlockFreshIDs() {
        let viewModel = makeViewModel().viewModel
        viewModel.addSegment(.intervalBlock)
        let originalID = viewModel.segments[0].id
        guard case let .intervalBlock(_, originalSteps, originalRepetitions) = viewModel.segments[0] else {
            Issue.record("Expected an .intervalBlock segment")
            return
        }

        viewModel.duplicateSegment(id: originalID)

        #expect(viewModel.segments.count == 2)
        guard case let .intervalBlock(copyBlockID, copySteps, copyRepetitions) = viewModel.segments[1] else {
            Issue.record("Expected an .intervalBlock segment")
            return
        }
        #expect(copyBlockID != originalID)
        #expect(copyRepetitions == originalRepetitions)
        #expect(copySteps.count == originalSteps.count)
        let originalStepIDs = Set(originalSteps.map(\.id))
        let copyStepIDs = Set(copySteps.map(\.id))
        #expect(originalStepIDs.isDisjoint(with: copyStepIDs))
        let originalInnerStepIDs = Set(originalSteps.map(\.step.id))
        let copyInnerStepIDs = Set(copySteps.map(\.step.id))
        #expect(originalInnerStepIDs.isDisjoint(with: copyInnerStepIDs))
    }

    @Test("duplicateSegment no-ops for an unknown id")
    func duplicateSegmentUnknownIDNoOps() {
        let viewModel = makeViewModel().viewModel
        viewModel.addSegment(.warmUp)
        let before = viewModel.segments

        viewModel.duplicateSegment(id: UUID())

        #expect(viewModel.segments == before)
    }

    // MARK: - deleteSegment

    @Test("deleteSegment removes exactly the targeted segment")
    func deleteSegmentRemovesTarget() {
        let viewModel = makeViewModel().viewModel
        viewModel.addSegment(.warmUp)
        viewModel.addSegment(.tempo)
        viewModel.addSegment(.coolDown)
        let targetID = viewModel.segments[1].id

        viewModel.deleteSegment(id: targetID)

        #expect(viewModel.segments.count == 2)
        #expect(!viewModel.segments.contains { $0.id == targetID })
    }

    // MARK: - validationIssues

    @Test("validationIssues is non-empty for an unnamed, segment-less workout")
    func validationIssuesForEmptyDraft() {
        let viewModel = makeViewModel().viewModel
        #expect(!viewModel.validationIssues.isEmpty)
        #expect(viewModel.validationIssues.contains(ValidationIssue(rule: .workoutHasNoSegments, locator: .workout)))
        #expect(viewModel.validationIssues.contains(ValidationIssue(rule: .workoutNameEmpty, locator: .workout)))
    }

    @Test("validationIssues updates after a mutation fixes the underlying problem")
    func validationIssuesUpdatesOnMutation() {
        let viewModel = makeViewModel().viewModel
        viewModel.name = "Easy Run"
        viewModel.addSegment(.easy)
        #expect(viewModel.validationIssues.isEmpty)

        viewModel.name = ""
        #expect(viewModel.validationIssues.contains(ValidationIssue(rule: .workoutNameEmpty, locator: .workout)))
    }

    @Test("validationIssues reports a non-positive distance goal at the segment's locator")
    func validationIssuesReportsInvalidGoal() {
        let viewModel = makeViewModel().viewModel
        viewModel.name = "Bad Workout"
        let step = SegmentStep(intent: .tempo, goal: .distance(meters: -5))
        viewModel.addSegment(.tempo)
        viewModel.replaceSegment(id: viewModel.segments[0].id, with: .step(step))

        #expect(viewModel.validationIssues.contains(
            ValidationIssue(rule: .goalDistanceNotPositive(meters: -5), locator: .segment(id: step.id))
        ))
    }

    // MARK: - save()

    @Test("save() persists exactly the edited workout, with updatedAt stamped by the clock")
    func savePersistsWorkout() async {
        let harness = makeViewModel()
        let viewModel = harness.viewModel
        viewModel.name = "Long Run"
        viewModel.addSegment(.easy)
        harness.clock.advance(by: 3_600)

        await viewModel.save()

        #expect(viewModel.saveError == nil)
        let persisted = try? await harness.repository.fetch(id: viewModel.workout.id)
        #expect(persisted?.name == "Long Run")
        #expect(persisted?.segments.count == 1)
        #expect(persisted?.updatedAt == referenceDate.addingTimeInterval(3_600))
        #expect(persisted?.createdAt == referenceDate)
        #expect(viewModel.workout.updatedAt == referenceDate.addingTimeInterval(3_600))
    }

    @Test("save() surfaces a typed error and leaves the in-memory draft unchanged on failure")
    func saveFailureSurfacesError() async {
        let harness = makeViewModel()
        let viewModel = harness.viewModel
        viewModel.name = "Will Fail"
        harness.repository.errorToThrow = WorkoutRepositoryError.underlying("disk full")

        await viewModel.save()

        #expect(viewModel.saveError == .underlying("disk full"))
        #expect(viewModel.name == "Will Fail")
        #expect(viewModel.isSaving == false)
    }

    // MARK: - load(workoutID:)

    @Test("load(workoutID:) round-trips an existing workout into the draft")
    func loadRoundTripsExistingWorkout() async {
        let existing = Workout(
            name: "Tempo Run",
            segments: [.step(SegmentStep(intent: .tempo, goal: .distance(meters: 8_000)))],
            createdAt: referenceDate,
            updatedAt: referenceDate
        )
        let viewModel = makeViewModel(workouts: [existing]).viewModel

        await viewModel.load(workoutID: existing.id)

        #expect(viewModel.loadError == nil)
        #expect(viewModel.workout == existing)
        #expect(viewModel.name == "Tempo Run")
    }

    @Test("load(workoutID:) surfaces workoutNotFound for an unknown id and leaves the draft unchanged")
    func loadUnknownIDSurfacesError() async {
        let viewModel = makeViewModel().viewModel
        viewModel.name = "Draft In Progress"
        let unknownID = UUID()

        await viewModel.load(workoutID: unknownID)

        #expect(viewModel.loadError == .workoutNotFound(id: unknownID))
        #expect(viewModel.name == "Draft In Progress")
    }
}
