import Foundation

/// The status of Stride's request to read HealthKit run data.
public enum HealthPermissionStatus: Equatable, Hashable, Sendable {
    /// The system could not determine whether a request is needed.
    case unknown
    /// The user has not yet been asked for read access.
    case shouldRequest
    /// The user has already been asked for read access.
    case unnecessary
}

/// A typed failure from the HealthKit permission boundary.
public enum HealthPermissionPrimingError: Error, Equatable, Hashable, Sendable {
    /// Health data is unavailable on this device or OS.
    case unavailable
    /// HealthKit rejected the authorization request.
    case requestFailed(String)
    /// An unexpected framework or storage failure.
    case underlying(String)
}

/// Domain-owned capability for priming read-only HealthKit access.
///
/// DataKit provides the Apple-framework implementation and TestSupport
/// provides a fake; FeatureSettings depends on this port only.
public protocol HealthPermissionPriming: Sendable {
    /// The current request status.
    var status: HealthPermissionStatus { get async throws }

    /// Requests read-only HealthKit access and returns the resulting status.
    func requestAccess() async throws -> HealthPermissionStatus
}
