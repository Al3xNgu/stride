#if canImport(HealthKit)
import DomainKit
import Testing
import Foundation
import HealthKit
@testable import DataKit

/// Exercises `HealthKitRunHistoryRepository`'s real `HKHealthStore`-backed
/// guard clauses. This runs for real (not against a fake) because HealthKit's
/// framework module is present on this package's macOS 14+ target too, and
/// `HKHealthStore.isHealthDataAvailable()` reliably reports `false` there
/// (confirmed by direct execution during task 1.11) -- unlike
/// `WorkoutKitSyncService`, whose `WorkoutScheduler.isSupported` behavior is
/// simulator/hardware-only, this adapter's availability guard is genuinely
/// testable in CI.
@Suite("HealthKitRunHistoryRepository — availability guard")
struct HealthKitAvailabilityGuardTests {
    @Test("requestAuthorizationIfNeeded throws .notAvailable when HealthKit data is unavailable on this platform")
    func requestAuthorizationThrowsWhenUnavailable() async {
        guard !HKHealthStore.isHealthDataAvailable() else { return }
        let repository = HealthKitRunHistoryRepository()
        await #expect(throws: RunIngestionSourceError.notAvailable) {
            try await repository.requestAuthorizationIfNeeded()
        }
    }

    @Test("fetchRunningWorkouts throws .notAvailable when HealthKit data is unavailable on this platform")
    func fetchRunningWorkoutsThrowsWhenUnavailable() async {
        guard !HKHealthStore.isHealthDataAvailable() else { return }
        let repository = HealthKitRunHistoryRepository()
        await #expect(throws: RunIngestionSourceError.notAvailable) {
            _ = try await repository.fetchRunningWorkouts(since: nil, splitDistanceMeters: SplitDerivation.kilometerMeters)
        }
    }
}
#endif
