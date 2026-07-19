import DomainKit
import Foundation
import Observation

/// Screen state and mutations for the workout library: every saved
/// `Workout` paired with its latest `SyncJob` (for the sync badge), the
/// send-to-watch / schedule-by-date / retry flows, and delete.
///
/// This view model is a thin `SyncCoordinator` client, never a re-
/// implementation of it: every state transition of a `SyncJob` (pending ->
/// syncing -> synced/failed, retry-with-backoff, stale-on-edit, foreground
/// reconciliation) is driven exclusively by `SyncCoordinator`
/// (`docs/ARCHITECTURE.md` §6 component table: "`SyncCoordinator` | Domain |
/// Owns the SyncJob state machine... | UI" — the UI is a *consumer* of the
/// coordinator, not a second driver of the same state). `SyncCoordinator` is
/// a concrete `actor` over `DomainKit` ports (not a protocol itself), so it
/// is injected directly here with no additional protocol seam: calling an
/// actor's `public` methods from a `@MainActor` view model is already a
/// clean, directly-testable async boundary (see `SyncCoordinatorTests`,
/// which constructs a real coordinator over `TestSupport` fakes the same
/// way this view model's tests do).
@MainActor
@Observable
public final class LibraryViewModel {
    /// One row in the library list: a workout plus its latest sync job (if
    /// any), from which `badgeState` is derived.
    public struct Row: Identifiable, Equatable, Sendable {
        public var workout: Workout
        public var latestSyncJob: SyncJob?

        public var id: UUID { workout.id }

        /// The badge state to render for this row.
        public var badgeState: BadgeState { BadgeState.from(latestSyncJob) }

        /// Creates a row.
        public init(workout: Workout, latestSyncJob: SyncJob?) {
            self.workout = workout
            self.latestSyncJob = latestSyncJob
        }
    }

    /// Every saved workout paired with its latest sync job, sorted by most
    /// recently updated first (a freshly authored or edited workout is the
    /// one a user is most likely looking for next).
    public private(set) var rows: [Row] = []

    /// Whether a `load()`/`reconcileOnForeground()` call is in flight.
    public private(set) var isLoading = false

    /// The error from the most recent `load()` attempt, or `nil`.
    public private(set) var loadError: WorkoutRepositoryError?

    /// The workout ids currently mid-send/schedule/retry. A set, not a
    /// scalar: two quick sends of different workouts overlap, and each row's
    /// spinner/disable state must key on its own membership so the first
    /// send's completion can't clear the second row's spinner early.
    public private(set) var sendingWorkoutIDs: Set<UUID> = []

    /// Whether `workoutID` is currently mid-send/schedule/retry.
    public func isSending(workoutID: UUID) -> Bool {
        sendingWorkoutIDs.contains(workoutID)
    }

    /// The error from the most recent send/schedule/retry attempt, or `nil`
    /// if the last attempt (if any) didn't hit this pre-job-creation failure
    /// class (see `LibrarySendError`'s doc comment — a `WatchSyncService`
    /// failure is *not* surfaced here; it is visible via the row's
    /// `badgeState` instead).
    public private(set) var sendError: LibrarySendError?

    /// The error from the most recent `delete(workoutID:)` attempt, or `nil`.
    public private(set) var deleteError: WorkoutRepositoryError?

    /// A human-readable description of the most recent `reconcileOnForeground()`
    /// failure, or `nil`. `SyncCoordinator.reconcile()`'s own per-job outcomes
    /// are not errors (they are the `ReconciliationReport` it returns and are
    /// reflected into `rows` via the following `load()`); this only captures
    /// a hard failure of the reconciliation pass itself (e.g. the watch sync
    /// service's `fetchScheduledWorkouts()` throwing).
    public private(set) var reconcileError: String?

    private let workoutRepository: WorkoutRepository
    private let syncCoordinator: SyncCoordinator
    private let clock: Clock

    /// Creates a library view model.
    /// - Parameters:
    ///   - workoutRepository: Loads workouts and their sync-job history.
    ///   - syncCoordinator: Drives every `SyncJob` state transition (send,
    ///     retry, reconcile) — see the type's doc comment.
    ///   - clock: Supplies "now" for the schedule-by-date sheet's minimum
    ///     selectable date; never `Date()` directly (CLAUDE.md rule 5).
    public init(workoutRepository: WorkoutRepository, syncCoordinator: SyncCoordinator, clock: Clock) {
        self.workoutRepository = workoutRepository
        self.syncCoordinator = syncCoordinator
        self.clock = clock
    }

    /// The current time, per the injected `Clock` — for seeding/bounding the
    /// schedule-by-date sheet's `DatePicker`.
    public var now: Date { clock.now() }

    // MARK: - Loading

    /// Loads every saved workout and each one's latest sync job, replacing
    /// `rows`. On failure, `rows` is left unchanged and `loadError` is set.
    public func load() async {
        loadError = nil
        isLoading = true
        defer { isLoading = false }

        do {
            let workouts = try await workoutRepository.fetchAll()
            var loadedRows: [Row] = []
            loadedRows.reserveCapacity(workouts.count)
            for workout in workouts {
                let latestJob = try await workoutRepository.fetchLatestSyncJob(workoutID: workout.id)
                loadedRows.append(Row(workout: workout, latestSyncJob: latestJob))
            }
            rows = loadedRows.sorted { $0.workout.updatedAt > $1.workout.updatedAt }
        } catch let error as WorkoutRepositoryError {
            loadError = error
        } catch {
            loadError = .underlying(String(describing: error))
        }
    }

    /// Runs `SyncCoordinator.reconcile()` (the §7 foreground-reconciliation
    /// pass) and then reloads `rows` so any job it repaired is reflected in
    /// the badges. Intended for the view's `.task`/`.onChange(of: scenePhase)`
    /// hook on every foreground.
    public func reconcileOnForeground() async {
        reconcileError = nil
        do {
            _ = try await syncCoordinator.reconcile()
        } catch {
            reconcileError = String(describing: error)
        }
        await load()
    }

    // MARK: - Send / schedule / retry

    /// Sends `workoutID` to the Watch for the next available slot ("Send to
    /// Watch" — a `nil` date).
    public func sendToWatch(workoutID: UUID) async {
        await send(workoutID: workoutID, scheduledDate: nil)
    }

    /// Schedules `workoutID` to the Watch for a specific `date`
    /// ("schedule by date").
    public func scheduleForDate(workoutID: UUID, date: Date) async {
        await send(workoutID: workoutID, scheduledDate: date)
    }

    /// Re-attempts a failed/abandoned send for `workoutID`, reusing the date
    /// (if any) the user originally chose, from its latest sync job.
    ///
    /// `SyncCoordinator` exposes no separate per-workout "retry" entry point
    /// of its own (only `retryDueJobs()`, which retries every job whose
    /// in-memory backoff timer has *already* elapsed, and is meant to be
    /// polled/driven by the composition root, not a single row's tap) — a
    /// manual user-initiated retry is, per `ScheduleWorkoutUseCase`'s own doc
    /// comment, indistinguishable from any other re-send: it "reuses the
    /// latest `SyncJob` (any state, including `.abandoned`/.stale — a manual
    /// re-send legitimately resurrects it)". So this simply calls
    /// `scheduleWorkout` again rather than reaching for a nonexistent
    /// coordinator API.
    public func retryFailed(workoutID: UUID) async {
        let existingDate = rows.first { $0.workout.id == workoutID }?.latestSyncJob?.scheduledDate
        await send(workoutID: workoutID, scheduledDate: existingDate)
    }

    /// Clears the most recent `sendError`, e.g. once its alert has been
    /// dismissed.
    public func clearSendError() {
        sendError = nil
    }

    private func send(workoutID: UUID, scheduledDate: Date?) async {
        sendError = nil
        sendingWorkoutIDs.insert(workoutID)
        defer { sendingWorkoutIDs.remove(workoutID) }

        do {
            try await syncCoordinator.scheduleWorkout(workoutID: workoutID, scheduledDate: scheduledDate)
        } catch {
            sendError = LibrarySendError.map(error)
        }
        await refreshRow(workoutID: workoutID)
    }

    // MARK: - Delete

    /// Deletes the workout with `workoutID` from the library.
    ///
    /// `WorkoutRepository.delete(id:)` cascade-deletes every local
    /// `SyncJob` recorded for the workout (its own documented contract), so
    /// no separate local cleanup is needed here. This deliberately does
    /// **not** also call `WatchSyncService.remove(planID:)` to unschedule a
    /// still-`.synced` plan from the Watch itself: `SyncCoordinator` (the
    /// sole driver of sync effects — see this type's doc comment) exposes no
    /// "cancel"/"unschedule" operation, and reaching around it to call
    /// `WatchSyncService` directly from this view model would race its
    /// documented per-workout lock (a concurrent retry/reconcile pass could
    /// re-schedule the very plan this call just removed). Per §7, "local
    /// store is authoritative for intent; WorkoutKit is authoritative for
    /// what's actually scheduled" — deleting the local workout deletes its
    /// authored intent; the stale Watch-side entry (if any) is self-healing:
    /// the next `reconcile()` pass will find it has no matching local job and
    /// flag it as `ReconciliationReport.orphanedPlanIDs` (currently
    /// visibility-only, per that type's doc comment). Actively removing it
    /// from the Watch is a real product gap worth closing with a proper
    /// `SyncCoordinator.cancel(workoutID:)` API — noted for a follow-up task
    /// rather than guessed at here.
    public func delete(workoutID: UUID) async {
        deleteError = nil
        do {
            try await workoutRepository.delete(id: workoutID)
            rows.removeAll { $0.workout.id == workoutID }
        } catch let error as WorkoutRepositoryError {
            deleteError = error
        } catch {
            deleteError = .underlying(String(describing: error))
        }
    }

    // MARK: - Private

    /// Re-fetches `workoutID`'s workout and latest sync job and updates (or
    /// removes, or inserts) its row, without reloading the entire list.
    ///
    /// A `nil` fetch result (the workout is genuinely gone) removes the row;
    /// a *thrown* read error leaves the existing row untouched — deleting or
    /// blanking a row over a transient repository error would render the
    /// error as misleading UX. The stale row self-heals on the next
    /// `load()`/reconcile pass.
    private func refreshRow(workoutID: UUID) async {
        let workout: Workout?
        let latestJob: SyncJob?
        do {
            workout = try await workoutRepository.fetch(id: workoutID)
            latestJob = workout == nil
                ? nil
                : try await workoutRepository.fetchLatestSyncJob(workoutID: workoutID)
        } catch {
            return
        }

        guard let workout else {
            rows.removeAll { $0.workout.id == workoutID }
            return
        }
        let refreshedRow = Row(workout: workout, latestSyncJob: latestJob)

        if let index = rows.firstIndex(where: { $0.workout.id == workoutID }) {
            rows[index] = refreshedRow
        } else {
            rows.append(refreshedRow)
            rows.sort { $0.workout.updatedAt > $1.workout.updatedAt }
        }
    }
}
