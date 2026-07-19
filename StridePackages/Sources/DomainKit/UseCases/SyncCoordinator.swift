import Foundation

/// The outcome of one `SyncCoordinator.reconcile()` pass.
public struct ReconciliationReport: Equatable, Hashable, Sendable {
    /// `SyncJob.id`s transitioned `.synced` -> `.stale` because their
    /// workout was edited after the job was last synced (§7 "edit-after-
    /// sync" flow).
    public var markedStale: [UUID]
    /// `SyncJob.id`s transitioned `.synced` -> `.failed(.transient)`
    /// because the Watch no longer reports them as scheduled (removed by
    /// the user, or expired).
    public var markedFailed: [UUID]
    /// Plan identifiers found scheduled on the Watch with no corresponding
    /// local `SyncJob`. Per §7, "local store is authoritative for intent;
    /// WorkoutKit is authoritative for what's actually scheduled" — there is
    /// no local `Workout` to attach these to and no documented action to
    /// take, so they are only flagged for visibility (e.g. future debug/
    /// support tooling), never mutated or removed from the Watch.
    public var orphanedPlanIDs: [UUID]

    /// Creates a reconciliation report.
    public init(markedStale: [UUID] = [], markedFailed: [UUID] = [], orphanedPlanIDs: [UUID] = []) {
        self.markedStale = markedStale
        self.markedFailed = markedFailed
        self.orphanedPlanIDs = orphanedPlanIDs
    }
}

/// The long-lived owner of the `SyncJob` state machine
/// (`docs/ARCHITECTURE.md` §6/§7): retry with backoff for transient
/// failures, marking jobs `.stale` when their workout is edited after sync,
/// and foreground reconciliation against what WorkoutKit actually has
/// scheduled. The composition root owns exactly one instance.
///
/// **Retry/backoff policy** (§7 says only "backoff for transient; surface
/// actionable message for permanent" — the schedule/cap below are this
/// implementation's documented choice, not an §7-specified number):
/// exponential backoff (`backoffBaseSeconds * 2^(attemptCount - 1)`),
/// capped at `maxAttempts` total attempts (default 3) before a still-
/// transiently-failing job is moved to `.abandoned` (an explicit "will not
/// be retried automatically" state already in the `SyncJobState` vocabulary
/// — no new case introduced). §7 explicitly names `.notAuthorized`,
/// `.invalidComposition`, and `.noPairedWatch` as *permanent* — those are
/// left in `.failed(reason)` for the UI to surface an actionable message and
/// are never auto-retried or auto-abandoned; only `.transient` is retried.
///
/// **Timing** is entirely `Clock`-driven, never `Date()`: each retryable
/// failure records a due `Date` (`clock.now() + backoff`) in memory, and
/// `retryDueJobs()` only retries jobs whose due date has passed. This is
/// intentionally *not* persisted onto `SyncJob` (the entity has no
/// "next attempt at" field, and adding one is out of this task's scope per
/// CLAUDE.md rule 8 / the task's "do not invent" instruction) — so a
/// still-pending in-memory retry timer does not survive an app relaunch.
/// The composition root should call `reconcile()` on every foreground/
/// launch to independently re-discover jobs that need attention instead of
/// depending on the timer surviving.
///
/// **Serialization guarantee:** actor isolation alone does *not* prevent
/// two concurrent calls for the *same* workout from interleaving into an
/// invalid state, because `await`s inside an actor method are reentrancy
/// points. `SyncCoordinator` therefore holds an explicit per-`workoutID`
/// lock (`acquireLock`/`releaseLock`, a `CheckedContinuation`-based queue)
/// around every read-modify-write of a workout's `SyncJob`, so a second
/// `scheduleWorkout`/reconciliation touching the same workout always waits
/// for the first to fully finish before it starts. Different workouts
/// proceed fully concurrently.
public actor SyncCoordinator {
    private let repository: WorkoutRepository
    private let watchSyncService: WatchSyncService
    private let clock: Clock
    private let scheduleWorkoutUseCase: ScheduleWorkoutUseCase
    private let maxAttempts: Int
    private let backoffBaseSeconds: TimeInterval

    /// Due dates for pending retries, keyed by `SyncJob.id`. In-memory only
    /// (see the type's doc comment).
    private var retrySchedule: [UUID: Date] = [:]

    /// Workout ids currently "locked" by an in-progress operation.
    private var busyWorkoutIDs: Set<UUID> = []
    /// Continuations waiting for a workout's lock, in FIFO order.
    private var waiters: [UUID: [CheckedContinuation<Void, Never>]] = [:]

    /// Creates the coordinator.
    /// - Parameters:
    ///   - maxAttempts: total attempts allowed before a persistently
    ///     `.transient`-failing job is moved to `.abandoned`. Defaults to 3.
    ///   - backoffBaseSeconds: the base of the exponential backoff schedule.
    ///     Defaults to 30 seconds.
    public init(
        repository: WorkoutRepository,
        watchSyncService: WatchSyncService,
        clock: Clock,
        maxAttempts: Int = 3,
        backoffBaseSeconds: TimeInterval = 30
    ) {
        self.repository = repository
        self.watchSyncService = watchSyncService
        self.clock = clock
        self.maxAttempts = maxAttempts
        self.backoffBaseSeconds = backoffBaseSeconds
        self.scheduleWorkoutUseCase = ScheduleWorkoutUseCase(
            repository: repository,
            watchSyncService: watchSyncService,
            clock: clock
        )
    }

    /// Runs the §7 send-to-watch flow for `workoutID` (delegating to
    /// `ScheduleWorkoutUseCase`), then — if it failed — registers it for
    /// automatic retry (transient) or leaves it surfaced for the user
    /// (permanent), per the type's doc comment.
    @discardableResult
    public func scheduleWorkout(workoutID: UUID, scheduledDate: Date? = nil) async throws -> SyncJob {
        await acquireLock(for: workoutID)
        defer { releaseLock(for: workoutID) }

        let job = try await scheduleWorkoutUseCase.execute(workoutID: workoutID, scheduledDate: scheduledDate)
        try await registerRetryOrAbandon(job)
        return job
    }

    /// Retries every job whose backoff timer is due (`clock.now()` at or
    /// past its recorded due date), returning the resulting jobs in no
    /// particular order. Jobs not yet due, or with no pending retry, are
    /// left untouched.
    @discardableResult
    public func retryDueJobs() async throws -> [SyncJob] {
        let now = clock.now()
        let dueJobIDs = retrySchedule.filter { $0.value <= now }.map(\.key)

        var results: [SyncJob] = []
        for jobID in dueJobIDs {
            retrySchedule.removeValue(forKey: jobID)

            guard let job = try await repository.fetchSyncJob(id: jobID) else { continue }
            guard case .failed = job.state else { continue }

            await acquireLock(for: job.workoutID)
            // registerRetryOrAbandon must run INSIDE the lock: at the
            // attempt cap it persists `.abandoned` from its snapshot, and
            // doing that unlocked could clobber a concurrent send that just
            // persisted `.synced` (an illegal synced -> abandoned write).
            let retried = try await withLockReleasedOnReturn(workoutID: job.workoutID) { () -> SyncJob in
                let retried = try await self.scheduleWorkoutUseCase.execute(
                    workoutID: job.workoutID, scheduledDate: job.scheduledDate
                )
                try await self.registerRetryOrAbandon(retried)
                return retried
            }
            results.append(retried)
        }
        return results
    }

    /// Runs one foreground reconciliation pass (`docs/ARCHITECTURE.md` §7):
    /// for every workout with a `.synced` job, first checks edit-after-sync
    /// staleness, then diffs the remaining `.synced` jobs against what
    /// `WatchSyncService.fetchScheduledWorkouts()` actually reports,
    /// transitioning any that vanished from the Watch to
    /// `.failed(.transient)` (self-heals via the normal retry path) and
    /// flagging any Watch-side entries with no matching local job.
    @discardableResult
    public func reconcile() async throws -> ReconciliationReport {
        let workouts = try await repository.fetchAll()
        var markedStale: [UUID] = []
        var syncedByPlanID: [UUID: SyncJob] = [:]

        for workout in workouts {
            guard let job = try await repository.fetchLatestSyncJob(workoutID: workout.id) else { continue }
            guard job.state == .synced else { continue }

            await acquireLock(for: workout.id)
            let outcome = try await withLockReleasedOnReturn(workoutID: workout.id) {
                try await self.staleIfEdited(workout: workout, job: job)
            }

            switch outcome {
            case .markedStale(let jobID):
                markedStale.append(jobID)
            case .unchanged(let job):
                if let planIdentifier = job.planIdentifier, let planID = UUID(uuidString: planIdentifier) {
                    syncedByPlanID[planID] = job
                }
            }
        }

        let scheduledOnWatch = try await watchSyncService.fetchScheduledWorkouts()
        let scheduledPlanIDs = Set(scheduledOnWatch.map(\.id))

        var markedFailed: [UUID] = []
        for (planID, job) in syncedByPlanID where !scheduledPlanIDs.contains(planID) {
            await acquireLock(for: job.workoutID)
            let updatedID = try await withLockReleasedOnReturn(workoutID: job.workoutID) { () -> UUID? in
                // Re-fetch inside the lock: the workout (and, via cascade,
                // this job) may have been deleted — or the job re-stated —
                // since the snapshot above. Persisting the stale in-memory
                // copy would resurrect a job for a deleted workout,
                // violating the repository's cascade invariant.
                guard var current = try await self.repository.fetchSyncJob(id: job.id),
                      current.state == .synced else {
                    return nil
                }
                current.state = .failed(.transient(description: "no longer scheduled on the Watch — expired or removed"))
                current.updatedAt = self.clock.now()
                try await self.repository.saveSyncJob(current)
                try await self.registerRetryOrAbandon(current)
                return current.id
            }
            if let updatedID {
                markedFailed.append(updatedID)
            }
        }

        let orphaned = scheduledPlanIDs.subtracting(syncedByPlanID.keys)
        return ReconciliationReport(
            markedStale: markedStale,
            markedFailed: markedFailed,
            orphanedPlanIDs: Array(orphaned)
        )
    }

    /// Checks a single workout's latest job for edit-after-sync staleness
    /// and marks/persists `.stale` if so (§7: "Workout edited after synced
    /// ⇒ mark job `stale`, prompt re-send"). Exposed so callers can react
    /// immediately after saving an edited workout, without waiting for the
    /// next full `reconcile()` pass.
    @discardableResult
    public func markStaleIfEdited(workoutID: UUID) async throws -> SyncJob? {
        guard let workout = try await repository.fetch(id: workoutID) else { return nil }
        guard let job = try await repository.fetchLatestSyncJob(workoutID: workoutID) else { return nil }
        guard job.state == .synced else { return nil }

        await acquireLock(for: workoutID)
        let outcome = try await withLockReleasedOnReturn(workoutID: workoutID) {
            try await self.staleIfEdited(workout: workout, job: job)
        }
        if case .markedStale = outcome {
            return try await repository.fetchSyncJob(id: job.id)
        }
        return nil
    }

    // MARK: - Private

    private enum StaleCheckOutcome {
        case markedStale(UUID)
        case unchanged(SyncJob)
    }

    /// Must be called while holding `workoutID`'s lock.
    private func staleIfEdited(workout: Workout, job: SyncJob) async throws -> StaleCheckOutcome {
        // Re-fetch inside the lock: `job` was snapshotted before the lock
        // was acquired, and the workout (cascading this job) may have been
        // deleted — or the job re-stated — in between. Persisting the stale
        // snapshot would resurrect a job for a deleted workout (same bug
        // shape as the reconcile phase-2 deletion race).
        guard var current = try await repository.fetchSyncJob(id: job.id),
              current.state == .synced else {
            return .unchanged(job)
        }
        guard workout.updatedAt > current.updatedAt else {
            return .unchanged(current)
        }
        current.state = .stale
        current.updatedAt = clock.now()
        try await repository.saveSyncJob(current)
        return .markedStale(current.id)
    }

    /// Decides what happens next to a job that just finished a sync
    /// attempt: no-op if it isn't `.failed`, register a backoff-timed retry
    /// if the failure is `.transient` and under the attempt cap, or abandon
    /// it (persisting `.abandoned`) once the cap is reached. Permanent
    /// failure reasons (`.notAuthorized`, `.invalidComposition`,
    /// `.noPairedWatch`) are left as `.failed(reason)` untouched, per §7.
    private func registerRetryOrAbandon(_ job: SyncJob) async throws {
        guard case .failed(let reason) = job.state else {
            retrySchedule.removeValue(forKey: job.id)
            return
        }
        guard Self.isRetryable(reason) else {
            retrySchedule.removeValue(forKey: job.id)
            return
        }
        guard job.attemptCount < maxAttempts else {
            retrySchedule.removeValue(forKey: job.id)
            var abandoned = job
            abandoned.state = .abandoned
            abandoned.updatedAt = clock.now()
            try await repository.saveSyncJob(abandoned)
            return
        }
        let delay = Self.backoffInterval(forAttempt: job.attemptCount, base: backoffBaseSeconds)
        retrySchedule[job.id] = clock.now().addingTimeInterval(delay)
    }

    /// Only `.transient` is retryable — §7 explicitly names
    /// `.notAuthorized`/`.invalidComposition`/`.noPairedWatch` as permanent
    /// failures requiring an actionable message, not a retry loop.
    static func isRetryable(_ reason: SyncFailureReason) -> Bool {
        if case .transient = reason {
            return true
        }
        return false
    }

    /// Exponential backoff: `base * 2^(attempt - 1)` for `attempt >= 1`.
    static func backoffInterval(forAttempt attempt: Int, base: TimeInterval) -> TimeInterval {
        guard attempt >= 1 else { return base }
        return base * pow(2, Double(attempt - 1))
    }

    // MARK: - Per-workout locking

    /// Waits until `workoutID` is free, then marks it busy. Pairs with
    /// `releaseLock(for:)`.
    private func acquireLock(for workoutID: UUID) async {
        if busyWorkoutIDs.contains(workoutID) {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                waiters[workoutID, default: []].append(continuation)
            }
            // Ownership was handed directly to us by `releaseLock`;
            // `busyWorkoutIDs` already contains `workoutID`.
            return
        }
        busyWorkoutIDs.insert(workoutID)
    }

    /// Releases `workoutID`'s lock, handing it directly to the next waiter
    /// (if any) instead of freeing it, to keep waiters strictly FIFO.
    private func releaseLock(for workoutID: UUID) {
        guard var pending = waiters[workoutID], !pending.isEmpty else {
            busyWorkoutIDs.remove(workoutID)
            waiters.removeValue(forKey: workoutID)
            return
        }
        let next = pending.removeFirst()
        waiters[workoutID] = pending
        next.resume()
    }

    /// Runs `body` while holding `workoutID`'s lock (already acquired by
    /// the caller), releasing it once `body` returns or throws.
    private func withLockReleasedOnReturn<T>(
        workoutID: UUID,
        _ body: () async throws -> T
    ) async throws -> T {
        defer { releaseLock(for: workoutID) }
        return try await body()
    }

}
