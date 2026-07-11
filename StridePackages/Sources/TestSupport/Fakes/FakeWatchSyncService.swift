import DomainKit
import Foundation

/// An in-memory `WatchSyncService` fake.
///
/// Every settable property is public (`isSupported`, `authorizationState`,
/// `maxScheduledWorkoutCount`, `scheduledWorkouts`) so a test can pin the
/// exact device/authorization scenario it needs, and every effectful call is
/// recorded (`scheduleCalls`, `removeCalls`, `requestAuthorizationCallCount`)
/// so tests can assert on what was invoked, matching WorkoutKit's own
/// call-then-verify-via-`scheduledWorkouts` pattern (RESEARCH-LOG §6).
/// `errorToThrow` makes every throwing method fail identically, for testing
/// the §7 failure/retry paths without a real Watch.
///
/// Not internally synchronized: intended for single-threaded test usage.
public final class FakeWatchSyncService: WatchSyncService, @unchecked Sendable {
    /// One recorded call to `schedule(planID:workout:at:)`.
    public struct ScheduleCall: Equatable, Sendable {
        /// The plan id the call was made with.
        public let planID: UUID
        /// The workout the call was made with.
        public let workout: Workout
        /// The date the call was made with, if any.
        public let date: Date?
    }

    /// The value returned for `isSupported`.
    public var isSupported: Bool
    /// The value returned for `authorizationState`, also updated by
    /// `requestAuthorization()` to `requestAuthorizationResult` (or
    /// `.authorized` by default).
    public var authorizationState: WatchAuthorizationState
    /// The value returned for `maxScheduledWorkoutCount`.
    public var maxScheduledWorkoutCount: Int
    /// When set, overrides the state `requestAuthorization()` transitions to
    /// and returns; defaults to `.authorized` when `nil`.
    public var requestAuthorizationResult: WatchAuthorizationState?
    /// When set, every throwing method throws this error instead of
    /// succeeding (calls are still recorded first).
    public var errorToThrow: Error?

    /// The current in-memory "scheduled on the Watch" list, mutated by
    /// `schedule`/`remove` and returned by `fetchScheduledWorkouts()`.
    public private(set) var scheduledWorkouts: [ScheduledWatchWorkout]
    /// Every `schedule` call, in call order.
    public private(set) var scheduleCalls: [ScheduleCall] = []
    /// Every `remove` call's `planID`, in call order.
    public private(set) var removeCalls: [UUID] = []
    /// Number of times `requestAuthorization()` has been called.
    public private(set) var requestAuthorizationCallCount = 0

    /// Creates a fake watch sync service. Defaults to supported + authorized
    /// so existing happy-path tests don't need to configure authorization
    /// explicitly; tests exercising the unsupported/unauthorized guard paths
    /// should override these defaults.
    public init(
        isSupported: Bool = true,
        authorizationState: WatchAuthorizationState = .authorized,
        maxScheduledWorkoutCount: Int = 50,
        scheduledWorkouts: [ScheduledWatchWorkout] = []
    ) {
        self.isSupported = isSupported
        self.authorizationState = authorizationState
        self.maxScheduledWorkoutCount = maxScheduledWorkoutCount
        self.scheduledWorkouts = scheduledWorkouts
    }

    public func requestAuthorization() async -> WatchAuthorizationState {
        requestAuthorizationCallCount += 1
        let result = requestAuthorizationResult ?? .authorized
        authorizationState = result
        return result
    }

    public func schedule(planID: UUID, workout: Workout, at date: Date?) async throws {
        // Recorded before any guard/error check, so tests can observe an
        // attempted call even when it goes on to fail — mirroring a real
        // adapter, which must check support/authorization itself since
        // WorkoutKit's own `schedule` call never throws (RESEARCH-LOG §6).
        scheduleCalls.append(ScheduleCall(planID: planID, workout: workout, date: date))
        if let errorToThrow {
            throw errorToThrow
        }
        guard isSupported else {
            throw WatchSyncError.unsupported
        }
        guard authorizationState == .authorized else {
            throw WatchSyncError.unauthorized(authorizationState)
        }
        scheduledWorkouts.removeAll { $0.id == planID }
        scheduledWorkouts.append(ScheduledWatchWorkout(id: planID, scheduledDate: date))
    }

    public func remove(planID: UUID) async throws {
        // Recorded before any guard/error check — see `schedule` above.
        removeCalls.append(planID)
        if let errorToThrow {
            throw errorToThrow
        }
        guard isSupported else {
            throw WatchSyncError.unsupported
        }
        guard authorizationState == .authorized else {
            throw WatchSyncError.unauthorized(authorizationState)
        }
        guard scheduledWorkouts.contains(where: { $0.id == planID }) else {
            throw WatchSyncError.notScheduled
        }
        scheduledWorkouts.removeAll { $0.id == planID }
    }

    public func fetchScheduledWorkouts() async throws -> [ScheduledWatchWorkout] {
        if let errorToThrow {
            throw errorToThrow
        }
        return scheduledWorkouts
    }
}
