import DomainKit

/// In-memory fake for the DomainKit Health permission port.
///
/// Tests can inject status, a typed failure, and a request result without
/// importing HealthKit or requiring entitlements.
public final class FakeHealthPermissionPriming: HealthPermissionPriming, @unchecked Sendable {
    /// Status returned by `status`.
    public var statusValue: HealthPermissionStatus
    /// Result returned by a successful `requestAccess()` call.
    public var requestResult: HealthPermissionStatus
    /// Optional failure for status reads.
    public var statusError: HealthPermissionPrimingError?
    /// Optional failure for access requests.
    public var requestError: HealthPermissionPrimingError?
    /// Number of access requests received.
    public private(set) var requestCallCount = 0

    /// Creates a fake with the supplied status.
    public init(status: HealthPermissionStatus = .shouldRequest) {
        statusValue = status
        requestResult = status
    }

    public var status: HealthPermissionStatus {
        get async throws {
            if let statusError {
                throw statusError
            }
            return statusValue
        }
    }

    public func requestAccess() async throws -> HealthPermissionStatus {
        requestCallCount += 1
        if let requestError {
            throw requestError
        }
        statusValue = requestResult
        return requestResult
    }
}
