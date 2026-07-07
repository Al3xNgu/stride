import Foundation

/// A heart-rate target expressed either as a named zone or an explicit
/// beats-per-minute range.
///
/// Modeling both forms lets the builder UI default to zones (simple, most
/// runners' mental model) while still supporting explicit ranges for users
/// who know their numbers, without a schema change later.
public enum HeartRateTarget: Equatable, Hashable, Codable, Sendable {
    /// A named heart-rate zone, e.g. 1...5 in typical five-zone models.
    case zone(Int)
    /// An explicit beats-per-minute range.
    case range(ClosedRange<Double>)
}

/// The in-run alert/guidance target for a single workout step.
///
/// There is deliberately no `.none` case: a step without a target is
/// represented as `Target?` being `nil` at the call site, avoiding the
/// confusing `Target.none` vs. `Optional<Target>.none` collision that a
/// same-named case would create (see task summary for rationale).
public enum Target: Equatable, Hashable, Codable, Sendable {
    /// A pace range, in seconds-per-meter (CLAUDE.md rule 4), lower bound
    /// is the faster pace.
    case pace(range: ClosedRange<Double>)
    /// A heart-rate target, either a zone or an explicit bpm range.
    case heartRate(HeartRateTarget)
    /// A cadence range, in steps-per-minute.
    case cadence(range: ClosedRange<Double>)
}
