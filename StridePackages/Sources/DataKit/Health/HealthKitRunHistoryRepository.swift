#if canImport(HealthKit)
import DomainKit
import Foundation
import HealthKit

/// The real `RunIngestionSource` adapter, backed by `HKHealthStore`'s
/// modern async descriptor surface (`docs/ARCHITECTURE.md` §3.4/§6/§8;
/// concrete surface verified in `docs/RESEARCH-LOG.md` 2026-07-19 Task 1.10 —
/// every symbol below was re-confirmed directly against the shipped
/// `HealthKit.swiftinterface`/headers and independently type-checked with
/// `swiftc -typecheck` against both the iphonesimulator and macosx SDKs
/// during this task, not merely paraphrased from the log). This is the only
/// type in `DataKit` that talks to `HKHealthStore` directly for run
/// ingestion — everything above it only ever sees the DomainKit
/// `RunIngestionSource` port (CLAUDE.md rule 1/5).
///
/// Unlike `WorkoutKit` (`WorkoutKitSyncService`), HealthKit's framework
/// module — and every API this type calls — is present in the SDK for both
/// this package's iOS 17+ and macOS 14+ deployment targets, so no additional
/// `@available` gate beyond the package's own floor is required here. Health
/// *data* itself is never actually available on macOS
/// (`HKHealthStore.isHealthDataAvailable()` reliably returns `false` there,
/// confirmed by direct execution during this task) — every method below
/// checks that first and throws `.notAvailable` rather than assuming iOS.
/// This also means `DataKitTests` can and does exercise this type's guard
/// clauses for real on macOS, unlike `WorkoutKitSyncService`'s
/// simulator-only surface.
///
/// HARDWARE-VERIFY: authorization-denial opacity, background-delivery
/// cadence, `workoutPlan` round-trip, and real Apple Watch sample
/// granularity are all unconfirmed on-device per RESEARCH-LOG's
/// hardware-verify list — see the doc comments on the individual methods
/// below and on `SplitDerivation` for the specific unverifiable claims.
public struct HealthKitRunHistoryRepository: RunIngestionSource, HealthPermissionPriming {
    private let healthStore: HKHealthStore

    /// Creates the real HealthKit-backed ingestion source.
    public init(healthStore: HKHealthStore = HKHealthStore()) {
        self.healthStore = healthStore
    }

    private static var workoutType: HKObjectType { HKObjectType.workoutType() }
    private static var distanceType: HKQuantityType { HKQuantityType(.distanceWalkingRunning) }
    private static var heartRateType: HKQuantityType { HKQuantityType(.heartRate) }
    private static var readTypes: Set<HKObjectType> { [workoutType, distanceType, heartRateType] }
    /// `HKUnit(from: "count/min")` is the verified unit string for
    /// beats-per-minute heart-rate quantities (RESEARCH-LOG 2026-07-19 §4).
    private static var beatsPerMinute: HKUnit { HKUnit(from: "count/min") }

    /// The current HealthKit read-request status, mapped at the DataKit
    /// boundary so FeatureSettings never imports HealthKit.
    public var status: HealthPermissionStatus {
        get async throws {
            guard HKHealthStore.isHealthDataAvailable() else {
                throw HealthPermissionPrimingError.unavailable
            }
            do {
                let requestStatus = try await healthStore.statusForAuthorizationRequest(
                    toShare: [], read: Self.readTypes
                )
                switch requestStatus {
                case .unknown:
                    return .unknown
                case .shouldRequest:
                    return .shouldRequest
                case .unnecessary:
                    return .unnecessary
                @unknown default:
                    return .unknown
                }
            } catch {
                throw HealthPermissionPrimingError.underlying(String(describing: error))
            }
        }
    }

    /// Requests read-only HealthKit access and returns the resulting request
    /// status. A successful request means the prompt completed; HealthKit
    /// intentionally does not disclose whether read access was granted.
    public func requestAccess() async throws -> HealthPermissionStatus {
        do {
            try await requestAuthorizationIfNeeded()
            return try await status
        } catch RunIngestionSourceError.notAvailable {
            throw HealthPermissionPrimingError.unavailable
        } catch RunIngestionSourceError.authorizationFailed(let description) {
            throw HealthPermissionPrimingError.requestFailed(description)
        } catch RunIngestionSourceError.underlying(let description) {
            throw HealthPermissionPrimingError.underlying(description)
        } catch {
            throw HealthPermissionPrimingError.underlying(String(describing: error))
        }
    }

    public func requestAuthorizationIfNeeded() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw RunIngestionSourceError.notAvailable
        }

        // HARDWARE-VERIFY: `.unnecessary` means "already asked" but
        // HealthKit gives no way to tell whether that prior request was
        // granted or denied for reads (RESEARCH-LOG §3) -- empty results
        // do not prove denial and must never be presented as such.
        let status: HKAuthorizationRequestStatus
        do {
            status = try await healthStore.statusForAuthorizationRequest(toShare: [], read: Self.readTypes)
        } catch {
            throw RunIngestionSourceError.underlying("\(error)")
        }
        guard status == .shouldRequest else { return }

        do {
            try await healthStore.requestAuthorization(toShare: [], read: Self.readTypes)
        } catch {
            throw RunIngestionSourceError.authorizationFailed("\(error)")
        }
    }

    public func fetchRunningWorkouts(
        since anchorData: Data?,
        splitDistanceMeters: Double
    ) async throws -> RunIngestionFetchResult {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw RunIngestionSourceError.notAvailable
        }

        let anchor = try Self.decodeAnchor(anchorData)
        let predicate = HKSamplePredicate.workout(HKQuery.predicateForWorkouts(with: .running))
        let descriptor = HKAnchoredObjectQueryDescriptor(predicates: [predicate], anchor: anchor)

        let result: HKAnchoredObjectQueryDescriptor<HKWorkout>.Result
        do {
            result = try await descriptor.result(for: healthStore)
        } catch {
            throw RunIngestionSourceError.underlying("\(error)")
        }

        var ingestedRuns: [IngestedRun] = []
        for workout in result.addedSamples {
            let run = Self.project(workout)
            let series = try await distanceSeries(for: workout)
            let splits = SplitDerivation.deriveSplits(
                from: series,
                runID: workout.uuid,
                splitDistanceMeters: splitDistanceMeters
            )
            ingestedRuns.append(IngestedRun(run: run, splits: splits))
        }

        let deletedIDs = result.deletedObjects.map(\.uuid)
        let newAnchorData = try Self.encodeAnchor(result.newAnchor)

        return RunIngestionFetchResult(
            batch: IngestionBatch(runs: ingestedRuns, deletedRunIDs: deletedIDs),
            newAnchor: newAnchorData
        )
    }

    // MARK: - Per-workout projection

    /// Builds a `CompletedRun` from workout-level statistics
    /// (`HKWorkout.statistics(for:)`, iOS 16+/macOS 13+ — RESEARCH-LOG §4:
    /// "Avg HR for run summary = `workout.statisticsForType(HKQuantityType(.heartRate))?.averageQuantity()`",
    /// confirmed as `statistics(for:)` under Swift by direct SDK
    /// type-checking during this task), never the deprecated
    /// `HKWorkout.totalDistance`/`totalEnergyBurned` properties.
    private static func project(_ workout: HKWorkout) -> CompletedRun {
        let distanceStats = workout.statistics(for: distanceType)
        let heartRateStats = workout.statistics(for: heartRateType)

        let input = HealthKitRunProjectionInput(
            workoutUUID: workout.uuid,
            startDate: workout.startDate,
            totalDistanceMeters: distanceStats?.sumQuantity()?.doubleValue(for: .meter()) ?? 0,
            totalDurationSeconds: workout.duration,
            averageHeartRateBPM: heartRateStats?.averageQuantity()?.doubleValue(for: beatsPerMinute),
            maxHeartRateBPM: heartRateStats?.maximumQuantity()?.doubleValue(for: beatsPerMinute),
            sourceName: workout.sourceRevision.source.name
        )
        return CompletedRunProjector.project(input)
    }

    // MARK: - Split series

    /// Fetches the workout's cumulative-distance series
    /// (`HKQuantitySeriesSampleQueryDescriptor`, scoped to `workout` via
    /// `HKQuery.predicateForObjects(from:)` — RESEARCH-LOG §4) and converts
    /// it into the pure `DistanceSeriesPoint`s `SplitDerivation` consumes.
    private func distanceSeries(for workout: HKWorkout) async throws -> [DistanceSeriesPoint] {
        let seriesPredicate = HKSamplePredicate.quantitySample(
            type: Self.distanceType,
            predicate: HKQuery.predicateForObjects(from: workout)
        )
        let seriesDescriptor = HKQuantitySeriesSampleQueryDescriptor(predicate: seriesPredicate)

        var points: [DistanceSeriesPoint] = []
        do {
            for try await entry in seriesDescriptor.results(for: healthStore) {
                points.append(
                    DistanceSeriesPoint(
                        startDate: entry.dateInterval.start,
                        endDate: entry.dateInterval.end,
                        deltaMeters: entry.quantity.doubleValue(for: .meter())
                    )
                )
            }
        } catch {
            throw RunIngestionSourceError.underlying("\(error)")
        }
        return points
    }

    // MARK: - Anchor archival

    /// Decodes a caller-supplied anchor blob (`nil` = initial fetch).
    /// `HKQueryAnchor : NSSecureCoding` — round-tripped via
    /// `NSKeyedUnarchiver`/`NSKeyedArchiver` per RESEARCH-LOG §1.
    static func decodeAnchor(_ data: Data?) throws -> HKQueryAnchor? {
        guard let data else { return nil }
        do {
            guard let anchor = try NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data) else {
                throw RunIngestionSourceError.anchorDecodeFailed
            }
            return anchor
        } catch {
            throw RunIngestionSourceError.anchorDecodeFailed
        }
    }

    private static func encodeAnchor(_ anchor: HKQueryAnchor) throws -> Data {
        do {
            return try NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true)
        } catch {
            throw RunIngestionSourceError.underlying("failed to archive anchor: \(error)")
        }
    }
}
#endif
