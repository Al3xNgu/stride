import DomainKit
import Foundation
import Observation

/// Screen state and mutations for authoring or editing a single `Workout`.
///
/// Owns an in-memory draft `Workout` and every segment-list operation the
/// builder UI exposes (add-from-palette, reorder, edit, duplicate, delete),
/// persists via the injected `WorkoutRepository`, and stamps `updatedAt` from
/// the injected `Clock` — never `Date()` directly (CLAUDE.md rule 5: all
/// Apple-framework/non-deterministic access goes through a `DomainKit/Ports`
/// protocol).
///
/// Live validation and the planned-totals summary (task 1.5) are exposed as
/// `validationIssues` and `summary`, both recomputed on every access from
/// the pure `ValidateWorkoutPolicy`/`WorkoutSummaryPolicy` so they are
/// always current after a mutating call, without this view model needing to
/// cache and invalidate anything itself (`docs/ARCHITECTURE.md` §7: "live
/// validation... on every builder edit").
///
/// Per `docs/ARCHITECTURE.md` §3.1/§7, live validation here is
/// builder-local, inline surfacing — it does not gate `save()`. Saving a
/// draft with outstanding issues is intentionally allowed (a workout is
/// "authored intent" that must be able to exist mid-edit); only
/// `ScheduleWorkoutUseCase`'s pre-flight "Send to Watch" validation (a
/// future task) is a hard gate.
@MainActor
@Observable
public final class BuilderViewModel {
    /// The workout currently being authored/edited.
    public private(set) var workout: Workout

    /// The error from the most recent `save()` attempt, or `nil` if the last
    /// attempt (if any) succeeded. The view renders this; the view model
    /// never prints or swallows it (CLAUDE.md definition of done).
    public private(set) var saveError: WorkoutRepositoryError?

    /// The error from the most recent `load(workoutID:)` attempt, or `nil`.
    public private(set) var loadError: WorkoutRepositoryError?

    /// Whether a `save()` call is in flight, for view spinner/disable state.
    public private(set) var isSaving = false

    /// Whether a `load(workoutID:)` call is in flight.
    public private(set) var isLoading = false

    private let workoutRepository: WorkoutRepository
    private let clock: Clock

    /// Every structural validation issue currently present in `workout`,
    /// recomputed from `ValidateWorkoutPolicy` on every access — so it is
    /// always current after a mutating call (add/move/replace/duplicate/
    /// delete) without the view model needing to cache and invalidate it.
    public var validationIssues: [ValidationIssue] {
        ValidateWorkoutPolicy.validate(workout)
    }

    /// The workout's planned totals (distance, duration, open-goal step
    /// count), recomputed from `WorkoutSummaryPolicy` on every access —
    /// always current after a mutating call, same as `validationIssues`.
    public var summary: WorkoutSummary {
        WorkoutSummaryPolicy.summarize(workout)
    }

    /// Validation issues anchored to the workout as a whole (`.workout`
    /// locator, e.g. "no segments" or "empty name") rather than to a
    /// specific segment — for a workout-level issues section distinct from
    /// per-row badges.
    public var workoutLevelIssues: [ValidationIssue] {
        validationIssues.filter { $0.locator == .workout }
    }

    /// Every validation issue anchored to the top-level segment with `id`,
    /// either directly (`.segment(id:)`, e.g. an interval block's own
    /// repetitions/step-count rules) or nested inside it as one of its
    /// interval steps (`.intervalStep(blockID:stepID:)`) — so the builder's
    /// segment list can badge a row with every issue that lives underneath
    /// it, without the view needing to know `ValidationLocator`'s cases.
    public func issues(forSegmentID id: UUID) -> [ValidationIssue] {
        validationIssues.filter { issue in
            switch issue.locator {
            case .workout:
                return false
            case let .segment(segmentID):
                return segmentID == id
            case let .intervalStep(blockID, _):
                return blockID == id
            }
        }
    }

    /// The workout's user-facing name, exposed as a settable proxy onto
    /// `workout.name` so the view can bind a `TextField` directly.
    public var name: String {
        get { workout.name }
        set { workout.name = newValue }
    }

    /// The workout's ordered segments, for the builder's list UI.
    public var segments: [WorkoutSegment] {
        workout.segments
    }

    /// Creates a builder view model.
    ///
    /// - Parameters:
    ///   - workoutRepository: Persists/fetches the workout being edited.
    ///   - clock: Supplies `createdAt`/`updatedAt` timestamps.
    ///   - workout: The workout to edit, or `nil` (the default) to start a
    ///     fresh, unnamed draft with no segments — a brand-new workout that
    ///     does not yet exist in the repository until `save()` succeeds.
    public init(
        workoutRepository: WorkoutRepository,
        clock: Clock,
        workout: Workout? = nil
    ) {
        self.workoutRepository = workoutRepository
        self.clock = clock
        if let workout {
            self.workout = workout
        } else {
            let now = clock.now()
            self.workout = Workout(name: "", segments: [], createdAt: now, updatedAt: now)
        }
    }

    // MARK: - Segment list operations

    /// Appends a new segment created from a palette selection to the end of
    /// the workout.
    public func addSegment(_ item: SegmentPaletteItem) {
        workout.segments.append(item.makeSegment())
    }

    /// Reorders segments, matching `List.onMove(perform:)`'s signature.
    public func moveSegments(fromOffsets source: IndexSet, toOffset destination: Int) {
        workout.segments.move(fromOffsets: source, toOffset: destination)
    }

    /// Replaces the segment with `id` with `newSegment`, e.g. after editing
    /// it in `SegmentEditorView`/`IntervalBlockEditorView`. No-ops if no
    /// segment with `id` exists (e.g. it was deleted from another binding
    /// while a stale editor was still open).
    public func replaceSegment(id: UUID, with newSegment: WorkoutSegment) {
        guard let index = workout.segments.firstIndex(where: { $0.id == id }) else {
            return
        }
        workout.segments[index] = newSegment
    }

    /// Inserts a fresh-identity copy of the segment with `id` directly after
    /// the original. Every step/block/interval-step id in the copy is
    /// regenerated (see `WorkoutSegment` id semantics) so the duplicate is
    /// independently addressable in the list and by
    /// `ValidateWorkoutPolicy`'s locators. No-ops if no segment with `id`
    /// exists.
    public func duplicateSegment(id: UUID) {
        guard let index = workout.segments.firstIndex(where: { $0.id == id }) else {
            return
        }
        let copy = Self.freshCopy(of: workout.segments[index])
        workout.segments.insert(copy, at: index + 1)
    }

    /// Removes the segment with `id`. No-ops if no segment with `id` exists.
    public func deleteSegment(id: UUID) {
        workout.segments.removeAll { $0.id == id }
    }

    // MARK: - Persistence

    /// Persists the current draft via the injected `WorkoutRepository`,
    /// stamping `updatedAt` from the injected `Clock`. On success, `workout`
    /// reflects the persisted `updatedAt` and `saveError` is cleared. On
    /// failure, `saveError` is set and the in-memory draft is left
    /// unchanged (so the user doesn't lose edits and can retry).
    public func save() async {
        saveError = nil
        isSaving = true
        defer { isSaving = false }

        var toSave = workout
        toSave.updatedAt = clock.now()

        do {
            try await workoutRepository.save(toSave)
            workout = toSave
        } catch let error as WorkoutRepositoryError {
            saveError = error
        } catch {
            saveError = .underlying(String(describing: error))
        }
    }

    /// Loads `workoutID` from the repository for editing, replacing the
    /// current in-memory draft on success and clearing `loadError`. Sets
    /// `loadError` (leaving the current draft unchanged) on failure, or if
    /// no workout with `workoutID` exists.
    public func load(workoutID: UUID) async {
        loadError = nil
        isLoading = true
        defer { isLoading = false }

        do {
            guard let loaded = try await workoutRepository.fetch(id: workoutID) else {
                loadError = .workoutNotFound(id: workoutID)
                return
            }
            workout = loaded
        } catch let error as WorkoutRepositoryError {
            loadError = error
        } catch {
            loadError = .underlying(String(describing: error))
        }
    }

    // MARK: - Private

    /// Deep-copies `segment`, minting a fresh `UUID` for the step (or block
    /// and every interval step within it), per `duplicateSegment(id:)`.
    private static func freshCopy(of segment: WorkoutSegment) -> WorkoutSegment {
        switch segment {
        case let .step(step):
            return .step(SegmentStep(intent: step.intent, goal: step.goal, target: step.target))

        case let .intervalBlock(_, steps, repetitions):
            let freshSteps = steps.map {
                IntervalStep(
                    purpose: $0.purpose,
                    step: SegmentStep(intent: $0.step.intent, goal: $0.step.goal, target: $0.step.target)
                )
            }
            // The `steps:repetitions:` convenience constructor mints a fresh
            // block id too, so the duplicate block itself is a distinct
            // `ValidationLocator.segment(id:)` target.
            return .intervalBlock(steps: freshSteps, repetitions: repetitions)
        }
    }
}
