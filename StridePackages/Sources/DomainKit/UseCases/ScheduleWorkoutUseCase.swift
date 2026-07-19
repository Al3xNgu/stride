import Foundation

/// A typed error surfaced by `ScheduleWorkoutUseCase` itself (as opposed to
/// errors from its collaborating ports, which propagate untouched — see the
/// type's doc comment).
public enum ScheduleWorkoutError: Error, Equatable, Hashable, Sendable {
    /// No `Workout` exists for the given id.
    case workoutNotFound(id: UUID)
    /// The workout failed pre-flight structural validation
    /// (`docs/ARCHITECTURE.md` §7 step 1); every violation found is included.
    case invalidWorkout([ValidationIssue])
}

/// Orchestrates "send this workout to the Watch for date `D` (or `nil` for
/// the next available slot)" — the `docs/ARCHITECTURE.md` §7 "Send to Watch"
/// flow, steps 1–5.
///
/// This type owns exactly the orchestration in §7: re-validate, create-or-
/// reuse the workout's `SyncJob`, persist every state transition
/// (`.pending` -> `.syncing` -> `.synced`/`.failed`) via `WorkoutRepository`
/// before/after each effectful step so a crash mid-sync leaves an accurate,
/// resumable record, then call `WatchSyncService` and map its typed error
/// surface onto the domain's `SyncFailureReason` vocabulary. It has no UI
/// concerns and does not decide retry policy — that is `SyncCoordinator`'s
/// job (`docs/ARCHITECTURE.md` §6 component table).
///
/// **Concurrency:** this is a plain value type with no isolation of its own.
/// Calling `execute` concurrently for the *same* `workoutID` from multiple
/// tasks can race on the read-modify-write of that workout's `SyncJob`.
/// Callers that need that guarantee should route scheduling through
/// `SyncCoordinator`, which serializes per-workout access (see its doc
/// comment).
public struct ScheduleWorkoutUseCase: Sendable {
    private let repository: WorkoutRepository
    private let watchSyncService: WatchSyncService
    private let clock: Clock

    /// Creates the use case from its ports.
    public init(repository: WorkoutRepository, watchSyncService: WatchSyncService, clock: Clock) {
        self.repository = repository
        self.watchSyncService = watchSyncService
        self.clock = clock
    }

    /// Runs the full §7 send-to-watch flow for `workoutID`, returning the
    /// resulting `SyncJob` (in `.synced` or `.failed(reason)` state).
    ///
    /// - Throws: `ScheduleWorkoutError.workoutNotFound` if no such workout
    ///   exists; `ScheduleWorkoutError.invalidWorkout` if pre-flight
    ///   validation fails (no `SyncJob` is created/mutated in that case —
    ///   validation happens *before* §7 step 2, "crash-safe from here").
    ///   Errors from `WorkoutRepository` propagate untouched (a persistence
    ///   failure mid-flow is not a sync failure the state machine can
    ///   represent — there is nowhere left to durably record it).
    @discardableResult
    public func execute(workoutID: UUID, scheduledDate: Date? = nil) async throws -> SyncJob {
        guard let workout = try await repository.fetch(id: workoutID) else {
            throw ScheduleWorkoutError.workoutNotFound(id: workoutID)
        }

        let issues = ValidateWorkoutPolicy.validate(workout)
        guard issues.isEmpty else {
            throw ScheduleWorkoutError.invalidWorkout(issues)
        }

        var job = try await loadOrCreateJob(for: workout, scheduledDate: scheduledDate)

        // §7 step 2: create-or-reuse the SyncJob and persist `.pending`
        // before doing anything effectful — crash-safe from here on.
        //
        // The job's own `id` doubles as the WorkoutKit plan identifier
        // passed to `WatchSyncService.schedule(planID:workout:at:)`.
        // Reusing the *same* `SyncJob` (and therefore the same `id`) across
        // every send/retry/re-send for a given workout — rather than
        // minting a fresh one each time — is what makes the "stable plan
        // identifier for replace semantics" requirement trivial: WorkoutKit
        // replaces (not duplicates) a re-scheduled plan with the same id
        // (`docs/RESEARCH-LOG.md` 2026-07-10 item 6), so reusing the job id
        // as the plan id means every re-send is automatically a replace.
        job.scheduledDate = scheduledDate
        job.state = .pending
        job.updatedAt = clock.now()
        try await repository.saveSyncJob(job)

        job.state = .syncing
        job.updatedAt = clock.now()
        try await repository.saveSyncJob(job)

        let planID = job.id
        do {
            try await watchSyncService.schedule(planID: planID, workout: workout, at: scheduledDate)
            job.state = .synced
            job.planIdentifier = planID.uuidString
            job.attemptCount += 1
            job.updatedAt = clock.now()
        } catch {
            job.state = .failed(Self.map(error))
            job.attemptCount += 1
            job.updatedAt = clock.now()
        }
        try await repository.saveSyncJob(job)

        return job
    }

    /// Finds the workout's most recent `SyncJob` to reuse (any state,
    /// including `.abandoned`/`.stale` — a manual re-send legitimately
    /// resurrects it), or creates a fresh `.draft` one if the workout has
    /// never been synced.
    private func loadOrCreateJob(for workout: Workout, scheduledDate: Date?) async throws -> SyncJob {
        if let existing = try await repository.fetchLatestSyncJob(workoutID: workout.id) {
            return existing
        }
        let now = clock.now()
        return SyncJob(
            workoutID: workout.id,
            state: .draft,
            createdAt: now,
            updatedAt: now,
            scheduledDate: scheduledDate
        )
    }

    /// Maps a `WatchSyncService` failure onto the domain's
    /// `SyncFailureReason` vocabulary. No new `SyncFailureReason` cases are
    /// introduced (CLAUDE.md rule 8 / task instruction) — every
    /// `WatchSyncError` case is mapped onto the closest existing reason:
    ///
    /// - `.unauthorized` -> `.notAuthorized` (exact match).
    /// - `.watchNotPaired` -> `.noPairedWatch` (exact match).
    /// - `.unsupported` -> `.noPairedWatch`: in practice on a phone the only
    ///   way scheduling becomes unsupported is no paired Watch (or
    ///   Simulator, which is not a real user-facing case); this is the
    ///   closest permanent-failure vocabulary entry.
    /// - `.workoutApplicationNotInstalled` -> `.noPairedWatch`: also a
    ///   "the Watch isn't properly set up" permanent condition, closest to
    ///   `.noPairedWatch` of the available cases.
    /// - `.invalidComposition` -> `.invalidComposition` (the free-form
    ///   `reason` string is intentionally dropped — `SyncFailureReason`'s
    ///   case carries no payload; presentation-layer messaging is generic
    ///   for this case).
    /// - `.notScheduled` -> `.transient`: this error is only documented for
    ///   `remove(planID:)`, not `schedule`; if a `WatchSyncService`
    ///   implementation ever surfaces it from `schedule` it is treated as a
    ///   retryable transient condition rather than invented as a new case.
    /// - `.underlying` -> `.transient(description:)` (exact-shape match;
    ///   an unrecognized underlying error is assumed retryable so
    ///   `SyncCoordinator`'s backoff gets a chance before giving up).
    /// - Any non-`WatchSyncError` thrown by a `WatchSyncService`
    ///   implementation (contract violation) is also treated as
    ///   `.transient`, described via `String(describing:)`.
    static func map(_ error: Error) -> SyncFailureReason {
        guard let watchError = error as? WatchSyncError else {
            return .transient(description: String(describing: error))
        }
        switch watchError {
        case .unauthorized:
            return .notAuthorized
        case .unsupported:
            return .noPairedWatch
        case .notScheduled:
            return .transient(description: "no scheduled entry found for this plan")
        case .watchNotPaired:
            return .noPairedWatch
        case .workoutApplicationNotInstalled:
            return .noPairedWatch
        case .invalidComposition:
            return .invalidComposition
        case .underlying(let description):
            return .transient(description: description)
        }
    }
}
