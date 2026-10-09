#if canImport(HealthKit)
import DomainKit
import HealthKit
import Testing
@testable import DataKit

@Suite("HealthKitRunBackgroundDelivery — availability guard")
struct HealthKitRunBackgroundDeliveryTests {
    @MainActor
    @Test("Registration reports unavailable when HealthKit data is unavailable")
    func registrationThrowsWhenUnavailable() async {
        guard !HKHealthStore.isHealthDataAvailable() else { return }
        let delivery = HealthKitRunBackgroundDelivery(onUpdate: { _ in })
        await #expect(throws: RunIngestionDeliveryError.notAvailable) {
            try await delivery.start()
        }
    }
}
#endif
