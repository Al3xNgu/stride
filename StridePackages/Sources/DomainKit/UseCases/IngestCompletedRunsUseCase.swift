import Foundation

/// One `CompletedRun` and its derived `Split`s, already projected from an
/// `HKWorkout` by the ingestion adapter (task 1.11's `RunHistoryRepository`-
/// facing HealthKit adapter, built in parallel with this use case).
///
/// `IngestCompletedRunsUseCase` depends only on these domain types and the
/// ports below — never on HealthKit itself (CLAUDE.md rule 1) — so the
/// adapter's job is exactly "produce this shape," and this type's job is
/// "make ingesting it idempotent, attributed, and PR-aware."
public struct IngestedRun: Equatable, Hashable, Sendable {
    /// The projected run. Per `CompletedRun`'s own doc comment, `id` is the
    /// source `HKWorkout`'s UUID — the stable identity ingestion upserts by.
    public var run: CompletedRun
    /// Splits derived from the run's distance samples (possibly empty, e.g.
    /// a very short run with no split boundaries crossed).
    public var splits: [Split]

    /// Creates an ingested run/splits pair.
    public init(run: CompletedRun, splits: [Split] = []) {
        self.run = run
        self.splits = splits
    }
}

/// One batch of HealthKit ingestion results for `IngestCompletedRunsUseCase`
/// to apply: newly-observed or updated runs, plus HealthKit-side deletions
/// reported in the same anchored-query pass (`docs/ARCHITECTURE.md` §8 step 2
/// — `HKAnchoredObjectQueryDescriptor.Result` carries `addedSamples` and
/// `deletedObjects` together; `docs/RESEARCH-LOG.md` 2026-07-19 task 1.10 §1).
///
/// Defined here, in Domain, rather than imported from DataKit: the adapter
/// (task 1.11) depends on `DomainKit` and builds one of these per anchored
/// fetch; this use case has no HealthKit-shaped input of its own.
public struct IngestionBatch: Equatable, Hashable, Sendable {
    /// Runs to upsert (new or updated since the last anchor), each with its
    /// derived splits.
    public var runs: [IngestedRun]
    /// `HKWorkout` UUIDs HealthKit reports as deleted since the last anchor
    /// — matches `CompletedRun.id` (`docs/ARCHITECTURE.md` §8 step 4).
    public var deletedRunIDs: [UUID]

    /// Creates an ingestion batch. Defaults to empty, so an anchored fetch
    /// that returned nothing new can still be applied as a harmless no-op.
    public init(runs: [IngestedRun] = [], deletedRunIDs: [UUID] = []) {
        self.runs = runs
        self.deletedRunIDs = deletedRunIDs
    }
}

/// The outcome of one `IngestCompletedRunsUseCase.execute(_:)` call, for
/// observability/testing (e.g. driving the future domain-event emission
/// `docs/ARCHITECTURE.md` §8 step 7 describes — the `Events` bus itself is a
/// later task, per `Events.swift`'s placeholder doc comment; this report is
/// deliberately shaped so wiring that emission later is additive, not a
/// signature change here).
public struct IngestionReport: Equatable, Hashable, Sendable {
    /// Ids of every run upserted this batch, in the order `batch.runs` listed
    /// them (deduplicated to each id's *final* processed state, per
    /// `RunHistoryRepository.upsert`'s "keyed by id" contract).
    public var upsertedRunIDs: [UUID]
    /// Run id -> `Workout.id` for every run the schedule-window heuristic
    /// newly attributed this batch (§8 step 5). Runs that were already
    /// attributed by a prior ingestion, or arrived pre-attributed, are not
    /// included here even though they remain attributed in the store — see
    /// `execute(_:)`'s doc comment.
    public var attributedRunIDs: [UUID: UUID]
    /// Run ids newly tombstoned this batch via `markDeleted`.
    public var tombstonedRunIDs: [UUID]
    /// Deleted-ids from the batch that matched no known run (`runNotFound`,
    /// tolerated — see `execute(_:)`'s doc comment) rather than being applied.
    public var skippedUnknownDeletionIDs: [UUID]
    /// Every `PersonalBest` newly persisted this batch (`.newRecord`
    /// decisions only — `.tie`/`.noChange` are never persisted, per
    /// `PersonalBestDecision`'s doc comment).
    public var newPersonalBests: [PersonalBest]

    /// Creates a report. Defaults to "nothing happened," matching an empty
    /// `IngestionBatch`'s outcome.
    public init(
        upsertedRunIDs: [UUID] = [],
        attributedRunIDs: [UUID: UUID] = [:],
        tombstonedRunIDs: [UUID] = [],
        skippedUnknownDeletionIDs: [UUID] = [],
        newPersonalBests: [PersonalBest] = []
    ) {
        self.upsertedRunIDs = upsertedRunIDs
        self.attributedRunIDs = attributedRunIDs
        self.tombstonedRunIDs = tombstonedRunIDs
        self.skippedUnknownDeletionIDs = skippedUnknownDeletionIDs
        self.newPersonalBests = newPersonalBests
    }
}

/// Applies one `IngestionBatch` from the HealthKit ingestion pipeline:
/// idempotent upsert, deletion tombstoning, schedule-window workout
/// attribution, and personal-best recalculation
/// (`docs/ARCHITECTURE.md` §6's `IngestCompletedRunsUseCase` row / §8 steps
/// 4-7).
///
/// **Concurrency — plain value type, not an actor:** per this task's own
/// instruction and `docs/ARCHITECTURE.md` §8's single diagram ("App launch /
/// foreground / background delivery wake-up -> RunHistoryRepository ->
/// IngestCompletedRunsUseCase"), batches are assumed to arrive **serially**
/// from one ingestion pipeline (one anchored-query pass completes, persists
/// its new anchor, and only then does the next pass begin) — there is no
/// documented scenario where two batches are in flight concurrently the way
/// `SyncCoordinator` must tolerate concurrent `scheduleWorkout` calls for
/// different workouts from UI actions. This use case therefore follows
/// `ScheduleWorkoutUseCase`'s precedent (a plain `Sendable` struct with no
/// isolation of its own) rather than `SyncCoordinator`'s per-key actor lock.
/// If a future caller cannot guarantee serial delivery (e.g. both a
/// foreground reconciliation and a background-delivery wake-up racing), it
/// should serialize calls to `execute(_:)` itself — e.g. via an actor or a
/// single-task queue at the composition root — the same way `SyncCoordinator`
/// serializes access to `ScheduleWorkoutUseCase`.
///
/// **`SyncJob` writes are NOT this use case's own responsibility.**
/// `SyncCoordinator` is the sole owner of every `SyncJob` state transition
/// (`docs/ARCHITECTURE.md` §6 component table); this use case only *reads*
/// `SyncJob`s via `WorkoutRepository` (to find schedule-window attribution
/// candidates) and delegates the one write it needs — flipping a matched
/// job to `.completedRunLinked` — to the injected `SyncCoordinator`'s
/// `linkCompletedRun(workoutID:)`, which performs that write under its own
/// per-workout lock. Writing `SyncJob` state directly here, outside that
/// lock, would race with `SyncCoordinator.reconcile()` /
/// `markStaleIfEdited(workoutID:)` running concurrently on the same workout
/// (see `linkCompletedRun(workoutID:)`'s doc comment for the exact hazard).
public struct IngestCompletedRunsUseCase: Sendable {
    private let runHistoryRepository: RunHistoryRepository
    private let workoutRepository: WorkoutRepository
    private let syncCoordinator: SyncCoordinator
    private let milestones: [Milestone]
    private let attributionWindow: TimeInterval

    /// Creates the use case from its ports.
    ///
    /// Takes no `Clock` of its own: `PersonalBestPolicy` derives `achievedAt`
    /// from `run.date` (never "now" — see `PersonalBestPolicy.evaluate`'s doc
    /// comment), and the one transition that used to need "now" here
    /// (`.completedRunLinked`'s `updatedAt`) is now `SyncCoordinator`'s
    /// responsibility, timestamped with its own injected `Clock` — see the
    /// type's doc comment.
    /// - Parameters:
    ///   - workoutRepository: read-only access to workouts and their
    ///     `SyncJob`s for schedule-window attribution candidates. Never
    ///     written to directly by this use case — see the type's doc
    ///     comment.
    ///   - syncCoordinator: the sole owner of `SyncJob` state transitions;
    ///     injected directly as the concrete actor (the same pattern
    ///     `LibraryViewModel` uses), not behind an additional protocol seam.
    ///   - milestones: the milestone catalog PR recalculation evaluates
    ///     every qualifying run against. Defaults to `Milestone.mvpPresets`.
    ///   - attributionWindow: the schedule-window attribution heuristic's
    ///     tolerance, in seconds, symmetric around a `SyncJob.scheduledDate`
    ///     (see `execute(_:)`'s doc comment for the full rule). Defaults to
    ///     6 hours — **a documented policy choice flagged for reviewer
    ///     confirmation**, not a number `docs/ARCHITECTURE.md` §8 specifies:
    ///     §8 says only "match to Workout via schedule window" and §11 risk 2
    ///     warns "matching by time window can mis-attribute," without giving
    ///     a duration. 6 hours is chosen to comfortably cover a runner
    ///     starting well before/after a planned time (a morning workout
    ///     scheduled for 7am but actually run at 6am or delayed to noon)
    ///     while still being far tighter than "same day," keeping false
    ///     positives (two unrelated scheduled workouts on the same day)
    ///     unlikely for typical single-run-per-day usage.
    public init(
        runHistoryRepository: RunHistoryRepository,
        workoutRepository: WorkoutRepository,
        syncCoordinator: SyncCoordinator,
        milestones: [Milestone] = Milestone.mvpPresets,
        attributionWindow: TimeInterval = 6 * 60 * 60
    ) {
        self.runHistoryRepository = runHistoryRepository
        self.workoutRepository = workoutRepository
        self.syncCoordinator = syncCoordinator
        self.milestones = milestones
        self.attributionWindow = attributionWindow
    }

    /// Applies `batch`, per `docs/ARCHITECTURE.md` §8 steps 4-7:
    ///
    /// 1. **Upsert (idempotent).** Each `IngestedRun.run` is upserted keyed
    ///    by `run.id` (§8 step 4) and its splits are saved with replace
    ///    semantics (`RunHistoryRepository.saveSplits(_:for:)`).
    /// 2. **Attribution (§8 step 5).** Before upserting, a run whose
    ///    `workoutID` is not already known — neither on the incoming
    ///    projection itself, nor on any existing stored run with the same
    ///    id — is matched against every workout's most recent `SyncJob`:
    ///    a candidate must be `.synced` with a non-nil `scheduledDate`
    ///    within `attributionWindow` seconds of `run.date` (either
    ///    direction). Among candidates, the one with the smallest time delta
    ///    wins; remaining ties are broken by `SyncJob.workoutID.uuidString`
    ///    ascending, for total determinism — **both the window and the
    ///    tie-break are this use case's documented policy choice** (§8 names
    ///    only "schedule window," not a concrete tie-break rule). A
    ///    successful match also asks `SyncCoordinator.linkCompletedRun(workoutID:)`
    ///    to transition that `SyncJob` to `.completedRunLinked`
    ///    (`SyncJobState`'s own doc comment: "successful attribution after
    ///    `.synced`" — this use case is that transition's only intended
    ///    trigger, but `SyncCoordinator` is the only thing that actually
    ///    writes it, under its per-workout lock — see the type's doc
    ///    comment). That call can decline the transition (returning `false`)
    ///    if the job is no longer `.synced` by the time the coordinator's
    ///    lock is acquired (e.g. concurrently marked `.stale`); **the run's
    ///    own `workoutID` attribution is persisted regardless** — attributing
    ///    a `CompletedRun` to a `Workout` and bookkeeping the `SyncJob`'s
    ///    linked-state are independent concerns, and a race losing the
    ///    latter must not undo the former. A run whose id was already stored
    ///    with a non-nil `workoutID` keeps that attribution unconditionally,
    ///    and the heuristic is **not** re-run for it — re-ingesting the same
    ///    batch must be a no-op (idempotent), and re-running the heuristic
    ///    could flap a run onto a *different* workout if its once-`.synced`
    ///    candidate job has since moved on (e.g. re-sent and re-linked to a
    ///    later run). An incoming run that already carries a non-nil
    ///    `workoutID` (an adapter- or caller-supplied override) is likewise
    ///    respected as-is, skipping the heuristic.
    /// 3. **Tombstones (§8 step 4).** Every id in `batch.deletedRunIDs` is
    ///    passed to `markDeleted`. An already-deleted run is tolerated (the
    ///    port's `markDeleted` has no "already deleted" error — setting
    ///    `isDeleted = true` again is a harmless no-op). An **unknown** id
    ///    throws `RunHistoryRepositoryError.runNotFound`; this use case
    ///    **catches and tolerates** that specific case (recorded in
    ///    `IngestionReport.skippedUnknownDeletionIDs` rather than thrown) —
    ///    a HealthKit deletion for a workout this app never ingested (e.g.
    ///    deleted before the app was installed, or between two anchors in a
    ///    way that never surfaced it as `addedSamples`) represents no actual
    ///    local-state problem, so failing the entire batch over it would
    ///    discard every other run/tombstone/PR update it also contained for
    ///    no benefit. Any *other* thrown error propagates untouched and
    ///    aborts the batch (matching `ScheduleWorkoutUseCase`'s "a
    ///    persistence failure mid-flow ... propagates untouched" precedent).
    /// 4. **Personal-best recalculation (§8 steps 6-7).** For every run still
    ///    present (i.e. not tombstoned by this same batch) after upsert,
    ///    `PersonalBestPolicy.qualifyingMilestones(for:among:)` determines
    ///    which milestones it qualifies for; each is evaluated via
    ///    `PersonalBestPolicy.evaluate(run:milestone:currentBest:)` against
    ///    the store's current record (freshly fetched per milestone, so two
    ///    qualifying runs for the *same* milestone within one batch are
    ///    compared against each other correctly in `batch.runs` order).
    ///    Only `.newRecord` decisions are persisted, via `savePersonalBest`;
    ///    `.tie` and `.noChange` are ignored, per `PersonalBestDecision`'s
    ///    own doc comment.
    ///
    /// **Tombstoned-PR-source semantics — decided and documented here for
    /// reviewer confirmation.** Tombstoning a run that is the *current*
    /// `PersonalBest` source for some milestone does **not** trigger any
    /// recalculation, deletion, or replacement of that `PersonalBest`: it is
    /// left exactly as stored, still referencing the now-tombstoned run.
    /// This follows directly from `CompletedRun.isDeleted`'s own doc
    /// comment — the projection is retained rather than removed "so
    /// dependent records, such as a `PersonalBest` referencing it, remain
    /// explainable" — which is a direct, load-bearing statement about
    /// exactly this case; recalculating (or worse, deleting) the record
    /// would contradict "remain explainable" by silently promoting a
    /// different run to "the record" with no trace of why. A future,
    /// strictly faster run can still supersede it in the ordinary way
    /// (`fetchPersonalBest(milestoneID:)`'s "lowest `elapsedSeconds` wins"
    /// contract applies regardless of whether the current record's source
    /// run happens to be tombstoned); this use case only declines to
    /// *manufacture* that supersession itself on tombstone.
    ///
    /// - Throws: any non-`runNotFound` error from `runHistoryRepository` or
    ///   `workoutRepository`, propagated untouched.
    public func execute(_ batch: IngestionBatch) async throws -> IngestionReport {
        let upsertOutcome = try await upsertAndAttribute(batch.runs)
        let tombstoneOutcome = try await tombstone(
            batch.deletedRunIDs, removingFrom: upsertOutcome.finalRuns
        )
        let newPersonalBests = try await recalculatePersonalBests(
            for: upsertOutcome.order, in: tombstoneOutcome.finalRuns
        )

        return IngestionReport(
            upsertedRunIDs: upsertOutcome.order,
            attributedRunIDs: upsertOutcome.attributed,
            tombstonedRunIDs: tombstoneOutcome.tombstoned,
            skippedUnknownDeletionIDs: tombstoneOutcome.skippedUnknownDeletions,
            newPersonalBests: newPersonalBests
        )
    }

    /// Intermediate result of `upsertAndAttribute(_:)` — grouped into a type
    /// (rather than a tuple) to stay under swiftlint's `large_tuple` rule.
    private struct UpsertOutcome {
        var order: [UUID]
        var finalRuns: [UUID: CompletedRun]
        var attributed: [UUID: UUID]
    }

    /// Intermediate result of `tombstone(_:removingFrom:)` — grouped into a
    /// type (rather than a tuple) to stay under swiftlint's `large_tuple`
    /// rule.
    private struct TombstoneOutcome {
        var finalRuns: [UUID: CompletedRun]
        var tombstoned: [UUID]
        var skippedUnknownDeletions: [UUID]
    }

    // MARK: - Phase 1: upsert + attribution

    /// Upserts every `IngestedRun`, attributing each (per `execute(_:)`'s doc
    /// comment, point 2) before persisting it. Returns the final, deduplicated
    /// per-id state and processing order, plus which runs were newly
    /// attributed this batch.
    private func upsertAndAttribute(_ ingestedRuns: [IngestedRun]) async throws -> UpsertOutcome {
        var attributed: [UUID: UUID] = [:]
        var order: [UUID] = []
        var finalRuns: [UUID: CompletedRun] = [:]

        for ingested in ingestedRuns {
            var run = ingested.run
            let existing = try await runHistoryRepository.fetch(id: run.id)

            if let existingWorkoutID = existing?.workoutID {
                run.workoutID = existingWorkoutID
            } else if run.workoutID == nil, let matchedJob = try await attributeWorkoutID(for: run) {
                // The run-side attribution is persisted regardless of
                // whether the coordinator's job-state transition below is
                // actually applied — see `execute(_:)`'s doc comment, point 2.
                run.workoutID = matchedJob.workoutID
                attributed[run.id] = matchedJob.workoutID
                try await syncCoordinator.linkCompletedRun(workoutID: matchedJob.workoutID)
            }

            try await runHistoryRepository.upsert(run)
            try await runHistoryRepository.saveSplits(ingested.splits, for: run.id)

            if finalRuns[run.id] == nil {
                order.append(run.id)
            }
            finalRuns[run.id] = run
        }

        return UpsertOutcome(order: order, finalRuns: finalRuns, attributed: attributed)
    }

    // MARK: - Phase 2: tombstones

    /// Applies every deletion in `deletedRunIDs` (per `execute(_:)`'s doc
    /// comment, point 3), removing any tombstoned id from `finalRuns` so
    /// phase 3 never PR-recalculates a run deleted within this same batch.
    private func tombstone(
        _ deletedRunIDs: [UUID],
        removingFrom finalRuns: [UUID: CompletedRun]
    ) async throws -> TombstoneOutcome {
        var finalRuns = finalRuns
        var tombstoned: [UUID] = []
        var skippedUnknownDeletions: [UUID] = []

        for id in deletedRunIDs {
            do {
                try await runHistoryRepository.markDeleted(id: id)
                tombstoned.append(id)
                finalRuns.removeValue(forKey: id)
            } catch RunHistoryRepositoryError.runNotFound {
                skippedUnknownDeletions.append(id)
            }
        }

        return TombstoneOutcome(
            finalRuns: finalRuns, tombstoned: tombstoned, skippedUnknownDeletions: skippedUnknownDeletions
        )
    }

    // MARK: - Phase 3: personal-best recalculation

    /// Evaluates `PersonalBestPolicy` for every still-present run in `order`
    /// (per `execute(_:)`'s doc comment, point 4), persisting and returning
    /// only `.newRecord` decisions.
    private func recalculatePersonalBests(
        for order: [UUID],
        in finalRuns: [UUID: CompletedRun]
    ) async throws -> [PersonalBest] {
        var newPersonalBests: [PersonalBest] = []

        for id in order {
            guard let run = finalRuns[id] else { continue }
            let qualifying = PersonalBestPolicy.qualifyingMilestones(for: run, among: milestones)
            for milestone in qualifying {
                let currentBest = try await runHistoryRepository.fetchPersonalBest(milestoneID: milestone.id)
                let decision = PersonalBestPolicy.evaluate(run: run, milestone: milestone, currentBest: currentBest)
                if case .newRecord(let personalBest) = decision {
                    try await runHistoryRepository.savePersonalBest(personalBest)
                    newPersonalBests.append(personalBest)
                }
            }
        }

        return newPersonalBests
    }

    // MARK: - Attribution

    /// Finds the best schedule-window candidate `SyncJob` for `run`, or
    /// `nil` if none is within `attributionWindow`. See `execute(_:)`'s doc
    /// comment for the full rule (window + tie-break).
    private func attributeWorkoutID(for run: CompletedRun) async throws -> SyncJob? {
        let workouts = try await workoutRepository.fetchAll()
        var best: (job: SyncJob, delta: TimeInterval)?

        for workout in workouts {
            guard let job = try await workoutRepository.fetchLatestSyncJob(workoutID: workout.id),
                  job.state == .synced,
                  let scheduledDate = job.scheduledDate else { continue }

            let delta = abs(run.date.timeIntervalSince(scheduledDate))
            guard delta <= attributionWindow else { continue }

            let candidate = (job: job, delta: delta)
            if let current = best, !Self.isBetter(candidate, than: current) {
                continue
            }
            best = candidate
        }

        return best?.job
    }

    /// Whether `candidate` should replace `current` as the best attribution
    /// match: strictly smaller time delta wins; a tied delta is broken by
    /// `workoutID.uuidString` ascending, for a total, deterministic order.
    private static func isBetter(
        _ candidate: (job: SyncJob, delta: TimeInterval),
        than current: (job: SyncJob, delta: TimeInterval)
    ) -> Bool {
        if candidate.delta != current.delta {
            return candidate.delta < current.delta
        }
        return candidate.job.workoutID.uuidString < current.job.workoutID.uuidString
    }

}
