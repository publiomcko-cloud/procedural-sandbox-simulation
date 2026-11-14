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


## Terminal DM25 result — run 43611787222 (PASS)

The [corrected DM25 A/A workflow](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/43611787222), commit \`3b2ea1d676f568982c77ea5391f4cadfadc9e993\`, completed exact, 10-trial smoke and 40-trial replicated A/A with no failures, identical instrumentation and no DM24 policy intervention. Artifact \`dm25-focal-validated-evidence\`, ID \`14122020809\`, holds per-run receipts. DM18 ON in all arms. No GPU visual qualification and no change to \`main\`.

**Primary warm-long A/A, n=8 paired runs, repeat minus control:**

| Metric | Control mean | Repeat mean | Paired difference [95% t CI] |
|---|---:|---:|---:|
| Missing focus | 23.7293% | 23.7241% | −0.0051 pp [−0.191, +0.181] |
| Frame p99 | 17.9941 ms | 18.0560 ms | +0.0619 ms [−0.0845, +0.2082] |
| HIGH completed | 578.0 | 578.75 | +0.75 [−3.04, +4.54] |
| First-dispatch latency, successfully dispatched only | — | — | +19.24 ms [−31.52, +70.01] |

The diagnostic observer's **exclusive bucket partition exactly reconciled to DM19's \`awaiting_first_dispatch\` count in every warm-long trial**. On average 533.625 missing first-dispatch frames in control and 533.125 in repeat were attributed to **selected focal first-chunk snapshot with effects pending**; the seven alternative buckets contributed **zero** in warm-long. Of all *missing focus* frames, first-dispatch pending accounts for ~93%; the 100% share applies only inside that first-dispatch subset, **not** all frame gaps.

**All 16 warm-long receipts show the same unresolved source-scope identifier:** \`region:23,14\`, and no other source ID in their DM25 missing-source maps. DM22 logged 396 source queue events and 395 source publications in every trial, but it **does not establish whether this particular scope was queued, dispatched, cancelled, evicted, invalidated or not protected**; those are aggregate totals, not scope-specific evidence. DM22 critical published-source attribution is empty for most warm-long focal waits because 10 focal first-chunk waits/trial ended in cancellation, while only one was first-submitted while focal. The first chunk that never dispatched is absent from successful-dispatch latency summaries. Do not infer a failed projection worker or CPU saturation without scope-state evidence.

Cold-forward first-dispatch gap attribution is also predominantly effects-pending (~97–98%); the remaining ~2–3% is unavailable worker capacity. Warm-forward after prewarm has zero first-dispatch missing-focus frames in both arms. A/A cold-forward missing-focus delta was −1.967 pp (95% t CI [−4.854, +0.920]) and frame p99 difference +0.801 ms (95% CI [−4.176, +5.778]), demonstrating material background variance in secondary cold measurements without an algorithm change.

**Decision:** \`DM25_DIAGNOSTIC_QUALIFIED_SOURCE_STATE_UNRESOLVED\`. H2 is supported at the actual focal-frame boundary; H1 is not supported for warm-long. Keep DM18, keep DM24-F disabled. Do not promote or merge to \`main\`.

### Follow-on diagnostic DM26 (single-source scope-state census)

Observe \`region:23,14\` and every focal pending source at each first-chunk pending attempt: is it in the required 9×9 protected set, present in projection, valid for authority revision, in the urgent/normal queue (with actual position/age), generation in-flight, projection in-flight, projection-ready, cancelled, or absent from the queue? Record source scope lifecycle transitions and queue eviction/promotion **by actual scope ID**, not aggregate counters. Preserve the exact same observer in both A/A arms, with no scheduling or working-set changes. Prove whether a source is never admitted, repeatedly invalidated/cancelled, or simply delayed before considering any treatment. Specifically test the protected-scope invariant for the focal source at runtime and the opposite boundary case; keep all tests revision-gated and 16-chunk publication-authoritative.
