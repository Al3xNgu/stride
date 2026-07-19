import Testing
import Foundation
import DomainKit
@testable import DataKit

/// Shared fixtures for `WatchCompositionPlanner` test suites.
enum WatchCompositionPlannerFixtures {
    static let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)

    static func makeWorkout(
        name: String = "Test Workout",
        segments: [WorkoutSegment]
    ) -> Workout {
        Workout(name: name, segments: segments, createdAt: referenceDate, updatedAt: referenceDate)
    }

    static func step(
        intent: SegmentIntent,
        goal: Goal = .open,
        target: Target? = nil
    ) -> SegmentStep {
        SegmentStep(intent: intent, goal: goal, target: target)
    }
}

/// Segment partitioning coverage: leading warm-up / trailing cool-down
/// detection, the "only the leading one is special-cased" rule for multiple
/// warm-up-intent steps, and the empty-workout error path.
@Suite("WatchCompositionPlanner — segment partitioning")
struct WatchCompositionPlannerSegmentTests {
    private typealias Fixtures = WatchCompositionPlannerFixtures

    @Test("No warm-up or cool-down: every segment becomes a 1-iteration block")
    func noWarmupNoCooldown() throws {
        let workout = Fixtures.makeWorkout(segments: [
            .step(Fixtures.step(intent: .easy, goal: .duration(seconds: 300))),
            .step(Fixtures.step(intent: .tempo, goal: .duration(seconds: 600)))
        ])
        let plan = try WatchCompositionPlanner.plan(for: workout)
        #expect(plan.warmup == nil)
        #expect(plan.cooldown == nil)
        #expect(plan.blocks.count == 2)
        #expect(plan.blocks[0].iterations == 1)
        #expect(plan.blocks[0].steps.count == 1)
    }

    @Test("Leading warmUp-intent step is extracted as the plan's warmup")
    func leadingWarmupExtracted() throws {
        let workout = Fixtures.makeWorkout(segments: [
            .step(Fixtures.step(intent: .warmUp, goal: .duration(seconds: 300))),
            .step(Fixtures.step(intent: .easy, goal: .duration(seconds: 600)))
        ])
        let plan = try WatchCompositionPlanner.plan(for: workout)
        #expect(plan.warmup?.intent == .warmUp)
        #expect(plan.blocks.count == 1)
        #expect(plan.blocks[0].steps.first?.step.intent == .easy)
    }

    @Test("Trailing coolDown-intent step is extracted as the plan's cooldown")
    func trailingCooldownExtracted() throws {
        let workout = Fixtures.makeWorkout(segments: [
            .step(Fixtures.step(intent: .easy, goal: .duration(seconds: 600))),
            .step(Fixtures.step(intent: .coolDown, goal: .duration(seconds: 300)))
        ])
        let plan = try WatchCompositionPlanner.plan(for: workout)
        #expect(plan.cooldown?.intent == .coolDown)
        #expect(plan.blocks.count == 1)
        #expect(plan.blocks[0].steps.first?.step.intent == .easy)
    }

    @Test("Warmup and cooldown are both extracted, leaving only the interior segments as blocks")
    func warmupAndCooldownBothExtracted() throws {
        let intervalStep = IntervalStep(purpose: .work, step: Fixtures.step(intent: .work, goal: .duration(seconds: 60)))
        let workout = Fixtures.makeWorkout(segments: [
            .step(Fixtures.step(intent: .warmUp, goal: .duration(seconds: 300))),
            .intervalBlock(steps: [intervalStep], repetitions: 4),
            .step(Fixtures.step(intent: .coolDown, goal: .duration(seconds: 300)))
        ])
        let plan = try WatchCompositionPlanner.plan(for: workout)
        #expect(plan.warmup?.intent == .warmUp)
        #expect(plan.cooldown?.intent == .coolDown)
        #expect(plan.blocks.count == 1)
        #expect(plan.blocks[0].iterations == 4)
    }

    @Test("Only the leading warmUp-intent step is special-cased; a second one becomes a block")
    func onlyLeadingWarmupSpecialCased() throws {
        let workout = Fixtures.makeWorkout(segments: [
            .step(Fixtures.step(intent: .warmUp, goal: .duration(seconds: 300))),
            .step(Fixtures.step(intent: .warmUp, goal: .duration(seconds: 120))),
            .step(Fixtures.step(intent: .easy, goal: .duration(seconds: 600)))
        ])
        let plan = try WatchCompositionPlanner.plan(for: workout)
        #expect(plan.warmup?.goal == .duration(seconds: 300))
        #expect(plan.blocks.count == 2)
        // The second warmUp-intent step, now a block, maps to `.work`
        // purpose (only `.recovery`/`.rest` intents map to `.recovery`).
        #expect(plan.blocks[0].steps.first?.purpose == .work)
        #expect(plan.blocks[0].steps.first?.step.intent == .warmUp)
    }

    @Test("An empty workout throws invalidComposition rather than producing an empty plan")
    func emptyWorkoutThrows() {
        let workout = Fixtures.makeWorkout(segments: [])
        #expect(throws: WatchSyncError.self) {
            _ = try WatchCompositionPlanner.plan(for: workout)
        }
    }

    @Test("A workout with only a single warmUp-intent step has no blocks and no cooldown")
    func onlyWarmupStep() throws {
        let workout = Fixtures.makeWorkout(segments: [
            .step(Fixtures.step(intent: .warmUp, goal: .duration(seconds: 300)))
        ])
        let plan = try WatchCompositionPlanner.plan(for: workout)
        #expect(plan.warmup != nil)
        #expect(plan.cooldown == nil)
        #expect(plan.blocks.isEmpty)
    }

    @Test("A workout with only a single coolDown-intent step has no blocks and no warmup")
    func onlyCooldownStep() throws {
        let workout = Fixtures.makeWorkout(segments: [
            .step(Fixtures.step(intent: .coolDown, goal: .duration(seconds: 300)))
        ])
        let plan = try WatchCompositionPlanner.plan(for: workout)
        #expect(plan.cooldown != nil)
        #expect(plan.warmup == nil)
        #expect(plan.blocks.isEmpty)
    }

    @Test("A leading interval block is never treated as a warmup, even if its steps are warmUp-intent")
    func leadingIntervalBlockNeverWarmup() throws {
        let intervalStep = IntervalStep(purpose: .work, step: Fixtures.step(intent: .warmUp, goal: .duration(seconds: 60)))
        let workout = Fixtures.makeWorkout(segments: [
            .intervalBlock(steps: [intervalStep], repetitions: 2),
            .step(Fixtures.step(intent: .easy, goal: .duration(seconds: 600)))
        ])
        let plan = try WatchCompositionPlanner.plan(for: workout)
        #expect(plan.warmup == nil)
        #expect(plan.blocks.count == 2)
    }

    @Test("A trailing interval block is never treated as a cooldown, even if its steps are coolDown-intent")
    func trailingIntervalBlockNeverCooldown() throws {
        let intervalStep = IntervalStep(purpose: .work, step: Fixtures.step(intent: .coolDown, goal: .duration(seconds: 60)))
        let workout = Fixtures.makeWorkout(segments: [
            .step(Fixtures.step(intent: .easy, goal: .duration(seconds: 600))),
            .intervalBlock(steps: [intervalStep], repetitions: 2)
        ])
        let plan = try WatchCompositionPlanner.plan(for: workout)
        #expect(plan.cooldown == nil)
        #expect(plan.blocks.count == 2)
    }

    @Test("Multiple interior interval blocks preserve order and don't cross-contaminate")
    func multipleBlocksPreserveOrder() throws {
        let firstStep = IntervalStep(purpose: .work, step: Fixtures.step(intent: .work, goal: .distance(meters: 400)))
        let secondStep = IntervalStep(purpose: .work, step: Fixtures.step(intent: .work, goal: .distance(meters: 800)))
        let workout = Fixtures.makeWorkout(segments: [
            .intervalBlock(steps: [firstStep], repetitions: 3),
            .intervalBlock(steps: [secondStep], repetitions: 5)
        ])
        let plan = try WatchCompositionPlanner.plan(for: workout)
        #expect(plan.blocks.count == 2)
        #expect(plan.blocks[0].iterations == 3)
        #expect(plan.blocks[0].steps.first?.step.goal == .distance(meters: 400))
        #expect(plan.blocks[1].iterations == 5)
        #expect(plan.blocks[1].steps.first?.step.goal == .distance(meters: 800))
    }

    @Test("A warmUp-intent step in the middle of the workout is never special-cased, only mapped into a block")
    func midWorkoutWarmupIntentNeverSpecialCased() throws {
        let workout = Fixtures.makeWorkout(segments: [
            .step(Fixtures.step(intent: .easy, goal: .duration(seconds: 300))),
            .step(Fixtures.step(intent: .warmUp, goal: .duration(seconds: 120))),
            .step(Fixtures.step(intent: .easy, goal: .duration(seconds: 300)))
        ])
        let plan = try WatchCompositionPlanner.plan(for: workout)
        #expect(plan.warmup == nil)
        #expect(plan.cooldown == nil)
        #expect(plan.blocks.count == 3)
        #expect(plan.blocks[1].steps.first?.step.intent == .warmUp)
    }

    @Test("A coolDown-intent step in the middle of the workout is never special-cased, only mapped into a block")
    func midWorkoutCooldownIntentNeverSpecialCased() throws {
        let workout = Fixtures.makeWorkout(segments: [
            .step(Fixtures.step(intent: .easy, goal: .duration(seconds: 300))),
            .step(Fixtures.step(intent: .coolDown, goal: .duration(seconds: 120))),
            .step(Fixtures.step(intent: .easy, goal: .duration(seconds: 300)))
        ])
        let plan = try WatchCompositionPlanner.plan(for: workout)
        #expect(plan.warmup == nil)
        #expect(plan.cooldown == nil)
        #expect(plan.blocks.count == 3)
        #expect(plan.blocks[1].steps.first?.step.intent == .coolDown)
    }

    @Test("A workout that is only a warmUp step followed by a coolDown step (no middle) has no blocks")
    func onlyWarmupThenCooldownNoMiddle() throws {
        let workout = Fixtures.makeWorkout(segments: [
            .step(Fixtures.step(intent: .warmUp, goal: .duration(seconds: 300))),
            .step(Fixtures.step(intent: .coolDown, goal: .duration(seconds: 300)))
        ])
        let plan = try WatchCompositionPlanner.plan(for: workout)
        #expect(plan.warmup?.intent == .warmUp)
        #expect(plan.cooldown?.intent == .coolDown)
        #expect(plan.blocks.isEmpty)
    }

    @Test("An interval block with 50 iterations maps its iterations through unchanged")
    func largeIterationCountPreserved() throws {
        let work = IntervalStep(purpose: .work, step: Fixtures.step(intent: .work, goal: .distance(meters: 400)))
        let workout = Fixtures.makeWorkout(segments: [.intervalBlock(steps: [work], repetitions: 50)])
        let plan = try WatchCompositionPlanner.plan(for: workout)
        #expect(plan.blocks[0].iterations == 50)
    }

    @Test("Adjacent single top-level steps each become their own separate 1-iteration block, not a merged block")
    func adjacentSingleStepsRemainSeparateBlocks() throws {
        let workout = Fixtures.makeWorkout(segments: [
            .step(Fixtures.step(intent: .easy, goal: .duration(seconds: 60))),
            .step(Fixtures.step(intent: .tempo, goal: .duration(seconds: 120))),
            .step(Fixtures.step(intent: .easy, goal: .duration(seconds: 60)))
        ])
        let plan = try WatchCompositionPlanner.plan(for: workout)
        #expect(plan.blocks.count == 3)
        for block in plan.blocks {
            #expect(block.iterations == 1)
            #expect(block.steps.count == 1)
        }
    }

    @Test("A single open-goal top-level step (no warmup/cooldown intent) becomes a single block with a nil alert")
    func singleOpenGoalStepBecomesOneBlock() throws {
        let workout = Fixtures.makeWorkout(segments: [
            .step(Fixtures.step(intent: .easy, goal: .open))
        ])
        let plan = try WatchCompositionPlanner.plan(for: workout)
        #expect(plan.blocks.count == 1)
        #expect(plan.blocks[0].steps.first?.step.goal == .open)
        #expect(plan.blocks[0].steps.first?.step.alert == nil)
    }

    @Test("An invalid goal hidden in the 3rd step of the 2nd interval block still throws, never silently composing")
    func deeplyNestedInvalidValueThrows() {
        let blockOneSteps = [
            IntervalStep(purpose: .work, step: Fixtures.step(intent: .work, goal: .distance(meters: 400))),
            IntervalStep(purpose: .recovery, step: Fixtures.step(intent: .recovery, goal: .distance(meters: 200)))
        ]
        let blockTwoSteps = [
            IntervalStep(purpose: .work, step: Fixtures.step(intent: .work, goal: .distance(meters: 400))),
            IntervalStep(purpose: .recovery, step: Fixtures.step(intent: .recovery, goal: .distance(meters: 200))),
            // The 3rd step of the 2nd block carries the sole invalid value.
            IntervalStep(purpose: .work, step: Fixtures.step(intent: .work, goal: .distance(meters: -1)))
        ]
        let workout = Fixtures.makeWorkout(segments: [
            .step(Fixtures.step(intent: .warmUp, goal: .duration(seconds: 300))),
            .intervalBlock(steps: blockOneSteps, repetitions: 3),
            .intervalBlock(steps: blockTwoSteps, repetitions: 2),
            .step(Fixtures.step(intent: .coolDown, goal: .duration(seconds: 300)))
        ])
        #expect(throws: WatchSyncError.self) {
            _ = try WatchCompositionPlanner.plan(for: workout)
        }
    }
}

/// Interval block/step purpose and iterations mapping.
@Suite("WatchCompositionPlanner — interval blocks")
struct WatchCompositionPlannerIntervalTests {
    private typealias Fixtures = WatchCompositionPlannerFixtures

    @Test("An interval block's repetitions map exactly to the planned block's iterations")
    func repetitionsMapToIterations() throws {
        let work = IntervalStep(purpose: .work, step: Fixtures.step(intent: .work, goal: .distance(meters: 400)))
        let recovery = IntervalStep(purpose: .recovery, step: Fixtures.step(intent: .recovery, goal: .distance(meters: 200)))
        let workout = Fixtures.makeWorkout(segments: [
            .intervalBlock(steps: [work, recovery], repetitions: 6)
        ])
        let plan = try WatchCompositionPlanner.plan(for: workout)
        #expect(plan.blocks[0].iterations == 6)
        #expect(plan.blocks[0].steps.map(\.purpose) == [.work, .recovery])
    }

    @Test("A lone top-level step becomes a 1-iteration block")
    func loneStepBecomesSingleIterationBlock() throws {
        let workout = Fixtures.makeWorkout(segments: [
            .step(Fixtures.step(intent: .tempo, goal: .duration(seconds: 600)))
        ])
        let plan = try WatchCompositionPlanner.plan(for: workout)
        #expect(plan.blocks[0].iterations == 1)
        #expect(plan.blocks[0].steps.count == 1)
    }

    @Test(
        "A lone top-level step's purpose is .recovery only for recovery/rest intents",
        arguments: [
            (SegmentIntent.easy, IntervalStepPurpose.work),
            (.tempo, .work),
            (.threshold, .work),
            (.work, .work),
            (.recovery, .recovery),
            (.rest, .recovery)
        ]
    )
    func loneStepPurposeMapping(intent: SegmentIntent, expectedPurpose: IntervalStepPurpose) throws {
        let workout = Fixtures.makeWorkout(segments: [.step(Fixtures.step(intent: intent, goal: .open))])
        let plan = try WatchCompositionPlanner.plan(for: workout)
        #expect(plan.blocks[0].steps.first?.purpose == expectedPurpose)
    }

    @Test("An interval block with 0 repetitions throws (ValidateWorkoutPolicy pre-flight)")
    func zeroRepetitionsThrows() {
        let work = IntervalStep(purpose: .work, step: Fixtures.step(intent: .work, goal: .open))
        let workout = Fixtures.makeWorkout(segments: [.intervalBlock(steps: [work], repetitions: 0)])
        #expect(throws: WatchSyncError.self) {
            _ = try WatchCompositionPlanner.plan(for: workout)
        }
    }

    @Test("An interval block with negative repetitions throws (ValidateWorkoutPolicy pre-flight)")
    func negativeRepetitionsThrows() {
        let work = IntervalStep(purpose: .work, step: Fixtures.step(intent: .work, goal: .open))
        let workout = Fixtures.makeWorkout(segments: [.intervalBlock(steps: [work], repetitions: -1)])
        #expect(throws: WatchSyncError.self) {
            _ = try WatchCompositionPlanner.plan(for: workout)
        }
    }

    @Test("An interval block with no steps throws (ValidateWorkoutPolicy pre-flight)")
    func noStepsThrows() {
        let workout = Fixtures.makeWorkout(segments: [.intervalBlock(steps: [], repetitions: 3)])
        #expect(throws: WatchSyncError.self) {
            _ = try WatchCompositionPlanner.plan(for: workout)
        }
    }
}

/// Determinism ("id stability"): planning the same domain `Workout` twice
/// produces an identical `WorkoutCompositionPlan`, and distinct interval
/// blocks (each with their own `WorkoutSegment.id`) never bleed into each
/// other's planned steps — the IR itself carries no ids (WorkoutKit's own
/// types have none either), so determinism/no-cross-contamination is the
/// property that matters for reconciliation to behave predictably.
@Suite("WatchCompositionPlanner — determinism")
struct WatchCompositionPlannerDeterminismTests {
    private typealias Fixtures = WatchCompositionPlannerFixtures

    @Test("Planning the same workout twice produces an equal plan")
    func planningIsDeterministic() throws {
        let work = IntervalStep(purpose: .work, step: Fixtures.step(intent: .work, goal: .distance(meters: 400)))
        let recovery = IntervalStep(purpose: .recovery, step: Fixtures.step(intent: .recovery, goal: .distance(meters: 200)))
        let workout = Fixtures.makeWorkout(segments: [
            .step(Fixtures.step(intent: .warmUp, goal: .duration(seconds: 300))),
            .intervalBlock(steps: [work, recovery], repetitions: 4),
            .step(Fixtures.step(intent: .coolDown, goal: .duration(seconds: 300)))
        ])
        let first = try WatchCompositionPlanner.plan(for: workout)
        let second = try WatchCompositionPlanner.plan(for: workout)
        #expect(first == second)
    }

    @Test("Two distinct interval blocks (different WorkoutSegment ids) map to independent, non-cross-contaminated blocks")
    func distinctBlockIdsDoNotCrossContaminate() throws {
        let stepA = IntervalStep(purpose: .work, step: Fixtures.step(intent: .work, goal: .distance(meters: 100)))
        let stepB = IntervalStep(purpose: .work, step: Fixtures.step(intent: .work, goal: .distance(meters: 999)))
        let blockA = WorkoutSegment.intervalBlock(id: UUID(), steps: [stepA], repetitions: 2)
        let blockB = WorkoutSegment.intervalBlock(id: UUID(), steps: [stepB], repetitions: 9)
        let workout = Fixtures.makeWorkout(segments: [blockA, blockB])

        let plan = try WatchCompositionPlanner.plan(for: workout)

        #expect(plan.blocks[0].iterations == 2)
        #expect(plan.blocks[0].steps.first?.step.goal == .distance(meters: 100))
        #expect(plan.blocks[1].iterations == 9)
        #expect(plan.blocks[1].steps.first?.step.goal == .distance(meters: 999))
    }
}
