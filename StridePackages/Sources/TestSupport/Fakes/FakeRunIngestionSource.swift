import DomainKit
import Foundation

/// In-memory source fake for coordinator tests.
public final class FakeRunIngestionSource: RunIngestionSource, @unchecked Sendable {
    /// The next result returned by `fetchRunningWorkouts`.
    public var result: RunIngestionFetchResult
    /// An optional error thrown by either source operation.
    public var errorToThrow: Error?
    /// Optional delay used to keep a fetch in flight during concurrency tests.
    public var delayNanoseconds: UInt64 = 0
    /// Every anchor supplied to a fetch, in order.
    public private(set) var receivedAnchors: [Data?] = []
    /// Number of authorization requests.
    public private(set) var authorizationRequestCount = 0

    /// Creates a source returning `result`.
    public init(result: RunIngestionFetchResult) {
        self.result = result
    }

    public func requestAuthorizationIfNeeded() async throws {
        authorizationRequestCount += 1
        if let errorToThrow {
            throw errorToThrow
        }
    }

    public func fetchRunningWorkouts(
        since anchor: Data?,
        splitDistanceMeters: Double
    ) async throws -> RunIngestionFetchResult {
        receivedAnchors.append(anchor)
        if let errorToThrow {
            throw errorToThrow
        }
        if delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }
        return result
    }
}
