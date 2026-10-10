# Task 1.11 — Signed-device validation protocol

Task 1.11's implementation is complete. This protocol collects the remaining
hardware evidence without changing the production data model or reintroducing
the retired WorkoutKit debug screen.

## Preconditions

- Install a signed Debug build on a physical iPhone running iOS 17 or later.
- Use a paired Apple Watch running watchOS 10 or later for Watch-originated
  runs and scheduled-workout checks.
- Confirm Stride has the HealthKit and HealthKit Background Delivery
  entitlements, and that the Health permission explanation is present.
- Record the iPhone model, iOS version, Watch model, watchOS version, Low
  Power Mode state, and the exact local start time for every run below.
- Do not force-quit Stride before the background-delivery check. A manually
  terminated app is not a valid test of HealthKit background wake behavior.

## Evidence to collect

| Check | Procedure | Expected result | Record |
| --- | --- | --- | --- |
| Initial request | On a device where Stride has not requested Health read access, tap **Connect Health**. | The Health prompt completes and the app can foreground-refresh. `unnecessary` only means the request has already been made; it does not prove read access. | Prompt result, first import count, and any visible error. |
| Read-denial recovery | In Health's data-access controls, deny Stride access to running workouts, distance, or heart rate; return to Stride and refresh. | HealthKit may intentionally make denial indistinguishable from an empty result. The UI must remain usable and point the runner to Health settings instead of claiming access was granted. | Settings path used, refresh result, and recovery copy shown. |
| Initial fetch and durable cursor | With at least one existing running workout, connect Health and foreground-refresh. Relaunch Stride, then foreground-refresh again. | The run appears once; relaunch must not duplicate it. | History count before/after each refresh and the workout UUID/date if visible in Health. |
| Background delivery | Leave Stride suspended in the app switcher. Complete and save a short Watch run, then wait for the expected Health sync window before reopening Stride. | A background observer wake may import the run; foreground refresh remains the fallback because HealthKit delivery timing is best effort. | Run end time, first observed import time, whether Stride was resumed or launched in the interim, and Low Power Mode state. |
| Deletion tombstone | After a run is imported, delete that workout in Health and foreground-refresh Stride. | The local projection becomes a tombstone and stops appearing in normal History/Records views. | Deleted Health workout date/UUID and the resulting app state. |
| Distance and HR samples | Use an outdoor Watch run long enough to create multiple splits. Compare the imported splits and heart-rate summary with Health. | Arbitrary sample cadence must not create negative distance, non-monotonic split indices, or an invalid pace. | Number of splits, sample gaps/irregularities observed, HR availability, and any discrepancy. |
| Scheduled-workout attribution | Send a uniquely named Stride workout to the Watch, perform it near its scheduled time, and import the completed run. | The existing schedule-window heuristic may associate the run with its SyncJob. | Plan name/id, schedule time, run start time, imported workout link, and SyncJob state. |

## Workout-plan linkage limitation

The production adapter currently uses schedule-window attribution. It does not
read `HKWorkout.workoutPlan`, so this validation cannot establish whether an
`HKWorkout` returns the original `WorkoutPlan.id`. That needs a separately
approved, DataKit-scoped extension to carry the optional plan identifier across
the HealthKit boundary. Record the observed heuristic association above, but
leave strong plan-linkage verification open until that design is approved and
implemented.

## Result format

Append each completed check to `docs/RESEARCH-LOG.md` with the device and OS
versions, dates/times, observed behavior, and whether it passed. Do not record
health metrics or other sensitive run data beyond what is necessary to identify
the test run. Mark task 1.11 complete only after every check has a result or a
documented platform blocker.
