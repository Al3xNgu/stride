import DomainKit
import Foundation
import Observation

/// Screen state and mutations for a single completed run's detail screen:
/// its splits table, heart-rate summary, and attribution.
///
/// A separate view model from `HistoryViewModel`, rather than a
/// `selectedRun`/`loadDetail(runID:)` extension on it, because the detail
/// screen is independently navigable — a `runID` is all a push or deep link
/// needs — and its own async lifecycle (`load()`/`isLoading`/`loadError`)
/// would otherwise have to be threaded through the list view model's state
/// alongside, and potentially racing, the list's own `load()`. This reads
/// `docs/ARCHITECTURE.md` §4's "ViewModels (`@Observable`, per-feature)" at
/// screen granularity, matching how `FeatureLibrary`'s `ScheduleSheetView`
/// takes plain values rather than reaching back into `LibraryViewModel` for
/// its own transient state.
@MainActor
@Observable
public final class RunDetailViewModel {
    /// One row in the splits table.
    public struct SplitRow: Identifiable, Equatable, Sendable {
        /// Identity, matching the source `Split.id`.
        public var id: UUID
        /// Zero-based position of this split within the run.
        public var index: Int
        /// Distance covered by this split, in meters.
        public var distanceMeters: Double
        /// Time elapsed for this split, in seconds.
        public var durationSeconds: TimeInterval
        /// Pace for this split, in seconds-per-meter; `nil` when the split's
        /// distance is zero (matches `CompletedRun.averagePace`'s guard).
        public var paceSecondsPerMeter: Double?

        /// Creates a split row.
        public init(
            id: UUID,
            index: Int,
            distanceMeters: Double,
            durationSeconds: TimeInterval,
            paceSecondsPerMeter: Double?
        ) {
            self.id = id
            self.index = index
            self.distanceMeters = distanceMeters
            self.durationSeconds = durationSeconds
            self.paceSecondsPerMeter = paceSecondsPerMeter
        }
    }

    /// The run this detail screen shows, once loaded.
    public private(set) var run: CompletedRun?
    /// The run's splits, ordered by `index` ascending.
    public private(set) var splitRows: [SplitRow] = []
    /// The name of the `Workout` this run was attributed to, or `nil` when
    /// unattributed or the attributed workout no longer exists.
    public private(set) var attributedWorkoutName: String?
    /// Whether a `load()` call is in flight.
    public private(set) var isLoading = false
    /// The error from the most recent `load()` attempt, or `nil`.
    public private(set) var loadError: RunHistoryRepositoryError?

    private let runID: UUID
    private let runHistoryRepository: RunHistoryRepository
    private let workoutRepository: WorkoutRepository

    /// Creates a run detail view model for `runID`.
    public init(runID: UUID, runHistoryRepository: RunHistoryRepository, workoutRepository: WorkoutRepository) {
        self.runID = runID
        self.runHistoryRepository = runHistoryRepository
        self.workoutRepository = workoutRepository
    }

    /// Loads the run, its splits, and its attribution. A missing or tombstoned
    /// run clears the detail state and sets `loadError`; a later repository
    /// failure preserves the last successful detail so the view can show it
    /// alongside the visible error and offer a retry.
    public func load() async {
        loadError = nil
        isLoading = true
        defer { isLoading = false }

        do {
            guard let fetchedRun = try await runHistoryRepository.fetch(id: runID), !fetchedRun.isDeleted else {
                run = nil
                splitRows = []
                attributedWorkoutName = nil
                loadError = .runNotFound(id: runID)
                return
            }

            let splits = try await runHistoryRepository.fetchSplits(runID: runID)
            let workoutName = await resolveWorkoutName(workoutID: fetchedRun.workoutID)

            run = fetchedRun
            splitRows = splits
                .sorted { $0.index < $1.index }
                .map(Self.makeSplitRow)
            attributedWorkoutName = workoutName
        } catch let error as RunHistoryRepositoryError {
            loadError = error
        } catch {
            loadError = .underlying(String(describing: error))
        }
    }

    /// Resolves `workoutID` to its `Workout.name`, tolerating a `nil` id, a
    /// missing workout, or a repository failure — attribution is
    /// best-effort display, not load-blocking (`docs/ARCHITECTURE.md` §3.4).
    private func resolveWorkoutName(workoutID: UUID?) async -> String? {
        guard let workoutID else { return nil }
        let workout = try? await workoutRepository.fetch(id: workoutID)
        return workout?.name
    }

    private static func makeSplitRow(_ split: Split) -> SplitRow {
        SplitRow(
            id: split.id,
            index: split.index,
            distanceMeters: split.distanceMeters,
            durationSeconds: split.durationSeconds,
            paceSecondsPerMeter: split.distanceMeters > 0 ? split.durationSeconds / split.distanceMeters : nil
        )
    }
}
