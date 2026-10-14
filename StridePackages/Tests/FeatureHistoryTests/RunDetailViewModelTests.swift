import Testing
import Foundation
@testable import FeatureHistory
import DomainKit
import TestSupport

/// Coverage of `RunDetailViewModel`'s splits/HR/attribution loading against
/// `TestSupport` fakes.
@MainActor
@Suite("RunDetailViewModel")
struct RunDetailViewModelTests {
    private typealias Fixtures = HistoryViewModelFixtures

    private struct Harness {
        let viewModel: RunDetailViewModel
        let runRepository: FakeRunHistoryRepository
        let workoutRepository: FakeWorkoutRepository
    }

    private func makeViewModel(
        runID: UUID,
        runs: [CompletedRun] = [],
        workouts: [Workout] = []
    ) -> Harness {
        let runRepository = FakeRunHistoryRepository(runs: runs)
        let workoutRepository = FakeWorkoutRepository(workouts: workouts)
        let viewModel = RunDetailViewModel(
            runID: runID,
            runHistoryRepository: runRepository,
            workoutRepository: workoutRepository
        )
        return Harness(
            viewModel: viewModel,
            runRepository: runRepository,
            workoutRepository: workoutRepository
        )
    }

    @Test("load() populates the run, ordered splits with derived pace, and HR summary")
    func loadPopulatesRunSplitsAndHR() async throws {
        let run = Fixtures.makeRun(
            distanceMeters: 3_000,
            durationSeconds: 900
        )
        let harness = makeViewModel(runID: run.id, runs: [run])
        let splitTwo = Split(runID: run.id, index: 1, distanceMeters: 1_000, durationSeconds: 300)
        let splitOne = Split(runID: run.id, index: 0, distanceMeters: 1_000, durationSeconds: 290)
        try await harness.runRepository.saveSplits([splitTwo, splitOne], for: run.id)

        await harness.viewModel.load()

        #expect(harness.viewModel.loadError == nil)
        #expect(harness.viewModel.run?.id == run.id)
        #expect(harness.viewModel.splitRows.map(\.index) == [0, 1])
        #expect(harness.viewModel.splitRows.first?.paceSecondsPerMeter == 290.0 / 1_000)
    }

    @Test("load() derives a nil pace for a zero-distance split rather than dividing by zero")
    func loadHandlesZeroDistanceSplit() async throws {
        let run = Fixtures.makeRun()
        let harness = makeViewModel(runID: run.id, runs: [run])
        let zeroSplit = Split(runID: run.id, index: 0, distanceMeters: 0, durationSeconds: 10)
        try await harness.runRepository.saveSplits([zeroSplit], for: run.id)

        await harness.viewModel.load()

        #expect(harness.viewModel.splitRows.first?.paceSecondsPerMeter == nil)
    }

    @Test("load() resolves attribution on a hit")
    func loadResolvesAttributionOnHit() async {
        let workout = Fixtures.makeWorkout(name: "Long Run")
        let run = Fixtures.makeRun(workoutID: workout.id)
        let harness = makeViewModel(runID: run.id, runs: [run], workouts: [workout])

        await harness.viewModel.load()

        #expect(harness.viewModel.attributedWorkoutName == "Long Run")
    }

    @Test("load() tolerates a missing attributed workout (miss) without failing the load")
    func loadTreatsMissingWorkoutAsNilAttribution() async {
        let run = Fixtures.makeRun(workoutID: UUID())
        let harness = makeViewModel(runID: run.id, runs: [run])

        await harness.viewModel.load()

        #expect(harness.viewModel.loadError == nil)
        #expect(harness.viewModel.run != nil)
        #expect(harness.viewModel.attributedWorkoutName == nil)
    }

    @Test("load() with an unknown run id surfaces RunHistoryRepositoryError.runNotFound and clears state")
    func loadUnknownRunSurfacesRunNotFound() async {
        let unknownID = UUID()
        let harness = makeViewModel(runID: unknownID)

        await harness.viewModel.load()

        #expect(harness.viewModel.loadError == .runNotFound(id: unknownID))
        #expect(harness.viewModel.run == nil)
        #expect(harness.viewModel.splitRows.isEmpty)
        #expect(harness.viewModel.attributedWorkoutName == nil)
    }

    @Test("load() treats a tombstoned run as unavailable and clears detail state")
    func loadTombstonedRunSurfacesRunNotFound() async {
        let run = Fixtures.makeRun(isDeleted: true)
        let harness = makeViewModel(runID: run.id, runs: [run])

        await harness.viewModel.load()

        #expect(harness.viewModel.loadError == .runNotFound(id: run.id))
        #expect(harness.viewModel.run == nil)
        #expect(harness.viewModel.splitRows.isEmpty)
    }

    @Test("a later load failure preserves the last successful detail and surfaces the error")
    func subsequentLoadFailurePreservesStaleDetail() async {
        let run = Fixtures.makeRun()
        let harness = makeViewModel(runID: run.id, runs: [run])

        await harness.viewModel.load()
        #expect(harness.viewModel.run?.id == run.id)

        harness.runRepository.errorToThrow = RunHistoryRepositoryError.underlying("Health data unavailable")
        await harness.viewModel.load()

        #expect(harness.viewModel.loadError == .underlying("Health data unavailable"))
        #expect(harness.viewModel.run?.id == run.id)
    }

    @Test("load() with no splits produces an empty splits table")
    func loadWithNoSplitsIsEmpty() async {
        let run = Fixtures.makeRun()
        let harness = makeViewModel(runID: run.id, runs: [run])

        await harness.viewModel.load()

        #expect(harness.viewModel.loadError == nil)
        #expect(harness.viewModel.splitRows.isEmpty)
    }

    @Test("displayRows groups kilometre storage into a complete mile")
    func displayRowsRebinsKilometersToMiles() async throws {
        let run = Fixtures.makeRun(distanceMeters: 1_609.344, durationSeconds: 420)
        let harness = makeViewModel(runID: run.id, runs: [run])
        let firstKilometer = Split(runID: run.id, index: 0, distanceMeters: 1_000, durationSeconds: 260)
        let remainingDistance = 609.344
        let finalPartial = Split(runID: run.id, index: 1, distanceMeters: remainingDistance, durationSeconds: 160)
        try await harness.runRepository.saveSplits([firstKilometer, finalPartial], for: run.id)

        await harness.viewModel.load()
        let rows = harness.viewModel.displayRows(forSplitDistanceMeters: 1_609.344)
        let kilometerRows = harness.viewModel.displayRows(forSplitDistanceMeters: 1_000)

        #expect(rows.count == 1)
        #expect(rows[0].index == 0)
        #expect(abs(rows[0].distanceMeters - 1_609.344) < 0.000_001)
        #expect(abs(rows[0].durationSeconds - 420) < 0.000_001)
        #expect(abs((rows[0].paceSecondsPerMeter ?? 0) - (420 / 1_609.344)) < 0.000_001)
        #expect(kilometerRows == harness.viewModel.splitRows)
    }

    @Test("displayRows preserves a partial final mile and valid stored rows on invalid input")
    func displayRowsPreservesPartialAndInvalidBoundaryFallback() async throws {
        let run = Fixtures.makeRun(distanceMeters: 2_000, durationSeconds: 600)
        let harness = makeViewModel(runID: run.id, runs: [run])
        let firstKilometer = Split(runID: run.id, index: 0, distanceMeters: 1_000, durationSeconds: 300)
        let secondKilometer = Split(runID: run.id, index: 1, distanceMeters: 1_000, durationSeconds: 300)
        try await harness.runRepository.saveSplits([firstKilometer, secondKilometer], for: run.id)

        await harness.viewModel.load()
        let mileRows = harness.viewModel.displayRows(forSplitDistanceMeters: 1_609.344)
        let fallbackRows = harness.viewModel.displayRows(forSplitDistanceMeters: 0)

        #expect(mileRows.count == 2)
        #expect(abs(mileRows[0].distanceMeters - 1_609.344) < 0.000_001)
        #expect(abs(mileRows[0].durationSeconds - 482.8032) < 0.000_001)
        #expect(abs(mileRows[1].distanceMeters - 390.656) < 0.000_001)
        #expect(abs(mileRows[1].durationSeconds - 117.1968) < 0.000_001)
        #expect(fallbackRows == harness.viewModel.splitRows)
    }

    @Test("displayRows gives every re-binned portion a stable unique identity")
    func displayRowsMakesRebinnedRowIDsUniqueAndStable() async throws {
        let run = Fixtures.makeRun(distanceMeters: 4_000, durationSeconds: 1_000)
        let harness = makeViewModel(runID: run.id, runs: [run])
        let oversizedSplit = Split(runID: run.id, index: 0, distanceMeters: 4_000, durationSeconds: 1_000)
        try await harness.runRepository.saveSplits([oversizedSplit], for: run.id)

        await harness.viewModel.load()
        let firstProjection = harness.viewModel.displayRows(forSplitDistanceMeters: 1_000)
        let secondProjection = harness.viewModel.displayRows(forSplitDistanceMeters: 1_000)

        #expect(firstProjection.count == 4)
        #expect(Set(firstProjection.map(\.id)).count == 4)
        #expect(firstProjection.map(\.id) == secondProjection.map(\.id))
    }
}
