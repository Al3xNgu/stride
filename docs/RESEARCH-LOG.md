# Research Log

Append-only log of Apple API findings (api-researcher) and hardware spike results (human). Builders may only use WorkoutKit/HealthKit surface recorded here as **verified**.

---

## 2026-10-08 — Continuation audit and MVP presentation fixes

The read-only continuation audit found that the current HealthKit adapter performs a one-shot anchored fetch and returns an archived anchor, but no production caller persists that anchor or pairs the fetch with `HKObserverQuery` and background delivery. Task 1.11 remains open until those pieces and the app's HealthKit capability/`NSHealthShareUsageDescription` are added. The existing July SDK findings remain valid; this entry records implementation status, not a new Apple API claim.

The Health permission boundary is now a DomainKit `HealthPermissionPriming` port with typed `HealthPermissionStatus`/`HealthPermissionPrimingError`, a DataKit implementation backed by the verified authorization APIs, and a TestSupport fake. FeatureSettings only consumes the port and does not import HealthKit. Read authorization remains opaque after the prompt: `.unnecessary` means already requested, not granted.

The audit also found and fixed a retry-order defect in `IngestCompletedRunsUseCase`: run and split persistence now precede the `.completedRunLinked` transition, and replay retries the transition for an already-attributed run. Adversarial tests cover failures at both persistence boundaries.

---

## 2026-07-06 — Task 0.5: WorkoutKit API surface (compose / validate / preview / authorize / schedule)

**Researcher:** api-researcher. **Primary evidence (strongest):** the Swift module interface shipped in Xcode 26.6, read directly at
`/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk/System/Library/Frameworks/WorkoutKit.framework/Modules/WorkoutKit.swiftmodule/arm64e-apple-ios.swiftinterface`
(module version 2026.5.10, target iOS 26.5). SwiftUI overlay read at the sibling `_WorkoutKit_SwiftUI.framework/.../arm64e-apple-ios.swiftinterface`.
**Secondary evidence:** WWDC23 session 10016 "Build custom workouts with WorkoutKit" (numbers for limits/window). Apple HTML docs are JS-rendered and could not be fetched; SDK interface used instead — it is authoritative for signatures.
Every signature below is copied verbatim from the interface unless marked otherwise. All base types are `iOS 17.0+ / watchOS 10.0+` unless a tighter gate is noted.

### 1. Composition types — **verified** (SDK interface)
- `public struct CustomWorkout : Equatable, Hashable, Sendable`
  `public init(activity: HKWorkoutActivityType, location: HKWorkoutSessionLocationType = .unknown, displayName: String? = nil, warmup: WorkoutStep? = nil, blocks: [IntervalBlock] = [], cooldown: WorkoutStep? = nil)`
  — **non-throwing.** Fields: `activity`, `location`, `displayName: String?`, `warmup: WorkoutStep?`, `blocks: [IntervalBlock]`, `cooldown: WorkoutStep?`. Warm-up and cool-down are single optional `WorkoutStep`s; all repeated work lives in `blocks`.
- `public struct WorkoutStep : Equatable, Hashable, Sendable`
  `public init(goal: WorkoutGoal = .open, alert: (any WorkoutAlert)? = nil)`. Fields: `goal: WorkoutGoal`, `alert: (any WorkoutAlert)?`. **At most ONE alert per step** (single optional, not an array).
  `@available(iOS 18.0, watchOS 11.0, *) public var displayName: String?` + an `init(goal:alert:displayName:)` — **named/labelled steps require iOS 18 / watchOS 11** (above our floor; feature-gate it).
- `public struct IntervalBlock : Equatable, Hashable, Sendable`
  `public init(steps: [IntervalStep] = [], iterations: Int = 1)`. Repetitions are expressed by `iterations: Int` (this is "×N"). A block holds an ordered `[IntervalStep]` — supports ladders/pyramids.
- `public struct IntervalStep : Equatable, Hashable, Sendable`
  `public enum Purpose { case work; case recovery }`
  `public init(_ purpose: IntervalStep.Purpose, step: WorkoutStep)`
  `public init(_ purpose: IntervalStep.Purpose, goal: WorkoutGoal = .open, alert: (any WorkoutAlert)? = nil)`. Fields: `purpose`, `step: WorkoutStep`.
- `public struct WorkoutPlan : Equatable, Hashable, Sendable, Identifiable`
  `public var workout: WorkoutPlan.Workout`; `public var id: UUID` (stable identifier — persist this).
  `public enum Workout { case goal(SingleGoalWorkout); case custom(CustomWorkout); case pacer(PacerWorkout); case swimBikeRun(SwimBikeRunWorkout) }`
  `public init(_ workout: WorkoutPlan.Workout, id: UUID = UUID())` and `public init(from data: Data) throws`.
  → For Stride a custom running workout is `WorkoutPlan(.custom(myCustomWorkout))`.

### 2. Goals — **verified** (SDK interface)
`public enum WorkoutGoal : Equatable, Hashable, Sendable`:
- `case open`
- `case distance(Double, UnitLength)`
- `case time(Double, UnitDuration)`
- `case energy(Double, UnitEnergy)`
- `@available(iOS 18.0, watchOS 11.0, *) case poolSwimDistanceWithTime(Measurement<UnitLength>, Measurement<UnitDuration>)` (not relevant to running).
Note: distance/time goals take a bare `(Double, Unit…)` pair, NOT a `Measurement`. Stride stores meters/seconds internally → map to `.distance(meters, .meters)` / `.time(seconds, .seconds)`.

### 3. Alerts / targets — **verified** (SDK interface). Protocol: `public protocol WorkoutAlert : Hashable, Sendable { var metric: WorkoutAlertMetric { get }; func supports(activity:location:) -> Bool }`. `enum WorkoutAlertMetric { case current; case average }`.
Running-relevant alert types (each has a value init + a `WorkoutAlert` static-factory convenience):
- Pace/speed: `SpeedThresholdAlert(target: Measurement<UnitSpeed>, metric: WorkoutAlertMetric)` and `SpeedRangeAlert(target: ClosedRange<Measurement<UnitSpeed>>, metric: WorkoutAlertMetric)`. Factories: `.speed(_ value:unit:metric: = .current)`, `.speed(_ range:unit:metric: = .current)`. **There is NO "PaceAlert" type — pace is modeled as speed (UnitSpeed).** Stride stores seconds-per-meter → invert to m/s at the WorkoutKit edge.
- Heart rate: `HeartRateRangeAlert(target: ClosedRange<Measurement<UnitFrequency>>)` via `.heartRate(_ range:unit: = .countPerMinute)`, and `HeartRateZoneAlert(zone: Int)` via `.heartRate(zone:)`. Both zone-based (user's zones on device) and explicit-range are supported.
- Cadence: `CadenceThresholdAlert(target: Measurement<UnitFrequency>)` / `CadenceRangeAlert(target: ClosedRange<…>)` via `.cadence(_:unit:)` / `.cadence(_ range:unit:)`.
- Power: `PowerThresholdAlert` / `PowerRangeAlert` / `PowerZoneAlert(zone: Int)`. Power alerts gained a `metric:` selector only at **iOS 17.4 / watchOS 10.4** (base 17.0 init has no metric param).
- **One alert per step** (see §1 — `WorkoutStep.alert` is a single optional). No documented "alerts-per-step" list; the type system caps it at 1.

### 4. Validation — **verified (mechanism) / probable (exact error type)**
- The shipping SDK `CustomWorkout.init` and `WorkoutStep.init` are **non-throwing**. Validation is surfaced two ways:
  (a) **static capability checks** — `CustomWorkout.supportsActivity(_:)`, `CustomWorkout.supportsGoal(_ goal:activity:location:)`, `CustomWorkout.supportsAlert(_ alert:activity:location:)` (all return `Bool`); plus `WorkoutAlert.supports(activity:location:)`. Use these for pre-flight inline validation (matches ARCHITECTURE §3.1 "validate before Send").
  (b) **throwing at export/serialize** — `WorkoutPlan.dataRepresentation` is `get throws`; `WorkoutPlan.init(from: Data) throws`. WWDC23-10016 states WorkoutKit "provides very granular validation errors" thrown when composition is exported. **The concrete error type is NOT in the WorkoutKit swiftinterface** (no public `WorkoutError` symbol found via grep) — likely surfaced as a generic `Error`/`NSError`. Verdict: **probable** — capture the actual thrown error type in the 0.6 spike.
- Implication: Stride's `ValidateWorkout` should combine domain rules + the `supports*` static checks; do NOT rely on a throwing initializer that does not exist in this SDK.

### 5. Authorization — **verified** (SDK interface). This is `WorkoutScheduler`-based and **separate from HealthKit authorization** (no HKHealthStore involvement).
- `final public class WorkoutScheduler` — `public static let shared`.
- `public enum AuthorizationState : Int { case notDetermined; case restricted; case denied; case authorized }`
- `final public var authorizationState: WorkoutScheduler.AuthorizationState { get async }`
- `final public func requestAuthorization() async -> WorkoutScheduler.AuthorizationState`  — **returns the resulting state; does NOT throw.**
- `public static var isSupported: Bool { get }` — check before use.
- Denial recovery: no in-API re-prompt after `denied`; user must re-enable in Watch app / Settings (WWDC23-10016). Surface a deep-link/instruction, not a re-request loop.

### 6. Scheduling / removal — **verified (API) / probable (limit numbers)**
`final public class WorkoutScheduler`:
- `public static let maxAllowedScheduledWorkoutCount: Int` — exists as a runtime `static let`; the numeric value is NOT a literal in the interface. WWDC23-10016 states the cap is **15** and the visibility/scheduling window is **the next 7 days and previous 7 days** (workouts outside that window expire/disappear). Verdict on exact numbers: **probable** — read `maxAllowedScheduledWorkoutCount` at runtime and confirm the 7-day expiry on hardware.
- `final public func schedule(_ workout: WorkoutPlan, at: DateComponents) async` — **async, NON-throwing, no return value.** Date is a `DateComponents`, not a `Date`. No success/failure signal from the call itself → must verify via `scheduledWorkouts` afterward.
- `final public var scheduledWorkouts: [ScheduledWorkoutPlan] { get async }` — list currently scheduled (drives §7 reconciliation).
- `public struct ScheduledWorkoutPlan { public var plan: WorkoutPlan; public var date: DateComponents; public var complete: Bool; public init(_ plan: WorkoutPlan, date: DateComponents) }`.
- `final public func remove(_ workout: WorkoutPlan, at: DateComponents) async`, `final public func markComplete(_ workout: WorkoutPlan, at: DateComponents) async`, `final public func removeAllWorkouts() async` — all async, non-throwing.
- **Update semantics** (edit-then-resend, ARCHITECTURE §7 "stale"): no `update` method exists → pattern is `remove(old, at:)` then `schedule(new, at:)`. Whether re-scheduling the same `WorkoutPlan.id` replaces vs duplicates is **unknown-needs-hardware.**
- Error surface for "no paired watch": `public enum StateError : Error { case watchNotPaired; case workoutApplicationNotInstalled }` — present in interface, but note `schedule` itself is non-throwing, so where `StateError` is thrown is **probable/unknown** (likely from `openInWorkoutApp()` and possibly export). Verify in spike.

### 7. Preview sheet — **verified** (SwiftUI overlay interface)
- `@available(iOS 17.0, watchOS 11.0, *) extension View { public func workoutPreview(_ workout: WorkoutPlan, isPresented: Binding<Bool>) -> some View }`.
- **Gate mismatch to note:** the modifier is available on **iOS 17.0**, but the overlay module header declares `watchOS 11.0` as its floor. On iPhone (Stride's target) this is iOS 17-safe. It is a SwiftUI `View` modifier (not UIKit). `.custom` running plans are previewable.

### 8. Completed-run linkage — **verified (API exists) / unknown-needs-hardware (reliability)**
- `extension HKWorkout { @available(iOS 17.0, watchOS 10.0, *) public var workoutPlan: WorkoutPlan? { get async throws } }` — a completed `HKWorkout` can asynchronously yield the originating `WorkoutPlan` (including its `id: UUID`). This is the strong-attribution path (ARCHITECTURE §13.3 / risk #2).
- Returns optional → not every HKWorkout has a plan; async throws → may fail. **Round-trip reliability, whether the plan `id` we scheduled survives, and per-OS-version behavior are unknown-needs-hardware.** Keep the time-window heuristic as fallback per §13.3.
- `WorkoutPlan.dataRepresentation` / `init(from:Data)` give a stable serialization to persist the plan alongside our SyncJob and match by `id`.

### Hardware-verify list (feeds Task 0.6 spike + human checkpoint)
1. Concrete thrown **validation error type** from `WorkoutPlan.dataRepresentation` / scheduling, and its granularity (§4). → CLOSED for value errors 2026-07-10 (they trap at composition, not throw); no throw path observed yet — see the root-cause section below.
2. Runtime value of `WorkoutScheduler.maxAllowedScheduledWorkoutCount` and confirmation of the **7-day-ahead / 7-day-past** window + exact expiry behavior (§6).
3. **Replace vs duplicate** when scheduling a plan with a reused `id` (or same plan at same DateComponents) — decides "stale re-send" implementation (§6, ARCHITECTURE §7).
4. Where `StateError.watchNotPaired` / `.workoutApplicationNotInstalled` actually surface (schedule is non-throwing) — i.e. how "no paired watch" is detected pre-send (§6).
5. `HKWorkout.workoutPlan` round-trip: does the scheduled plan's `id` come back intact, on iOS 17 vs 18? Reliability for attribution (§8).
6. Denied-authorization recovery UX: exact settings location / any deep link (§5).
7. Whether `workoutPreview` is required in the send flow or optional after first use (ARCHITECTURE §13.8).
8. Pace-alert field feel: `.current` vs `.average` `WorkoutAlertMetric` for `SpeedRangeAlert` outdoors; indoor-run pace support (§4 of ARCHITECTURE).


---

## 2026-07-06 — Task 0.4 assumption (orchestrator note)

- `ValidateWorkoutPolicy` bounds heart-rate zones to **1...5** (Apple's five-zone model). This is an **assumption**, not SDK-verified — `HeartRateZoneAlert(zone: Int)` takes an unconstrained Int. Confirm on device whether user-configured zone counts other than 5 exist when the WorkoutKit mapper lands (task 1.7). Mark the mapper call site `// HARDWARE-VERIFY:`.

---

## 2026-07-10 — Task 0.6 pre-flight: WorkoutKit app configuration

**Researcher:** api-researcher. **Question:** what app-target config does WorkoutKit *scheduling* require on iOS 17+ (entitlements / Info.plist / capabilities / simulator)? **Evidence:** SDK framework files in Xcode 26.6 (WorkoutKit.swiftinterface, HealthKit HKHealthStore.h header) + Apple docs JSON API (developer.apple.com/tutorials/data/...) + WWDC23-10016 sample README. Blogs treated as leads only.

### 1. Entitlements — **verified: none required for WorkoutKit scheduling**
- No WorkoutKit-specific entitlement exists. Apple's entitlements index (`bundleresources/entitlements.json`) lists only HealthKit-family keys (`com.apple.developer.healthkit`, `...healthkit.background-delivery`, `...healthkit.recalibrate-estimates`) — **no `com.apple.developer.workoutkit`**. Grep of `WorkoutKit.tbd` / `.swiftinterface` shows no entitlement symbols.
- **HealthKit entitlement is NOT pulled in by `CustomWorkout(activity: HKWorkoutActivityType…)`.** `HKWorkoutActivityType` / `HKWorkoutSessionLocationType` are plain enums; using them does not touch `HKHealthStore`. The HealthKit entitlement is gated on requesting authorization to *read/write Health data*, which the WorkoutKit send path never does. WorkoutKit overview explicitly separates them: "To access health data for the workout, see the HealthKit framework."
- ⇒ The 0.6 spike's Send-to-Watch path needs **zero entitlements**. (HealthKit entitlement will be needed later by FeatureHistory/FeatureRecords for `HKWorkout` reads — separate concern, add when DataKit's HealthKit adapter lands.)

### 2. Info.plist — **verified (HealthKit) / probable (WorkoutKit)**
- `NSHealthShareUsageDescription` / `NSHealthUpdateUsageDescription` are required **only if the app calls HealthKit data APIs** (HKHealthStore.h header: these keys customize the *HealthKit* auth sheet; `NSHealthShareUsageDescription` doc: "required if your app uses APIs that access someone's health data"). Missing string + HKHealthStore auth call = **runtime crash** (standard Apple usage-string behavior). Not relevant to WorkoutKit-only scheduling.
- `WorkoutScheduler.requestAuthorization()` has **no documented Info.plist usage-description key**; its permission is managed in the **Apple Watch app on iPhone**, not iOS Settings > Privacy (Apple DevForums 736223). No crash-on-missing-string documented for the WorkoutKit prompt. Verdict **probable** — confirm no usage string is silently needed during the spike.

### 3. Capabilities & background modes — **verified: none for WorkoutKit-only**
- WWDC23/24 sample "Customizing workouts with WorkoutKit" setup README requires only: "Click the target and select a team in the Signing & Capabilities pane." **No capability toggle** — no HealthKit capability, no background mode — for compose/preview/schedule.
- No documented background-mode requirement for `schedule(_:at:)` (it's a one-shot sync to the paired watch, not a background-run session). ⇒ Spike app target needs only a signing **Team**; do NOT add the HealthKit capability yet.

### 4. Simulator behavior — **unknown-needs-hardware (paired-watch dependent)**
- `WorkoutScheduler.isSupported` = "whether the current device supports scheduled workouts" (docs). Scheduling **syncs to the Workout app on a paired Apple Watch**; the WWDC sample README mandates running on a *physical iPhone with a paired Apple Watch (watchOS 11+)*. A simulator has no paired watch, so `isSupported` is **very likely false** and `requestAuthorization()` likely returns non-`authorized` — but this is **unknown-needs-hardware**; confirm exact simulator return values in the spike. Treat all of §4 (and the send/schedule round-trip) as `// HARDWARE-VERIFY:`; the builder can only unit-test the mapper + gate on `isSupported`, not the actual sync, in simulator.

### Implications for the 0.6 spike app target
- Add **no** entitlements file and **no** HealthKit capability for the Send-to-Watch spike — only set a Signing Team.
- Gate the whole send flow behind `WorkoutScheduler.isSupported`; surface a "requires paired Apple Watch" state when false (also covers simulator).
- Denied-auth recovery must deep-link/instruct toward the **Watch app on iPhone**, not iOS Settings (§5 of Task 0.5, corroborated here).
- Defer HealthKit Info.plist strings + entitlement to the FeatureHistory/Records work; they are not part of WorkoutKit scheduling.

---

## 2026-07-10 — Task 0.6 spike shipped: device-run checklist

**Builder:** swift-builder. The now-retired debug spike screen
(`Stride/DebugSpike/WorkoutKitSpikeView.swift` + `WorkoutKitSpikeModel.swift`) was run on a
**physical iPhone with a paired Apple Watch (watchOS 11+)** — WorkoutKit scheduling has no
simulator equivalent. Its findings informed the production DataKit adapter. The source files were
removed on 2026-10-09 after task 1.17's dependency audit restored the strict rule that only
DataKit imports Apple health/workout frameworks. This record preserves the eight-step device
procedure and findings.

1. **Environment readout** (auto-runs on appear; also has a manual refresh button) → confirms
   HARDWARE-VERIFY(2): runtime `maxAllowedScheduledWorkoutCount` value + the 7-day scheduling
   window (confirm expiry behavior by leaving an entry scheduled past the window, separately).
   - Finding (device, iPhone 13 Pro Max + paired Watch, 2026-07-10): `maxAllowedScheduledWorkoutCount`
     = **50** — NOT the 15 stated in WWDC23-10016; treat 50 as the runtime truth and always read the
     property, never hardcode. `isSupported` = true. 7-day window/expiry behavior still unconfirmed
     (needs an entry left in place past the window — low priority, revisit opportunistically).
2. **Authorize button** → confirms HARDWARE-VERIFY(6): denied-state recovery path (exact Watch-app
   on iPhone location/deep link, if any).
   - Finding (device, 2026-07-10): authorization granted on first request; happy path works.
     Denied-state recovery path NOT exercised (user allowed) — HARDWARE-VERIFY(6) stays open until
     someone tests a denial; non-blocking for Phase 1 (gate on `authorizationState` + instructions).
3. **Pre-flight checks button** (`supportsActivity` / `supportsGoal` / `supportsAlert`) → sanity
   check only, not a numbered HARDWARE-VERIFY item, but log the boolean results here in case any
   come back `false` for the hardcoded plan.
   - Finding (device, 2026-07-10): all `supports*` checks returned true for the hardcoded plan.
4. **Serialize button** → HARDWARE-VERIFY(1) is **ANSWERED in simulator** (see the 2026-07-10
   "spike crash root-caused" section below) — bad goal values trap at composition, they do not
   throw at serialization. The button now only confirms the valid plan serializes on device.
   - Finding (simulator, 2026-07-10): composition traps on goal values ≤ 0; valid plan serialized
     to 219 bytes; empty / zero-iteration compositions serialize without error.
5. **Schedule tomorrow 07:00 button** → confirms HARDWARE-VERIFY(4): where/whether
   `StateError.watchNotPaired` / `.workoutApplicationNotInstalled` surface, or whether an unpaired
   watch causes `schedule` to silently no-op (compare against `scheduledWorkouts` dump logged
   right after). Also note: HARDWARE-VERIFY(5) (`HKWorkout.workoutPlan` round-trip) can only be
   checked after actually running this workout on-wrist and syncing to Health — separate, later
   check, not blocking this spike.
   - Finding (device, 2026-07-10): schedule at tomorrow 07:00 succeeded; `scheduledWorkouts`
     count = 1 immediately after, and the workout **appeared in the Watch's Workout app**.
     Unpaired-watch behavior NOT tested (watch was paired) — HARDWARE-VERIFY(4) stays open;
     mitigate with the `isSupported` gate until tested.
6. **Schedule again tomorrow 18:00 button** (same `plan.id`, different time) → confirms
   HARDWARE-VERIFY(3): replace vs duplicate when scheduling a reused `id`. Compare the
   `scheduledWorkouts` dump from step 5 against the dump after this step.
   - Finding (device, 2026-07-10, human-confirmed + Xcode console): **REPLACE.** Re-scheduling the
     same `plan.id` at a different `DateComponents` left `scheduledWorkouts` count = 1, with only
     the hour-18 entry present (console: `plan.id=C5CCA7BC-… hour: 18 … complete=false`). The
     "stale re-send" flow (ARCHITECTURE §7) can therefore be a single `schedule(new)` call reusing
     the id — no explicit `remove(old)` needed when the plan id is stable. Keep remove-then-schedule
     as belt-and-braces if the id changes.
7. **Remove 07:00 / Remove 18:00 / Remove ALL buttons** → sanity check that `remove(_:at:)` /
   `removeAllWorkouts()` reflect correctly in the `scheduledWorkouts` dump; not independently
   numbered but supports interpreting steps 5–6.
   - Finding (device, 2026-07-10): `removeAllWorkouts()` dropped count to 0 (verified twice in
     console), and the removal **propagated to the Watch** correctly.
8. **Preview toggle button** → confirms HARDWARE-VERIFY(7): whether `workoutPreview` is required
   before every send or optional after first use, and general fidelity of the rendered preview for
   the hardcoded plan.
   - Finding (device, 2026-07-10): preview sheet rendered the plan correctly. Scheduling succeeded
     independent of the preview — `workoutPreview` is **optional** in the send flow (UX choice, not
     an API requirement).

Also record general notes on HARDWARE-VERIFY(8) (pace-alert `.current` feel outdoors for the
2.98–3.35 m/s work-interval range) while actually running the composed workout, if time allows.
→ **DEFERRED 2026-07-10** along with HARDWARE-VERIFY(5) (`HKWorkout.workoutPlan` round-trip): the
actual on-wrist run is on hold per the human. Neither blocks Phase 1 persistence/builder work;
HV(5) matters from task 1.10 onward (attribution) — schedule a run before then.

**Session observations (orchestrator, from Xcode console):** ~6 minutes after the last interaction,
iOS terminated the suspended app with a memory kill ("code 9: Terminated due to memory issue",
~28 MB) — consistent with routine jetsam of a suspended debug build, not a leak; no action taken.
Device: iPhone 13 Pro Max, iOS 26.x, Xcode 26.6 debug build.

---

## 2026-07-10 — Task 0.6 spike crash root-caused: WorkoutKit traps on non-positive goal values (HARDWARE-VERIFY(1) answered)

**Reporter:** orchestrator. **Trigger:** human's first device run crashed on opening the spike screen with `Fatal error: requiresNonZeroValue`.

**Root cause (verified, reproduced in iOS 26.5 simulator via a standalone binary spawned with `simctl`):**
- `CustomWorkout.init` **traps** — `WorkoutKit/CustomWorkout.swift:139: Fatal error: requiresNonZeroValue` — when any contained step carries a goal value **≤ 0** (both `-100` and `0` meters reproduce it). The spike's deliberately-broken plan (`.distance(-100, .meters)`, composed eagerly in the model's `init` to probe serialization errors) killed the screen before it rendered.
- `WorkoutStep.init` / `WorkoutGoal` do **not** validate — the bad value passes composition of the step and only traps when wrapped in `CustomWorkout`.

**Consequences for §4 "Validation" of the 0.5 entry (supersedes the "granular thrown errors" theory for value errors):**
- Value validation is a **runtime precondition at composition, not a thrown error at export**. `WorkoutPlan.dataRepresentation` was never reached.
- Conversely, semantically-empty compositions serialize **without error** in simulator: an empty `CustomWorkout` (no warmup/blocks/cooldown) → 57 bytes; a block with `iterations: 0` → 87 bytes. WorkoutKit does not enforce "≥ 1 segment" or "reps ≥ 1" at composition or export — **Stride's `ValidateWorkoutPolicy` is the only guard for those.**
- The valid hardcoded spike plan serializes fine in simulator (219 bytes) — serialization itself is not hardware-gated.

**Hard requirement for task 1.7 (domain → WorkoutKit mapper):** the mapper MUST refuse (typed domain error) any workout whose goal values are ≤ 0 *before* touching `CustomWorkout.init` — a bad value is a process kill, not a catchable error. `ValidateWorkoutPolicy` already rejects these; the mapper must still guard defensively since a trap is unrecoverable.

**Spike change:** broken-plan composition removed from the spike (crash fix); serialize button now round-trips the valid plan only. HARDWARE-VERIFY(1) is closed for value errors (no throw path from `dataRepresentation` has been observed in any tested case); items 2–8 remain for the device run.

---

## 2026-07-19 — Task 1.7 corrections to the 0.5 alert-surface notes (verified against SDK swiftinterface)

**Reporter:** orchestrator, relaying swift-builder findings read directly from the Xcode 26.6 `WorkoutKit.swiftinterface` while implementing the composition mapper.

1. **Alert factory parameter shapes:** the `WorkoutAlert` static factories (`.speed(_:unit:metric:)`, `.speed(_:unit:metric:)` range variant, `.heartRate(_:unit:)`, `.cadence(_:unit:)`) take a bare `Double` / `ClosedRange<Double>` plus a `unit:` parameter — NOT `Measurement` values. (The underlying alert *types*' designated inits do take `Measurement`s; the factories are the convenience layer Stride uses.) §3 of the 0.5 entry conflated the two.
2. **`.countPerMinute` location:** the `countPerMinute` static convenience is declared on `WorkoutAlertMetric`, not on `UnitFrequency` — leading-dot shorthand does not resolve it in the factory call; write `WorkoutAlertMetric.countPerMinute` explicitly.
3. **WorkoutKit exists on macOS 15+** in this SDK (contrary to earlier working assumption). DataKit still isolates WorkoutKit behind `#if canImport(WorkoutKit)` + `@available(iOS 17.0, macOS 15.0, *)` because the package's macOS floor is 14 and the pure planner must stay testable everywhere.
4. **No "unscheduled send" sentinel:** `WorkoutScheduler.schedule` requires `DateComponents`; a nil domain date is mapped to "now" in `WorkoutKitSyncService` — `// HARDWARE-VERIFY:` whether a now-dated schedule surfaces well in the Watch Workout app (open with HV-4/6).

---

## 2026-07-19 — Task 1.10: HealthKit ingestion surface (anchored fetch / background / auth / splits / attribution / config)

**Researcher:** api-researcher. **Primary evidence (strongest):** the HealthKit Swift module interface + ObjC headers shipped in Xcode 26.6, read directly at
`…/iPhoneOS.sdk/System/Library/Frameworks/HealthKit.framework/Modules/HealthKit.swiftmodule/arm64e-apple-ios.swiftinterface` and `…/HealthKit.framework/Headers/*.h`.
Signatures below are copied verbatim. **Prefer the modern async descriptor surface** (`HK…QueryDescriptor`, gated iOS 15.4+ — well under our iOS 17 floor) over the legacy `HKQuery` subclasses (marked `API_DEPRECATED("Use …Descriptor")` under Swift). Secondary: Apple docs / WWDC where noted. Legend: **verified** = in this SDK; **probable** = strong secondary; **unknown-needs-hardware**.

### 1. Anchored incremental fetch — **verified** (swiftinterface)
- `public struct HKAnchoredObjectQueryDescriptor<Sample> : Sendable where Sample : HKSample` (iOS 15.4+):
  `public init(predicates: [HKSamplePredicate<Sample>], anchor: HKQueryAnchor?, limit: Int? = nil)`
  `public struct Result { public let addedSamples: [Sample]; public let deletedObjects: [HKDeletedObject]; public let newAnchor: HKQueryAnchor }`
  `public func result(for healthStore: HKHealthStore) async throws -> …Result`  — one-shot initial/incremental fetch.
  `public func results(for healthStore: HKHealthStore) -> …Results` — an `AsyncSequence` that yields a `Result` on the initial fetch **and** again on every subsequent change (long-lived; the modern replacement for `updateHandler`).
- Predicate factory: `public static func workout(_ predicate: NSPredicate? = nil) -> HKSamplePredicate<HKWorkout>`. For running-only: pass `HKQuery.predicateForWorkouts(with: .running)` (ObjC `+predicateForWorkoutsWithWorkoutActivityType:`) as the inner `NSPredicate`. So: `HKSamplePredicate.workout(HKQuery.predicateForWorkouts(with: .running))`.
- **Anchor persistence (verified):** `HKQueryAnchor : NSObject <NSSecureCoding, NSCopying>` — serialize with `NSKeyedArchiver.archivedData(withRootObject:requiringSecureCoding: true)` and restore with `NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from:)`. Store the `Data` blob in SwiftData (per ARCHITECTURE §8: anchor in SwiftData). First run: pass `anchor: nil`.
- **Semantics (verified from header discussion):** `nil` anchor → initial fetch returns *all* matching samples as `addedSamples`; thereafter only new/changed come back and `newAnchor` advances. **Deletions/tombstones** arrive as `deletedObjects: [HKDeletedObject]` — `HKDeletedObject` (`<NSSecureCoding>`) exposes `UUID: NSUUID` (+ optional `metadata`). ARCHITECTURE §8 tombstone step keys off `deletedObjects[].UUID` matching our `CompletedRun`/HKWorkout UUID.

### 2. Background delivery — **verified (API) / unknown-needs-hardware (behavior)**
- `HKHealthStore` category (ObjC): `enableBackgroundDeliveryForType:frequency:withCompletion:` and `disableBackgroundDeliveryForType:…` / `disableAllBackgroundDeliveryWithCompletion:`. Swift async: throws-on-false → `func enableBackgroundDelivery(for type: HKObjectType, frequency: HKUpdateFrequency) async throws`.
- `HKUpdateFrequency { .immediate = 1, .hourly, .daily, .weekly }`. Header note: some cumulative types (e.g. stepCount) are floored to `.hourly` transparently; **no documented floor for `workoutType()`** — treat effective cadence as **unknown-needs-hardware**.
- **Pairing is mandatory (verified from header):** background delivery only *wakes* the app; you MUST also run an `HKObserverQuery` to learn what changed, then run the anchored fetch. `HKObserverQuery` init (iOS 15+ descriptor form): `initWithQueryDescriptors:updateHandler:` whose handler is `(query, sampleTypesAdded, completionHandler, error)` — you **must call the passed `completionHandler` (`HKObserverQueryCompletionHandler = void(^)(void)`)** when done or iOS throttles/stops delivery. (No `HKObserverQueryDescriptor` async type exists in this SDK — observer stays callback-based; anchored fetch is async.)
- **Entitlement:** background delivery requires `com.apple.developer.healthkit.background-delivery` (HealthKit entitlements family, per Task 0.6 entitlements-index finding) — this is the ONE extra key beyond plain read. `enableBackgroundDelivery` is `API_UNAVAILABLE(watchos)`-free but is an iPhone-side call for us.
- **Simulator:** observer/background wake-ups are **unknown-needs-hardware** (best-effort, §13 risk #5) — do not depend on them for correctness; always reconcile via anchored fetch on foreground.

### 3. Authorization (read-only) — **verified** (swiftinterface + header)
- Swift async: `public func requestAuthorization(toShare typesToShare: Set<HKSampleType>, read typesToRead: Set<HKObjectType>) async throws` — for read-only pass `toShare: []`. **`success`/throw indicates the prompt completed, NOT that access was granted** (header: "does NOT indicate whether the application was granted authorization").
- Read types to request: `HKObjectType.workoutType()` (→ `HKWorkoutType`), `HKQuantityType(.distanceWalkingRunning)`, `HKQuantityType(.heartRate)` (modern init `HKQuantityType(_:)`; legacy `HKObjectType.quantityType(forIdentifier:)` is deprecated under Swift).
- **Read-denial opacity (verified):** `authorizationStatusForType:` returns `HKAuthorizationStatus { .notDetermined=0, .sharingDenied, .sharingAuthorized }` — this reflects **share (write)** authorization only; for **read**, HealthKit deliberately hides denial (a denied read looks identical to "no data"). To decide whether to prompt, use `getRequestStatusForAuthorizationToShareTypes:readTypes:completion:` → Swift `statusForAuthorizationRequest(toShare:read:)` returning `HKAuthorizationRequestStatus { .unknown=0, .shouldRequest, .unnecessary }`. `.shouldRequest` ⇒ haven't asked; `.unnecessary` ⇒ already asked (grant unknowable). ⇒ Stride cannot detect read-denial directly; infer from empty results + surface a "check Health > Data Access" recovery hint.
- **Info.plist:** `NSHealthShareUsageDescription` is **required** for read (header §requestAuthorization; missing string + auth call = runtime crash). `NSHealthUpdateUsageDescription` NOT needed (read-only, no writes).

### 4. Split derivation inputs — **verified (API) / unknown-needs-hardware (granularity)**
- Per-workout summary stats without extra queries: `HKWorkout.statisticsForType(_:) -> HKStatistics?` and `HKWorkout.allStatistics: [HKQuantityType: HKStatistics]` (both iOS 16+). `HKStatistics` accessors: `sumQuantity()` (distance, energy — cumulative), `averageQuantity()` / `minimumQuantity()` / `maximumQuantity()` (HR — discrete). **Avg HR for run summary = `workout.statisticsForType(HKQuantityType(.heartRate))?.averageQuantity()`.** Note `HKWorkout.totalDistance`/`totalEnergyBurned` are **deprecated** — use `statisticsForType:`.
- For **per-split** derivation you need the raw distance series over time, not a single sum. Query cumulative distance samples scoped to the workout: `HKQuantitySeriesSampleQueryDescriptor(predicate: .quantitySample(type: HKQuantityType(.distanceWalkingRunning), predicate: HKQuery.predicateForObjects(from: workout)), options: …)` → async-sequence of `Result { quantity: HKQuantity; dateInterval: DateInterval; sample: HKQuantitySample? }`; accumulate distance vs. `dateInterval` to cut splits at each km/mi boundary. `predicateForObjects(from:)` (ObjC `+predicateForObjectsFromWorkout:`) scopes samples to that HKWorkout.
- **Sample granularity from Apple Watch outdoor runs is unknown-needs-hardware** — Apple docs don't guarantee cadence; commonly cumulative-distance series arrive as short irregular batches (unverified, secondary). Design split math to integrate arbitrary `dateInterval` chunks, never assume per-second/per-meter. Mark the split calculator `// HARDWARE-VERIFY:` on real run data.

### 5. Plan linkage / attribution — **verified (API exists) / unknown-needs-hardware (reliability)**
- Re-confirmed from Task 0.5 §8: `extension HKWorkout { @available(iOS 17.0, *) public var workoutPlan: WorkoutPlan? { get async throws } }` (declared by **WorkoutKit**, not HealthKit — DataKit's HealthKit adapter would need WorkoutKit import to read it; keep behind the port). Optional + async-throws ⇒ not every workout has one; round-trip reliability of the scheduled `id` remains **unknown-needs-hardware** (§13 risk #2; still deferred per 0.6 spike — no on-wrist run yet).
- **Attribution fallback (verified):** `HKObject.metadata: [String: Any]?` and `HKObject.sourceRevision` / `HKSource` are readable on every `HKWorkout` — use `sourceRevision.source.bundleIdentifier` + start-time window as the conservative heuristic match (ARCHITECTURE §13.3), and expose a manual "link to workout" affordance. No app-writable metadata in MVP (read-only).

### 6. App-config checklist (1.11, read-only) — **verified / probable**
- **Capability:** add **HealthKit** capability to the app target (turns on the `com.apple.developer.healthkit` entitlement). For §2 background wake-ups also enable **HealthKit → Background Delivery** (`com.apple.developer.healthkit.background-delivery`). *(WorkoutKit send path needs neither — separate concern per Task 0.6.)*
- **Info.plist:** `NSHealthShareUsageDescription` (required, read purpose string). No `NSHealthUpdateUsageDescription` (no writes).
- **Background modes:** no UIBackgroundModes toggle is required for HealthKit background delivery (the entitlement + observer pairing is the mechanism). — **probable**; confirm during 1.11 device bring-up.
- **Simulator (verified-ish):** HealthKit **works in the iOS Simulator** with manually-added Health data (add workouts/samples via the Health app in the sim) — anchored fetch, predicates, statistics, and split math are all **simulator-testable**. Hardware-only: real Apple-Watch sample granularity (§4), `workoutPlan` round-trip (§5), and background/observer wake-up latency + `HKUpdateFrequency` behavior for workouts (§2).

### Hardware-verify list (feeds 1.11/1.12)
1. Apple-Watch outdoor-run distance-series granularity & whether HR arrives per-beat vs batched (§4) — drives split-calculator tolerance.
2. `HKWorkout.workoutPlan` round-trip: does our scheduled `id` return intact on iOS 17 vs 18 (§5, still open from 0.5/0.6).
3. Background-delivery/observer wake latency for `workoutType()` and effective `HKUpdateFrequency` cadence + Low Power Mode interaction (§2, §13.4/§13 risk #5).
4. Empty-result-vs-read-denied disambiguation UX: confirm there is no API to detect read denial and validate the recovery hint (§3).

## 2026-10-08 — Task 1.11 implementation slice

The HealthKit ingestion path has a framework-free DomainKit source port, a SwiftData-backed opaque anchor store, a serialized `RunIngestionCoordinator`, a SwiftData `RunHistoryRepository`, and a HealthKit observer/background-delivery adapter. Each trigger waits FIFO and performs a fresh anchored fetch. The coordinator saves the returned anchor only after `IngestCompletedRunsUseCase` succeeds; persistence failures replay from the prior cursor. SwiftData writes disable autosave and roll back failed operations. Kilometer splits are the current ingestion policy; a user-selected unit policy can follow with the wider feature composition in task 1.16.

The app composition root constructs one shared model container and installs the HealthKit observer during application launch. Authorization is requested only from the explicit Connect Health action; foreground refresh and background registration errors remain independently visible. The app target includes HealthKit and background-delivery entitlements plus `NSHealthShareUsageDescription`. If storage cannot open at launch, the app preserves the failure and offers a foreground retry; background observation starts after storage is available.

Package coverage includes cursor persistence/replay, malformed anchors, projection and tombstone persistence, disk reopen, and serialized triggers. The simulator app launched, but its unsigned build displayed recoverable HealthKit/background registration errors; this did not validate permission, ingestion, or background delivery. The code review and API review found no remaining blockers. Observer wake latency, signed-device permission recovery, actual Apple Watch sample granularity, and `HKWorkout.workoutPlan` linkage remain `HARDWARE-VERIFY` items. See the [task 1.11 device checklist](TASK-1.11-PLAN.md#device-verification-checklist).
