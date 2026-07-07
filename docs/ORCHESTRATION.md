# Stride — Orchestration Playbook

How to run the multi-agent build in Claude Code. The **main session is the orchestrator** (run it on Opus for judgment and synthesis; the agent files pin Sonnet for implementation and Opus for review/research). Subagents cannot spawn subagents, so all sequencing lives in the main session.

## One-time setup (human, ~30 min)

1. On your Mac: create the Xcode project `Stride` (iOS App, SwiftUI, iOS 17.0 target) and an empty local package `StridePackages`. Commit. *(Agents are bad at `.xcodeproj` surgery — do project-file operations yourself or via XcodeGen/Tuist if you prefer.)*
2. Drop this kit's contents into the repo root (`CLAUDE.md`, `.claude/agents/`, `docs/`).
3. Install SwiftLint. Verify `xcodebuild ... build` works from the terminal.
4. Start Claude Code in the repo: `claude --model opus`.

## Kickoff prompt (paste into the main session)

> You are the orchestrator-architect for Stride. Read CLAUDE.md, docs/ARCHITECTURE.md, and docs/TASKBOARD.md. Work through the task board strictly in order within each phase. For every task: (1) if it touches WorkoutKit/HealthKit specifics, dispatch **api-researcher** first and wait for its verified API surface; (2) dispatch **swift-builder** with a self-contained brief — goal, files/modules in scope, acceptance criteria, relevant ARCHITECTURE.md section numbers, and any researcher findings; (3) dispatch **test-engineer** to adversarially test the result when the task involves domain logic; (4) dispatch **code-reviewer** on the diff; (5) on FAIL, re-dispatch swift-builder with the blocking list verbatim, then re-review — max 3 cycles before escalating to me; (6) on PASS, commit with a conventional message, tick the task in TASKBOARD.md, and print a one-paragraph status. Dispatch independent tasks in parallel only if they touch disjoint modules. Never mark a task done without a green build, green tests, and a reviewer PASS. Stop and ask me whenever: an architectural change seems needed, a HARDWARE-VERIFY item blocks progress, or a dependency would be added.

## The dispatch loop (what the orchestrator does per task)

```
TASKBOARD item
   ├─(if Apple-API-touching)─► api-researcher ──► verified surface
   ├─► swift-builder (brief + surface) ──► summary + files
   ├─(if domain logic)─► test-engineer ──► coverage + bugs found
   ├─► code-reviewer ──► PASS / FAIL(+blocking list)
   │        └─FAIL─► swift-builder(fix list) ─► code-reviewer  (≤3 loops)
   └─PASS─► commit, tick TASKBOARD, status paragraph
```

Briefing rule: every subagent starts with a **fresh context** — it has not seen this conversation. Each brief must be self-contained: repeat constraints, name exact files, quote acceptance criteria. Vague briefs are the main way orchestration fails.

## Human checkpoints (don't automate these)

- **End of Phase 0:** run the WorkoutKit spike on a real iPhone + Watch. Every `HARDWARE-VERIFY` and RESEARCH-LOG "unknown" gets answered here before Phase 1 proceeds.
- **End of each phase:** run the app yourself; review TASKBOARD deltas and the reviewer verdicts log.
- **Any permission-sensitive step:** signing, entitlements (HealthKit, WorkoutKit), App Group setup — do in Xcode by hand.

## Escalation triggers (orchestrator must stop and ask)

- Reviewer FAIL persists after 3 fix cycles.
- Any proposal to add a dependency, change module boundaries, or alter the data model beyond ARCHITECTURE.md §5.
- api-researcher returns "unknown-needs-hardware" for something on the critical path.
- Build broken for reasons outside the current task's scope.
