# Research Log

Append-only log of Apple API findings (api-researcher) and hardware spike results (human). Builders may only use WorkoutKit/HealthKit surface recorded here as **verified**.

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
1. Concrete thrown **validation error type** from `WorkoutPlan.dataRepresentation` / scheduling, and its granularity (§4).
2. Runtime value of `WorkoutScheduler.maxAllowedScheduledWorkoutCount` and confirmation of the **7-day-ahead / 7-day-past** window + exact expiry behavior (§6).
3. **Replace vs duplicate** when scheduling a plan with a reused `id` (or same plan at same DateComponents) — decides "stale re-send" implementation (§6, ARCHITECTURE §7).
4. Where `StateError.watchNotPaired` / `.workoutApplicationNotInstalled` actually surface (schedule is non-throwing) — i.e. how "no paired watch" is detected pre-send (§6).
5. `HKWorkout.workoutPlan` round-trip: does the scheduled plan's `id` come back intact, on iOS 17 vs 18? Reliability for attribution (§8).
6. Denied-authorization recovery UX: exact settings location / any deep link (§5).
7. Whether `workoutPreview` is required in the send flow or optional after first use (ARCHITECTURE §13.8).
8. Pace-alert field feel: `.current` vs `.average` `WorkoutAlertMetric` for `SpeedRangeAlert` outdoors; indoor-run pace support (§4 of ARCHITECTURE).

