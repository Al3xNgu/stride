import DomainKit
import Foundation
import Observation

/// Screen state and mutations for the personal-records board: each MVP
/// `Milestone`'s current best (or empty slot) plus per-milestone PR history.
///
/// PR history is in scope here — not just the current-record board — because
/// `RunHistoryRepository.fetchPersonalBests()` is documented to return
/// *every* stored `PersonalBest` (current and superseded records alike), not
/// only the current one. History is therefore derived client-side by
/// grouping and ordering that single fetch, rather than requiring new port
/// surface (per the task's own guidance: only add a board if the port
/// genuinely only exposed the current record — it exposes both).
@MainActor
@Observable
public final class RecordsViewModel {
    /// One entry on the PR board: a milestone plus its current record (if
    /// any) and that record's source run (best-effort; `nil` if the run was
    /// tombstoned/deleted or otherwise unresolvable).
    public struct BoardEntry: Identifiable, Equatable, Sendable {
        /// The milestone this entry represents.
        public var milestone: Milestone
        /// The current personal best for `milestone`, or `nil` for an empty
        /// slot (no record set yet).
        public var personalBest: PersonalBest?
        /// The `CompletedRun` that achieved `personalBest`, resolved
        /// best-effort; `nil` when there is no record, or the source run is
        /// missing/tombstoned.
        public var sourceRun: CompletedRun?
        /// The name of the `Workout` `sourceRun` was attributed to, or
        /// `nil` when unattributed, unresolvable, or no `workoutRepository`
        /// was injected.
        public var sourceWorkoutName: String?

        public var id: UUID { milestone.id }

        /// Creates a board entry.
        public init(
            milestone: Milestone,
            personalBest: PersonalBest? = nil,
            sourceRun: CompletedRun? = nil,
            sourceWorkoutName: String? = nil
        ) {
            self.milestone = milestone
            self.personalBest = personalBest
            self.sourceRun = sourceRun
            self.sourceWorkoutName = sourceWorkoutName
        }
    }

    /// One entry per `milestones`, in that order (`Milestone.mvpPresets`'
    /// ascending-distance order by default) — an entry with a `nil`
    /// `personalBest` is an empty slot.
    public private(set) var board: [BoardEntry] = []

    /// Whether a `load()` call is in flight.
    public private(set) var isLoading = false

    /// The error from the most recent `load()` attempt, or `nil`.
    public private(set) var loadError: RunHistoryRepositoryError?

    private let runHistoryRepository: RunHistoryRepository
    private let workoutRepository: WorkoutRepository?
    private let milestones: [Milestone]
    private var historyByMilestoneID: [UUID: [PersonalBest]] = [:]

    /// Creates a records view model.
    /// - Parameters:
    ///   - runHistoryRepository: Loads `PersonalBest` records and their
    ///     source `CompletedRun`s.
    ///   - workoutRepository: Optionally resolves a source run's attributed
    ///     workout name; `nil` skips that resolution (`sourceWorkoutName`
    ///     stays `nil` on every entry).
    ///   - milestones: The milestones shown on the board, in order. Defaults
    ///     to `Milestone.mvpPresets`.
    public init(
        runHistoryRepository: RunHistoryRepository,
        workoutRepository: WorkoutRepository? = nil,
        milestones: [Milestone] = Milestone.mvpPresets
    ) {
        self.runHistoryRepository = runHistoryRepository
        self.workoutRepository = workoutRepository
        self.milestones = milestones
    }

    /// Loads every stored personal best, derives the current record and full
    /// history per milestone, resolves each current record's source run
    /// (and, if a `workoutRepository` was injected, its attributed workout
    /// name), and replaces `board`. On failure, `board` is left unchanged
    /// and `loadError` is set.
    public func load() async {
        loadError = nil
        isLoading = true
        defer { isLoading = false }

        do {
            let personalBests = try await runHistoryRepository.fetchPersonalBests()
            historyByMilestoneID = Self.grouped(personalBests: personalBests)

            var entries: [BoardEntry] = []
            entries.reserveCapacity(milestones.count)
            for milestone in milestones {
                entries.append(await makeBoardEntry(for: milestone))
            }
            board = entries
        } catch let error as RunHistoryRepositoryError {
            loadError = error
        } catch {
            loadError = .underlying(String(describing: error))
        }
    }

    /// Every stored record for `milestoneID`, current record first — per
    /// `RunHistoryRepository.fetchPersonalBest(milestoneID:)`'s documented
    /// "current" ordering — then remaining superseded records in that same
    /// total order. Empty if `load()` hasn't run yet or no record exists.
    public func history(for milestoneID: UUID) -> [PersonalBest] {
        historyByMilestoneID[milestoneID] ?? []
    }

    private func makeBoardEntry(for milestone: Milestone) async -> BoardEntry {
        guard let current = historyByMilestoneID[milestone.id]?.first else {
            return BoardEntry(milestone: milestone)
        }

        let sourceRun = try? await runHistoryRepository.fetch(id: current.completedRunID)
        let activeSourceRun = sourceRun?.isDeleted == true ? nil : sourceRun
        var sourceWorkoutName: String?
        if let workoutID = activeSourceRun?.workoutID, let workoutRepository {
            let workout = try? await workoutRepository.fetch(id: workoutID)
            sourceWorkoutName = workout?.name
        }

        return BoardEntry(
            milestone: milestone,
            personalBest: current,
            sourceRun: activeSourceRun,
            sourceWorkoutName: sourceWorkoutName
        )
    }

    /// Groups `personalBests` by `milestoneID`, each group ordered by the
    /// exact contract `RunHistoryRepository.fetchPersonalBest(milestoneID:)`
    /// documents as "current": lowest `elapsedSeconds`, ties broken by
    /// latest `achievedAt`, remaining ties by `id.uuidString` ascending.
    private static func grouped(personalBests: [PersonalBest]) -> [UUID: [PersonalBest]] {
        var grouped: [UUID: [PersonalBest]] = [:]
        for personalBest in personalBests {
            grouped[personalBest.milestoneID, default: []].append(personalBest)
        }
        for key in grouped.keys {
            grouped[key]?.sort(by: isOrderedAsCurrentFirst)
        }
        return grouped
    }

    private static func isOrderedAsCurrentFirst(_ lhs: PersonalBest, _ rhs: PersonalBest) -> Bool {
        if lhs.elapsedSeconds != rhs.elapsedSeconds {
            return lhs.elapsedSeconds < rhs.elapsedSeconds
        }
        if lhs.achievedAt != rhs.achievedAt {
            return lhs.achievedAt > rhs.achievedAt
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
