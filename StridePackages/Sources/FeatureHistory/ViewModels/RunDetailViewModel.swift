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

    /// Loads the run, then its splits and attribution. Once the run itself is
    /// available, it is published immediately so the detail header can render
    /// while the independent, secondary reads continue. A missing or
    /// tombstoned run clears the detail state and sets `loadError`; a later
    /// repository failure preserves the available detail alongside the visible
    /// error and retry action.
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

            run = fetchedRun
            async let fetchedSplits = runHistoryRepository.fetchSplits(runID: runID)
            async let fetchedWorkoutName = Self.resolveWorkoutName(
                workoutID: fetchedRun.workoutID,
                workoutRepository: workoutRepository
            )
            let (splits, workoutName) = try await (fetchedSplits, fetchedWorkoutName)
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

    /// Returns the loaded, kilometre-granular storage rows grouped into full
    /// runner-facing units. Durations are apportioned linearly inside each
    /// stored segment, matching the interpolation assumption used when the
    /// HealthKit adapter derived the stored splits.
    ///
    /// Invalid boundaries and malformed stored rows deliberately fall back to
    /// the original rows. A presentation preference must never hide history.
    public func displayRows(forSplitDistanceMeters splitDistanceMeters: Double) -> [SplitRow] {
        SplitRowRebinner.rebin(splitRows, to: splitDistanceMeters)
    }

    /// Resolves `workoutID` to its `Workout.name`, tolerating a `nil` id, a
    /// missing workout, or a repository failure — attribution is
    /// best-effort display, not load-blocking (`docs/ARCHITECTURE.md` §3.4).
    private static func resolveWorkoutName(
        workoutID: UUID?,
        workoutRepository: WorkoutRepository
    ) async -> String? {
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

/// Re-groups persisted split segments without altering SwiftData storage.
///
/// Health ingestion persists kilometre segments as its canonical, durable
/// representation. This keeps existing records stable while allowing the
/// detail screen to show whole-mile laps for runners using imperial units.
enum SplitRowRebinner {
    private static let epsilon = 0.000_001

    static func rebin(
        _ rows: [RunDetailViewModel.SplitRow],
        to splitDistanceMeters: Double
    ) -> [RunDetailViewModel.SplitRow] {
        guard splitDistanceMeters.isFinite, splitDistanceMeters > epsilon,
              rows.allSatisfy(isValid)
        else {
            return rows
        }

        let orderedRows = rows.sorted { $0.index < $1.index }
        guard !orderedRows.isEmpty else { return [] }

        var accumulator = Accumulator()
        for row in orderedRows {
            accumulator.consume(row, splitDistanceMeters: splitDistanceMeters)
        }
        accumulator.appendActiveRow(isComplete: false, splitDistanceMeters: splitDistanceMeters)
        return accumulator.rows
    }

    private static func isValid(_ row: RunDetailViewModel.SplitRow) -> Bool {
        row.distanceMeters.isFinite && row.distanceMeters > 0
            && row.durationSeconds.isFinite && row.durationSeconds >= 0
    }

    private struct Accumulator {
        var rows: [RunDetailViewModel.SplitRow] = []
        private var activeDistance = 0.0
        private var activeDuration = 0.0
        private var activeSourceID: UUID?
        private var usedIDs = Set<UUID>()

        mutating func consume(
            _ row: RunDetailViewModel.SplitRow,
            splitDistanceMeters: Double
        ) {
            var remainingDistance = row.distanceMeters
            var remainingDuration = row.durationSeconds

            while remainingDistance > epsilon {
                activeSourceID = activeSourceID ?? row.id
                let distanceToBoundary = splitDistanceMeters - activeDistance
                if distanceToBoundary <= epsilon {
                    appendActiveRow(isComplete: true, splitDistanceMeters: splitDistanceMeters)
                    resetActiveRow()
                    continue
                }

                let consumedDistance = min(remainingDistance, distanceToBoundary)
                let consumedDuration = remainingDuration * consumedDistance / remainingDistance
                activeDistance += consumedDistance
                activeDuration += consumedDuration
                remainingDistance -= consumedDistance
                remainingDuration -= consumedDuration

                if activeDistance + epsilon >= splitDistanceMeters {
                    appendActiveRow(isComplete: true, splitDistanceMeters: splitDistanceMeters)
                    resetActiveRow()
                }
            }
        }

        mutating func appendActiveRow(isComplete: Bool, splitDistanceMeters: Double) {
            guard let activeSourceID, activeDistance > epsilon else { return }
            let distance = isComplete ? splitDistanceMeters : activeDistance
            rows.append(
                RunDetailViewModel.SplitRow(
                    id: uniqueID(for: activeSourceID),
                    index: rows.count,
                    distanceMeters: distance,
                    durationSeconds: activeDuration,
                    paceSecondsPerMeter: activeDuration / distance
                )
            )
        }

        private mutating func resetActiveRow() {
            activeDistance = 0
            activeDuration = 0
            activeSourceID = nil
        }

        private mutating func uniqueID(for sourceID: UUID) -> UUID {
            guard !usedIDs.contains(sourceID) else {
                var salt = rows.count + 1
                var candidate = SplitRowRebinner.derivedID(from: sourceID, salt: salt)
                while usedIDs.contains(candidate) {
                    salt += 1
                    candidate = SplitRowRebinner.derivedID(from: sourceID, salt: salt)
                }
                usedIDs.insert(candidate)
                return candidate
            }
            usedIDs.insert(sourceID)
            return sourceID
        }
    }

    private static func derivedID(from sourceID: UUID, salt: Int) -> UUID {
        var bytes = sourceID.uuid
        var encodedSalt = UInt64(salt).bigEndian
        withUnsafeMutableBytes(of: &bytes) { destination in
            withUnsafeBytes(of: &encodedSalt) { source in
                for index in source.indices {
                    destination[8 + index] ^= source[index]
                }
            }
        }
        return UUID(uuid: bytes)
    }
}
