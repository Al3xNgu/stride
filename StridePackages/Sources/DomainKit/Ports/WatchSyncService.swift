import Foundation

/// Watch-scheduling authorization state.
///
/// Mirrors `WorkoutScheduler.AuthorizationState` case-for-case (verified in
/// `docs/RESEARCH-LOG.md` 2026-07-06 §5: `notDetermined`, `restricted`,
/// `denied`, `authorized`) so the adapter's mapping is a trivial 1:1 switch,
/// while keeping WorkoutKit's type out of DomainKit entirely. This is a
/// separate authorization domain from HealthKit's (RESEARCH-LOG §5/§Task 0.6
/// §1) — a user can authorize one without the other.
public enum WatchAuthorizationState: Equatable, Hashable, Sendable {
    /// The user has not yet been asked.
    case notDetermined
    /// Authorization is restricted (e.g. parental controls) and cannot be
    /// changed by the user directly.
    case restricted
    /// The user explicitly denied authorization. There is no in-API
    /// re-prompt (RESEARCH-LOG §5) — recovery requires the user to
    /// re-enable access in the Watch app on iPhone.
    case denied
    /// The user has granted authorization; scheduling is permitted.
    case authorized
}

/// A typed error surfaced by a `WatchSyncService` implementation.
///
/// Shaped from the §7 sync-state-machine failure states
/// (`docs/ARCHITECTURE.md` §7's `SyncFailureReason`-adjacent cases) and the
/// concrete failure surface verified in `docs/RESEARCH-LOG.md`: WorkoutKit's
/// own `schedule`/`remove` calls are non-throwing (RESEARCH-LOG §6), so an
/// adapter must proactively check authorization/support and translate the
/// documented-but-unverified-call-site `StateError` cases itself, which is
/// why every case below is produced by the *adapter's* own guard logic, not
/// by catching a WorkoutKit throw.
public enum WatchSyncError: Error, Equatable, Hashable, Sendable {
    /// Watch-scheduling authorization has not been granted; carries the
    /// current state so callers can distinguish "ask" (`.notDetermined`)
    /// from "direct the user to Settings" (`.denied`/`.restricted`).
    case unauthorized(WatchAuthorizationState)
    /// This device/OS does not support Watch scheduling
    /// (`WorkoutScheduler.isSupported == false` — e.g. no paired Watch,
    /// or running in Simulator per RESEARCH-LOG Task 0.6 §4).
    case unsupported
    /// No scheduled entry exists for the given plan id (e.g. `remove` called
    /// for a plan that was never scheduled or was already removed).
    case notScheduled
    /// No Apple Watch is currently paired
    /// (`WorkoutKit.StateError.watchNotPaired`, RESEARCH-LOG §6 — the exact
    /// call site that throws this is `unknown-needs-hardware`, so an adapter
    /// may also need to detect this proactively).
    case watchNotPaired
    /// The Workout app is not installed on the paired Watch
    /// (`WorkoutKit.StateError.workoutApplicationNotInstalled`, RESEARCH-LOG §6).
    case workoutApplicationNotInstalled
    /// The domain `Workout` could not be mapped to a valid WorkoutKit
    /// composition (e.g. a non-positive goal value, which traps rather than
    /// throws inside WorkoutKit itself per RESEARCH-LOG's 2026-07-10 "spike
    /// crash root-caused" entry — the mapper MUST catch this before it ever
    /// reaches `CustomWorkout.init`).
    case invalidComposition(reason: String)
    /// An unexpected underlying failure, with a human-readable description.
    case underlying(String)
}

/// One entry currently scheduled on the paired Apple Watch, as reported by
/// the adapter for §7 foreground reconciliation.
///
/// Mirrors the shape of `WorkoutKit.ScheduledWorkoutPlan` (RESEARCH-LOG §6)
/// without exposing `WorkoutPlan`/`DateComponents`: `id` is the stable plan
/// identifier the caller supplied to `schedule(planID:workout:at:)`. Diffing
/// against local `SyncJob.planIdentifier` values requires a conversion first:
/// `SyncJob.planIdentifier` is stored as an opaque `String?`, so callers must
/// parse it back to a `UUID` (`UUID(uuidString:)`, which returns `nil` for a
/// malformed/foreign string) before comparing it to this `id`.
public struct ScheduledWatchWorkout: Identifiable, Equatable, Hashable, Sendable {
    /// The plan identifier this entry was scheduled under.
    public var id: UUID
    /// The date/time this entry is scheduled for, if any.
    public var scheduledDate: Date?
    /// Whether the Watch has reported this scheduled workout as completed
    /// (mirrors `ScheduledWorkoutPlan.complete`).
    public var isComplete: Bool

    /// Creates a scheduled-watch-workout reconciliation entry.
    public init(id: UUID, scheduledDate: Date? = nil, isComplete: Bool = false) {
        self.id = id
        self.scheduledDate = scheduledDate
        self.isComplete = isComplete
    }
}

/// The domain-facing abstraction over WorkoutKit scheduling
/// (`docs/ARCHITECTURE.md` §3.3/§6/§7; concrete surface verified in
/// `docs/RESEARCH-LOG.md` 2026-07-06/2026-07-10 entries).
///
/// No WorkoutKit type (`WorkoutPlan`, `WorkoutScheduler`, `CustomWorkout`,
/// `DateComponents`, ...) appears in this protocol; the `DataKit` adapter
/// owns the domain `Workout` -> `CustomWorkout` mapping and the
/// `Date` -> `DateComponents` conversion. `HARDWARE-VERIFY:` this entire
/// port's real (`DataKit`) implementation — WorkoutKit scheduling cannot be
/// exercised in a simulator or in unit tests (RESEARCH-LOG Task 0.6 §4);
/// only the mapper logic and this protocol's contract are unit-testable via
/// `TestSupport.FakeWatchSyncService`.
public protocol WatchSyncService: Sendable {
    /// Whether this device/OS supports scheduling to a paired Watch
    /// (`WorkoutScheduler.isSupported`). Gate the entire "Send to Watch" flow
    /// on this; `false` on Simulator and unpaired devices.
    var isSupported: Bool { get async }

    /// The current Watch-scheduling authorization state.
    var authorizationState: WatchAuthorizationState { get async }

    /// The maximum number of workouts that may be scheduled at once, as
    /// reported by the adapter at runtime.
    ///
    /// MUST be read from the underlying framework, never hardcoded: the
    /// value observed on device (50) does not match the number quoted at
    /// WWDC23 (15) — see RESEARCH-LOG's 2026-07-10 spike findings, item 1.
    var maxScheduledWorkoutCount: Int { get async }

    /// Requests Watch-scheduling authorization, returning the resulting
    /// state. Never throws (mirrors `WorkoutScheduler.requestAuthorization()`
    /// exactly); a `.denied` result has no in-API re-prompt — the caller must
    /// direct the user to the Watch app on iPhone (RESEARCH-LOG §5).
    func requestAuthorization() async -> WatchAuthorizationState

    /// Schedules `workout` under the stable identity `planID`, optionally at
    /// a specific `date` (`nil` schedules for the next available slot).
    ///
    /// Re-scheduling the same `planID` REPLACES the previously-scheduled
    /// entry rather than duplicating it — confirmed on device
    /// (RESEARCH-LOG 2026-07-10, item 6) — so the §7 "stale re-send" flow is
    /// a single call reusing the existing `planID`, not a remove-then-schedule
    /// pair (though an adapter may still remove-then-schedule defensively if
    /// `planID` itself changes).
    func schedule(planID: UUID, workout: Workout, at date: Date?) async throws

    /// Removes the scheduled entry for `planID`, if any. Throws
    /// `WatchSyncError.notScheduled` if no such entry exists.
    func remove(planID: UUID) async throws

    /// Lists every entry currently scheduled on the paired Watch, for §7
    /// foreground reconciliation against local `SyncJob`s.
    func fetchScheduledWorkouts() async throws -> [ScheduledWatchWorkout]
}
