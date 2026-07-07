import Foundation

/// A single, non-repeating step within a workout or interval block.
///
/// A step is the atomic unit of the domain model: an intent tag, a
/// completion goal, and an optional in-run target. This single shape covers
/// warm-up, easy, recovery, tempo, threshold, work, rest, and cool-down —
/// differentiated only by `intent` — which keeps the model small and maps
/// 1:1 onto WorkoutKit's step model (see `docs/ARCHITECTURE.md` §5).
public struct SegmentStep: Identifiable, Equatable, Hashable, Codable, Sendable {
    /// Stable identity for SwiftUI list editing (reorder/delete in the builder).
    public let id: UUID
    /// The runner-facing purpose of this step.
    public var intent: SegmentIntent
    /// The completion condition for this step.
    public var goal: Goal
    /// The optional in-run alert/guidance target for this step. `nil` means
    /// no target is configured (see `Target` doc comment for rationale).
    public var target: Target?

    /// Creates a step.
    public init(
        id: UUID = UUID(),
        intent: SegmentIntent,
        goal: Goal,
        target: Target? = nil
    ) {
        self.id = id
        self.intent = intent
        self.goal = goal
        self.target = target
    }
}

/// The role a step plays within an interval block: the effort bout or the
/// recovery bout between effort bouts.
///
/// Per `docs/ARCHITECTURE.md` §3.1 ("work step + recovery step, each with
/// its own goal/target"), an interval block's steps are tagged with a
/// purpose so the builder and WorkoutKit mapper can distinguish them while
/// still allowing a block to contain more than two steps for future
/// ladders/pyramids.
public enum IntervalStepPurpose: String, Equatable, Hashable, Codable, Sendable {
    /// The effort bout of an interval.
    case work
    /// The recovery bout between effort bouts.
    case recovery
}

/// A single step inside an interval block, tagged with its purpose.
///
/// `IntervalStep` wraps a `SegmentStep` rather than duplicating its fields,
/// so an interval step is "everything a normal step is, plus which role it
/// plays in the repeating block."
public struct IntervalStep: Identifiable, Equatable, Hashable, Codable, Sendable {
    /// Stable identity for SwiftUI list editing.
    public let id: UUID
    /// Whether this step is the work bout or the recovery bout.
    public var purpose: IntervalStepPurpose
    /// The step's own intent, goal, and target.
    public var step: SegmentStep

    /// Creates an interval step.
    public init(
        id: UUID = UUID(),
        purpose: IntervalStepPurpose,
        step: SegmentStep
    ) {
        self.id = id
        self.purpose = purpose
        self.step = step
    }
}

/// An ordered element of a `Workout`: either a single step or a repeating
/// interval block.
///
/// `WorkoutSegment` is a sum type rather than a class hierarchy, matching
/// `docs/ARCHITECTURE.md` §5 exactly, so the WorkoutKit mapper can switch
/// over two cases instead of a type hierarchy.
public enum WorkoutSegment: Identifiable, Equatable, Hashable, Codable, Sendable {
    /// A single, non-repeating step (warm-up, easy, tempo, cool-down, etc).
    case step(SegmentStep)
    /// A block of one or more steps (typically work + recovery) repeated
    /// `repetitions` times, with its own stable identity for SwiftUI list
    /// editing. Multiple steps per block leave room for ladders/pyramids
    /// without a model change.
    case intervalBlock(id: UUID, steps: [IntervalStep], repetitions: Int)

    /// Stable identity for SwiftUI list editing (reorder/delete in the
    /// builder): the step's own id for `.step`, or the block's own stored
    /// id for `.intervalBlock`.
    public var id: UUID {
        switch self {
        case let .step(step):
            return step.id
        case let .intervalBlock(id, _, _):
            return id
        }
    }

    /// Convenience constructor for an interval block that generates a new
    /// block identity, so call sites don't need to mint a `UUID` themselves.
    public static func intervalBlock(steps: [IntervalStep], repetitions: Int) -> WorkoutSegment {
        .intervalBlock(id: UUID(), steps: steps, repetitions: repetitions)
    }
}
