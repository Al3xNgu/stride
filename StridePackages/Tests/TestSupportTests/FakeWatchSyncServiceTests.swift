import Testing
import Foundation
import DomainKit
import TestSupport

/// Call recording, schedule-replaces-not-duplicates semantics, authorization
/// state, and `errorToThrow` injection for `FakeWatchSyncService`.
@Suite("FakeWatchSyncService")
struct FakeWatchSyncServiceTests {
    private func makeWorkout(name: String = "Tempo Run") -> Workout {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        return Workout(name: name, createdAt: now, updatedAt: now)
    }

    // MARK: - Settable device/authorization state

    @Test("isSupported, authorizationState, and maxScheduledWorkoutCount reflect what a test sets")
    func settablePropertiesReflectConfiguration() {
        let service = FakeWatchSyncService(
            isSupported: false,
            authorizationState: .denied,
            maxScheduledWorkoutCount: 15
        )
        #expect(service.isSupported == false)
        #expect(service.authorizationState == .denied)
        #expect(service.maxScheduledWorkoutCount == 15)
    }

    @Test("requestAuthorization() defaults to returning and setting .authorized")
    func requestAuthorizationDefaultsToAuthorized() async {
        let service = FakeWatchSyncService(authorizationState: .notDetermined)
        let result = await service.requestAuthorization()
        #expect(result == .authorized)
        #expect(service.authorizationState == .authorized)
        #expect(service.requestAuthorizationCallCount == 1)
    }

    @Test("requestAuthorization() returns requestAuthorizationResult when overridden")
    func requestAuthorizationHonorsOverride() async {
        let service = FakeWatchSyncService(authorizationState: .notDetermined)
        service.requestAuthorizationResult = .denied
        let result = await service.requestAuthorization()
        #expect(result == .denied)
        #expect(service.authorizationState == .denied)
    }

    @Test("requestAuthorization() never throws, even with errorToThrow set")
    func requestAuthorizationNeverThrows() async {
        let service = FakeWatchSyncService()
        service.errorToThrow = WatchSyncError.unsupported
        let result = await service.requestAuthorization()
        #expect(result == .authorized)
    }

    // MARK: - schedule(planID:workout:at:)

    @Test("schedule(planID:workout:at:) records the call and adds a scheduled entry")
    func scheduleRecordsCallAndAddsEntry() async throws {
        let service = FakeWatchSyncService()
        let planID = UUID()
        let workout = makeWorkout()
        let date = Date(timeIntervalSince1970: 2_000_000_000)

        try await service.schedule(planID: planID, workout: workout, at: date)

        #expect(service.scheduleCalls.count == 1)
        #expect(service.scheduleCalls[0].planID == planID)
        #expect(service.scheduleCalls[0].workout == workout)
        #expect(service.scheduleCalls[0].date == date)

        let scheduled = try await service.fetchScheduledWorkouts()
        #expect(scheduled == [ScheduledWatchWorkout(id: planID, scheduledDate: date)])
    }

    @Test("Re-scheduling the same planID REPLACES the entry, not duplicates it")
    func rescheduleSamePlanIDReplacesNotDuplicates() async throws {
        let service = FakeWatchSyncService()
        let planID = UUID()
        let firstDate = Date(timeIntervalSince1970: 1_000)
        let secondDate = Date(timeIntervalSince1970: 2_000)

        try await service.schedule(planID: planID, workout: makeWorkout(name: "First"), at: firstDate)
        try await service.schedule(planID: planID, workout: makeWorkout(name: "Second"), at: secondDate)

        let scheduled = try await service.fetchScheduledWorkouts()
        #expect(scheduled.count == 1)
        #expect(scheduled.first?.id == planID)
        #expect(scheduled.first?.scheduledDate == secondDate)
        // Both attempts are still recorded in scheduleCalls for call-order assertions.
        #expect(service.scheduleCalls.count == 2)
    }

    @Test("Scheduling a different planID adds a second, independent entry")
    func scheduleDifferentPlanIDsCoexist() async throws {
        let service = FakeWatchSyncService()
        let firstPlanID = UUID()
        let secondPlanID = UUID()
        try await service.schedule(planID: firstPlanID, workout: makeWorkout(), at: nil)
        try await service.schedule(planID: secondPlanID, workout: makeWorkout(), at: nil)

        let scheduled = try await service.fetchScheduledWorkouts()
        #expect(Set(scheduled.map(\.id)) == Set([firstPlanID, secondPlanID]))
    }

    @Test("schedule(planID:workout:at:) with nil date schedules with no explicit date")
    func scheduleWithNilDate() async throws {
        let service = FakeWatchSyncService()
        let planID = UUID()
        try await service.schedule(planID: planID, workout: makeWorkout(), at: nil)
        let scheduled = try await service.fetchScheduledWorkouts()
        #expect(scheduled.first?.scheduledDate == nil)
    }

    // MARK: - remove(planID:)

    @Test("remove(planID:) removes a previously-scheduled entry and records the call")
    func removeRemovesScheduledEntry() async throws {
        let service = FakeWatchSyncService()
        let planID = UUID()
        try await service.schedule(planID: planID, workout: makeWorkout(), at: nil)
        try await service.remove(planID: planID)

        #expect(service.removeCalls == [planID])
        let scheduled = try await service.fetchScheduledWorkouts()
        #expect(scheduled.isEmpty)
    }

    @Test("remove(planID:) for a planID that was never scheduled throws notScheduled")
    func removeUnscheduledPlanIDThrows() async {
        let service = FakeWatchSyncService()
        let planID = UUID()
        await #expect(throws: WatchSyncError.notScheduled) {
            try await service.remove(planID: planID)
        }
        // The attempted call is still recorded even though it failed.
        #expect(service.removeCalls == [planID])
    }

    // MARK: - Auto-guards (isSupported / authorizationState)

    @Test("schedule(planID:workout:at:) throws .unsupported when isSupported is false, but still records the call")
    func scheduleThrowsUnsupportedWhenNotSupported() async {
        let service = FakeWatchSyncService(isSupported: false)
        let planID = UUID()
        await #expect(throws: WatchSyncError.unsupported) {
            try await service.schedule(planID: planID, workout: makeWorkout(), at: nil)
        }
        #expect(service.scheduleCalls.map(\.planID) == [planID])
        let scheduled = try? await service.fetchScheduledWorkouts()
        #expect(scheduled?.isEmpty == true)
    }

    @Test("schedule(planID:workout:at:) throws .unauthorized when not authorized, but still records the call")
    func scheduleThrowsUnauthorizedWhenNotAuthorized() async {
        let service = FakeWatchSyncService(authorizationState: .denied)
        let planID = UUID()
        await #expect(throws: WatchSyncError.unauthorized(.denied)) {
            try await service.schedule(planID: planID, workout: makeWorkout(), at: nil)
        }
        #expect(service.scheduleCalls.map(\.planID) == [planID])
    }

    @Test("remove(planID:) throws .unsupported when isSupported is false, but still records the call")
    func removeThrowsUnsupportedWhenNotSupported() async throws {
        let service = FakeWatchSyncService()
        let planID = UUID()
        try await service.schedule(planID: planID, workout: makeWorkout(), at: nil)
        service.isSupported = false

        await #expect(throws: WatchSyncError.unsupported) {
            try await service.remove(planID: planID)
        }
        #expect(service.removeCalls == [planID])
    }

    @Test("remove(planID:) throws .unauthorized when not authorized, but still records the call")
    func removeThrowsUnauthorizedWhenNotAuthorized() async throws {
        let service = FakeWatchSyncService()
        let planID = UUID()
        try await service.schedule(planID: planID, workout: makeWorkout(), at: nil)
        service.authorizationState = .restricted

        await #expect(throws: WatchSyncError.unauthorized(.restricted)) {
            try await service.remove(planID: planID)
        }
        #expect(service.removeCalls == [planID])
    }

    // MARK: - Call order across schedule/remove

    @Test("schedule and remove calls are recorded independently, each in its own call order")
    func scheduleAndRemoveCallsRecordedInOrder() async throws {
        let service = FakeWatchSyncService()
        let planA = UUID()
        let planB = UUID()
        try await service.schedule(planID: planA, workout: makeWorkout(), at: nil)
        try await service.schedule(planID: planB, workout: makeWorkout(), at: nil)
        try await service.remove(planID: planA)

        #expect(service.scheduleCalls.map(\.planID) == [planA, planB])
        #expect(service.removeCalls == [planA])
    }

    // MARK: - errorToThrow

    @Test("errorToThrow makes schedule/remove/fetchScheduledWorkouts throw the injected error")
    func errorToThrowAffectsThrowingMethods() async {
        let service = FakeWatchSyncService()
        let planID = UUID()
        service.errorToThrow = WatchSyncError.watchNotPaired

        await #expect(throws: WatchSyncError.watchNotPaired) {
            try await service.schedule(planID: planID, workout: makeWorkout(), at: nil)
        }
        await #expect(throws: WatchSyncError.watchNotPaired) {
            try await service.remove(planID: planID)
        }
        await #expect(throws: WatchSyncError.watchNotPaired) {
            _ = try await service.fetchScheduledWorkouts()
        }
    }

    @Test("A failed schedule() call does not mutate scheduledWorkouts, but is still recorded")
    func failedScheduleDoesNotMutateState() async {
        let service = FakeWatchSyncService()
        let planID = UUID()
        service.errorToThrow = WatchSyncError.invalidComposition(reason: "zero-rep segment")

        await #expect(throws: WatchSyncError.invalidComposition(reason: "zero-rep segment")) {
            try await service.schedule(planID: planID, workout: makeWorkout(), at: nil)
        }
        #expect(service.scheduleCalls.count == 1)

        service.errorToThrow = nil
        let scheduled = try? await service.fetchScheduledWorkouts()
        #expect(scheduled?.isEmpty == true)
    }

    @Test("Clearing errorToThrow restores normal schedule()/remove() behavior")
    func clearingErrorRestoresBehavior() async throws {
        let service = FakeWatchSyncService()
        let planID = UUID()
        service.errorToThrow = WatchSyncError.unsupported
        service.errorToThrow = nil

        try await service.schedule(planID: planID, workout: makeWorkout(), at: nil)
        let scheduled = try await service.fetchScheduledWorkouts()
        #expect(scheduled.map(\.id) == [planID])
    }
}
