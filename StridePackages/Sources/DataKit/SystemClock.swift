import DomainKit
import Foundation

/// Wall-clock implementation used by the application composition root.
public struct SystemClock: Clock {
    public init() {}

    public func now() -> Date {
        Date()
    }
}
