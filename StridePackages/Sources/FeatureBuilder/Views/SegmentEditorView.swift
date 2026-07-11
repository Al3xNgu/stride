import DesignSystem
import DomainKit
import SwiftUI

/// Editor for a single `SegmentStep`: intent, goal (open/distance/duration),
/// and an optional pace target.
///
/// Bound directly to the step via `Binding<SegmentStep>` — a computed
/// binding that reads/writes through to `BuilderViewModel` (see
/// `BuilderView.stepBinding(for:)`), so every field edit here is
/// immediately reflected in the workout draft and its live
/// `validationIssues` (task 1.5 wires up full inline-error rendering; this
/// view only needs the edits to land).
///
/// HR/cadence targets are model-ready (`Target.heartRate`/`Target.cadence`)
/// but intentionally not exposed here: `docs/ARCHITECTURE.md` §3.1 gates
/// them behind a future UI unlock, so only `Target.pace` is editable in the
/// MVP builder.
public struct SegmentEditorView: View {
    @Binding private var step: SegmentStep
    private let displayUnit: DisplayDistanceUnit

    /// Creates a step editor.
    /// - Parameters:
    ///   - step: A two-way binding to the step being edited.
    ///   - displayUnit: The unit distance/pace previews are shown in.
    public init(step: Binding<SegmentStep>, displayUnit: DisplayDistanceUnit) {
        self._step = step
        self.displayUnit = displayUnit
    }

    public var body: some View {
        Form {
            Section("Intent") {
                Picker("Intent", selection: $step.intent) {
                    ForEach(SegmentPaletteItem.allCases.compactMap(\.intent), id: \.self) { intent in
                        Text(intent.displayName).tag(intent)
                    }
                }
            }

            Section("Goal") {
                Picker("Goal Type", selection: goalKindBinding) {
                    Text("Open").tag(GoalKind.open)
                    Text("Distance").tag(GoalKind.distance)
                    Text("Duration").tag(GoalKind.duration)
                }
                .pickerStyle(.segmented)

                goalDetailFields
            }

            Section("Pace Target") {
                Toggle("Pace target", isOn: hasPaceTargetBinding)
                if hasPaceTargetBinding.wrappedValue {
                    paceRangeFields
                }
            }
        }
        .navigationTitle(step.intent.displayName)
    }

    // MARK: - Goal

    private enum GoalKind: Hashable {
        case open, distance, duration
    }

    private var goalKindBinding: Binding<GoalKind> {
        Binding(
            get: {
                switch step.goal {
                case .open: return .open
                case .distance: return .distance
                case .duration: return .duration
                }
            },
            set: { newKind in
                switch newKind {
                case .open:
                    step.goal = .open
                case .distance:
                    if case .distance = step.goal { return }
                    step.goal = .distance(meters: 1_000)
                case .duration:
                    if case .duration = step.goal { return }
                    step.goal = .duration(seconds: 600)
                }
            }
        )
    }

    @ViewBuilder
    private var goalDetailFields: some View {
        switch step.goal {
        case .distance:
            Stepper(value: distanceMetersBinding, in: 0...100_000, step: 50) {
                Text(UnitFormatter.segmentDistanceString(meters: distanceMetersBinding.wrappedValue, unit: displayUnit))
            }

        case .duration:
            Stepper(value: durationMinutesBinding, in: 0...180) {
                Text("Minutes: \(durationMinutesBinding.wrappedValue)")
            }
            Stepper(value: durationSecondsBinding, in: 0...59) {
                Text("Seconds: \(durationSecondsBinding.wrappedValue)")
            }

        case .open:
            EmptyView()
        }
    }

    private var distanceMetersBinding: Binding<Double> {
        Binding(
            get: {
                if case let .distance(meters) = step.goal { return meters }
                return 0
            },
            set: { step.goal = .distance(meters: max(0, $0)) }
        )
    }

    private var durationSecondsTotal: Int {
        if case let .duration(seconds) = step.goal { return Int(seconds) }
        return 0
    }

    private var durationMinutesBinding: Binding<Int> {
        Binding(
            get: { durationSecondsTotal / 60 },
            set: { newMinutes in
                let seconds = durationSecondsTotal % 60
                step.goal = .duration(seconds: Double(max(0, newMinutes) * 60 + seconds))
            }
        )
    }

    private var durationSecondsBinding: Binding<Int> {
        Binding(
            get: { durationSecondsTotal % 60 },
            set: { newSeconds in
                let minutes = durationSecondsTotal / 60
                step.goal = .duration(seconds: Double(minutes * 60 + max(0, newSeconds)))
            }
        )
    }

    // MARK: - Pace target

    private var defaultPaceRange: ClosedRange<Double> {
        let lower = UnitFormatter.secondsPerMeter(minutes: 5, seconds: 0, unit: displayUnit)
        let upper = UnitFormatter.secondsPerMeter(minutes: 6, seconds: 0, unit: displayUnit)
        return lower...upper
    }

    private var paceRange: ClosedRange<Double> {
        if case let .pace(range) = step.target { return range }
        return defaultPaceRange
    }

    private var hasPaceTargetBinding: Binding<Bool> {
        Binding(
            get: {
                if case .pace = step.target { return true }
                return false
            },
            set: { isOn in
                step.target = isOn ? .pace(range: defaultPaceRange) : nil
            }
        )
    }

    @ViewBuilder
    private var paceRangeFields: some View {
        let fastest = UnitFormatter.paceComponents(secondsPerMeter: paceRange.lowerBound, unit: displayUnit)
        let slowest = UnitFormatter.paceComponents(secondsPerMeter: paceRange.upperBound, unit: displayUnit)

        Stepper(value: fastestMinutesBinding(currentSeconds: fastest.seconds), in: 0...30) {
            Text("Fastest: \(fastest.minutes) min")
        }
        Stepper(value: fastestSecondsBinding(currentMinutes: fastest.minutes), in: 0...59) {
            Text("Fastest: \(fastest.seconds) sec")
        }
        Stepper(value: slowestMinutesBinding(currentSeconds: slowest.seconds), in: 0...30) {
            Text("Slowest: \(slowest.minutes) min")
        }
        Stepper(value: slowestSecondsBinding(currentMinutes: slowest.minutes), in: 0...59) {
            Text("Slowest: \(slowest.seconds) sec")
        }
    }

    private func fastestMinutesBinding(currentSeconds: Int) -> Binding<Int> {
        Binding(
            get: { UnitFormatter.paceComponents(secondsPerMeter: paceRange.lowerBound, unit: displayUnit).minutes },
            set: { updateFastest(minutes: $0, seconds: currentSeconds) }
        )
    }

    private func fastestSecondsBinding(currentMinutes: Int) -> Binding<Int> {
        Binding(
            get: { UnitFormatter.paceComponents(secondsPerMeter: paceRange.lowerBound, unit: displayUnit).seconds },
            set: { updateFastest(minutes: currentMinutes, seconds: $0) }
        )
    }

    private func slowestMinutesBinding(currentSeconds: Int) -> Binding<Int> {
        Binding(
            get: { UnitFormatter.paceComponents(secondsPerMeter: paceRange.upperBound, unit: displayUnit).minutes },
            set: { updateSlowest(minutes: $0, seconds: currentSeconds) }
        )
    }

    private func slowestSecondsBinding(currentMinutes: Int) -> Binding<Int> {
        Binding(
            get: { UnitFormatter.paceComponents(secondsPerMeter: paceRange.upperBound, unit: displayUnit).seconds },
            set: { updateSlowest(minutes: currentMinutes, seconds: $0) }
        )
    }

    private func updateFastest(minutes: Int, seconds: Int) {
        let newLower = UnitFormatter.secondsPerMeter(minutes: minutes, seconds: seconds, unit: displayUnit)
        let upper = max(newLower, paceRange.upperBound)
        step.target = .pace(range: newLower...upper)
    }

    private func updateSlowest(minutes: Int, seconds: Int) {
        let newUpper = UnitFormatter.secondsPerMeter(minutes: minutes, seconds: seconds, unit: displayUnit)
        let lower = min(paceRange.lowerBound, newUpper)
        step.target = .pace(range: lower...newUpper)
    }
}

#if DEBUG
/// Wraps `SegmentEditorView` with local `@State` so `#Preview` can supply a
/// `Binding<SegmentStep>` without a `BuilderViewModel`.
private struct SegmentEditorPreviewContainer: View {
    @State private var step: SegmentStep

    init(step: SegmentStep) {
        self._step = State(initialValue: step)
    }

    var body: some View {
        SegmentEditorView(step: $step, displayUnit: .kilometers)
    }
}

#Preview("Open goal, no target") {
    NavigationStack {
        SegmentEditorPreviewContainer(step: SegmentStep(intent: .easy, goal: .open))
    }
}

#Preview("Distance goal with pace target") {
    NavigationStack {
        SegmentEditorPreviewContainer(
            step: SegmentStep(intent: .tempo, goal: .distance(meters: 5_000), target: .pace(range: 0.2...0.22))
        )
    }
}

#Preview("Duration goal") {
    NavigationStack {
        SegmentEditorPreviewContainer(step: SegmentStep(intent: .warmUp, goal: .duration(seconds: 600)))
    }
}
#endif
