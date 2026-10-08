import Testing
import Foundation
@testable import FeatureHistory
import DomainKit
import TestSupport

/// Coverage of `HistoryViewModel`'s load/sort/grouping/attribution flows
/// against `TestSupport` fakes.
@MainActor
@Suite("HistoryViewModel")
struct HistoryViewModelTests {
    private typealias Fixtures = HistoryViewModelFixtures

    // MARK: - load() / sort / grouping

    @Test("load() sorts runs newest first within a single month section")
    func loadSortsNewestFirstWithinAMonth() async {
        let older = Fixtures.makeRun(date: Fixtures.date(year: 2024, month: 1, day: 5))
        let newer = Fixtures.makeRun(date: Fixtures.date(year: 2024, month: 1, day: 20))
        let harness = Fixtures.makeViewModel(runs: [older, newer])

        await harness.viewModel.load()

        #expect(harness.viewModel.loadError == nil)
        #expect(harness.viewModel.sections.count == 1)
        #expect(harness.viewModel.sections.first?.rows.map(\.id) == [newer.id, older.id])
    }

    @Test("load() groups runs into month sections, newest month first, preserving row order within each")
    func loadGroupsByMonth() async {
        let januaryOlder = Fixtures.makeRun(date: Fixtures.date(year: 2024, month: 1, day: 5))
        let januaryNewer = Fixtures.makeRun(date: Fixtures.date(year: 2024, month: 1, day: 20))
        let december = Fixtures.makeRun(date: Fixtures.date(year: 2023, month: 12, day: 25))
        let harness = Fixtures.makeViewModel(runs: [januaryOlder, januaryNewer, december])

        await harness.viewModel.load()

        #expect(harness.viewModel.sections.count == 2)
        #expect(harness.viewModel.sections[0].rows.map(\.id) == [januaryNewer.id, januaryOlder.id])
        #expect(harness.viewModel.sections[1].rows.map(\.id) == [december.id])
    }

    @Test("load() groups correctly across a year rollover")
    func loadGroupsAcrossYearRollover() async {
        let newYear = Fixtures.makeRun(date: Fixtures.date(year: 2024, month: 1, day: 1))
        let oldYear = Fixtures.makeRun(date: Fixtures.date(year: 2023, month: 12, day: 31))
        let harness = Fixtures.makeViewModel(runs: [newYear, oldYear])

        await harness.viewModel.load()

        #expect(harness.viewModel.sections.count == 2)
        #expect(harness.viewModel.sections[0].rows.map(\.id) == [newYear.id])
        #expect(harness.viewModel.sections[1].rows.map(\.id) == [oldYear.id])
        // The newer month section's `monthStart` must itself be later, not
        // just contain the newer row — this is what would break if grouping
        // ever regressed to bucketing by day-of-month rather than
        // year+month.
        let firstMonthStart = harness.viewModel.sections[0].monthStart
        let secondMonthStart = harness.viewModel.sections[1].monthStart
        #expect(firstMonthStart > secondMonthStart)
    }

    @Test("load() excludes tombstoned runs")
    func loadExcludesTombstonedRuns() async {
        let active = Fixtures.makeRun(date: Fixtures.date(year: 2024, month: 1, day: 5))
        let tombstoned = Fixtures.makeRun(date: Fixtures.date(year: 2024, month: 1, day: 10), isDeleted: true)
        let harness = Fixtures.makeViewModel(runs: [active, tombstoned])

        await harness.viewModel.load()

        let allRowIDs = harness.viewModel.sections.flatMap { $0.rows.map(\.id) }
        #expect(allRowIDs == [active.id])
    }

    @Test("load() with no active runs produces an empty state")
    func loadWithNoRunsIsEmpty() async {
        let harness = Fixtures.makeViewModel()

        await harness.viewModel.load()

        #expect(harness.viewModel.isEmpty)
        #expect(harness.viewModel.sections.isEmpty)
    }

    @Test("load() with only tombstoned runs produces an empty state")
    func loadWithOnlyTombstonedRunsIsEmpty() async {
        let tombstoned = Fixtures.makeRun(isDeleted: true)
        let harness = Fixtures.makeViewModel(runs: [tombstoned])

        await harness.viewModel.load()

        #expect(harness.viewModel.isEmpty)
    }

    // MARK: - Attribution

    @Test("load() resolves an attributed run's workout name on a hit")
    func loadResolvesAttributionOnHit() async {
        let workout = Fixtures.makeWorkout(name: "5x1km Intervals")
        let run = Fixtures.makeRun(workoutID: workout.id)
        let harness = Fixtures.makeViewModel(runs: [run], workouts: [workout])

        await harness.viewModel.load()

        #expect(harness.viewModel.sections.first?.rows.first?.attributedWorkoutName == "5x1km Intervals")
    }

    @Test("load() tolerates a workoutID that no longer resolves (miss)")
    func loadTreatsUnresolvedAttributionAsNil() async {
        let run = Fixtures.makeRun(workoutID: UUID())
        let harness = Fixtures.makeViewModel(runs: [run])

        await harness.viewModel.load()

        #expect(harness.viewModel.loadError == nil)
        #expect(harness.viewModel.sections.first?.rows.first?.attributedWorkoutName == nil)
    }

    @Test("load() leaves attributedWorkoutName nil for an unattributed run")
    func loadLeavesUnattributedRunsNil() async {
        let run = Fixtures.makeRun(workoutID: nil)
        let harness = Fixtures.makeViewModel(runs: [run])

        await harness.viewModel.load()

        #expect(harness.viewModel.sections.first?.rows.first?.attributedWorkoutName == nil)
    }

    // MARK: - Failure path

    @Test("load() surfaces a typed error and leaves sections unchanged on failure")
    func loadFailureSurfacesError() async {
        let run = Fixtures.makeRun()
        let harness = Fixtures.makeViewModel(runs: [run])
        await harness.viewModel.load()
        #expect(harness.viewModel.sections.count == 1)

        harness.runRepository.errorToThrow = RunHistoryRepositoryError.underlying("disk full")
        await harness.viewModel.load()

        #expect(harness.viewModel.loadError == .underlying("disk full"))
        #expect(harness.viewModel.sections.count == 1)
    }
}
