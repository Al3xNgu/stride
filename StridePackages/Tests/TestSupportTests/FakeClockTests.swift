import Testing
import Foundation
import TestSupport

/// `FakeClock` must be deterministic: `now()` only ever reflects
/// `currentDate`, never wall-clock time, and only moves when a test
/// explicitly calls `advance(by:)` (CLAUDE.md rule 5).
@Suite("FakeClock")
struct FakeClockTests {
    @Test("Default init pins now() at the Unix epoch")
    func defaultsToEpoch() {
        let clock = FakeClock()
        #expect(clock.now() == Date(timeIntervalSince1970: 0))
    }

    @Test("now() reflects the date supplied at init")
    func reflectsSuppliedDate() {
        let pinned = Date(timeIntervalSince1970: 1_700_000_000)
        let clock = FakeClock(currentDate: pinned)
        #expect(clock.now() == pinned)
    }

    @Test("now() does not drift between calls without advance(by:)")
    func doesNotDriftOnItsOwn() {
        let clock = FakeClock(currentDate: Date(timeIntervalSince1970: 500))
        let first = clock.now()
        let second = clock.now()
        #expect(first == second)
    }

    @Test("advance(by:) moves now() forward by the given interval")
    func advanceMovesForward() {
        let clock = FakeClock(currentDate: Date(timeIntervalSince1970: 0))
        clock.advance(by: 60)
        #expect(clock.now() == Date(timeIntervalSince1970: 60))
    }

    @Test("advance(by:) with a negative interval moves now() backward")
    func advanceCanMoveBackward() {
        let clock = FakeClock(currentDate: Date(timeIntervalSince1970: 100))
        clock.advance(by: -40)
        #expect(clock.now() == Date(timeIntervalSince1970: 60))
    }

    @Test("Multiple advances accumulate")
    func advancesAccumulate() {
        let clock = FakeClock(currentDate: Date(timeIntervalSince1970: 0))
        clock.advance(by: 30)
        clock.advance(by: 30)
        #expect(clock.now() == Date(timeIntervalSince1970: 60))
    }
}
