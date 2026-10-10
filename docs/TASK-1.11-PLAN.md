# Task 1.11 — HealthKit ingestion completion plan

Task 1.11 is the next implementation milestone. The existing adapter can perform a one-shot anchored fetch and project runs, but it does not yet own durable cursor state, receive background changes, or call `IngestCompletedRunsUseCase` from the app.

## Target flow

```text
App launch / foreground / HealthKit observer wake-up
        ↓
RunIngestionCoordinator (serialized actor)
        ↓
HealthKitRunIngestionSource.fetchRunningWorkouts(since: anchor)
        ↓
IngestCompletedRunsUseCase.execute(IngestionBatch)
        ↓
RunHistoryRepository + SyncCoordinator writes
        ↓
Persist new anchor only after the batch succeeds
```

The anchor is a commit cursor. A failed projection, split write, tombstone, or personal-best update must leave the previous anchor available so the next attempt replays the same HealthKit changes safely.

## Implementation order

1. **Promote the ingestion seam to DomainKit.** Define a Foundation-only port for the source and the anchor-store contract. Keep HealthKit-shaped types out of DomainKit; the port should use `Data`, `UUID`, `IngestedRun`, and `IngestionBatch` only. Add TestSupport fakes in the same change. Remove the DataKit-only duplicate protocol/types after callers migrate.
2. **Persist the cursor in SwiftData.** Add a single-row `HealthKitAnchorModel` keyed by a stable source and query kind, plus a DataKit actor/repository that reads and replaces the opaque anchor blob. Include the model in every `ModelContainer` schema used by the app and tests.
3. **Add the serialized ingestion coordinator.** Inject the source, anchor store, `IngestCompletedRunsUseCase`, and split-distance policy. It should:
   - read the current anchor;
   - fetch one anchored batch;
   - execute the domain use case;
   - persist the returned anchor only after execution succeeds;
   - leave the old anchor intact on any failure;
   - queue overlapping triggers FIFO and perform a fresh anchored fetch for each one so foreground and observer wake-ups cannot race or lose a change notification.
4. **Wire HealthKit background delivery.** Verify the exact SDK signatures before coding. Register the running-workout observer and enable background delivery for workout changes. The observer callback should only wake the coordinator and always call its completion handler, even when ingestion fails; retries happen on the next foreground/observer pass.
5. **Add app configuration and launch wiring.** Add the HealthKit capability/entitlements and `NSHealthShareUsageDescription`. Construct one shared model container, repositories, coordinator, and delivery adapter in the app composition root. Install the observer synchronously during application launch; request authorization only after the user taps Connect Health. Foreground refresh works independently and failures have a visible retry path. Full feature view models and navigation remain in task 1.16.

## Required tests

- Anchor store: empty state, replacement, persistence across a new actor instance, and malformed-data handling.
- Coordinator: successful batch advances the anchor; source/use-case/anchor-save failure preserves a replayable cursor; empty batches still advance the cursor; deleted IDs reach tombstoning; overlapping triggers run FIFO from the latest committed cursor.
- Authorization/configuration: unavailable HealthKit and request failures remain typed; background registration failures are surfaced rather than swallowed.
- Integration seam: a fake source plus fake anchor store can drive the real `IngestCompletedRunsUseCase` and verify that the cursor commits after, never before, domain persistence.

## Device verification checklist

Mark each result in `docs/RESEARCH-LOG.md` with the device and OS:

Use the detailed [signed-device validation protocol](TASK-1.11-DEVICE-VALIDATION.md)
to execute and record these checks.

- Initial permission grant, prior denial, and re-request behavior.
- First fetch imports existing running workouts and stores a cursor.
- A newly completed Apple Watch run arrives through background delivery while the app is suspended.
- Relaunch resumes from the stored cursor without duplicate projections.
- HealthKit deletion produces a local tombstone.
- `HKWorkout.workoutPlan` linkage is present when a scheduled Stride workout is completed.
- Observer callback completion is called on success and failure.
- Storage-open failure preserves the store and presents a foreground retry; no background observer can be installed until storage opens.

## Definition of done

Task 1.11 can be marked complete only when the package tests, strict lint, and simulator build pass; the app target contains the HealthKit capability and usage string; the composition root has a production ingestion caller; and the device checklist has results or explicit documented blockers. Until then, task 1.16 should remain sequenced after 1.11 rather than hiding the missing ingestion path behind navigation work.
