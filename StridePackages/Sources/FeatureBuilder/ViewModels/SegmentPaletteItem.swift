import DomainKit
import Foundation

/// A selectable entry in the builder's "add segment" palette
/// (`docs/ARCHITECTURE.md` §3.1's segment palette).
///
/// Mirrors `SegmentIntent` one case at a time, plus `.intervalBlock` for the
/// repeating work/recovery block — a distinct `WorkoutSegment` case rather
/// than an intent, so it isn't a `SegmentIntent` case itself.
public enum SegmentPaletteItem: CaseIterable, Equatable, Hashable, Sendable {
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
    /// A standalone "work" effort step (outside an interval block).
    case work
    /// A standalone "rest" step (outside an interval block).
    case rest
    /// Cool-down effort at the end of a workout.
    case coolDown
    /// A repeating work/recovery block (`WorkoutSegment.intervalBlock`).
    case intervalBlock

    /// The single-step intent this palette item creates, or `nil` for
    /// `.intervalBlock` (which isn't a step at all).
    public var intent: SegmentIntent? {
        switch self {
        case .warmUp: return .warmUp
        case .easy: return .easy
        case .recovery: return .recovery
        case .tempo: return .tempo
        case .threshold: return .threshold
        case .work: return .work
        case .rest: return .rest
        case .coolDown: return .coolDown
        case .intervalBlock: return nil
        }
    }

    /// A short display label for the add-segment menu.
    public var displayName: String {
        intent?.displayName ?? "Interval Block"
    }

    /// Builds the default `WorkoutSegment` this palette item adds to the
    /// workout: an open-goal, no-target step for single-intent items, or a
    /// starter work/recovery block (400 m work, 60 s recovery, ×4) for
    /// `.intervalBlock` — a reasonable, immediately-editable starting point
    /// rather than an invalid empty block (`ValidateWorkoutPolicy` requires
    /// at least one step and at least one repetition).
    public func makeSegment() -> WorkoutSegment {
        if let intent {
            return .step(SegmentStep(intent: intent, goal: .open))
        }
        return .intervalBlock(
            steps: [
                IntervalStep(purpose: .work, step: SegmentStep(intent: .work, goal: .distance(meters: 400))),
                IntervalStep(purpose: .recovery, step: SegmentStep(intent: .rest, goal: .duration(seconds: 60)))
            ],
            repetitions: 4
        )
    }
}

extension SegmentIntent {
    /// A short display label for the builder UI. Presentation-layer copy
    /// deliberately lives here rather than on the entity (CLAUDE.md rule 4
    /// pattern: display concerns stay at the presentation edge).
    public var displayName: String {
        switch self {
        case .warmUp: return "Warm-up"
        case .easy: return "Easy"
        case .recovery: return "Recovery"
        case .tempo: return "Tempo"
        case .threshold: return "Threshold"
        case .work: return "Work"
        case .rest: return "Rest"
        case .coolDown: return "Cool-down"
        }
    }
}
