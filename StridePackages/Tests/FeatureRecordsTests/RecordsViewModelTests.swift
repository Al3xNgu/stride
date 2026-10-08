import Testing
import Foundation
@testable import FeatureRecords
import DomainKit
import TestSupport

/// Coverage of `RecordsViewModel`'s board/history/source-run-resolution
/// flows against `TestSupport` fakes.
@MainActor
@Suite("RecordsViewModel")
struct RecordsViewModelTests {
    private typealias Fixtures = RecordsViewModelFixtures

    // MARK: - Board composition

    @Test("load() produces one board entry per milestone with a record for every MVP milestone")
    func loadWithAllRecordsPopulatesEveryEntry() async {
        var runs: [CompletedRun] = []
        var personalBests: [PersonalBest] = []
        for milestone in Milestone.mvpPresets {
            let run = Fixtures.makeRun()
            runs.append(run)
            personalBests.append(
                Fixtures.makePersonalBest(milestoneID: milestone.id, elapsedSeconds: 1_000, completedRunID: run.id)
            )
        }
        let harness = Fixtures.makeViewModel(runs: runs, personalBests: personalBests)

        await harness.viewModel.load()

        #expect(harness.viewModel.loadError == nil)
        #expect(harness.viewModel.board.count == Milestone.mvpPresets.count)
        #expect(harness.viewModel.board.map(\.milestone.id) == Milestone.mvpPresets.map(\.id))
        #expect(harness.viewModel.board.allSatisfy { $0.personalBest != nil })
    }

    @Test("load() produces empty slots for milestones with no record, alongside populated ones")
    func loadWithPartialRecordsLeavesEmptySlots() async {
        let run = Fixtures.makeRun()
        let personalBest = Fixtures.makePersonalBest(
            milestoneID: Milestone.fiveK.id, elapsedSeconds: 1_200, completedRunID: run.id
        )
        let harness = Fixtures.makeViewModel(runs: [run], personalBests: [personalBest])

        await harness.viewModel.load()

        let fiveKEntry = harness.viewModel.board.first { $0.milestone.id == Milestone.fiveK.id }
        #expect(fiveKEntry?.personalBest?.id == personalBest.id)

        let tenKEntry = harness.viewModel.board.first { $0.milestone.id == Milestone.tenK.id }
        #expect(tenKEntry?.personalBest == nil)
        #expect(tenKEntry?.sourceRun == nil)
    }

    @Test("load() with no records produces an entry per milestone, every one an empty slot")
    func loadWithNoRecordsIsAllEmptySlots() async {
        let harness = Fixtures.makeViewModel()

        await harness.viewModel.load()

        #expect(harness.viewModel.board.count == Milestone.mvpPresets.count)
        #expect(harness.viewModel.board.allSatisfy { $0.personalBest == nil && $0.sourceRun == nil })
    }

    // MARK: - Source-run resolution

    @Test("load() resolves a current record's source run on a hit")
    func loadResolvesSourceRunOnHit() async {
        let run = Fixtures.makeRun()
        let personalBest = Fixtures.makePersonalBest(
            milestoneID: Milestone.fiveK.id, elapsedSeconds: 1_200, completedRunID: run.id
        )
        let harness = Fixtures.makeViewModel(runs: [run], personalBests: [personalBest])

        await harness.viewModel.load()

        let entry = harness.viewModel.board.first { $0.milestone.id == Milestone.fiveK.id }
        #expect(entry?.sourceRun?.id == run.id)
    }

    @Test("load() tolerates a source run that no longer resolves (deleted/tombstoned-away) without failing")
    func loadTreatsMissingSourceRunAsNil() async {
        let personalBest = Fixtures.makePersonalBest(
            milestoneID: Milestone.fiveK.id, elapsedSeconds: 1_200, completedRunID: UUID()
        )
        let harness = Fixtures.makeViewModel(personalBests: [personalBest])

        await harness.viewModel.load()

        #expect(harness.viewModel.loadError == nil)
        let entry = harness.viewModel.board.first { $0.milestone.id == Milestone.fiveK.id }
        #expect(entry?.personalBest?.id == personalBest.id)
        #expect(entry?.sourceRun == nil)
    }

    @Test("load() treats a tombstoned source run as unavailable")
    func loadTreatsTombstonedSourceRunAsNil() async {
        let workout = Fixtures.makeWorkout(name: "Deleted run workout")
        let run = Fixtures.makeRun(workoutID: workout.id, isDeleted: true)
        let personalBest = Fixtures.makePersonalBest(
            milestoneID: Milestone.fiveK.id,
            elapsedSeconds: 1_200,
            completedRunID: run.id
        )
        let harness = Fixtures.makeViewModel(
            runs: [run],
            workouts: [workout],
            personalBests: [personalBest]
        )

        await harness.viewModel.load()

        #expect(harness.viewModel.loadError == nil)
        let entry = harness.viewModel.board.first { $0.milestone.id == Milestone.fiveK.id }
        #expect(entry?.personalBest?.id == personalBest.id)
        #expect(entry?.sourceRun == nil)
        #expect(entry?.sourceWorkoutName == nil)
    }

    @Test("load() resolves the source run's attributed workout name when a workoutRepository is injected")
    func loadResolvesSourceWorkoutNameWhenInjected() async {
        let workout = Fixtures.makeWorkout(name: "5k Tempo")
        let run = Fixtures.makeRun(workoutID: workout.id)
        let personalBest = Fixtures.makePersonalBest(
            milestoneID: Milestone.fiveK.id, elapsedSeconds: 1_200, completedRunID: run.id
        )
        let harness = Fixtures.makeViewModel(runs: [run], workouts: [workout], personalBests: [personalBest])

        await harness.viewModel.load()

        let entry = harness.viewModel.board.first { $0.milestone.id == Milestone.fiveK.id }
        #expect(entry?.sourceWorkoutName == "5k Tempo")
    }

    @Test("load() leaves sourceWorkoutName nil when no workoutRepository was injected, even if attributed")
    func loadLeavesSourceWorkoutNameNilWithoutWorkoutRepository() async {
        let workout = Fixtures.makeWorkout(name: "5k Tempo")
        let run = Fixtures.makeRun(workoutID: workout.id)
        let personalBest = Fixtures.makePersonalBest(
            milestoneID: Milestone.fiveK.id, elapsedSeconds: 1_200, completedRunID: run.id
        )
        let harness = Fixtures.makeViewModel(
            runs: [run], workouts: [workout], personalBests: [personalBest], includeWorkoutRepository: false
        )

        await harness.viewModel.load()

        let entry = harness.viewModel.board.first { $0.milestone.id == Milestone.fiveK.id }
        #expect(entry?.sourceRun?.id == run.id)
        #expect(entry?.sourceWorkoutName == nil)
    }

    // MARK: - Per-milestone history

    @Test("history(for:) returns the current record first, then superseded records")
    func historyReturnsCurrentFirst() async {
        let slowerRun = Fixtures.makeRun(date: Fixtures.referenceDate.addingTimeInterval(-86_400))
        let fasterRun = Fixtures.makeRun(date: Fixtures.referenceDate)
        let slowerRecord = Fixtures.makePersonalBest(
            milestoneID: Milestone.fiveK.id,
            elapsedSeconds: 1_400,
            completedRunID: slowerRun.id,
            achievedAt: Fixtures.referenceDate.addingTimeInterval(-86_400)
        )
        let fasterRecord = Fixtures.makePersonalBest(
            milestoneID: Milestone.fiveK.id,
            elapsedSeconds: 1_200,
            completedRunID: fasterRun.id,
            achievedAt: Fixtures.referenceDate
        )
        let harness = Fixtures.makeViewModel(
            runs: [slowerRun, fasterRun], personalBests: [slowerRecord, fasterRecord]
        )

        await harness.viewModel.load()

        let history = harness.viewModel.history(for: Milestone.fiveK.id)
        #expect(history.map(\.id) == [fasterRecord.id, slowerRecord.id])

        let boardEntry = harness.viewModel.board.first { $0.milestone.id == Milestone.fiveK.id }
        #expect(boardEntry?.personalBest?.id == fasterRecord.id)
    }

    @Test("history(for:) is empty for a milestone with no records")
    func historyIsEmptyForNoRecords() async {
        let harness = Fixtures.makeViewModel()

        await harness.viewModel.load()

        #expect(harness.viewModel.history(for: Milestone.marathon.id).isEmpty)
    }

    // MARK: - Failure path

    @Test("load() surfaces a typed error and leaves board unchanged on failure")
    func loadFailureSurfacesError() async {
        let run = Fixtures.makeRun()
        let personalBest = Fixtures.makePersonalBest(
            milestoneID: Milestone.fiveK.id, elapsedSeconds: 1_200, completedRunID: run.id
        )
        let harness = Fixtures.makeViewModel(runs: [run], personalBests: [personalBest])
        await harness.viewModel.load()
        #expect(harness.viewModel.board.contains { $0.personalBest != nil })

        harness.runRepository.errorToThrow = RunHistoryRepositoryError.underlying("disk full")
        await harness.viewModel.load()

        #expect(harness.viewModel.loadError == .underlying("disk full"))
        #expect(harness.viewModel.board.contains { $0.personalBest != nil })
    }
}
