#if canImport(HealthKit)
import DomainKit
import Foundation
import HealthKit
import Testing
@testable import DataKit

@Suite("HealthKit anchor decoding")
struct HealthKitAnchorDecodingTests {
    @Test("Invalid cursor bytes fail explicitly rather than initiating a full fetch")
    func invalidBytes() {
        #expect(throws: RunIngestionSourceError.anchorDecodeFailed) {
            try HealthKitRunHistoryRepository.decodeAnchor(Data([1, 2, 3]))
        }
    }

    @Test("A securely archived anchor can be restored")
    func secureArchive() throws {
        let anchor = HKQueryAnchor(fromValue: 42)
        let data = try NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true)
        #expect(try HealthKitRunHistoryRepository.decodeAnchor(data) == anchor)
        #expect(try HealthKitRunHistoryRepository.decodeAnchor(nil) == nil)
    }
}
#endif
