# DM25 — Focal first-dispatch stall attribution, matched equal-observer A/A

**Date:** 2026-11-14. **Branch:** `exp/dm25-focal-stall-attribution-aa` based on DM24 (DM18 ON). DM24 experimental fairness OFF in both arms. `main` remains untouched. This is a **diagnostic**, not a new priority policy.

## Motivation and preregistration

DM24 [corrected run 43606090913](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/43606090913) completed 40 replicated A/B trials with instrumentation parity. In primary warm-long, missing focus was 23.833% in control and 23.974% with fairness, paired delta +0.1405 percentage points (95% paired t CI [−0.080, +0.361]). Focal gaps in the DM19 `awaiting_first_dispatch` state account for ~93% of all missing-focus frames. DM24-F was not qualified. DM18 remains retained.

**Hypothesis H1:** Most first-dispatch misses with global capacity involve selecting other LOAD stages rather than missing worker slots or frame dispatch budget.

**Hypothesis H2:** An appreciable number of focal stages are selected but effect snapshots stay pending on source scopes. DM24 'eligible' was only globally eligible, not source-ready.

**Hypothesis H3:** The disparity between stage creation→first dispatch and end-user focal gaps is a *cohort / timing / cancellation* effect, not simply a worker queue.

No hypothesis is assumed true; all must be measured.

## Observer-only implementation

The DM25 additions to `DM24CanonicalStageFunnelProbe` observe the same real runtime in both arms, maintaining existing DM24 stage metrics and per-stage/token scoping. At the **same post-frame boundary as DM19.sample_frame**, an actually missing focal LOAD with `submit_index == 0` receives exactly one mutually exclusive reason:

- `selected_effect_pending` if focal selection was attempted and required effect snapshot was pending.
- `selected_without_pending_or_dispatch` if it was selected but no pending result or dispatch was observed.
- `no_budget_at_dispatch_entry` or `no_worker_at_dispatch_entry`.
- `protected_stage_selected` (edit/partial/full) or `other_load_selected` (nonfocal LOAD).
- `no_selection_with_global_capacity` when no focal selection occurred and global budget/workers existed.
- `untracked_or_changed_stage` for a token mismatch (an explicit epistemic guard, not attributed as runnable).

The observer counts missing source-region IDs when the focal first-chunk snapshot is selected and returns pending; the map is bounded to 128 keys. **Scope identity is not proof of which queue phase caused the wait.** No DM25 action changes selected jobs, revisions, source ownership, WorkerThreadPool, radius, budgets, task priority, or 16-chunk publication semantics.

DM25 reports exactly the same trace cost in both A/A arms; it inherits the normal DM22/23/24 shadow computations, DM19 diagnostic and DM18 cache configuration. Heavy PERF_TRACE OFF. A/A uses the same seed (424242), physical movement at 18 m/s, APPDATA isolation, interleaved pair order and profile as DM24. Each trial checks the disjoint bucket total and that DM25-attributed focal misses do not exceed DM19's first-dispatch misses (DM19 may include stage purposes excluded from DM25).

## Qualification

- Exact: Godot 4.7.2 parse; dedicated eight-category synthetic DM25 attribution contract; DM24/DM23/DM22/DM19/DM18/DM17/DM11/D7.3 regressions.
- Smoke A/A: 10 trials = 2 cold-forward pairs, 1 warm-forward pair, 2 warm-long pairs.
- Replicated A/A: 40 trials = 6 cold-forward pairs, 4 warm-forward pairs, 8 warm-long pairs, 2 idle pairs.
- All 40 runs must have DM24-F OFF, DM18 ON, DM19/DM22/DM23/DM24 trace enabled and identical shadow selector cost; any protocol violation invalidates the comparison. No win/loss claim from A/A.

## Readout and next gate

Primary readout is the warm-long distribution of **actual missing focal first-dispatch frames** by mutually exclusive reason, linked to same-region/token source-scope IDs. The control-vs-repeat A/A spread quantifies runner noise. Check missing-focus %, p99, frames>33ms, HIGH, source queue and snapshot pending. Important: DM25's `no_selection_with_global_capacity` is **not** certified source readiness, and `selected_without_pending_or_dispatch` requires targeted follow-up before interpretation. If a diagnostic class dominates, instrument that class's exact causal path and then design one independent treatment with equal overhead. Do not promote a scheduling policy or merge to main without replicated warm-long improvement, parity and GPU visual review.

**Current result:** implementation pending GitHub Actions qualification.
