import Testing
import Foundation
@testable import FeatureBuilder
import DomainKit
import TestSupport

/// Adversarial coverage for `BuilderViewModel`: degenerate mutation indices,
/// id-collision hunting after duplicating an interval block, save/load
/// failure semantics (error surfaced, prior state preserved, no partial
/// writes), consecutive-save upsert behavior, validation issue -> clean ->
/// issue transitions, and clock-vs-wall-clock stamping for
/// `createdAt`/`updatedAt`.
@MainActor
@Suite("BuilderViewModel — adversarial")
struct BuilderViewModelAdversarialTests {
    private typealias Fixtures = BuilderViewModelFixtures
    private let referenceDate = Fixtures.referenceDate

    private func makeViewModel(
        workouts: [Workout] = [],
        workout: Workout? = nil
    ) -> Fixtures.Harness {
        Fixtures.makeViewModel(workouts: workouts, workout: workout)
    }

    // MARK: - moveSegments edge cases

    @Test("moveSegments to the same offset is a no-op")
    func moveSegmentsSamePositionNoOp() {
        let viewModel = makeViewModel().viewModel
        viewModel.addSegment(.warmUp)
        viewModel.addSegment(.tempo)
        viewModel.addSegment(.coolDown)
        let before = viewModel.segments

        viewModel.moveSegments(fromOffsets: IndexSet(integer: 1), toOffset: 1)

        #expect(viewModel.segments == before)
    }

    @Test("moveSegments to destination == count moves a segment to the end of the list")
    func moveSegmentsToEnd() {
        let viewModel = makeViewModel().viewModel
        viewModel.addSegment(.warmUp)
        viewModel.addSegment(.tempo)
        viewModel.addSegment(.coolDown)

        viewModel.moveSegments(fromOffsets: IndexSet(integer: 0), toOffset: 3)

        let intents = viewModel.segments.compactMap { segment -> SegmentIntent? in
            guard case let .step(step) = segment else { return nil }
            return step.intent
        }
        #expect(intents == [.tempo, .coolDown, .warmUp])
    }

    @Test("moveSegments moving an interior segment past the last element sends it to the end")
    func moveSegmentsInteriorToEnd() {
        let viewModel = makeViewModel().viewModel
        viewModel.addSegment(.warmUp)
        viewModel.addSegment(.tempo)
        viewModel.addSegment(.coolDown)

        viewModel.moveSegments(fromOffsets: IndexSet(integer: 1), toOffset: 3)

        let intents = viewModel.segments.compactMap { segment -> SegmentIntent? in
            guard case let .step(step) = segment else { return nil }
            return step.intent
        }
        #expect(intents == [.warmUp, .coolDown, .tempo])
    }

    // MARK: - replaceSegment edge cases

    @Test("replaceSegment(id:with:) with a mismatched id overwrites in place, adopting the new segment's own id")
    func replaceSegmentMismatchedIDAdoptsNewIdentity() {
        // Pinning documented behavior: `replaceSegment` looks up the slot by
        // the `id` argument, then unconditionally overwrites that slot with
        // `newSegment` — including `newSegment`'s own id. It does not
        // require (or enforce) that `newSegment.id == id`.
        let viewModel = makeViewModel().viewModel
        viewModel.addSegment(.warmUp)
        viewModel.addSegment(.tempo)
        let targetID = viewModel.segments[0].id
        let replacement = SegmentStep(intent: .easy, goal: .open)
        #expect(replacement.id != targetID)

        viewModel.replaceSegment(id: targetID, with: .step(replacement))

        #expect(viewModel.segments.count == 2)
        #expect(viewModel.segments[0].id == replacement.id)
        #expect(!viewModel.segments.contains { $0.id == targetID })
        guard case let .step(step) = viewModel.segments[0] else {
            Issue.record("Expected a .step segment")
            return
        }
        #expect(step.intent == .easy)
    }

    // MARK: - duplicateSegment edge cases

    @Test("duplicateSegment on an interval block introduces no id collisions anywhere in the workout")
    func duplicateIntervalBlockNoIDCollisionsAnywhere() {
        let viewModel = makeViewModel().viewModel
        viewModel.addSegment(.intervalBlock)
        let originalID = viewModel.segments[0].id

        viewModel.duplicateSegment(id: originalID)

        #expect(viewModel.segments.count == 2)
        var allIDs: [UUID] = []
        for segment in viewModel.segments {
            allIDs.append(segment.id)
            if case let .intervalBlock(_, steps, _) = segment {
                for intervalStep in steps {
                    allIDs.append(intervalStep.id)
                    allIDs.append(intervalStep.step.id)
                }
            }
        }
        #expect(allIDs.count == Set(allIDs).count)
    }

    @Test("duplicateSegment leaves the original segment's identity and content untouched")
    func duplicateSegmentPreservesOriginal() {
        let viewModel = makeViewModel().viewModel
        viewModel.addSegment(.tempo)
        let original = viewModel.segments[0]

        viewModel.duplicateSegment(id: original.id)

        #expect(viewModel.segments[0] == original)
    }

    // MARK: - deleteSegment edge cases

    @Test("deleteSegment on the last remaining segment leaves validationIssues reporting workoutHasNoSegments")
    func deleteLastRemainingSegmentReintroducesNoSegmentsIssue() {
        let viewModel = makeViewModel().viewModel
        viewModel.name = "Solo Segment"
        viewModel.addSegment(.easy)
        #expect(viewModel.validationIssues.isEmpty)
        let onlyID = viewModel.segments[0].id

        viewModel.deleteSegment(id: onlyID)

        #expect(viewModel.segments.isEmpty)
        #expect(viewModel.validationIssues.contains(ValidationIssue(rule: .workoutHasNoSegments, locator: .workout)))
    }

    // MARK: - validationIssues reactivity

    @Test("validationIssues transitions from a negative-goal issue to clean once the goal is fixed")
    func validationIssuesTransitionsIssueToClean() {
        let viewModel = makeViewModel().viewModel
        viewModel.name = "Fixable Workout"
        viewModel.addSegment(.tempo)
        let stepID = viewModel.segments[0].id
        let bad = SegmentStep(id: stepID, intent: .tempo, goal: .distance(meters: -5))
        viewModel.replaceSegment(id: stepID, with: .step(bad))

        #expect(viewModel.validationIssues.contains(
            ValidationIssue(rule: .goalDistanceNotPositive(meters: -5), locator: .segment(id: stepID))
        ))

        let fixed = SegmentStep(id: stepID, intent: .tempo, goal: .distance(meters: 5_000))
        viewModel.replaceSegment(id: stepID, with: .step(fixed))

        #expect(viewModel.validationIssues.isEmpty)
    }

    @Test("validationIssues flags an interval block with zero repetitions")
    func validationIssuesFlagsZeroRepetitionIntervalBlock() {
        let viewModel = makeViewModel().viewModel
        viewModel.name = "Zero Reps"
        viewModel.addSegment(.intervalBlock)
        let blockID = viewModel.segments[0].id
        guard case let .intervalBlock(id, steps, _) = viewModel.segments[0] else {
            Issue.record("Expected an .intervalBlock segment")
            return
        }

        viewModel.replaceSegment(id: blockID, with: .intervalBlock(id: id, steps: steps, repetitions: 0))

        #expect(viewModel.validationIssues.contains(
            ValidationIssue(rule: .intervalBlockRepetitionsNotPositive(repetitions: 0), locator: .segment(id: blockID))
        ))
    }

    // MARK: - save() edge cases

    @Test("save() failure preserves in-progress segment edits and writes nothing to the repository")
    func saveFailurePreservesSegmentEdits() async {
        let harness = makeViewModel()
        let viewModel = harness.viewModel
        viewModel.name = "Will Fail"
        viewModel.addSegment(.warmUp)
        viewModel.addSegment(.tempo)
        let segmentsBeforeFailure = viewModel.segments
        harness.repository.errorToThrow = WorkoutRepositoryError.underlying("disk full")

        await viewModel.save()

        #expect(viewModel.saveError == .underlying("disk full"))
        #expect(viewModel.segments == segmentsBeforeFailure)
        let persisted = try? await harness.repository.fetch(id: viewModel.workout.id)
        #expect(persisted == nil)
    }

    @Test("save() on an unedited, freshly-loaded workout still bumps updatedAt to the clock's current time")
    func saveUneditedLoadedWorkoutStillBumpsUpdatedAt() async {
        let staleUpdatedAt = referenceDate.addingTimeInterval(-86_400)
        let existing = Workout(
            name: "Steady State",
            segments: [.step(SegmentStep(intent: .easy, goal: .open))],
            createdAt: staleUpdatedAt,
            updatedAt: staleUpdatedAt
        )
        let harness = makeViewModel(workouts: [existing])
        let viewModel = harness.viewModel
        await viewModel.load(workoutID: existing.id)
        #expect(viewModel.loadError == nil)

        // No edits at all: no name/segment mutation between load and save.
        await viewModel.save()

        #expect(viewModel.saveError == nil)
        #expect(viewModel.workout.updatedAt == referenceDate)
        #expect(viewModel.workout.updatedAt != staleUpdatedAt)
        #expect(viewModel.workout.createdAt == staleUpdatedAt)
    }

    @Test("Consecutive save() calls upsert the same workout rather than creating duplicates")
    func consecutiveSavesUpsertSameWorkout() async {
        let harness = makeViewModel()
        let viewModel = harness.viewModel
        viewModel.name = "Repeatable"
        viewModel.addSegment(.easy)

        await viewModel.save()
        harness.clock.advance(by: 60)
        viewModel.addSegment(.coolDown)
        await viewModel.save()

        #expect(viewModel.saveError == nil)
        #expect(harness.repository.workoutsByID.count == 1)
        let persisted = try? await harness.repository.fetch(id: viewModel.workout.id)
        #expect(persisted?.segments.count == 2)
        #expect(persisted?.updatedAt == referenceDate.addingTimeInterval(60))
    }

    @Test("save() stamps updatedAt from the injected clock, not the wall clock")
    func saveStampsUpdatedAtFromInjectedClockNotWallClock() async {
        // A date far outside "now" (2026) so a regression to `Date()` would
        // be unmistakably wrong rather than accidentally close.
        let farFutureDate = Date(timeIntervalSince1970: 4_102_444_800) // 2100-01-01
        let repository = FakeWorkoutRepository()
        let clock = FakeClock(currentDate: farFutureDate)
        let viewModel = BuilderViewModel(workoutRepository: repository, clock: clock)
        viewModel.name = "Future Dated"
        viewModel.addSegment(.easy)

        await viewModel.save()

        #expect(viewModel.saveError == nil)
        #expect(viewModel.workout.updatedAt == farFutureDate)
        #expect(viewModel.workout.updatedAt != Date())
    }

    @Test("createdAt for a brand-new workout is fixed at construction time, unaffected by clock advances before save")
    func createdAtFixedAtConstructionForNewWorkout() async {
        let harness = makeViewModel()
        let viewModel = harness.viewModel
        harness.clock.advance(by: 3_600)
        viewModel.name = "New Draft"
        viewModel.addSegment(.easy)

        await viewModel.save()

        #expect(viewModel.saveError == nil)
        #expect(viewModel.workout.createdAt == referenceDate)
        #expect(viewModel.workout.updatedAt == referenceDate.addingTimeInterval(3_600))
    }

    @Test("createdAt is preserved when editing and re-saving an existing loaded workout")
    func createdAtPreservedOnEditOfExistingWorkout() async {
        let existing = Workout(
            name: "Original Name",
            segments: [.step(SegmentStep(intent: .easy, goal: .open))],
            createdAt: referenceDate,
            updatedAt: referenceDate
        )
        let harness = makeViewModel(workouts: [existing])
        let viewModel = harness.viewModel
        await viewModel.load(workoutID: existing.id)
        harness.clock.advance(by: 120)
        viewModel.name = "Edited Name"

        await viewModel.save()

        #expect(viewModel.saveError == nil)
        #expect(viewModel.workout.createdAt == referenceDate)
        #expect(viewModel.workout.updatedAt == referenceDate.addingTimeInterval(120))
        let persisted = try? await harness.repository.fetch(id: existing.id)
        #expect(persisted?.createdAt == referenceDate)
    }

    // MARK: - load(workoutID:) edge cases

    @Test("load(workoutID:) surfaces a non-not-found repository error verbatim, leaving the draft unchanged")
    func loadSurfacesUnderlyingRepositoryErrorVerbatim() async {
        let harness = makeViewModel()
        let viewModel = harness.viewModel
        viewModel.name = "Draft In Progress"
        harness.repository.errorToThrow = WorkoutRepositoryError.underlying("network unavailable")

        await viewModel.load(workoutID: UUID())

        #expect(viewModel.loadError == .underlying("network unavailable"))
        #expect(viewModel.name == "Draft In Progress")
        #expect(viewModel.isLoading == false)
    }
}
