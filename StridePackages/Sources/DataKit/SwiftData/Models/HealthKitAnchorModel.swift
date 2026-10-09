import Foundation
import SwiftData

/// Durable opaque cursor for one HealthKit anchored query.
@Model
public final class HealthKitAnchorModel {
    /// Stable source/query key, for example running workouts.
    @Attribute(.unique) public var key: String
    /// Archived `HKQueryAnchor` bytes. DataKit never exposes the framework
    /// object above this persistence boundary.
    public var anchorData: Data
    public var updatedAt: Date

    /// Creates an anchor row.
    public init(key: String, anchorData: Data, updatedAt: Date = Date()) {
        self.key = key
        self.anchorData = anchorData
        self.updatedAt = updatedAt
    }
}
