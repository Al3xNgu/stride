# Stride Project Status

Updated: 2026-10-09

Stride is in Phase 1 (MVP). Tasks 1.1–1.10 and 1.12–1.17 are implemented in the current checkout. Task 1.11's implementation slice is present: durable cursor storage, run-history persistence, serialized ingestion, observer/background registration, app configuration, and a production composition-root caller. Task 1.11 remains open for signed-device verification of background delivery, permission-denial recovery, Apple Watch sample granularity, and `HKWorkout.workoutPlan` linkage.

The current change set completes production app composition for Library/Builder, History/Run Detail, Records, and Settings. First launch uses SettingsViewModel-owned UserPreferences with an explicit Health connection or continue choice and a recoverable corrupt-preferences state. Successful Health imports reload History/Records, returning from Builder reloads Library, and display units propagate from preferences. Persisted split storage remains kilometre-granular.

Verification on 2026-10-09:

- `swift test` with Xcode 27: all 636 Swift Testing tests across 9 package targets passed; XCTest discovered no tests.
- `swiftlint lint --strict --no-cache`: passed with 0 violations across 183 files.
- iOS simulator build: passed with Xcode 27 for iPhone 18 Pro, iOS 27, with signing disabled. Simulator launch smoke passed; the unsigned simulator showed recoverable HealthKit and background-registration errors, so no permission grant or ingestion was validated. No signed device or paired-Watch run was performed.

Known issues and blockers:

- HealthKit background delivery, observer queries, durable anchor persistence, and the composition-root ingestion caller are implemented. Signed-device verification is still required; the simulator cannot prove wake latency, read-denial UX, Apple-Watch sample granularity, or workout-plan linkage.
- Task 1.16's simulator smoke covered first-launch onboarding, the Library empty state, and the four-tab shell. Task 1.17's end-to-end UI test creates, saves, and sends a workout through a fake watch service; it passed on the iPhone 18 Pro simulator. The full package suite passed (636 tests across 9 targets), strict lint passed (0 violations across 181 files), and the module audit passed after retiring the completed task 0.6 debug spike.
- WorkoutKit and HealthKit round-trip behavior remains hardware-dependent; see the open items in `docs/RESEARCH-LOG.md`.

Implementation preparation for task 1.11 is captured in [`TASK-1.11-PLAN.md`](TASK-1.11-PLAN.md). The plan fixes the commit-cursor invariant: a HealthKit anchor advances only after the domain ingestion batch has persisted successfully.

Immediate next steps:

1. Run the [signed-device validation protocol](TASK-1.11-DEVICE-VALIDATION.md) for task 1.11: background delivery, permission denial, durable ingestion, deletion, and Apple-Watch sample granularity. `HKWorkout.workoutPlan` linkage remains a separately approved follow-up because the current adapter uses the documented schedule-window heuristic.
2. Start Phase 2 feature work after MVP sign-off, beginning with HR-zone and cadence targets.

The detailed architecture, research evidence, and orchestration procedure remain authoritative in [`ARCHITECTURE.md`](ARCHITECTURE.md), [`RESEARCH-LOG.md`](RESEARCH-LOG.md), and [`ORCHESTRATION.md`](ORCHESTRATION.md).
