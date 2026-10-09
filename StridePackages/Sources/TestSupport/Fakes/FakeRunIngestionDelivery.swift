import DomainKit
import Foundation

/// In-memory fake for background-delivery registration.
@MainActor
public final class FakeRunIngestionDelivery: RunIngestionDelivery {
    /// Optional failure returned by `start()`.
    public var errorToThrow: Error?
    /// Number of successful or failed start attempts.
    public private(set) var startCallCount = 0

    public init() {}

    public func observe() throws {
        if let errorToThrow { throw errorToThrow }
    }

    public func start() async throws {
        startCallCount += 1
        if let errorToThrow {
            throw errorToThrow
        }
    }
}
