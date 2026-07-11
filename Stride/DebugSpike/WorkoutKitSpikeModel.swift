//
//  WorkoutKitSpikeModel.swift
//  Stride
//
//  Task 0.6 — throwaway WorkoutKit spike, DEBUG-only, composition-root code.
//  Exempt from the DomainKit ports rule (CLAUDE.md rule 5): this is not feature/domain code,
//  it exists purely to be run once by a human on a physical iPhone + paired Watch to answer the
//  HARDWARE-VERIFY questions recorded in docs/RESEARCH-LOG.md ("Task 0.5" section).
//
//  Every WorkoutKit signature used below is copied verbatim from docs/RESEARCH-LOG.md — do not
//  add or "remember" any signature not recorded there.
//

#if DEBUG

import Foundation
import HealthKit
import Observation
import WorkoutKit

/// Instrumentation model backing `WorkoutKitSpikeView`. Not testable in CI (drives non-mockable
/// system singletons `WorkoutScheduler.shared` / the `.workoutPreview` overlay) — this is
/// intentionally excluded from the automated test suite per the task 0.6 scope.
@MainActor
@Observable
final class WorkoutKitSpikeModel {
    /// One timestamped line of the on-screen log (also mirrored to `print` for Console capture).
    struct LogEntry: Identifiable {
        let id = UUID()
        let formattedTimestamp: String
        let message: String
    }

    private(set) var logEntries: [LogEntry] = []

    /// Stable, hardcoded spike plan — composed once and held for the lifetime of this screen so the
    /// same `WorkoutPlan.id` is reused across schedule / re-schedule / remove calls.
    let plan: WorkoutPlan

    /// Deliberately-invalid variant (negative distance goal) used only to probe the serialize path.
    let brokenPlan: WorkoutPlan

    /// The exact `DateComponents` used for the "tomorrow 07:00" schedule call. `remove(_:at:)`
    /// requires passing back the same components, so we keep them here rather than recomputing.
    private(set) var morningDateComponents: DateComponents?

    /// The exact `DateComponents` used for the "tomorrow 18:00" re-schedule call.
    private(set) var eveningDateComponents: DateComponents?

    /// Bound to the `.workoutPreview` modifier on the view. HARDWARE-VERIFY(7): confirm whether the
    /// preview sheet is required before every send, or optional after the first use.
    var isPreviewPresented = false

    private static let logTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    init() {
        plan = WorkoutPlan(.custom(Self.makeSpikeWorkout()))
        brokenPlan = WorkoutPlan(.custom(Self.makeBrokenWorkout()))
        logEntries = []
        log("Model initialized. plan.id=\(plan.id) brokenPlan.id=\(brokenPlan.id)")
    }

    private func log(_ message: String) {
        let entry = LogEntry(
            formattedTimestamp: Self.logTimeFormatter.string(from: Date()),
            message: message
        )
        logEntries.append(entry)
        print("[WorkoutKitSpike \(entry.formattedTimestamp)] \(message)")
    }

    // MARK: - 1. Environment readout

    /// HARDWARE-VERIFY(2): confirm the runtime value of `maxAllowedScheduledWorkoutCount` and the
    /// 7-day-ahead / 7-day-past scheduling window on device (RESEARCH-LOG §6).
    /// The spike deliberately does NOT gate actions behind `isSupported` — HARDWARE-VERIFY(4)
    /// needs to observe what schedule/authorize do when unsupported or unpaired. Production
    /// code (task 1.7) must gate the whole send flow on `isSupported`.
    func readEnvironment() async {
        log("--- Environment readout ---")
        log("WorkoutScheduler.isSupported = \(WorkoutScheduler.isSupported)")
        log("WorkoutScheduler.maxAllowedScheduledWorkoutCount = \(WorkoutScheduler.maxAllowedScheduledWorkoutCount)")
        let state = await WorkoutScheduler.shared.authorizationState
        log("WorkoutScheduler.shared.authorizationState = \(state)")
    }

    // MARK: - 2. Authorize

    func requestAuthorization() async {
        log("--- Requesting authorization ---")
        let state = await WorkoutScheduler.shared.requestAuthorization()
        log("requestAuthorization() -> \(state)")
        if state == .denied {
            // HARDWARE-VERIFY(6): no in-API re-prompt after denial; recovery must happen in the
            // Watch app on iPhone, not iOS Settings > Privacy. Confirm exact path on device.
            log("Denied. Recovery must happen in the Watch app on iPhone, not iOS Settings.")
        }
    }

    // MARK: - 3. Hardcoded workout composition + pre-flight checks

    private static func makeSpikeWorkout() -> CustomWorkout {
        let warmup = WorkoutStep(goal: .time(300, .seconds))
        // ~5:00-5:35 min/km pace expressed as a m/s speed range: WorkoutKit models pace as speed
        // (UnitSpeed), there is no dedicated pace alert type (RESEARCH-LOG §3).
        // HARDWARE-VERIFY(8): does `.current` feel right outdoors vs `.average` for this alert?
        let work = IntervalStep(
            .work,
            goal: .distance(400, .meters),
            alert: .speed(2.98...3.35, unit: .metersPerSecond, metric: .current)
        )
        let recovery = IntervalStep(.recovery, goal: .distance(200, .meters))
        let block = IntervalBlock(steps: [work, recovery], iterations: 4)
        let cooldown = WorkoutStep(goal: .time(300, .seconds))
        return CustomWorkout(
            activity: .running,
            location: .outdoor,
            displayName: "Stride Spike",
            warmup: warmup,
            blocks: [block],
            cooldown: cooldown
        )
    }

    private static func makeBrokenWorkout() -> CustomWorkout {
        // Deliberately invalid: a negative distance goal, composed only to try to force a granular
        // validation error out of `WorkoutPlan.dataRepresentation` (RESEARCH-LOG §4 / HARDWARE-VERIFY(1)).
        let brokenWarmup = WorkoutStep(goal: .distance(-100, .meters))
        return CustomWorkout(
            activity: .running,
            location: .outdoor,
            displayName: "Stride Spike (broken)",
            warmup: brokenWarmup
        )
    }

    func runPreflightChecks() {
        log("--- Pre-flight capability checks (static supports* checks) ---")
        guard case let .custom(workout) = plan.workout else {
            log("plan.workout is not .custom — unexpected, aborting pre-flight checks.")
            return
        }
        let activity = workout.activity
        let location = workout.location
        log("CustomWorkout.supportsActivity(.running) = \(CustomWorkout.supportsActivity(activity))")

        if let warmup = workout.warmup {
            let supports = CustomWorkout.supportsGoal(warmup.goal, activity: activity, location: location)
            log("supportsGoal(warmup) = \(supports)")
        }
        for block in workout.blocks {
            for intervalStep in block.steps {
                let step = intervalStep.step
                let supportsGoal = CustomWorkout.supportsGoal(step.goal, activity: activity, location: location)
                log("supportsGoal(\(intervalStep.purpose)) = \(supportsGoal)")
                if let alert = step.alert {
                    let supportsAlert = CustomWorkout.supportsAlert(alert, activity: activity, location: location)
                    log("supportsAlert(\(intervalStep.purpose)) = \(supportsAlert)")
                    log("alert.supports(activity:location:) = \(alert.supports(activity: activity, location: location))")
                }
            }
        }
        if let cooldown = workout.cooldown {
            let supports = CustomWorkout.supportsGoal(cooldown.goal, activity: activity, location: location)
            log("supportsGoal(cooldown) = \(supports)")
        }
    }

    // MARK: - 4. Serialize

    func serializePlan() {
        log("--- Serializing spike plan ---")
        serialize(plan, label: "spike plan")
        log("--- Serializing deliberately-broken plan (distance goal = -100 meters) ---")
        serialize(brokenPlan, label: "broken plan")
    }

    private func serialize(_ plan: WorkoutPlan, label: String) {
        do {
            let data = try plan.dataRepresentation
            log("\(label): dataRepresentation succeeded, \(data.count) bytes.")
        } catch {
            // HARDWARE-VERIFY(1): capture the concrete thrown validation error type + granularity.
            log("\(label): dataRepresentation threw. type(of: error) = \(type(of: error))")
            log("\(label): error description = \(error.localizedDescription)")
            let nsError = error as NSError
            log("\(label): NSError domain=\(nsError.domain) code=\(nsError.code) userInfo=\(nsError.userInfo)")
        }
    }

    // MARK: - 5. Schedule

    func scheduleTomorrowMorning() async {
        log("--- Scheduling plan for tomorrow 07:00 ---")
        let components = Self.dateComponents(daysFromNow: 1, hour: 7, minute: 0)
        morningDateComponents = components
        // HARDWARE-VERIFY(4): schedule() is non-throwing with no return value; where
        // StateError.watchNotPaired / .workoutApplicationNotInstalled actually surface (if at all)
        // is unverified. Confirm on device whether "no paired watch" silently no-ops here.
        // HARDWARE-VERIFY(5): HKWorkout.workoutPlan round-trip is only verifiable after the human
        // actually runs this scheduled workout on the Watch and it syncs back to HealthKit — out of
        // scope for this screen, tracked separately.
        await WorkoutScheduler.shared.schedule(plan, at: components)
        log("schedule(plan, at: \(components)) returned (non-throwing, no result).")
        await dumpScheduledWorkouts()
    }

    // MARK: - 6. Schedule again (replace vs duplicate)

    func scheduleTomorrowEvening() async {
        log("--- Re-scheduling SAME plan.id for tomorrow 18:00 (replace-vs-duplicate check) ---")
        let components = Self.dateComponents(daysFromNow: 1, hour: 18, minute: 0)
        eveningDateComponents = components
        // HARDWARE-VERIFY(3): does reusing the same plan.id at a different DateComponents replace
        // the earlier entry or add a duplicate? Compare scheduledWorkouts before/after.
        await WorkoutScheduler.shared.schedule(plan, at: components)
        log("schedule(plan, at: \(components)) returned (non-throwing, no result).")
        await dumpScheduledWorkouts()
    }

    // MARK: - 7. Remove / remove all

    func removeMorningSchedule() async {
        guard let components = morningDateComponents else {
            log("No morning DateComponents recorded yet — schedule tomorrow 07:00 first.")
            return
        }
        log("--- Removing plan at tomorrow 07:00 ---")
        await WorkoutScheduler.shared.remove(plan, at: components)
        await dumpScheduledWorkouts()
    }

    func removeEveningSchedule() async {
        guard let components = eveningDateComponents else {
            log("No evening DateComponents recorded yet — schedule tomorrow 18:00 first.")
            return
        }
        log("--- Removing plan at tomorrow 18:00 ---")
        await WorkoutScheduler.shared.remove(plan, at: components)
        await dumpScheduledWorkouts()
    }

    func removeAll() async {
        log("--- Removing ALL scheduled workouts ---")
        await WorkoutScheduler.shared.removeAllWorkouts()
        await dumpScheduledWorkouts()
    }

    private func dumpScheduledWorkouts() async {
        let scheduled = await WorkoutScheduler.shared.scheduledWorkouts
        log("scheduledWorkouts count = \(scheduled.count)")
        for entry in scheduled {
            log("  plan.id=\(entry.plan.id) date=\(entry.date) complete=\(entry.complete)")
        }
    }

    private static func dateComponents(daysFromNow: Int, hour: Int, minute: Int) -> DateComponents {
        let calendar = Calendar.current
        let target = calendar.date(byAdding: .day, value: daysFromNow, to: Date()) ?? Date()
        var components = calendar.dateComponents([.year, .month, .day], from: target)
        components.hour = hour
        components.minute = minute
        return components
    }
}

#endif
