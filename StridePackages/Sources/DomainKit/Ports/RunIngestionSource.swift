import Foundation

/// A completed-run batch plus the opaque cursor that produced it.
///
/// The cursor is deliberately represented as `Data`: the concrete source may
/// use a framework-specific archive, while DomainKit remains independent of
/// HealthKit and other Apple data frameworks.
public struct RunIngestionFetchResult: Equatable, Hashable, Sendable {
    /// Runs and deletions to apply to the local projection store.
    public var batch: IngestionBatch
    /// Cursor to persist after `batch` is applied successfully.
    public var newAnchor: Data

    /// Creates a fetch result.
    public init(batch: IngestionBatch, newAnchor: Data) {
        self.batch = batch
        self.newAnchor = newAnchor
    }
}

/// A framework-free source of completed running workouts.
///
/// Implementations may be backed by HealthKit, an import file, or a test
/// fixture. The source returns projections ready for
/// `IngestCompletedRunsUseCase`; it does not persist them or advance its
/// cursor.
public protocol RunIngestionSource: Sendable {
    /// Requests read authorization when the underlying source requires it.
    func requestAuthorizationIfNeeded() async throws

    /// Fetches additions, updates, and deletions after `anchor`.
    /// - Parameters:
    ///   - anchor: The last successfully committed cursor, or `nil` initially.
    ///   - splitDistanceMeters: Distance used by the source's split policy.
    func fetchRunningWorkouts(
        since anchor: Data?,
        splitDistanceMeters: Double
    ) async throws -> RunIngestionFetchResult
}

/// Typed failures from a run-ingestion source.
public enum RunIngestionSourceError: Error, Equatable, Hashable, Sendable {
    /// The source is unavailable on this device or platform.
    case notAvailable
    /// Authorization request failed before a read could be attempted.
    case authorizationFailed(String)
    /// A persisted cursor could not be decoded by the source.
    case anchorDecodeFailed
    /// An unexpected source failure.
    case underlying(String)
}

/// Persists opaque ingestion cursors independently from the source that
/// creates them.
public protocol IngestionAnchorStore: Sendable {
    /// Loads the last committed cursor for `key`, or `nil` on first use.
    func loadAnchor(for key: String) async throws -> Data?

    /// Replaces the cursor for `key`.
    func saveAnchor(_ anchor: Data, for key: String) async throws
}

/// Registers the source's change notification with the operating system.
@MainActor
public protocol RunIngestionDelivery: Sendable {
    /// Installs observation at launch without requesting authorization.
    func observe() throws

    /// Starts observing source changes and enables background wake-ups.
    func start() async throws
}

/// Typed failures from background-delivery registration.
public enum RunIngestionDeliveryError: Error, Equatable, Hashable, Sendable {
    /// The source is unavailable on this device or platform.
    case notAvailable
    /// The operating system rejected registration.
    case registrationFailed(String)
    /// An unexpected delivery failure.
    case underlying(String)
}

/// Typed failures from an ingestion cursor store.
public enum IngestionAnchorStoreError: Error, Equatable, Hashable, Sendable {
    /// The backing store failed.
    case underlying(String)
}
