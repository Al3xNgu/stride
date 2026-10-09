#if canImport(HealthKit)
import DomainKit
import Foundation
import HealthKit

/// Registers an observer synchronously at application launch, including
/// background launches without a SwiftUI scene. Only DataKit touches HealthKit.
@MainActor
public final class HealthKitRunBackgroundDelivery: RunIngestionDelivery {
    private let healthStore: HKHealthStore
    private let onUpdate: @Sendable (RunIngestionDeliveryError?) async -> Void
    private var observer: HKObserverQuery?
    private var registration: Task<Void, Error>?
    private var isEnabled = false

    /// Creates a registrar. The callback receives observer failures as typed
    /// errors, and must return after processing to acknowledge HealthKit delivery.
    public init(
        healthStore: HKHealthStore = HKHealthStore(),
        onUpdate: @escaping @Sendable (RunIngestionDeliveryError?) async -> Void
    ) {
        self.healthStore = healthStore
        self.onUpdate = onUpdate
    }

    /// Installs exactly one observer before launch returns. Does not prompt.
    public func observe() throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw RunIngestionDeliveryError.notAvailable
        }
        guard observer == nil else { return }
        let query = HKObserverQuery(
            sampleType: HKObjectType.workoutType(),
            predicate: HKQuery.predicateForWorkouts(with: .running)
        ) { [onUpdate] _, completionHandler, error in
            let failure = error.map { RunIngestionDeliveryError.underlying($0.localizedDescription) }
            Task {
                defer { completionHandler() }
                await onUpdate(failure)
            }
        }
        observer = query
        healthStore.execute(query)
    }

    /// Enables background wake-ups. Concurrent calls share one registration.
    /// HARDWARE-VERIFY: delivery frequency and suspended/cold-launch behavior
    /// require a signed iPhone run; foreground fetching remains the fallback.
    public func start() async throws {
        try observe()
        guard !isEnabled else { return }
        if let registration {
            return try await registration.value
        }
        let task = Task { [healthStore] in
            do {
                try await healthStore.enableBackgroundDelivery(for: HKObjectType.workoutType(), frequency: .immediate)
            } catch {
                throw RunIngestionDeliveryError.registrationFailed(String(describing: error))
            }
        }
        registration = task
        defer { registration = nil }
        try await task.value
        isEnabled = true
    }
}
#endif
