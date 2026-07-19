import Testing
@testable import FeatureBuilder
import DomainKit

/// Exhaustive coverage of `ValidationMessagePresenter`: one case per
/// `ValidationRule`, so a new rule added in `DomainKit` without a
/// corresponding branch here fails at compile time (the presenter's own
/// `switch` has no `default:`), and this test is the guard that a message is
/// actually non-blank for every existing case.
@Suite("ValidationMessagePresenter")
struct ValidationMessagePresenterTests {
    private static let allRules: [ValidationRule] = [
        .workoutHasNoSegments,
        .workoutNameEmpty,
        .intervalBlockRepetitionsNotPositive(repetitions: 0),
        .intervalBlockHasNoSteps,
        .goalDistanceNotPositive(meters: -5),
        .goalDurationNotPositive(seconds: -1),
        .paceRangeNotPositive(lowerBound: 0, upperBound: .infinity),
        .heartRateRangeNotPositive(lowerBound: 0, upperBound: .infinity),
        .heartRateZoneOutOfBounds(zone: 9),
        .cadenceRangeNotPositive(lowerBound: 0, upperBound: .infinity)
    ]

    @Test("Every ValidationRule case maps to a non-empty message", arguments: allRules)
    func everyRuleHasAMessage(rule: ValidationRule) {
        #expect(!ValidationMessagePresenter.message(for: rule).isEmpty)
    }

    @Test("message(for: ValidationIssue) delegates to the rule, ignoring the locator")
    func issueOverloadDelegatesToRule() {
        let issue = ValidationIssue(rule: .workoutNameEmpty, locator: .workout)
        #expect(ValidationMessagePresenter.message(for: issue) == ValidationMessagePresenter.message(for: .workoutNameEmpty))
    }

    @Test("intervalBlockRepetitionsNotPositive's message includes the offending count")
    func repetitionsMessageIncludesCount() {
        let message = ValidationMessagePresenter.message(for: .intervalBlockRepetitionsNotPositive(repetitions: -2))
        #expect(message.contains("-2"))
    }

    @Test("heartRateZoneOutOfBounds's message includes the offending zone")
    func heartRateZoneMessageIncludesZone() {
        let message = ValidationMessagePresenter.message(for: .heartRateZoneOutOfBounds(zone: 9))
        #expect(message.contains("9"))
    }
}
