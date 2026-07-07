import Foundation

/// The runner-facing purpose of a single workout step.
///
/// `SegmentIntent` differentiates otherwise structurally-identical steps
/// (warm-up, easy, recovery, tempo, threshold, work, rest, cool-down) so the
/// domain can keep a single `SegmentStep` shape rather than a type per
/// intent (see `docs/ARCHITECTURE.md` §5). The intent also drives default
/// target ranges and display in the builder UI.
public enum SegmentIntent: String, Equatable, Hashable, Codable, Sendable {
    /// Warm-up effort at the start of a workout.
    case warmUp
    /// Easy, conversational-pace effort.
    case easy
    /// Recovery effort, typically between interval work bouts.
    case recovery
    /// Sustained tempo effort.
    case tempo
    /// Threshold effort (comfortably-hard, lactate-threshold pace).
    case threshold
    /// The "work" bout of an interval block.
    case work
    /// The "rest" bout of an interval block (walking or standing recovery).
    case rest
    /// Cool-down effort at the end of a workout.
    case coolDown
}
