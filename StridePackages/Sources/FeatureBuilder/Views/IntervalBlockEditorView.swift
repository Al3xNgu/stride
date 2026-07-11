import DesignSystem
import DomainKit
import SwiftUI

/// Editor for a `WorkoutSegment.intervalBlock`: repetitions, plus the
/// work-bout and recovery-bout steps.
///
/// Per `docs/ARCHITECTURE.md` §3.1 ("interval blocks: work step + recovery
/// step... × N repetitions"), the MVP builder edits exactly one work step
/// and one recovery step per block — the domain model's `steps: [IntervalStep]`
/// leaves room for future ladders/pyramids, but that UI is out of this
/// task's scope.
public struct IntervalBlockEditorView: View {
    @Binding private var steps: [IntervalStep]
    @Binding private var repetitions: Int
    private let displayUnit: DisplayDistanceUnit

    /// Creates an interval block editor.
    /// - Parameters:
    ///   - steps: A two-way binding to the block's interval steps.
    ///   - repetitions: A two-way binding to the block's repeat count.
    ///   - displayUnit: The unit distance/pace previews are shown in.
    public init(
        steps: Binding<[IntervalStep]>,
        repetitions: Binding<Int>,
        displayUnit: DisplayDistanceUnit
    ) {
        self._steps = steps
        self._repetitions = repetitions
        self.displayUnit = displayUnit
    }

    public var body: some View {
        Form {
            Section("Repetitions") {
                Stepper(value: $repetitions, in: 1...50) {
                    Text("Repeat ×\(repetitions)")
                }
            }

            if let workStepBinding {
                Section("Work") {
                    NavigationLink {
                        SegmentEditorView(step: workStepBinding, displayUnit: displayUnit)
                    } label: {
                        SegmentRowView(segment: .step(workStepBinding.wrappedValue), displayUnit: displayUnit)
                    }
                }
            }

            if let recoveryStepBinding {
                Section("Recovery") {
                    NavigationLink {
                        SegmentEditorView(step: recoveryStepBinding, displayUnit: displayUnit)
                    } label: {
                        SegmentRowView(segment: .step(recoveryStepBinding.wrappedValue), displayUnit: displayUnit)
                    }
                }
            }
        }
        .navigationTitle("Interval Block")
    }

    private var workStepBinding: Binding<SegmentStep>? {
        stepBinding(purpose: .work)
    }

    private var recoveryStepBinding: Binding<SegmentStep>? {
        stepBinding(purpose: .recovery)
    }

    private func stepBinding(purpose: IntervalStepPurpose) -> Binding<SegmentStep>? {
        guard steps.contains(where: { $0.purpose == purpose }) else {
            return nil
        }
        return Binding(
            get: {
                steps.first(where: { $0.purpose == purpose })?.step ?? SegmentStep(intent: .work, goal: .open)
            },
            set: { newStep in
                guard let index = steps.firstIndex(where: { $0.purpose == purpose }) else { return }
                steps[index].step = newStep
            }
        )
    }
}

#if DEBUG
/// Wraps `IntervalBlockEditorView` with local `@State` so `#Preview` can
/// supply bindings without a `BuilderViewModel`.
private struct IntervalBlockEditorPreviewContainer: View {
    @State private var steps: [IntervalStep]
    @State private var repetitions: Int

    init(steps: [IntervalStep], repetitions: Int) {
        self._steps = State(initialValue: steps)
        self._repetitions = State(initialValue: repetitions)
    }

    var body: some View {
        IntervalBlockEditorView(steps: $steps, repetitions: $repetitions, displayUnit: .kilometers)
    }
}

#Preview("Work/recovery interval block") {
    NavigationStack {
        IntervalBlockEditorPreviewContainer(
            steps: [
                IntervalStep(purpose: .work, step: SegmentStep(intent: .work, goal: .distance(meters: 1_000))),
                IntervalStep(purpose: .recovery, step: SegmentStep(intent: .recovery, goal: .duration(seconds: 120)))
            ],
            repetitions: 5
        )
    }
}
#endif
