import DomainKit
import Foundation
import Observation

/// Screen state and mutations for the run history list: every non-tombstoned
/// `CompletedRun`, sorted newest first and grouped into month sections for
/// section headers.
///
/// Detail loading (splits, heart-rate summary, attribution) is deliberately
/// **not** on this view model — see `RunDetailViewModel`'s doc comment for
/// why the detail screen gets its own, independently-constructible view
/// model rather than a `selectedRun`/`loadDetail(runID:)` extension here.
@MainActor
@Observable
public final class HistoryViewModel {
    /// One row in the history list: a completed run's summary values plus
    /// its attributed workout name, when resolvable.
    public struct Row: Identifiable, Equatable, Sendable {
        /// Identity, matching the source `CompletedRun.id`.
        public var id: UUID
        /// The date the run occurred.
        public var date: Date
        /// Total distance covered, in meters.
        public var distanceMeters: Double
        /// Total duration, in seconds.
        public var durationSeconds: TimeInterval
        /// Average pace, in seconds-per-meter (CLAUDE.md rule 4); `nil` when
        /// the run's distance is zero (matches `CompletedRun.averagePace`).
        public var averagePaceSecondsPerMeter: Double?
        /// The name of the `Workout` this run was attributed to, or `nil`
        /// when unattributed, attribution hasn't run yet, or the attributed
        /// workout no longer exists.
        public var attributedWorkoutName: String?

        /// Creates a row.
        public init(
            id: UUID,
            date: Date,
            distanceMeters: Double,
            durationSeconds: TimeInterval,
            averagePaceSecondsPerMeter: Double?,
            attributedWorkoutName: String?
        ) {
            self.id = id
            self.date = date
            self.distanceMeters = distanceMeters
            self.durationSeconds = durationSeconds
            self.averagePaceSecondsPerMeter = averagePaceSecondsPerMeter
            self.attributedWorkoutName = attributedWorkoutName
        }
    }

    /// One month's worth of rows, for the list's section headers.
    public struct MonthSection: Identifiable, Equatable, Sendable {
        /// The first instant of the month, in `calendar`'s time zone — a
        /// stable, sortable identity; the view formats it into a header
        /// string (CLAUDE.md rule 4 keeps this view model formatting-free).
        public var monthStart: Date
        /// This month's rows, newest first.
        public var rows: [Row]

        public var id: Date { monthStart }

        /// Creates a month section.
        public init(monthStart: Date, rows: [Row]) {
            self.monthStart = monthStart
            self.rows = rows
        }
    }

    /// Every non-tombstoned run, grouped by month, newest month and newest
    /// run within each month first.
    public private(set) var sections: [MonthSection] = []

    /// Whether a `load()` call is in flight.
    public private(set) var isLoading = false

    /// The error from the most recent `load()` attempt, or `nil`.
    public private(set) var loadError: RunHistoryRepositoryError?

    /// Whether there is nothing to show (no non-tombstoned runs), for the
    /// list's empty-state message.
    public var isEmpty: Bool { sections.isEmpty }

    private let runHistoryRepository: RunHistoryRepository
    private let workoutRepository: WorkoutRepository
    private let calendar: Calendar

    /// Creates a history view model.
    /// - Parameters:
    ///   - runHistoryRepository: Loads `CompletedRun` projections.
    ///   - workoutRepository: Resolves an attributed run's `workoutID` to a
    ///     display name.
    ///   - calendar: The calendar used to bucket runs into month sections.
    ///     Injected (rather than hard-coding `Calendar.current`) so tests can
    ///     pin a fixed time zone for deterministic month/year-boundary
    ///     assertions. Grouping is pure date math over each run's stored
    ///     `date` and never consults "now", so no `Clock` is needed here.
    public init(
        runHistoryRepository: RunHistoryRepository,
        workoutRepository: WorkoutRepository,
        calendar: Calendar = .current
    ) {
        self.runHistoryRepository = runHistoryRepository
        self.workoutRepository = workoutRepository
        self.calendar = calendar
    }

    /// Loads every non-tombstoned run, resolves each one's attribution, and
    /// replaces `sections`. On failure, `sections` is left unchanged and
    /// `loadError` is set.
    public func load() async {
        loadError = nil
        isLoading = true
        defer { isLoading = false }

        do {
            let runs = try await runHistoryRepository.fetchAll()
            // Defensive filter regardless of the port's own fetch semantics:
            // `fetchAll()` is documented to return both tombstoned and live
            // runs, so callers filter on `isDeleted`.
            let activeRuns = runs
                .filter { !$0.isDeleted }
                .sorted { $0.date > $1.date }

            var rows: [Row] = []
            rows.reserveCapacity(activeRuns.count)
            for run in activeRuns {
                rows.append(
                    Row(
                        id: run.id,
                        date: run.date,
                        distanceMeters: run.distanceMeters,
                        durationSeconds: run.durationSeconds,
                        averagePaceSecondsPerMeter: run.averagePace,
                        attributedWorkoutName: await resolveWorkoutName(workoutID: run.workoutID)
                    )
                )
            }
            sections = Self.grouped(rows: rows, calendar: calendar)
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

    /// Buckets `rows` (already sorted newest-first) into month sections,
    /// preserving that ordering across both section order and rows within a
    /// section — grouping walks `rows` in order and only appends a new
    /// section the first time each month is encountered, rather than sorting
    /// distinct months afterward, so a year rollover between two adjacent
    /// runs still produces sections in the correct (newest-first) order.
    private static func grouped(rows: [Row], calendar: Calendar) -> [MonthSection] {
        var rowsByMonthStart: [Date: [Row]] = [:]
        var monthOrder: [Date] = []

        for row in rows {
            let components = calendar.dateComponents([.year, .month], from: row.date)
            guard let monthStart = calendar.date(from: components) else { continue }
            if rowsByMonthStart[monthStart] == nil {
                monthOrder.append(monthStart)
            }
            rowsByMonthStart[monthStart, default: []].append(row)
        }

        return monthOrder.map { MonthSection(monthStart: $0, rows: rowsByMonthStart[$0] ?? []) }
    }
}
