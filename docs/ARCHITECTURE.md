# Structured Running Workouts for Apple Watch — Architecture Blueprint

**Role:** Senior iOS Architecture Plan (no implementation code)
**Working title:** "Stride" (placeholder)
**Targets:** iOS 17+ (WorkoutKit minimum), watchOS 10+ on the paired Watch
**Date:** July 2026

---

## 1. Executive Summary

Stride is an iPhone-first application that lets runners compose structured workouts (warm-up, intervals, tempo/threshold efforts, repeats, cool-down) and push them to the **native Apple Watch Workout app**, then closes the loop by reading completed runs from **HealthKit** and maintaining personal records.

The two most important architectural insights, from which most other decisions follow:

1. **Apple already ships the watch runtime.** WorkoutKit (iOS 17 / watchOS 10) lets a third-party iPhone app compose, validate, preview, and schedule structured workouts that appear directly in the Workout app on the paired Watch — with native pace/HR/cadence alerts, step-by-step guidance, and no companion watch app required. The MVP therefore ships **zero watchOS code**. Execution, sensors, and recording are Apple's problem; our job is authoring, syncing, and analysis.

2. **HealthKit is the system of record for completed activity; our local store is the system of record for authored intent.** We never duplicate HealthKit data as truth — we cache derived projections (summaries, PRs) locally for speed and offline use, and we own the workout definitions, sync state, and preferences in SwiftData.

**Architecture in one paragraph:** A modular, layered MVVM architecture ("MVVM + Clean-ish layering") built with SwiftUI, Swift Concurrency, and SwiftData, organized as Swift Package modules with a strict dependency rule (Features → Domain ← Data). All Apple frameworks (WorkoutKit, HealthKit, CloudKit-future) are hidden behind protocol-based repositories/services owned by the Domain layer and implemented in the Data layer, injected via a composition root. This gives Garmin-Connect-class authoring UX, offline-first behavior, high testability, and clean seams for every listed future feature (AI workouts, plans, coach mode, widgets, Live Activities, cloud sync) without a rewrite.

---

## 2. High-Level System Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│                              iPhone App                                  │
│                                                                          │
│  ┌───────────────────────── Presentation (SwiftUI) ──────────────────┐  │
│  │  WorkoutBuilder   Library   History   Records   Settings   (Feat.)│  │
│  │        │ ViewModels (@Observable, per-feature)                    │  │
│  └────────┼───────────────────────────────────────────────────────────┘ │
│           │  depends on protocols only                                  │
│  ┌────────▼──────────────────── Domain ──────────────────────────────┐  │
│  │  Entities: Workout, WorkoutSegment, CompletedRun, PersonalBest,   │  │
│  │            SyncJob, UserPreferences                               │  │
│  │  Use Cases: BuildWorkout, ValidateWorkout, ScheduleWorkout,       │  │
│  │             IngestCompletedRuns, RecalculatePersonalBests, ...    │  │
│  │  Ports (protocols): WorkoutRepository, RunHistoryRepository,      │  │
│  │             WatchSyncService, HealthPermissionPriming, Clock      │  │
│  └────────▲──────────────────────────────────────────────────────────┘  │
│           │  implements protocols                                       │
│  ┌────────┴───────────────────── Data ───────────────────────────────┐  │
│  │  SwiftDataWorkoutRepository ──► SwiftData store (local, on-device)│  │
│  │  WorkoutKitSyncService      ──► WorkoutKit (compose/validate/     │  │
│  │                                  schedule → Workout app)          │  │
│  │  HealthKitRunHistoryRepo    ──► HealthKit (read runs, HR, splits) │  │
│  │  UserDefaultsPreferences    ──► UserDefaults (lightweight prefs)  │  │
│  │  (future) CloudKitSyncAdapter ─► CloudKit                         │  │
│  └───────────────────────────────────────────────────────────────────┘  │
└──────────────┬───────────────────────────────────┬──────────────────────┘
               │ WorkoutKit scheduling (local,      │ HealthKit central store
               │ system-managed transport)          │ (encrypted, on-device/iCloud)
               ▼                                    ▼
     ┌──────────────────────┐            ┌──────────────────────┐
     │  Apple Watch          │  records  │  HealthKit database   │
     │  Workout app (native) │──────────►│  (HKWorkout, HR,      │
     │  runs the scheduled   │           │  distance, routes)    │
     │  custom workout       │           └──────────────────────┘
     └──────────────────────┘
```

Key property of the diagram: **arrows only point inward toward Domain.** Presentation and Data both depend on Domain; Domain depends on nothing (pure Swift, no Apple framework imports except Foundation). This is the dependency rule that makes the app testable and future-proof.

---

## 3. Feature Breakdown

### 3.1 Workout Builder (core differentiator)
- Segment palette: Warm-up, Easy, Recovery, Tempo, Threshold, Interval Block, Repeat Block, Cool-down. (Warm-up/Easy/Recovery/Tempo/Threshold are the *same structural type* — a single step — differentiated by an `intent` tag and default target ranges; this keeps the model small.)
- Per-segment goal: **distance** (mi/km, unit-aware), **duration**, or **open** (until user taps next).
- Per-segment target/alert: pace range or single threshold (MVP); heart-rate zone/range and cadence marked as model-ready, UI-gated behind a feature flag (WorkoutKit already supports these alert types, so "future" here is a product decision, not a technical one).
- Interval blocks: work step + recovery step, each with its own goal/target, × N repetitions; blocks can contain multiple steps to support ladders/pyramids later.
- Editing: reorder (drag), duplicate, delete, inline edit; whole-workout duplicate ("Save as copy").
- Live validation: total-distance/duration summary, and pre-flight WorkoutKit validation surfaced as inline errors *before* the user hits "Send to Watch" (WorkoutKit validates compositions at creation and returns granular errors — we surface these early rather than at sync time).
- Preview: system WorkoutKit preview sheet as the final confirmation step (free native UI, builds user trust).

### 3.2 Workout Library
- Saved workouts list with search, sort, duplicate, archive.
- Sync status badge per workout (Draft / Scheduled / On Watch / Failed / Stale — see §7 state machine).

### 3.3 Watch Sync
- One-tap "Send to Watch" and optional "Schedule for date/time".
- Sync queue with retry, failure reasons in plain language, and a "what's currently on the Watch" reconciliation view.

### 3.4 Run History (HealthKit read)
- Completed runs: distance, duration, average pace, splits (derived), heart-rate summary; elevation gain flagged future.
- Attribution: best-effort matching of a completed HKWorkout back to the scheduled Stride workout (via scheduled date/time proximity and workout plan association where available).

### 3.5 Personal Records
- Auto-maintained PRs for 1 mi, 5K, 10K, Half, Marathon; milestone list is data-driven (a `Milestone` value = distance + tolerance + display name) so adding "50K" is a one-line config change, not a refactor.
- PR history (previous bests), date achieved, link to the source run.

### 3.6 Settings / Preferences
- Units (mi/km), default paces per intent, HealthKit/WorkoutKit permission status and re-request flows, data export.

---

## 4. Module / Package Organization

Local Swift Package (`StridePackages`) with one library target per module; the Xcode app target is a thin shell. SPM enforces the dependency rule at compile time — a Feature module *cannot* import HealthKit code even by accident.

```
StrideApp (Xcode app target — composition root, App/Scene lifecycle only)
 └── depends on: all Feature modules + DataKit (for wiring)

StridePackages/
 ├── DomainKit          (entities, use cases, repository/service protocols,
 │                       validation, PR policy — pure Swift, zero Apple SDKs)
 ├── DataKit            (SwiftData models & mappers, HealthKit adapter,
 │                       WorkoutKit adapter, UserDefaults adapter)
 │        └── depends on: DomainKit
 ├── FeatureBuilder     (workout builder UI + view models)
 ├── FeatureLibrary     (library UI + view models)
 ├── FeatureHistory     (run history UI + view models)
 ├── FeatureRecords     (PR UI + view models)
 ├── FeatureSettings
 │        └── all Features depend on: DomainKit + DesignSystem (never DataKit)
 ├── DesignSystem       (colors, typography, reusable components, previews)
 └── TestSupport        (in-memory fakes of every Domain protocol, fixtures)
```

Why this decomposition:
- **DomainKit is dependency-free** → millisecond unit tests, and the future Watch companion app or widget extension can link it directly.
- **Features don't know about DataKit** → swapping SwiftData for something else, or adding CloudKit, touches one module.
- **TestSupport fakes** mean every feature is previewable and testable without HealthKit entitlements or a paired Watch — critical because Watch/HealthKit behavior can't run in unit tests or simulators reliably.

---

## 5. Data Model and Entity Relationships

Domain entities are plain Swift value types (structs/enums). SwiftData `@Model` classes live only in DataKit and are mapped to/from these — persistence details never leak upward.

```
UserPreferences (1) ────────────── singleton-ish; units, defaults, flags

Workout (1) ──────< WorkoutSegment (ordered, 1..n)
   │                     │
   │                     └── SegmentKind:
   │                          .step(intent, goal, target?)          — warm-up, easy,
   │                          .intervalBlock(steps: [IntervalStep], —  tempo, etc.
   │                                          repetitions: Int)
   │
   ├──────< SyncJob (0..n)          — one per sync attempt/schedule
   │
   └────── (soft link) ──► CompletedRun (0..n)   — attribution, not ownership

CompletedRun  ── read-model projected from HealthKit (HKWorkout UUID as key)
   │
   └──────< Split (derived, 0..n)   — computed from distance samples, cached

PersonalBest (per Milestone) ──► references CompletedRun (source of the record)
Milestone (config value)     ──  1mi / 5K / 10K / Half / Marathon / future…
```

Entity notes and rationale:

- **Workout** — user-authored template: name, notes, activity/location (outdoor run), ordered segments, createdAt/updatedAt, `schemaVersion`. It exists because authored intent must survive independently of both the Watch and HealthKit; it's the asset users build a library from.
- **WorkoutSegment** — a sum type rather than a class hierarchy. A single `intent` enum (warmUp, easy, recovery, tempo, threshold, work, rest, coolDown) on a common step shape avoids eight near-identical types and maps 1:1 onto WorkoutKit's step/block model, keeping the WorkoutKit mapper trivial. Targets are modeled as an enum (`pace(range)`, `heartRate(zone|range)`, `cadence(range)`, `none`) so HR/cadence "future" support is purely a UI unlock.
- **SyncJob** — exists because *sync is a process, not a property*. It records the state machine (§7), timestamps, the WorkoutKit plan identifier, scheduled date, attempt count, and last error. Keeping this separate from Workout means a workout can have history of syncs, retries are auditable, and the library badge is a cheap query.
- **CompletedRun** — a *projection* of an HKWorkout (UUID, distance, duration, avg pace, HR summary, source, date). It exists so History and PR screens work instantly and offline, and so we can attach app-side data (attribution to a Workout, user notes) that HealthKit can't store for us. HealthKit remains the source of truth; projections are rebuildable at any time (idempotent ingestion keyed by HKWorkout UUID).
- **PersonalBest** — exists as a stored entity (not computed on the fly) because computing PRs requires scanning full history; we compute incrementally on ingestion and persist. Stores milestone, elapsed time, achieving run reference, achievedAt, plus superseded records for "PR history".
- **UserPreferences** — units and defaults; separated so every feature doesn't grow its own settings tendrils.

Relationship rationale summary: Workout→Segments is composition (segments have no life outside a workout). Workout→SyncJob is one-to-many history. Workout↔CompletedRun is a *soft* reference (nullable), because runs can exist without our workouts and workouts without runs. PersonalBest→CompletedRun is a hard reference within our store but ultimately keys back to an HKWorkout UUID.

---

## 6. Component Responsibilities

| Component | Layer | Responsibility | Explicitly NOT responsible for |
|---|---|---|---|
| Feature ViewModels (`@Observable`) | Presentation | Screen state, user intent → use case calls, formatting via `UnitFormatter` | Persistence, HealthKit/WorkoutKit types, business rules |
| `BuildWorkoutUseCase` / `ValidateWorkout` | Domain | Structural rules (e.g., interval block needs ≥1 rep, pace ranges sane), unit normalization (store meters/seconds internally) | UI error presentation |
| `ScheduleWorkoutUseCase` | Domain | Orchestrates: validate → persist → enqueue SyncJob → invoke WatchSyncService → update state | Talking to WorkoutKit directly |
| `WatchSyncService` (protocol) / `WorkoutKitSyncService` (impl) | Domain / Data | Map domain Workout → WorkoutKit composition, request authorization, schedule/remove plans, report granular failures | Deciding retry policy (Domain's job) |
| `RunIngestionSource` / `HealthKitRunHistoryRepository` | Domain / Data | Map anchored HealthKit workout changes into `IngestionBatch` projections and an opaque cursor | Persisting projections or advancing the cursor |
| `IngestionAnchorStore` / `SwiftDataIngestionAnchorStore` | Domain / Data | Persist and replace the opaque HealthKit cursor in SwiftData | Query mechanics or projection mapping |
| `RunIngestionDelivery` / `HealthKitRunBackgroundDelivery` | Domain / Data | Register the running-workout observer and background-delivery wake-up | Performing ingestion or persistence |
| `RunHistoryRepository` / `SwiftDataRunHistoryRepository` | Domain / Data | Persist and query completed runs, splits, and personal-best records | HealthKit query mechanics |
| `HealthPermissionPriming` (protocol) / HealthKit impl | Domain / Data | Read-only HealthKit authorization status and priming, with typed operational failures | Claiming that read access was granted |
| `IngestCompletedRunsUseCase` | Domain | Idempotent upsert of projections, triggers PR recalculation, workout attribution heuristic | Query mechanics |
| `PersonalBestPolicy` | Domain | Pure function: (run, milestones, current PRs) → PR updates; distance tolerance rules | I/O of any kind (this purity makes it exhaustively unit-testable) |
| `WorkoutRepository` / SwiftData impl | Domain / Data | CRUD for workouts, sync jobs, PRs, prefs; migrations | Business rules |
| Composition Root (App target) | App | Build the object graph once at launch; choose real vs fake implementations (previews/tests/demo mode) | Everything else |
| `SyncCoordinator` | Domain | Owns the SyncJob state machine, retry/backoff, reconciliation on foreground | UI |

**Dependency injection approach:** constructor injection from a single composition root, with protocols defined in DomainKit. No third-party DI framework — the app has ~10 injectable services; a container library adds complexity without payoff. SwiftUI `Environment` is used only to pass already-constructed view models/routers down, not as a service locator.

---

## 7. Data Flow: Workout Creation → Apple Watch

```
User edits ──► BuilderViewModel ──► ValidateWorkout (live, on change)
                                        │ errors → inline UI
User taps "Save" ──► WorkoutRepository.save (SwiftData)  [offline-safe: done]

User taps "Send to Watch"
   └─► ScheduleWorkoutUseCase
         1. re-validate (domain + WorkoutKit pre-flight validation)
         2. create SyncJob(.pending), persist            ← crash-safe from here
         3. WatchSyncService:
              a. check WorkoutPlan authorization state → request if needed
              b. map Workout → custom workout composition
                 (warm-up step, interval blocks with work/recovery ×N,
                  cool-down step; pace/HR/cadence alerts per step)
              c. optionally present system preview sheet (user confirms)
              d. schedule plan (with date if user picked one)
         4. on success → SyncJob(.synced, planID); library badge updates
         5. on failure → SyncJob(.failed(reason)); SyncCoordinator applies
            retry policy (backoff for transient; surface actionable message
            for permanent: not authorized, invalid composition, no paired watch)

Watch side: scheduled workout appears in the native Workout app
            (dedicated section); user starts it from the wrist. No app code.

SyncJob state machine:
  draft ─► pending ─► syncing ─► synced ─► (completedRunLinked | stale)
                        │
                        └─► failed ─► pending (retry) | abandoned
  Workout edited after synced ⇒ mark job `stale`, prompt re-send
  (edit-after-sync is the classic footgun; making staleness explicit
   prevents "the watch ran my old version" support tickets).
```

Reconciliation: on app foreground, SyncCoordinator lists currently scheduled plans from WorkoutKit and diffs against local SyncJobs — repairing state if the user removed a workout on the Watch or the schedule expired. Local store is authoritative for *intent*; WorkoutKit is authoritative for *what's actually scheduled*.

---

## 8. Data Flow: HealthKit Ingestion & Personal Bests

```
App launch / foreground / background delivery wake-up
   └─► RunIngestionDelivery wakes RunIngestionCoordinator
         1. HKObserverQuery + background delivery on workoutType (running)
         2. FIFO coordinator reads SwiftData's persisted cursor and runs
            HKAnchoredObjectQuery → new/updated/deleted
            HKWorkouts since last sync (anchor stored in SwiftData)
         3. For each running HKWorkout:
              fetch distance & HR statistics/samples → build CompletedRun
              derive kilometre splits from cumulative distance samples
   └─► IngestCompletedRunsUseCase (called by the coordinator)
         4. Upsert projection keyed by HKWorkout.uuid (idempotent);
            handle HealthKit deletions by tombstoning the projection
         5. Attribution heuristic: match to Workout via schedule window
         6. PersonalBestPolicy per milestone:
              candidate if |run.distance − milestone.distance| ≤ tolerance
              (e.g., 5K tolerance ~1–2%: GPS overshoot counts, a 7K doesn't)
              MVP: whole-run time for milestone-distance runs
              Future flag: "fastest sub-segment" extraction from splits
              (true fastest 5K inside a 10K) — policy object swap, no schema change
         7. New PR ⇒ persist, archive superseded record, emit domain event
            → Records UI updates, (future) notification / widget reload
         8. Persist the returned opaque HealthKit cursor only after all prior
            projection, split, tombstone, and personal-best writes succeed
```

The observer is installed during application launch so background delivery has a retained callback before scene creation. Foreground activation independently reconciles through the same cursor path. HealthKit authorization is requested only from the explicit Connect Health action.

Privacy posture: all reads on-device; we request read-only HealthKit scopes (workouts, distance, HR; elevation later), never write to HealthKit in MVP, and never transmit health data off device. The Connect Health screen explains why each scope is needed (also an App Review requirement).

---

## 9. Architecture Choice & Technology Stack (with justification)

### 9.1 MVVM vs TCA vs Clean Architecture

| Criterion | MVVM (+ layering) | TCA | "Full" Clean/VIPER |
|---|---|---|---|
| Fit with SwiftUI/`@Observable` | Native | Good but framework-mediated | Awkward ceremony |
| Team ramp-up / hiring | Lowest | Steep (Reducer/Store/Effect model) | Moderate–high |
| Testability | High *if* domain is separated | Very high | High |
| 3rd-party dependency risk | None | Point-Free library churn tracking Swift releases | None |
| Boilerplate for CRUD+forms app | Low | Moderate–high | High |
| Complex shared state | Adequate here | Its sweet spot | Adequate |

**Decision: MVVM with Clean Architecture *layering* (Domain/Data/Presentation + dependency rule), not TCA, not full Clean/VIPER.**

Reasoning: this app's complexity lives in *integration* (WorkoutKit, HealthKit, sync state) and *domain rules* (validation, PR policy), not in intricate cross-screen state graphs — TCA's payoff. We take Clean Architecture's genuinely valuable ideas (entities, use cases, ports/adapters, dependency inversion) and skip the ceremonial ones (interactor/presenter indirection per screen). MVVM keeps SwiftUI idiomatic; the strict module boundary supplies the testability people usually adopt TCA for. TCA would also add a large third-party dependency to an app whose bet is "native Apple ecosystem" — a philosophical and practical mismatch. If a future feature (e.g., collaborative coach mode) develops genuinely complex state, TCA can be adopted *inside one feature module* without touching the rest — a benefit of the modular layout.

### 9.2 Patterns
- **Repository pattern** for anything persisted or queried (workouts, run history, PRs, prefs): isolates SwiftData/HealthKit, enables in-memory fakes, and gives one seam for the future CloudKit adapter.
- **Services** for imperative capabilities with external effects (WatchSyncService). **"Managers" are deliberately avoided as a naming/design pattern** — grab-bag `FooManager` singletons are how iOS codebases rot; every type gets a single responsibility and an injected lifetime instead.
- **Use cases** only where orchestration or rules exist (Schedule, Ingest, PR). Trivial pass-throughs are not wrapped — avoiding ceremony is a stated requirement.
- **Domain events** (lightweight AsyncStream-based bus in DomainKit) for cross-feature reactions (new PR → Records refresh, future widget reload) without feature-to-feature imports.

### 9.3 Stack

| Concern | Choice | Justification |
|---|---|---|
| UI | SwiftUI (iOS 17+) | WorkoutKit already forces iOS 17 floor; `@Observable` removes most Combine needs |
| Concurrency | Swift Concurrency (async/await, actors) | HealthKit/WorkoutKit are async-native; actors guard SyncCoordinator state |
| Persistence | SwiftData | iOS 17 floor makes it viable; models isolated in DataKit behind repositories so the Core Data escape hatch (or custom stack) is a module swap, not an app rewrite; built-in CloudKit path for future sync |
| Watch delivery | WorkoutKit | Purpose-built: compose/validate/preview/schedule custom workouts into the native Workout app; supports pace, cadence, HR, power alerts and named steps (watchOS 11) |
| Health data | HealthKit (read-only MVP) | System of record; anchored queries + background delivery for incremental ingest |
| Prefs | UserDefaults (thin adapter) | Correct tool for small flags/units |
| Networking | **None in MVP** | Deliberate: no backend, no accounts. `NetworkingKit` appears only when cloud features do; URLSession + Codable then |
| DI | Manual composition root | ~10 services; frameworks add cost without benefit |
| Testing | Swift Testing + XCTest UI tests; snapshot tests for DesignSystem | Domain purity → fast deterministic suites; TestSupport fakes for Watch/Health |
| Tooling | SwiftLint, SwiftFormat, Xcode Cloud or GitHub Actions CI | Consistency; PR-gated tests |

### 9.4 Storage decision table

| Data | Where | Why |
|---|---|---|
| Workout definitions, segments | SwiftData | Structured, relational, queried, migrated; the app's core asset |
| SyncJobs + WorkoutKit plan IDs | SwiftData | Must survive crashes mid-sync; queried for badges/retries |
| CompletedRun projections, splits, PRs, HK anchors | SwiftData | Cache/derived — rebuildable, but needed for offline & instant UI |
| Completed workouts, HR, distance samples, routes | HealthKit (read) | Already there, encrypted, user-controlled; duplicating raw samples would waste space and create consistency bugs |
| Units, default paces, flags, onboarding state | UserDefaults | Tiny, non-relational, no migration needs |
| Nothing in MVP | CloudKit | Future: private DB for workout library sync via SwiftData-CloudKit or CKSyncEngine; PRs re-derive per device so only *authored* data needs sync — a deliberately small sync surface |
| Secrets | Keychain (future, accounts only) | None exist in MVP |

---

## 10. Scalability: How Future Features Land

| Future feature | Landing zone | Refactor cost |
|---|---|---|
| AI-generated workouts | New `WorkoutGenerator` port in Domain + provider in DataKit (on-device model or API); output is a plain `Workout` → whole existing pipeline (validate/save/sync) works untouched | Low |
| Race training plans | New `TrainingPlan` entity composing existing `Workout`s + scheduling via existing WorkoutKit date-scheduling path | Low–medium |
| Coach mode / sharing / social | First real backend: add `NetworkingKit` + CloudKit shared DB or custom API behind new repositories; Domain unchanged | Medium (contained) |
| Cloud sync | CloudKit adapter behind existing `WorkoutRepository` protocol | Low–medium |
| Widgets / Live Activities | New extension targets linking DomainKit + DesignSystem; App Group container for the SwiftData store (decide **day one** — see risks) | Low if App Group set early |
| Watch companion app (custom in-run UX) | New watchOS target; HealthKit workout **session mirroring** already designed for this; DomainKit reused | Medium (it's a product, not a refactor) |
| Analytics / trends / VO₂ max / recovery | New Feature module + read-only HealthKit scopes; heavy computation into a dedicated module or background task | Low–medium |

The common thread: every feature is either a new port implementation, a new entity, or a new feature module — none require touching existing modules' internals. That is the payoff of the dependency rule.

---

## 11. Risks, Assumptions, Trade-offs

**Risks**
1. **WorkoutKit ceiling** (highest risk): scheduled-workout count limits, schedule expiry windows, alert-per-step limits, and authorization being separate from HealthKit's are all behaviors to verify on hardware early (spike in Phase 0). If a needed capability is missing, the fallback is a full watchOS companion app — a large scope change; better to learn in week 1 than month 4.
2. **Attribution is heuristic**: HealthKit doesn't reliably tell us "this HKWorkout came from your scheduled plan" across all OS versions; matching by time window can mis-attribute. Mitigate: conservative matching + manual "link to workout" affordance; validate the HKWorkout→composition extension on current OS.
3. **Split derivation accuracy**: deriving per-km/mi splits from cumulative distance samples has sampling-rate edge cases (pauses, tunnels). Mitigate: tolerance-based PR policy, golden-file tests with real exported sample data.
4. **SwiftData maturity**: known sharp edges (migrations, concurrency). Mitigate: repository isolation (swap-out escape hatch), `schemaVersion` on entities, migration tests in CI.
5. **Background delivery reliability**: HealthKit background updates are best-effort. Mitigate: always reconcile on foreground; never depend on background for correctness, only freshness.

**Assumptions**
- iOS 17+ / watchOS 10+ floor is acceptable (WorkoutKit requires it; by 2026 this covers the overwhelming majority of active devices).
- iPhone-first product; native Workout app in-run UX is sufficient for v1 (no custom watch metrics screens).
- Single user, no accounts, no backend in MVP.
- English-only launch acceptable; unit-handling (mi/km) built in from day one regardless.

**Trade-offs accepted**
- *No watch app in MVP*: dramatically less code and battery/reliability risk, at the cost of no custom in-run UI and dependence on Apple's execution UX. Right trade for a structured-workout authoring product.
- *MVVM over TCA*: less enforced uniformity in exchange for zero dependency risk and easier hiring; discipline supplied by module boundaries instead of a framework.
- *Projections over live HealthKit queries in UI*: small consistency lag + rebuild logic in exchange for offline-first instant screens.
- *Manual DI*: a few lines of wiring per service instead of a container dependency.

---

## 12. Phased Roadmap

**Phase 0 — Technical validation spike (1–2 weeks)**
Hardware prototype: compose one interval workout in code → authorize → schedule → run it on a real Watch → observe the HKWorkout that comes back (including whether the composition/plan linkage is retrievable). Verify: pace-alert UX outdoors, schedule limits/expiry, edit/replace behavior, background delivery wake-ups. *Everything in §13 gets answered here.* Also: set up SPM module skeleton, CI, App Group + entitlements.

**Phase 1 — MVP (6–8 weeks)**
- Builder: all segment intents, distance/time/open goals, pace targets, interval blocks with reps; reorder/edit/duplicate/delete; validation + preview sheet.
- Library with sync badges; Send to Watch + schedule-by-date; SyncJob state machine with retry + reconciliation.
- HealthKit ingest (runs, distance, duration, avg pace, HR summary), History list + run detail with splits.
- PRs for the five milestones (whole-run policy), Records screen.
- Settings: units, permissions status, priming flows.
- Test suite: PR policy & validation exhaustively unit-tested; sync state machine tested against fake WatchSyncService.

**Phase 2 — Version 1.x (4–6 weeks)**
- HR-zone and cadence targets (UI unlock of existing model), named steps on watchOS 11+.
- PR "fastest sub-segment" policy (true fastest 5K within longer runs) behind a flag.
- Manual run↔workout linking; workout notes; export/import workout files (WorkoutKit file format — cheap sharing before any backend).
- Widgets (next scheduled workout, latest PR) — App Group already in place.
- Polish: charts (Swift Charts) for splits/HR, elevation gain read.

**Phase 3 — Future**
- CloudKit sync of the workout library → multi-device.
- Training plans (calendar of workouts, bulk scheduling).
- AI-generated workouts (on-device generation producing standard `Workout`s).
- Live Activities for scheduled-workout day; watch companion app with session mirroring if custom in-run UX becomes the differentiator.
- Social/coach features (first backend), analytics/trends/VO₂ max module.

---

## 13. Areas Requiring Apple-API Research / Validation (Phase 0 checklist)

1. **WorkoutKit scheduling limits & lifecycle**: max concurrent scheduled plans, how far ahead scheduling works, when scheduled workouts expire/disappear, and replace-vs-duplicate semantics when re-sending an edited workout.
2. **Authorization model**: WorkoutPlan authorization states and recovery UX when denied; interaction (or lack thereof) with HealthKit authorization.
3. **Completed-run linkage**: reliability of retrieving the workout composition from a completed HKWorkout on current iOS/watchOS, per-version differences, and whether plan IDs survive round-trip — this determines how heuristic attribution must be.
4. **Alert behavior in the field**: current-vs-average pace alert feel, alerts-per-step constraints, HR-zone alert configuration (user zones vs explicit ranges), indoor-run pace support (watchOS 11+).
5. **Split/route data**: sampling granularity of distance samples for split derivation; HKWorkoutRoute access and its extra authorization for future map/elevation features.
6. **Background delivery**: real-world wake-up latency for workout background delivery; interaction with Low Power Mode.
7. **SwiftData + App Group + (later) CloudKit**: store-in-App-Group configuration for widget access; SwiftData↔CloudKit constraints (unique constraints, relationships) to pre-shape the schema now.
8. **Preview sheet UX**: whether the system preview presentation fits the send flow or should be optional after first use.

---

## 14. Suggested Project Folder Structure

```
Stride/
├── StrideApp/                        # Xcode app target (thin)
│   ├── StrideApp.swift               # @main, scene setup
│   ├── CompositionRoot.swift         # builds & injects the object graph
│   ├── AppRouter.swift               # tab/root navigation
│   └── Resources/                    # assets, Info.plist, entitlements
├── StridePackages/
│   ├── Package.swift
│   ├── Sources/
│   │   ├── DomainKit/
│   │   │   ├── Entities/             # Workout, Segment, CompletedRun, PR…
│   │   │   ├── UseCases/             # ScheduleWorkout, IngestRuns…
│   │   │   ├── Policies/             # PersonalBestPolicy, ValidationRules
│   │   │   ├── Ports/                # protocols: repositories & services
│   │   │   └── Events/               # domain event definitions + bus
│   │   ├── DataKit/
│   │   │   ├── Persistence/          # SwiftData models, mappers, migrations
│   │   │   ├── Health/               # HealthKit adapter, anchors, split calc
│   │   │   ├── WatchSync/            # WorkoutKit mapper + sync service
│   │   │   └── Preferences/          # UserDefaults adapter
│   │   ├── FeatureBuilder/           # Views/ ViewModels/ per feature
│   │   ├── FeatureLibrary/
│   │   ├── FeatureHistory/
│   │   ├── FeatureRecords/
│   │   ├── FeatureSettings/
│   │   ├── DesignSystem/             # tokens, components, formatters
│   │   └── TestSupport/              # fakes, builders, fixtures
│   └── Tests/
│       ├── DomainKitTests/           # policy & use-case tests (fast, pure)
│       ├── DataKitTests/             # mapper + migration tests
│       └── Feature…Tests/            # view-model tests against fakes
└── ci/                               # lint config, CI workflows
```

---

### Closing note

The blueprint's center of gravity is deliberately boring: native frameworks, a strict dependency rule, and two clear systems of record (SwiftData for intent, HealthKit for outcomes). The genuinely novel engineering lives in three well-isolated spots — the domain↔WorkoutKit mapper, the sync state machine, and the PR policy — and each is a pure or protocol-bounded component that a small team can build, test, and evolve independently.
