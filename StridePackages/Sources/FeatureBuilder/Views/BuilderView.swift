import DesignSystem
import DomainKit
import SwiftUI

/// The workout builder screen: name field, segment list (reorder/duplicate/
/// delete), an add-segment palette, a live validation-issue badge, and save.
///
/// Segment editing (goal/target/intent) happens in a pushed
/// `SegmentEditorView` or `IntervalBlockEditorView`; this view only manages
/// list-level operations, delegating each segment's own editing to those
/// screens via computed bindings that read/write through
/// `BuilderViewModel.replaceSegment(id:with:)`.
public struct BuilderView: View {
    @Bindable private var viewModel: BuilderViewModel
    private let displayUnit: DisplayDistanceUnit

    /// Creates the builder screen for `viewModel`.
    /// - Parameters:
    ///   - viewModel: The screen's state and mutations.
    ///   - displayUnit: The unit distance/pace previews are shown in. A
    ///     future task wires this to `UserPreferences`; the MVP builder
    ///     defaults to kilometers.
    public init(viewModel: BuilderViewModel, displayUnit: DisplayDistanceUnit = .kilometers) {
        self.viewModel = viewModel
        self.displayUnit = displayUnit
    }

    public var body: some View {
        List {
            Section("Name") {
                TextField("Workout name", text: $viewModel.name)
                    .accessibilityIdentifier("builder.workoutName")
            }

            Section("Summary") {
                Text(summaryText)
                    .foregroundStyle(Colors.secondaryText)
            }

            if !viewModel.workoutLevelIssues.isEmpty {
                Section {
                    ForEach(viewModel.workoutLevelIssues, id: \.self) { issue in
                        Label(ValidationMessagePresenter.message(for: issue), systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Colors.warning)
                    }
                }
            }

            Section("Segments") {
                if viewModel.segments.isEmpty {
                    Text("No segments yet. Add one below.")
                        .foregroundStyle(Colors.secondaryText)
                }

                ForEach(viewModel.segments) { segment in
                    NavigationLink {
                        editor(for: segment)
                    } label: {
                        SegmentRowView(
                            segment: segment,
                            displayUnit: displayUnit,
                            issues: viewModel.issues(forSegmentID: segment.id)
                        )
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            viewModel.deleteSegment(id: segment.id)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            viewModel.duplicateSegment(id: segment.id)
                        } label: {
                            Label("Duplicate", systemImage: "plus.square.on.square")
                        }
                        .tint(Colors.accent)
                    }
                    .contextMenu {
                        Button {
                            viewModel.duplicateSegment(id: segment.id)
                        } label: {
                            Label("Duplicate", systemImage: "plus.square.on.square")
                        }
                        Button(role: .destructive) {
                            viewModel.deleteSegment(id: segment.id)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
                .onMove { source, destination in
                    viewModel.moveSegments(fromOffsets: source, toOffset: destination)
                }

                Menu {
                    ForEach(SegmentPaletteItem.allCases, id: \.self) { item in
                        Button(item.displayName) {
                            viewModel.addSegment(item)
                        }
                    }
                } label: {
                    Label("Add Segment", systemImage: "plus.circle")
                }
                .accessibilityIdentifier("builder.addSegment")
            }

            if let saveError = viewModel.saveError {
                Section {
                    Text(message(for: saveError))
                        .foregroundStyle(Colors.danger)
                }
            }
        }
        .navigationTitle("Builder")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Save") {
                    Task { await viewModel.save() }
                }
                .disabled(viewModel.isSaving)
                .accessibilityIdentifier("builder.save")
            }
            #if os(iOS)
            ToolbarItem(placement: .automatic) {
                EditButton()
            }
            #endif
        }
    }

    @ViewBuilder
    private func editor(for segment: WorkoutSegment) -> some View {
        switch segment {
        case .step:
            SegmentEditorView(step: stepBinding(for: segment.id), displayUnit: displayUnit)
        case .intervalBlock:
            IntervalBlockEditorView(
                blockID: segment.id,
                steps: intervalStepsBinding(blockID: segment.id),
                repetitions: intervalRepetitionsBinding(blockID: segment.id),
                displayUnit: displayUnit,
                issues: viewModel.issues(forSegmentID: segment.id)
            )
        }
    }

    /// An honest, presentation-only rendering of `viewModel.summary`: total
    /// distance and/or duration (whichever are non-zero), plus an open-goal
    /// segment count annotation so open segments are never silently omitted
    /// from the total (task 1.5 design notes), e.g. "5.20 km + 12:00 + 2
    /// open segments" (pluralized).
    private var summaryText: String {
        let summary = viewModel.summary
        var parts: [String] = []

        if summary.totalDistanceMeters > 0 {
            parts.append(UnitFormatter.distanceString(meters: summary.totalDistanceMeters, unit: displayUnit))
        }
        if summary.totalDurationSeconds > 0 {
            parts.append(UnitFormatter.durationString(seconds: summary.totalDurationSeconds))
        }
        if summary.hasOpenGoalSteps {
            let noun = summary.openGoalStepCount == 1 ? "segment" : "segments"
            parts.append("\(summary.openGoalStepCount) open \(noun)")
        }

        guard !parts.isEmpty else {
            return "No planned segments yet"
        }
        return parts.joined(separator: " + ")
    }

    /// A binding to the `.step` segment with `id`, reading through to the
    /// view model's current `segments` (so edits stay correct even if the
    /// segment list changes while an editor is pushed) and writing back via
    /// `replaceSegment(id:with:)`.
    private func stepBinding(for id: UUID) -> Binding<SegmentStep> {
        Binding(
            get: {
                if case let .step(step) = segment(id) { return step }
                return SegmentStep(intent: .easy, goal: .open)
            },
            set: { viewModel.replaceSegment(id: id, with: .step($0)) }
        )
    }

    private func intervalStepsBinding(blockID: UUID) -> Binding<[IntervalStep]> {
        Binding(
            get: {
                if case let .intervalBlock(_, steps, _) = segment(blockID) { return steps }
                return []
            },
            set: { newSteps in
                guard case let .intervalBlock(_, _, repetitions) = segment(blockID) else { return }
                let updated = WorkoutSegment.intervalBlock(id: blockID, steps: newSteps, repetitions: repetitions)
                viewModel.replaceSegment(id: blockID, with: updated)
            }
        )
    }

    private func intervalRepetitionsBinding(blockID: UUID) -> Binding<Int> {
        Binding(
            get: {
                if case let .intervalBlock(_, _, repetitions) = segment(blockID) { return repetitions }
                return 1
            },
            set: { newRepetitions in
                guard case let .intervalBlock(_, steps, _) = segment(blockID) else { return }
                let updated = WorkoutSegment.intervalBlock(id: blockID, steps: steps, repetitions: newRepetitions)
                viewModel.replaceSegment(id: blockID, with: updated)
            }
        )
    }

    private func segment(_ id: UUID) -> WorkoutSegment? {
        viewModel.segments.first { $0.id == id }
    }

    private func message(for error: WorkoutRepositoryError) -> String {
        switch error {
        case let .workoutNotFound(id):
            return "Workout \(id) could not be found."
        case .syncJobNotFound:
            return "A sync record could not be found."
        case let .underlying(description):
            return "Couldn't save: \(description)"
        }
    }
}

#if DEBUG
#Preview("New workout") {
    NavigationStack {
        BuilderView(
            viewModel: BuilderViewModel(
                workoutRepository: PreviewWorkoutRepository(),
                clock: PreviewClock()
            )
        )
    }
}

#Preview("Editing an existing workout") {
    NavigationStack {
        BuilderView(
            viewModel: BuilderViewModel(
                workoutRepository: PreviewWorkoutRepository(workouts: [PreviewFixtures.sampleWorkout()]),
                clock: PreviewClock(),
                workout: PreviewFixtures.sampleWorkout()
            )
        )
    }
}
#endif
