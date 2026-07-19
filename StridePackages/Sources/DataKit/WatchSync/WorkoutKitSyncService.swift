#if canImport(WorkoutKit)
import DomainKit
import Foundation
import WorkoutKit

/// The real `WatchSyncService` adapter, backed by WorkoutKit's
/// `WorkoutScheduler` (`docs/ARCHITECTURE.md` §3.3/§6/§7; concrete surface
/// verified in `docs/RESEARCH-LOG.md` 2026-07-06/2026-07-10 entries). This is
/// the only type in `DataKit` that talks to `WorkoutScheduler` directly —
/// everything above it (domain use cases, `SyncCoordinator`) only ever sees
/// the `WatchSyncService` protocol (CLAUDE.md rule 1/5).
///
/// HARDWARE-VERIFY: none of `WorkoutScheduler`'s behavior can be exercised in
/// Simulator or unit tests (RESEARCH-LOG Task 0.6 §4) — `isSupported` is
/// reported `false` in the environments this package's tests run in, so
/// every method below is compile-verified only; the mapper
/// (`WatchCompositionPlanner`/`WorkoutKitCompositionMapper`) and this
/// protocol's contract are what `DataKitTests`/`TestSupport.FakeWatchSyncService`
/// actually exercise.
@available(iOS 17.0, macOS 15.0, *)
public struct WorkoutKitSyncService: WatchSyncService {
    /// Creates the real WorkoutKit-backed sync service.
    public init() {}

    public var isSupported: Bool {
        get async {
            WorkoutScheduler.isSupported
        }
    }

    public var authorizationState: WatchAuthorizationState {
        get async {
            // HARDWARE-VERIFY: unconfirmed exact value in Simulator/no-paired-watch
            // (RESEARCH-LOG Task 0.6 §4).
            Self.map(await WorkoutScheduler.shared.authorizationState)
        }
    }

    public var maxScheduledWorkoutCount: Int {
        get async {
            // Read at runtime, never hardcoded: device-observed value is 50,
            // not the 15 quoted at WWDC23 (RESEARCH-LOG 2026-07-10 item 1).
            WorkoutScheduler.maxAllowedScheduledWorkoutCount
        }
    }

    public func requestAuthorization() async -> WatchAuthorizationState {
        // HARDWARE-VERIFY: denied-state recovery path is untested on-device
        // (RESEARCH-LOG HARDWARE-VERIFY item 6) — no in-API re-prompt exists;
        // callers must direct the user to the Watch app on iPhone themselves.
        Self.map(await WorkoutScheduler.shared.requestAuthorization())
    }

    public func schedule(planID: UUID, workout: Workout, at date: Date?) async throws {
        guard WorkoutScheduler.isSupported else {
            throw WatchSyncError.unsupported
        }
        let authorization = await WorkoutScheduler.shared.authorizationState
        guard authorization == .authorized else {
            throw WatchSyncError.unauthorized(Self.map(authorization))
        }

        let plan = try WorkoutKitCompositionMapper.workoutPlan(for: workout, planID: planID)
        let components = Self.dateComponents(from: date)

        // HARDWARE-VERIFY: `schedule` is async and non-throwing with no
        // result (RESEARCH-LOG §6) — `StateError.watchNotPaired` /
        // `.workoutApplicationNotInstalled` are documented on `WorkoutKit`
        // but their exact throw site is unverified (schedule itself cannot
        // throw them), so this adapter has no way to detect an unpaired
        // watch beyond the `isSupported`/`authorizationState` guards above.
        // Re-scheduling the same `planID` REPLACES the previous entry rather
        // than duplicating it (RESEARCH-LOG 2026-07-10 item 6), so a single
        // call reusing `planID` is sufficient for the §7 "stale re-send" flow.
        await WorkoutScheduler.shared.schedule(plan, at: components)
    }

    public func remove(planID: UUID) async throws {
        guard WorkoutScheduler.isSupported else {
            throw WatchSyncError.unsupported
        }
        let scheduled = await WorkoutScheduler.shared.scheduledWorkouts
        guard let entry = scheduled.first(where: { $0.plan.id == planID }) else {
            throw WatchSyncError.notScheduled
        }
        // `remove(_:at:)` requires the exact `DateComponents` the entry was
        // scheduled under (RESEARCH-LOG §6); reading it back from
        // `scheduledWorkouts` avoids the caller needing to track it itself.
        await WorkoutScheduler.shared.remove(entry.plan, at: entry.date)
    }

    public func fetchScheduledWorkouts() async throws -> [ScheduledWatchWorkout] {
        guard WorkoutScheduler.isSupported else {
            throw WatchSyncError.unsupported
        }
        let scheduled = await WorkoutScheduler.shared.scheduledWorkouts
        return scheduled.map { entry in
            ScheduledWatchWorkout(
                id: entry.plan.id,
                scheduledDate: Calendar.current.date(from: entry.date),
                isComplete: entry.complete
            )
        }
    }

    private static func map(_ state: WorkoutScheduler.AuthorizationState) -> WatchAuthorizationState {
        switch state {
        case .notDetermined:
            return .notDetermined
        case .restricted:
            return .restricted
        case .denied:
            return .denied
        case .authorized:
            return .authorized
        @unknown default:
            // `WorkoutScheduler.AuthorizationState` is a resilient (library
            // -evolution) framework enum, so a future case must be handled
            // defensively. Mapping to `.denied` is the conservative choice:
            // it never silently treats an unrecognized state as authorized.
            return .denied
        }
    }

    /// Converts the port's `Date?` into the `DateComponents` WorkoutKit's
    /// `schedule(_:at:)` requires.
    ///
    /// HARDWARE-VERIFY: `WorkoutScheduler.schedule(_:at:)` has no documented
    /// "any time"/immediate-scheduling sentinel (RESEARCH-LOG §6); the
    /// port's `date == nil` ("next available slot") is interpreted here as
    /// "now" (the current date/time). This interpretation is unconfirmed on
    /// device — revisit once HARDWARE-VERIFY items 2/3 (scheduling window,
    /// replace-vs-duplicate) are exercised for an immediate (undated) send.
    private static func dateComponents(from date: Date?, calendar: Calendar = .current) -> DateComponents {
        calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date ?? Date())
    }
}
#endif
