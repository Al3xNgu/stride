import Foundation

/// Serializes foreground and background run-ingestion triggers.
///
/// The coordinator treats the anchor as a commit cursor: it reads the last
/// committed value, applies one fetched batch through the domain use case,
/// and persists the returned cursor only after that use case succeeds. If any
/// step fails, the previous cursor remains available and the next attempt
/// replays the same HealthKit changes safely.
public actor RunIngestionCoordinator {
    private let source: RunIngestionSource
    private let anchorStore: IngestionAnchorStore
    private let ingest: IngestCompletedRunsUseCase
    private let anchorKey: String
    private let splitDistanceMeters: Double
    private var isRunning = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    /// Creates a coordinator.
    /// - Parameters:
    ///   - source: The framework adapter that projects running workouts.
    ///   - anchorStore: Durable storage for the source cursor.
    ///   - ingest: Domain persistence and attribution use case.
    ///   - anchorKey: Stable key for this source/query combination.
    ///   - splitDistanceMeters: Distance used to derive splits.
    public init(
        source: RunIngestionSource,
        anchorStore: IngestionAnchorStore,
        ingest: IngestCompletedRunsUseCase,
        anchorKey: String,
        splitDistanceMeters: Double
    ) {
        self.source = source
        self.anchorStore = anchorStore
        self.ingest = ingest
        self.anchorKey = anchorKey
        self.splitDistanceMeters = splitDistanceMeters
    }

    /// Requests authorization through the source.
    public func requestAuthorizationIfNeeded() async throws {
        try await source.requestAuthorizationIfNeeded()
    }

    /// Runs one serialized pass per trigger. Waiting callbacks fetch again
    /// from the latest committed cursor, including changes that arrived after
    /// an earlier query took its snapshot. Actor reentrancy cannot overlap batches.
    @discardableResult
    public func ingestNow() async throws -> IngestionReport {
        await acquire()
        defer { release() }
        try Task.checkCancellation()
        let anchor = try await anchorStore.loadAnchor(for: anchorKey)
        let fetched = try await source.fetchRunningWorkouts(
            since: anchor,
            splitDistanceMeters: splitDistanceMeters
        )
        let report = try await ingest.execute(fetched.batch)
        try await anchorStore.saveAnchor(fetched.newAnchor, for: anchorKey)
        return report
    }

    private func acquire() async {
        if !isRunning {
            isRunning = true
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    private func release() {
        if waiters.isEmpty {
            isRunning = false
        } else {
            waiters.removeFirst().resume()
        }
    }
}
