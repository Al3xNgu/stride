import Testing
import Foundation
@testable import DomainKit

/// Exhaustive coverage of the MVP milestone presets: exact distances,
/// sane tolerances, non-empty display names, and distinctness.
@Suite("Milestone presets")
struct MilestoneTests {
    @Test("oneMile is exactly 1609.344 meters")
    func oneMileDistance() {
        #expect(Milestone.oneMile.distanceMeters == 1_609.344)
    }

    @Test("fiveK is exactly 5000 meters")
    func fiveKDistance() {
        #expect(Milestone.fiveK.distanceMeters == 5_000)
    }

    @Test("tenK is exactly 10000 meters")
    func tenKDistance() {
        #expect(Milestone.tenK.distanceMeters == 10_000)
    }

    @Test("halfMarathon is exactly 21097.5 meters")
    func halfMarathonDistance() {
        #expect(Milestone.halfMarathon.distanceMeters == 21_097.5)
    }

    @Test("marathon is exactly 42195 meters")
    func marathonDistance() {
        #expect(Milestone.marathon.distanceMeters == 42_195)
    }

    @Test(
        "Every MVP preset has a positive tolerance no greater than 5% of its distance",
        arguments: Milestone.mvpPresets
    )
    func toleranceIsPositiveAndSane(_ milestone: Milestone) {
        #expect(milestone.tolerance > 0)
        #expect(milestone.tolerance <= milestone.distanceMeters * 0.05)
    }

    @Test("Every MVP preset has a non-empty display name", arguments: Milestone.mvpPresets)
    func displayNameNonEmpty(_ milestone: Milestone) {
        #expect(!milestone.displayName.isEmpty)
    }

    @Test("MVP presets are distinct by id")
    func presetsDistinctByID() {
        let ids = Set(Milestone.mvpPresets.map(\.id))
        #expect(ids.count == Milestone.mvpPresets.count)
    }

    @Test("MVP presets are distinct by distance")
    func presetsDistinctByDistance() {
        let distances = Set(Milestone.mvpPresets.map(\.distanceMeters))
        #expect(distances.count == Milestone.mvpPresets.count)
    }

    @Test("MVP presets are in ascending distance order")
    func presetsAscendingOrder() {
        let distances = Milestone.mvpPresets.map(\.distanceMeters)
        #expect(distances == distances.sorted())
    }

    @Test("mvpPresets contains exactly the five documented milestones")
    func presetsContainsExactlyFive() {
        #expect(Milestone.mvpPresets.count == 5)
        #expect(Milestone.mvpPresets.map(\.displayName) == ["1 Mile", "5K", "10K", "Half Marathon", "Marathon"])
    }
}
