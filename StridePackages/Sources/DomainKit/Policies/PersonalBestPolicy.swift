import Foundation

/// The outcome of evaluating a `CompletedRun` that qualifies for a
/// `Milestone` against the current `PersonalBest` (if any) for that
/// milestone.
///
/// Emitted by `PersonalBestPolicy.evaluate(run:milestone:currentBest:)`.
/// `IngestCompletedRunsUseCase` (task 1.12) is the only intended consumer,
/// and acts on it by calling `RunHistoryRepository.savePersonalBest(_:)`
/// (only for `.newRecord`) — the policy itself performs no persistence
/// (CLAUDE.md rule 7; `docs/ARCHITECTURE.md` §6's `PersonalBestPolicy` row:
/// "pure function... this purity makes it exhaustively unit-testable").
public enum PersonalBestDecision: Equatable, Hashable, Sendable {
    /// No prior record existed for the milestone, or the run's elapsed time
    /// was strictly less than the current record's `elapsedSeconds`. The
    /// associated `PersonalBest` is the new record the caller should persist
    /// via `RunHistoryRepository.savePersonalBest(_:)`.
    ///
    /// No explicit "archive the old record" step is needed: per
    /// `RunHistoryRepository.fetchPersonalBest(milestoneID:)`'s documented
    /// ordering (lowest `elapsedSeconds` wins, ties broken by latest
    /// `achievedAt` then `id.uuidString` ascending), simply persisting this
    /// new, strictly-faster record is sufficient for it to become "current"
    /// on the very next fetch — the previous record remains stored,
    /// unmodified, as history. Supersession is therefore "no longer first
    /// in the repository's ordering," never a flag mutation, matching
    /// `PersonalBest`'s own doc comment ("no superseded flag... supersession
    /// is a repository/policy concern").
    case newRecord(PersonalBest)

    /// The run's elapsed time exactly equals the current record's
    /// `elapsedSeconds`. A tie is deliberately **not** treated as a new
    /// record: "current" in `RunHistoryRepository`'s ordering contract is
    /// the *lowest* `elapsedSeconds`, and an equal value does not lower it
    /// — nothing has strictly improved. Persisting a tied duplicate would
    /// only add a second, indistinguishable "current" candidate whose
    /// resolution then hinges entirely on the ordering's `achievedAt`/`id`
    /// tie-break (an implementation detail of the repository, not a
    /// meaningful new PR). The caller should not persist anything for a
    /// `.tie`; `currentBest` is echoed back unchanged for observability
    /// (e.g. a "matched your PR" UI moment) only.
    case tie(currentBest: PersonalBest)

    /// The run's elapsed time is slower than the current record, or the run
    /// did not actually qualify for this milestone at all (tombstoned, or
    /// non-finite/non-positive distance or duration — see
    /// `PersonalBestPolicy.isEligible(_:)`, applied defensively inside
    /// `evaluate` even though callers are expected to only invoke it for
    /// milestones `qualifyingMilestones(for:among:)` already returned).
    /// `currentBest` is `nil` only in that ineligible-run case when no
    /// record has ever been set; in every other no-change case it echoes
    /// the existing record unchanged.
    case noChange(currentBest: PersonalBest?)
}

/// Determines which milestones a completed run qualifies for, and whether a
/// qualifying run sets a new personal best.
///
/// Pure, stateless, and side-effect free — no I/O of any kind
/// (`docs/ARCHITECTURE.md` §6's `PersonalBestPolicy` row). Persistence (of
/// the new `PersonalBest`; no separate "archive" step is needed, per
/// `PersonalBestDecision.newRecord`'s doc comment) is entirely
/// `IngestCompletedRunsUseCase`'s (task 1.12) responsibility.
///
/// This is the MVP **whole-run policy** `docs/ARCHITECTURE.md` §8 and the
/// Phase 2 roadmap describe: elapsed time for a milestone is always the
/// run's whole `durationSeconds`, never a scaled or extracted sub-segment
/// time. The future "fastest sub-segment" policy (true fastest 5K inside a
/// longer run, using `Split` data) is explicitly out of scope — that is
/// task 2.2, a policy-object swap per §8, not a change to this type.
public enum PersonalBestPolicy {

    // MARK: - Qualification

    /// Returns every milestone in `milestones` that `run` qualifies for.
    ///
    /// **Tolerance rule — flagged prominently for reviewer confirmation:**
    /// a run qualifies for a milestone when
    /// `abs(run.distanceMeters - milestone.distanceMeters) <= milestone.tolerance`.
    /// This is exactly the symmetric band `docs/ARCHITECTURE.md` §8
    /// specifies verbatim: "candidate if `|run.distance − milestone.distance|
    /// ≤ tolerance` (e.g., 5K tolerance ~1-2%: GPS overshoot counts, a 7K
    /// doesn't)" — so this is not a novel policy invention, but the
    /// already-architected rule, using each `Milestone`'s own `tolerance`
    /// field (already populated at ~2% of distance for every MVP preset —
    /// see `Milestone.swift`). The band is symmetric: both a slight
    /// **undershoot** (e.g. a GPS-shortened "5.00K" that actually recorded
    /// 4,980 m) and a slight **overshoot** (the architecture's explicit GPS
    /// example) qualify, matching `Milestone.tolerance`'s own doc comment
    /// ("acceptable absolute **deviation**" — deviation is signed-agnostic).
    ///
    /// Elapsed time for a qualifying milestone is always the run's *whole*
    /// `durationSeconds` (see `evaluate`), with **no scaling** toward the
    /// milestone's exact nominal distance. Scaling would silently assert a
    /// pace assumption ("if 5.00 km took this long, 5.10 km would have
    /// taken proportionally longer") that this policy has no business
    /// making about a runner's actual effort; it is deliberately left
    /// un-scaled and documented here for review.
    ///
    /// **Multi-milestone semantics — also flagged prominently for reviewer
    /// confirmation:** a run qualifies **only** for milestones whose
    /// tolerance band actually contains its distance — never for every
    /// smaller milestone the distance happens to exceed. A whole-run
    /// elapsed time is only a meaningful proxy for *that* milestone's time;
    /// a marathon's finish time is not a meaningful 5K time, so a marathon
    /// run must never set a 5K PR under this whole-run policy. Concretely:
    /// a 10.1 km run (within the 10K band, 10,000 ± 200 m) qualifies for
    /// 10K but **not** 5K (its distance, 10,100 m, is far outside the 5K
    /// band of 5,000 ± 100 m). With the standard, widely-spaced MVP preset
    /// distances, at most one milestone's band will ever contain a given
    /// run's distance in practice — but this function does not assume
    /// that; it independently tests every milestone's band and returns
    /// every match, so a future milestone catalog with closely-spaced or
    /// wide-tolerance entries still behaves correctly (and multiple
    /// simultaneous qualifications, however unlikely today, are handled
    /// rather than silently collapsed to "the largest one").
    ///
    /// Never qualifies for anything (returns `[]` regardless of distance)
    /// when: `run.isDeleted` is `true` (a tombstoned projection, per
    /// `CompletedRun.isDeleted`'s doc comment); `run.distanceMeters` is not
    /// finite and strictly positive; or `run.durationSeconds` is not finite
    /// and strictly positive. `NaN` compares `false` against every
    /// relational operator, so an explicit finiteness check is required —
    /// see `ValidateWorkoutPolicy.isPositiveFinite` for the identical
    /// pattern used elsewhere in this module.
    public static func qualifyingMilestones(
        for run: CompletedRun,
        among milestones: [Milestone] = Milestone.mvpPresets
    ) -> [Milestone] {
        guard isEligible(run) else { return [] }
        return milestones.filter { qualifies(run: run, milestone: $0) }
    }

    /// Whether `run` alone qualifies for `milestone` (the single-milestone
    /// version of `qualifyingMilestones(for:among:)`, for callers that
    /// already have one specific milestone in hand and don't need the
    /// filtering convenience).
    public static func qualifies(run: CompletedRun, milestone: Milestone) -> Bool {
        guard isEligible(run) else { return false }
        return abs(run.distanceMeters - milestone.distanceMeters) <= milestone.tolerance
    }

    // MARK: - Evaluation

    /// Decides the outcome of a qualifying `run` against `currentBest`, the
    /// existing "current" `PersonalBest` for `milestone` (as resolved by
    /// `RunHistoryRepository.fetchPersonalBest(milestoneID:)`'s documented
    /// ordering), or `nil` if no record has ever been set for this
    /// milestone.
    ///
    /// - `currentBest == nil` → `.newRecord`: the run establishes the first
    ///   ever record for this milestone.
    /// - `run.durationSeconds < currentBest.elapsedSeconds` → `.newRecord`:
    ///   strictly faster, per the ordering's "lowest `elapsedSeconds` wins"
    ///   definition of "current".
    /// - `run.durationSeconds == currentBest.elapsedSeconds` → `.tie`: see
    ///   `PersonalBestDecision.tie`'s doc comment for why a tie is
    ///   deliberately not a new record.
    /// - otherwise (strictly slower) → `.noChange`.
    ///
    /// For a `.newRecord`, the returned `PersonalBest.id` is freshly
    /// generated; `milestoneID` is `milestone.id`, `elapsedSeconds` is
    /// `run.durationSeconds` (whole-run, unscaled — see
    /// `qualifyingMilestones(for:among:)`'s doc comment), `completedRunID`
    /// is `run.id`, and `achievedAt` is `run.date` (the date the run
    /// occurred, not "now" — so PR history stays correct even for runs
    /// ingested well after the fact, e.g. a backfill or a delayed
    /// background-delivery wake-up per `docs/ARCHITECTURE.md` §11's note
    /// that background delivery is best-effort).
    ///
    /// Defensively re-checks the FULL qualification (`qualifies(run:milestone:)`
    /// — eligibility plus the milestone's distance band) even though callers
    /// are expected to only call this for milestones
    /// `qualifyingMilestones(for:among:)` already returned. A run outside the
    /// milestone's band resolves to `.noChange` rather than fabricating a
    /// record — otherwise a mismatched call (e.g. a marathon run evaluated
    /// against 5K) would mint the marathon's whole-run duration as a 5K PR.
    public static func evaluate(
        run: CompletedRun,
        milestone: Milestone,
        currentBest: PersonalBest?
    ) -> PersonalBestDecision {
        guard qualifies(run: run, milestone: milestone) else {
            return .noChange(currentBest: currentBest)
        }

        guard let currentBest else {
            return .newRecord(makePersonalBest(run: run, milestone: milestone))
        }

        if run.durationSeconds < currentBest.elapsedSeconds {
            return .newRecord(makePersonalBest(run: run, milestone: milestone))
        }
        if run.durationSeconds == currentBest.elapsedSeconds {
            return .tie(currentBest: currentBest)
        }
        return .noChange(currentBest: currentBest)
    }

    // MARK: - Private helpers

    /// Whether `run` is eligible to qualify for *any* milestone at all: not
    /// tombstoned, and both `distanceMeters` and `durationSeconds` are
    /// finite and strictly positive.
    private static func isEligible(_ run: CompletedRun) -> Bool {
        !run.isDeleted && isPositiveFinite(run.distanceMeters) && isPositiveFinite(run.durationSeconds)
    }

    /// Whether `value` is both finite and strictly positive — `NaN` and
    /// `+.infinity` both fail every naive `<= 0` check, so this is the
    /// single source of truth for "positive" throughout this policy (same
    /// pattern as `ValidateWorkoutPolicy.isPositiveFinite`).
    private static func isPositiveFinite(_ value: Double) -> Bool {
        value.isFinite && value > 0
    }

    /// Builds the fresh `PersonalBest` a `.newRecord` decision carries.
    private static func makePersonalBest(run: CompletedRun, milestone: Milestone) -> PersonalBest {
        PersonalBest(
            milestoneID: milestone.id,
            elapsedSeconds: run.durationSeconds,
            completedRunID: run.id,
            achievedAt: run.date
        )
    }
}
