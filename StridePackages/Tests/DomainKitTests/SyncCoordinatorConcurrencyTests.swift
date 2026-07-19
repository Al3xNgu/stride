import Testing
import Foundation
@testable import DomainKit
import TestSupport

// MARK: - Concurrency test doubles

/// Actor-isolated so concurrent `enter`/`exit` calls from different `Task`s
/// are themselves race-free, and records whether two calls for the *same*
/// workout id were ever simultaneously "inside" a gated section — the thing
/// `SyncCoordinator`'s per-workout lock exists to prevent.
private actor OverlapDetector {
    private var active: Set<UUID> = []
    private(set) var overlapDetected = false

    func enter(workoutID: UUID) {
        if active.contains(workoutID) {
            overlapDetected = true
        }
        active.insert(workoutID)
    }

    func exit(workoutID: UUID) {
        active.remove(workoutID)
    }
}

/// A `WatchSyncService` decorator that inserts a real suspension point
/// (`Task.yield()`) before delegating to `inner`, so multiple concurrently-
/// scheduled `Task`s calling `SyncCoordinator` for the same workout have an
/// actual window to interleave. Without this, `FakeWatchSyncService.schedule`
/// never suspends internally, so a broken lock could go unproven simply
/// because nothing ever got the chance to race.
private final class YieldingWatchSyncService: WatchSyncService, @unchecked Sendable {
    private let inner: FakeWatchSyncService
    private let overlapDetector: OverlapDetector

    init(inner: FakeWatchSyncService, overlapDetector: OverlapDetector) {
        self.inner = inner
        self.overlapDetector = overlapDetector
    }

    var isSupported: Bool { get async { await inner.isSupported } }
    var authorizationState: WatchAuthorizationState { get async { await inner.authorizationState } }
    var maxScheduledWorkoutCount: Int { get async { await inner.maxScheduledWorkoutCount } }

    func requestAuthorization() async -> WatchAuthorizationState {
        await inner.requestAuthorization()
    }

    func schedule(planID: UUID, workout: Workout, at date: Date?) async throws {
        await overlapDetector.enter(workoutID: workout.id)
        await Task.yield()
        do {
            try await inner.schedule(planID: planID, workout: workout, at: date)
        } catch {
            await overlapDetector.exit(workoutID: workout.id)
            throw error
        }
        await overlapDetector.exit(workoutID: workout.id)
    }

    func remove(planID: UUID) async throws {
        try await inner.remove(planID: planID)
    }

    func fetchScheduledWorkouts() async throws -> [ScheduledWatchWorkout] {
        try await inner.fetchScheduledWorkouts()
    }
}

/// A `WatchSyncService` decorator whose `schedule` call for one specific
/// workout suspends on a test-controlled continuation until `release()` is
/// called, exposing a deterministic `waitUntilBlocked()` so a test never has
/// to guess via a sleep whether the gated call has been reached yet. Used to
/// prove both "different workouts proceed independently" (a gated workout
/// does not hold up an unrelated one) and reentrant in-flight FIFO ordering
/// for the *same* workout.
private actor GatedWatchSyncService: WatchSyncService {
    private let inner: FakeWatchSyncService
    private let gatedWorkoutID: UUID
    private var isArmed: Bool
    private var isBlocked = false
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private var blockedWaiters: [CheckedContinuation<Void, Never>] = []

    /// - Parameter startArmed: whether gating is active from construction.
    ///   Pass `false` when a test needs an initial, ungated call (e.g. to
    ///   seed a failure) before arming the gate for the call it actually
    ///   wants to catch in-flight.
    init(inner: FakeWatchSyncService, gatedWorkoutID: UUID, startArmed: Bool = true) {
        self.inner = inner
        self.gatedWorkoutID = gatedWorkoutID
        self.isArmed = startArmed
    }

    var isSupported: Bool { get async { await inner.isSupported } }
    var authorizationState: WatchAuthorizationState { get async { await inner.authorizationState } }
    var maxScheduledWorkoutCount: Int { get async { await inner.maxScheduledWorkoutCount } }

    func requestAuthorization() async -> WatchAuthorizationState {
        await inner.requestAuthorization()
    }

    func schedule(planID: UUID, workout: Workout, at date: Date?) async throws {
        if isArmed, workout.id == gatedWorkoutID {
            isBlocked = true
            blockedWaiters.forEach { $0.resume() }
            blockedWaiters.removeAll()
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                releaseContinuation = continuation
            }
            isBlocked = false
        }
        try await inner.schedule(planID: planID, workout: workout, at: date)
    }

    func remove(planID: UUID) async throws {
        try await inner.remove(planID: planID)
    }

    func fetchScheduledWorkouts() async throws -> [ScheduledWatchWorkout] {
        try await inner.fetchScheduledWorkouts()
    }

    /// Suspends until the gated `schedule` call is currently parked.
    func waitUntilBlocked() async {
        if isBlocked { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            blockedWaiters.append(continuation)
        }
    }

    /// Releases the currently-parked `schedule` call, if any.
    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }

    /// Disables gating so subsequent `schedule` calls pass straight through.
    func disarm() {
        isArmed = false
    }

    /// Enables gating so the *next* matching `schedule` call parks.
    func arm() {
        isArmed = true
    }
}

/// A `WatchSyncService` decorator whose `fetchScheduledWorkouts()` call
/// suspends until `release()` is called, opening a deterministic window
/// between `SyncCoordinator.reconcile()`'s local-state read phase and its
/// Watch-state read phase for a test to inject a concurrent mutation.
private actor FetchGatedWatchSyncService: WatchSyncService {
    private let inner: FakeWatchSyncService
    private var isBlocked = false
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private var blockedWaiters: [CheckedContinuation<Void, Never>] = []

    init(inner: FakeWatchSyncService) {
        self.inner = inner
    }

    var isSupported: Bool { get async { await inner.isSupported } }
    var authorizationState: WatchAuthorizationState { get async { await inner.authorizationState } }
    var maxScheduledWorkoutCount: Int { get async { await inner.maxScheduledWorkoutCount } }

    func requestAuthorization() async -> WatchAuthorizationState {
        await inner.requestAuthorization()
    }

    func schedule(planID: UUID, workout: Workout, at date: Date?) async throws {
        try await inner.schedule(planID: planID, workout: workout, at: date)
    }

    func remove(planID: UUID) async throws {
        try await inner.remove(planID: planID)
    }

    func fetchScheduledWorkouts() async throws -> [ScheduledWatchWorkout] {
        isBlocked = true
        blockedWaiters.forEach { $0.resume() }
        blockedWaiters.removeAll()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            releaseContinuation = continuation
        }
        isBlocked = false
        return try await inner.fetchScheduledWorkouts()
    }

    func waitUntilBlocked() async {
        if isBlocked { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            blockedWaiters.append(continuation)
        }
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

/// Actor-isolated wrapper making a `FakeWorkoutRepository` safe to use from
/// the genuinely-concurrent, cross-workout access this suite deliberately
/// exercises. `FakeWorkoutRepository` is documented "not internally
/// synchronized: intended for single-threaded test usage" — its backing
/// dictionaries are plain `var`s with no lock of their own, so calling it
/// directly from multiple truly-concurrent `Task`s (exactly what
/// `SyncCoordinator`'s "different workouts proceed independently" guarantee
/// permits) is a genuine, unsynchronized data race on the fake's storage,
/// not evidence of anything about `SyncCoordinator` itself. Wrapping access
/// in an actor makes the *storage* safe without changing what is under test:
/// `SyncCoordinator`'s own per-workout locking, which this wrapper does not
/// add or interfere with.
private actor SafeConcurrentWorkoutRepository: WorkoutRepository {
    private let inner: FakeWorkoutRepository

    init(inner: FakeWorkoutRepository) {
        self.inner = inner
    }

    func save(_ workout: Workout) async throws { try await inner.save(workout) }
    func fetchAll() async throws -> [Workout] { try await inner.fetchAll() }
    func fetch(id: UUID) async throws -> Workout? { try await inner.fetch(id: id) }
    func delete(id: UUID) async throws { try await inner.delete(id: id) }
    func saveSyncJob(_ syncJob: SyncJob) async throws { try await inner.saveSyncJob(syncJob) }
    func fetchSyncJob(id: UUID) async throws -> SyncJob? { try await inner.fetchSyncJob(id: id) }
    func fetchSyncJobs(workoutID: UUID) async throws -> [SyncJob] {
        try await inner.fetchSyncJobs(workoutID: workoutID)
    }
    func fetchLatestSyncJob(workoutID: UUID) async throws -> SyncJob? {
        try await inner.fetchLatestSyncJob(workoutID: workoutID)
    }
}

@Suite("SyncCoordinator — concurrency and reentrancy")
struct SyncCoordinatorConcurrencyTests {
    private typealias Fixtures = ScheduleWorkoutFixtures

    // MARK: - Same-workout serialization

    @Test("N concurrent scheduleWorkout calls for the SAME workout never interleave, each gets a distinct attemptCount")
    func concurrentScheduleSameWorkoutIsSerialized() async throws {
        let workout = Fixtures.makeWorkout()
        let repository = FakeWorkoutRepository(workouts: [workout])
        let overlapDetector = OverlapDetector()
        let watchSync = YieldingWatchSyncService(inner: FakeWatchSyncService(), overlapDetector: overlapDetector)
        let clock = FakeClock(currentDate: Fixtures.referenceDate)
        let coordinator = SyncCoordinator(repository: repository, watchSyncService: watchSync, clock: clock)

        let attemptCount = 8
        let results = try await withThrowingTaskGroup(of: SyncJob.self) { group in
            for _ in 0..<attemptCount {
                group.addTask { try await coordinator.scheduleWorkout(workoutID: workout.id) }
            }
            var collected: [SyncJob] = []
            for try await job in group { collected.append(job) }
            return collected
        }

        let overlapped = await overlapDetector.overlapDetected
        #expect(overlapped == false, "the per-workout lock let two attempts run inside schedule() at once")
        #expect(results.count == attemptCount)
        // Every concurrent caller reused the SAME SyncJob (stable plan id).
        #expect(Set(results.map(\.id)).count == 1)
        // A legal linear sequence: exactly one attempt got each number 1...N,
        // no duplicates and no gaps from a lost or double-counted update.
        #expect(Set(results.map(\.attemptCount)) == Set(1...attemptCount))
        let persisted = try await repository.fetchSyncJob(id: results[0].id)
        #expect(persisted?.attemptCount == attemptCount)
        #expect(persisted?.state == .synced)
    }

    // MARK: - Cross-workout independence

    @Test("scheduleWorkout for a different workout completes without waiting on another workout's in-flight sync")
    func differentWorkoutsProceedIndependently() async throws {
        let stalledWorkout = Fixtures.makeWorkout()
        let freeWorkout = Fixtures.makeWorkout()
        let repository = SafeConcurrentWorkoutRepository(
            inner: FakeWorkoutRepository(workouts: [stalledWorkout, freeWorkout])
        )
        let gated = GatedWatchSyncService(inner: FakeWatchSyncService(), gatedWorkoutID: stalledWorkout.id)
        let clock = FakeClock(currentDate: Fixtures.referenceDate)
        let coordinator = SyncCoordinator(repository: repository, watchSyncService: gated, clock: clock)

        let stalledTask = Task { try await coordinator.scheduleWorkout(workoutID: stalledWorkout.id) }
        // Deterministically wait until the stalled workout's attempt is
        // actually parked inside `schedule()`, holding its per-workout lock.
        await gated.waitUntilBlocked()

        let freeResult = try await coordinator.scheduleWorkout(workoutID: freeWorkout.id)
        #expect(freeResult.state == .synced, "an unrelated workout was blocked by another workout's in-flight sync")

        await gated.release()
        let stalledResult = try await stalledTask.value
        #expect(stalledResult.state == .synced)
    }

    // MARK: - Reentrancy

    @Test("a manual resend arriving while retryDueJobs is in-flight for the SAME workout queues FIFO, not dropped/cancelled")
    func reentrantScheduleDuringInFlightRetryQueuesFIFO() async throws {
        let workout = Fixtures.makeWorkout()
        let repository = SafeConcurrentWorkoutRepository(inner: FakeWorkoutRepository(workouts: [workout]))
        let fakeWatch = FakeWatchSyncService()
        // Starts ungated: the seed call below must not itself get stuck on
        // the gate with nothing yet waiting to release it.
        let gated = GatedWatchSyncService(inner: fakeWatch, gatedWorkoutID: workout.id, startArmed: false)
        let clock = FakeClock(currentDate: Fixtures.referenceDate)
        let coordinator = SyncCoordinator(
            repository: repository,
            watchSyncService: gated,
            clock: clock,
            maxAttempts: 5,
            backoffBaseSeconds: 10
        )

        // Seed a pending retry, ungated (the gate only matters for the retry
        // attempt we want to catch in-flight).
        fakeWatch.errorToThrow = WatchSyncError.underlying("busy")
        let first = try await coordinator.scheduleWorkout(workoutID: workout.id)
        #expect(first.attemptCount == 1)
        clock.advance(by: 10)
        fakeWatch.errorToThrow = nil

        await gated.arm()
        let retryTask = Task { try await coordinator.retryDueJobs() }
        await gated.waitUntilBlocked()

        // A manual resend arrives while the retry is actively parked inside
        // `schedule()`, holding the per-workout lock.
        let manualTask = Task { try await coordinator.scheduleWorkout(workoutID: workout.id) }

        // Give the manual task every opportunity to (incorrectly) race ahead;
        // it must still be waiting on the lock, not on the Watch call.
        await Task.yield()
        await Task.yield()
        #expect(fakeWatch.scheduleCalls.count == 1, "the manual call ran before the in-flight retry finished")

        await gated.disarm()
        await gated.release()

        let retryResult = try await retryTask.value
        #expect(retryResult.count == 1)
        #expect(retryResult.first?.attemptCount == 2)
        #expect(retryResult.first?.state == .synced)

        let manualResult = try await manualTask.value
        #expect(manualResult.state == .synced)
        #expect(manualResult.attemptCount == 3, "the manual resend was dropped/cancelled instead of queuing")

        #expect(fakeWatch.scheduleCalls.count == 3)
        let persisted = try await repository.fetchSyncJob(id: first.id)
        #expect(persisted?.attemptCount == 3)
        #expect(persisted?.state == .synced)
    }

    @Test("a manual resend during a pending (not-yet-due) backoff window supersedes it — the queued retry is cancelled")
    func manualScheduleDuringPendingBackoffCancelsQueuedRetry() async throws {
        let workout = Fixtures.makeWorkout()
        let repository = FakeWorkoutRepository(workouts: [workout])
        let watchSync = FakeWatchSyncService()
        watchSync.errorToThrow = WatchSyncError.underlying("busy")
        let clock = FakeClock(currentDate: Fixtures.referenceDate)
        let coordinator = SyncCoordinator(
            repository: repository,
            watchSyncService: watchSync,
            clock: clock,
            maxAttempts: 5,
            backoffBaseSeconds: 30
        )

        let first = try await coordinator.scheduleWorkout(workoutID: workout.id)
        guard case .failed(.transient) = first.state else {
            Issue.record("expected a transient failure to seed a pending retry")
            return
        }

        // Well before the 30s backoff window elapses, the user manually resends.
        clock.advance(by: 5)
        watchSync.errorToThrow = nil
        let manual = try await coordinator.scheduleWorkout(workoutID: workout.id)
        #expect(manual.state == .synced)
        #expect(manual.attemptCount == 2)

        // The superseded retry must not fire a redundant third attempt later.
        clock.advance(by: 1_000)
        let retried = try await coordinator.retryDueJobs()
        #expect(retried.isEmpty)
        #expect(watchSync.scheduleCalls.count == 2)
    }

    // MARK: - Reconciliation race

    @Test("Deleting a workout while reconcile is mid-pass does NOT resurrect its SyncJob (deletion-race fix)")
    func reconcileDeletionRaceDoesNotResurrectSyncJob() async throws {
        let workout = Fixtures.makeWorkout()
        let repository = FakeWorkoutRepository(workouts: [workout])
        let fakeWatch = FakeWatchSyncService()
        let gatedFetch = FetchGatedWatchSyncService(inner: fakeWatch)
        let clock = FakeClock(currentDate: Fixtures.referenceDate)
        let coordinator = SyncCoordinator(repository: repository, watchSyncService: gatedFetch, clock: clock)

        let synced = try await coordinator.scheduleWorkout(workoutID: workout.id)
        #expect(synced.state == .synced)

        // The user removed it directly on the Watch, so reconcile's second
        // phase (which we're about to stall) will find it missing.
        try await fakeWatch.remove(planID: synced.id)

        let reconcileTask = Task { try await coordinator.reconcile() }
        await gatedFetch.waitUntilBlocked()

        // Concurrently — strictly between reconcile's local-state snapshot
        // and its Watch-state read — the user deletes the workout locally.
        try await repository.delete(id: workout.id)
        #expect(try await repository.fetch(id: workout.id) == nil)
        #expect(try await repository.fetchSyncJob(id: synced.id) == nil)

        await gatedFetch.release()
        let report = try await reconcileTask.value

        // Fixed behavior: reconcile's second phase re-fetches the job
        // inside the per-workout lock and skips it when the cascade delete
        // already removed it — nothing is persisted, nothing resurrected,
        // and the job is not reported as marked-failed.
        #expect(report.markedFailed.isEmpty)
        let resurrected = try await repository.fetchSyncJob(id: synced.id)
        #expect(resurrected == nil, "a cascade-deleted SyncJob must stay deleted through a concurrent reconcile")
        #expect(try await repository.fetch(id: workout.id) == nil, "the workout itself stays deleted")
    }
}
