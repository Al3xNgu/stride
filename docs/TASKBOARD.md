# Stride — Task Board

Orchestrator: execute in order within a phase. `[R]` = dispatch api-researcher first. `[T]` = dispatch test-engineer after build. Every task ends with code-reviewer. Tick `[x]` only after reviewer PASS + green build.

## Phase 0 — Skeleton & validation spike

- [x] 0.1 Create `StridePackages` structure per ARCHITECTURE.md §14: DomainKit, DataKit, FeatureBuilder, FeatureLibrary, FeatureHistory, FeatureRecords, FeatureSettings, DesignSystem, TestSupport, with correct target dependencies (SPM must enforce the dependency rule). Empty placeholder types; `swift test` green.
- [x] 0.2 SwiftLint config + CI workflow (build + `swift test` on PR).
- [x] 0.3 [T] DomainKit entities: Workout, WorkoutSegment (sum type per §5), SegmentIntent, Goal, Target, Milestone, PersonalBest, CompletedRun, Split, SyncJob (+ state enum per §7), UserPreferences. Pure Swift, Equatable/Codable/Identifiable as appropriate.
- [x] 0.4 [T] Validation rules: ValidateWorkout policy (≥1 segment, interval reps ≥1, sane pace ranges, non-negative goals) with exhaustive tests.
- [x] 0.5 [R] RESEARCH: exact WorkoutKit surface for composing a custom running workout (warm-up/blocks/cool-down, goals, pace/HR/cadence alerts, display names + OS gates), validation errors, authorization states, and scheduling/removal APIs + limits. Output feeds 0.6 and 1.x.
- [x] 0.6 [R] SPIKE target: minimal hardcoded interval workout → authorize → schedule, behind a debug screen. Mark all `HARDWARE-VERIFY` points. **Human runs on device; findings go to RESEARCH-LOG before Phase 1.** *(Done 2026-07-10: reviewer PASS + human device run. Key findings in RESEARCH-LOG: schedule cap = 50 (not 15); same-id re-schedule REPLACES; invalid goal values trap at composition. HV-5/HV-8 (on-wrist run) deferred, needed before 1.10.)*

## Phase 1 — MVP

### Persistence
- [x] 1.1 [T] DomainKit ports: WorkoutRepository, RunHistoryRepository, WatchSyncService, PreferencesStore, Clock + TestSupport fakes for each.
- [x] 1.2 [T] DataKit SwiftData models + bidirectional mappers for Workout/Segments/SyncJob/PersonalBest/CompletedRun; SwiftDataWorkoutRepository. Round-trip mapper tests.
- [x] 1.3 UserDefaults-backed PreferencesStore (units, default paces).

### Builder feature
- [x] 1.4 FeatureBuilder: segment list editor — add from palette, reorder, edit, duplicate, delete; distance/time/open goals; pace target UI; interval block editor (work/recovery/reps). ViewModel against fakes. [T]
- [x] 1.5 Live validation surfacing + workout summary (total distance/time) in builder.
- [x] 1.6 DesignSystem: UnitFormatter (pace min/mi ↔ min/km, distance), tokens, shared components used by 1.4.

### Watch sync
- [x] 1.7 [R][T] DataKit WorkoutKitSyncService: domain → composition mapper (use RESEARCH-LOG surface only), authorization flow, schedule/remove, granular error mapping to domain errors.
- [x] 1.8 [T] SyncCoordinator actor + ScheduleWorkoutUseCase implementing the §7 state machine: pending→syncing→synced/failed, retry with backoff, stale-on-edit, foreground reconciliation against scheduled plans.
- [x] 1.9 FeatureLibrary: workout list, sync badges from SyncJob state, Send-to-Watch + schedule-by-date flows, failure reasons UI.

### Health ingestion & records
- [x] 1.10 [R] RESEARCH: HealthKit anchored query + background delivery patterns for running workouts; distance-sample granularity for split derivation; completed-workout ↔ plan linkage reliability.
- [ ] 1.11 [T] DataKit HealthKitRunHistoryRepository: read-only auth (workouts, distance, HR), anchored incremental fetch with persisted anchor, HKWorkout → CompletedRun projection, split derivation from cumulative distance samples.
- [ ] 1.12 [T] IngestCompletedRunsUseCase: idempotent upsert by UUID, deletion tombstones, schedule-window attribution heuristic, triggers PR recalc.
- [ ] 1.13 [T] PersonalBestPolicy: milestone config (1mi/5K/10K/Half/Marathon), tolerance rules, supersede/archive. Exhaustive tests — this is the flagship pure-logic suite.
- [ ] 1.14 FeatureHistory: run list + detail (splits, HR summary). FeatureRecords: PR board + history, link to source run.
- [ ] 1.15 FeatureSettings: units, permission status + priming/re-request flows.

### Assembly
- [ ] 1.16 Composition root wiring, tab navigation, onboarding/priming sequence, empty states.
- [ ] 1.17 End-to-end pass: UI test for build→save→send happy path (sync service faked); full-suite green; reviewer audit of module dependency graph.

## Phase 2 — v1.x (after human MVP sign-off)

- [ ] 2.1 HR-zone & cadence targets (UI unlock; model already supports). [R] for zone-alert specifics.
- [ ] 2.2 Fastest-sub-segment PR policy behind feature flag. [T]
- [ ] 2.3 Workout file export/import (WorkoutKit file format). [R]
- [ ] 2.4 Widgets: next scheduled workout, latest PR (App Group store access).
- [ ] 2.5 Swift Charts for splits/HR; elevation gain read.
- [ ] 2.6 Manual run↔workout linking; workout notes.
