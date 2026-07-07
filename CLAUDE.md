# Stride — Project Constitution

You are working on **Stride**, an iOS app for composing structured running workouts and sending them to the native Apple Watch Workout app via WorkoutKit, with HealthKit-based run history and personal records.

**The architecture is already decided.** Read `docs/ARCHITECTURE.md` before any non-trivial task. Do not re-litigate architectural decisions; propose changes as questions to the human, never as unilateral refactors.

## Non-negotiable rules (all agents)

1. **Dependency rule:** Feature modules and DomainKit never import DataKit, HealthKit, WorkoutKit, or SwiftData. DomainKit imports Foundation only. Violations are build-blocking review failures.
2. **Targets:** iOS 17.0+, Swift 5.10+, SwiftUI, Swift Concurrency (no Combine unless bridging a system API), SwiftData.
3. **No third-party dependencies** without explicit human approval. No TCA, no DI containers.
4. **Units:** store distance in meters, time in seconds, pace as seconds-per-meter internally. Convert at the presentation edge via `UnitFormatter` only.
5. **All Apple-framework access** goes through a protocol defined in `DomainKit/Ports` with an implementation in DataKit and a fake in TestSupport. If you add a port, add the fake in the same PR.
6. **Every PR-sized change** includes: the code, tests, and a 3–6 line summary of decisions made and anything you were unsure about (for the reviewer agent).
7. **Naming:** no `*Manager` types. Repositories for persistence/queries, Services for effectful capabilities, UseCases for orchestration, Policies for pure rules.
8. **Never invent WorkoutKit/HealthKit API signatures.** If unsure an API exists, say so and flag it in `docs/RESEARCH-LOG.md` instead of guessing. Compile errors from hallucinated APIs are the #1 expected failure mode — check against SDK headers or docs first.

## Build & test commands

- Build: `xcodebuild -scheme Stride -destination 'platform=iOS Simulator,name=iPhone 16' build`
- Tests: `xcodebuild -scheme Stride -destination 'platform=iOS Simulator,name=iPhone 16' test` (or `swift test` inside `StridePackages/` for pure-Swift modules — prefer this; it's much faster and covers DomainKit fully)
- Lint: `swiftlint --strict` (config at repo root)
- A task is not done until build + tests + lint pass locally.

## Definition of done for any task

- Compiles; all tests green; lint clean.
- New logic in DomainKit has unit tests (PR policy and validation require exhaustive cases).
- No force-unwraps outside tests; errors are typed and surfaced, not swallowed.
- Public types in DomainKit have doc comments.
- Anything hardware-dependent (WorkoutKit scheduling, HealthKit authorization) is marked with `// HARDWARE-VERIFY:` comments and listed in `docs/RESEARCH-LOG.md` — these cannot be validated in simulator and need a human with a paired Watch.

## Module map (see ARCHITECTURE.md §4 for details)

- `StrideApp/` — app target, composition root only
- `StridePackages/Sources/DomainKit` — entities, use cases, policies, ports, events
- `StridePackages/Sources/DataKit` — SwiftData, HealthKit adapter, WorkoutKit adapter, UserDefaults adapter
- `StridePackages/Sources/Feature{Builder,Library,History,Records,Settings}`
- `StridePackages/Sources/DesignSystem`, `.../TestSupport`

## Orchestration protocol (main session)

The main session is the orchestrator/architect. It decomposes phases from `docs/TASKBOARD.md`, dispatches implementation to `swift-builder`, tests to `test-engineer`, and **always** runs `code-reviewer` on the diff before marking a task complete. Subagents cannot spawn subagents — the orchestrator sequences everything. Dispatch independent tasks (e.g., two feature modules) in parallel; never parallelize two tasks that touch the same module.
