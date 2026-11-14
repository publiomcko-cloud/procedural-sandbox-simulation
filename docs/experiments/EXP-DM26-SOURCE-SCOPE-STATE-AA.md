# DM26 — Exact source-scope state at first canonical chunk (matched A/A)

**Date:** 2026-11-14. Branch `exp/dm26-source-scope-state-aa`; derived from DM25 with DM18 retained and DM24-F OFF. `main` unchanged. No scheduling, source authority, worker-pool, radius, or publication change.

## Pre-registered question

The complete [DM25 run 43611787222](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/43611787222) found that 100% of warm-long first-dispatch missing-focus frames were *selected focal snapshot → effect pending*. Across 16 runs, the exact same missing source scope was `region:23,14`. DM22 totals alone cannot identify why that scope never becomes ready during those waits. Distinguish scope **not protected**, **not enqueued despite being protected**, **queued but not started**, **generation in flight**, **projection in flight**, **projection ready but unpublished**, **invalidated**, and **resident** before hypothesizing a fix.

## DM26 observer

At each pending snapshot of the **tracked focal first chunk**, after normal enqueue, interrogate the existing effect runtime without mutating it. Record exact missing source ID, projected residency, invalidation flag, membership in the protected working set, tracking flag, queue position, urgent/normal queue classification, generation/projection in-flight, projection-ready, queue length, worker job counts and error presence. Collapse these into one exclusive lifecycle state per source observation, plus last state and number of observed transitions. Record no raw object data. Source maps are bounded to 128 IDs.

Sampling occurs from the preexisting DM25 first-chunk pending callback, with **identical new diagnostic cost in both A/A arms**. DM25 and DM19 continue to classify the actual post-frame focal gap at the same old boundary. The benchmark asserts that the new source-state census accounts for every DM25 pending-source observation. This counts *observations*, not independent regions or a wall-clock duration. States do not by themselves prove why a transition did not happen.

## Qualification gate

- Exact tests: new synthetic scope-state and reset contract, plus DM25/DM24/DM23/DM22/DM19/DM18/DM17/DM11/D7.3 inherited tests, Godot 4.7.2 and PowerShell 5.1 parse checks.
- Smoke A/A: 10 trials = 2 cold, 1 warm-forward, 2 warm-long matched pairs.
- Replicated A/A: 40 trials = 6 cold, 4 warm-forward, 8 warm-long and 2 idle matched pairs. Inputs, seed, profile, prewarm, motion speed and APPDATA isolation are unchanged.
- Both arms: DM18 ON, DM24-F OFF, DM19/DM22/DM23/DM24/DM25/DM26 observability ON; heavy perf trace OFF; identical shadow selector cost. No adaptive diagnostic switching by outcome.
- Require A/A outcome stability and no unexplained source-state accounting gap before any causal intervention. No performance-policy promotion from A/A.

**Pending:** GitHub Actions validation and per-scope state classification. The next intervention, if justified, must target the measured state bottleneck while retaining source authority, revision gates and 16-chunk publication parity.


## Terminal DM26 — A/A diagnostic result, 2026-11-14

**Qualified workflow:** [GitHub Actions 43622124490](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/43622124490), exact tested commit \`92d90bfacfe272e6a03552131da3cfe4535c0fca\`. All dependencies completed successfully in order: exact/parse/ten regressions, **one** full-instrumented \`warm-long\` preflight, 10-trial smoke, and 40-trial factorial A/A. Evidence artifact \`dm26-scope-validated-evidence\` (ID \`14125678563\`). Both arms keep DM18 ON, DM24-F OFF and all scope/focal observers equal. \`main\` unchanged.

| Scenario | Matched pairs | Control focus missing | Repeat focus missing | Mean paired repeat-control [95% paired t CI] | Mean p99 difference [95% CI] |
|---|---:|---:|---:|---:|---:|
| cold-forward | 6 | 38.9352% | 38.6573% | −0.2778 pp [−9.7356,+9.1800] | +1.8773 ms [−3.5726,+7.3273] |
| warm-forward | 4 | 0.9028% | 5.0350% | +4.1323 pp [−3.6913,+11.9558] | −0.3513 ms [−11.8691,+11.1666] |
| **warm-long** | **8** | **25.3595%** | **25.7343%** | **+0.3748 pp [−1.0958,+1.8453]** | **+0.0510 ms [−0.6694,+0.7714]** |
| idle | 2 | n/a | n/a | n/a | 0 ms |

**Key causal boundary:** In **all 16 warm-long runs**, every pending-source observation of the focal first chunk refers to \`region:23,14\` in the exclusive \`projection_inflight\` observer state: 4,261 occurrences across eight controls and 4,264 across eight repeats (100% of sampled warm-long blocking-source observations). Per trial, DM25 first-dispatch focal missing frame count averages 532.625 control and 533.000 repeat, and the DM26 source census reconciles to this count. No pending-frame scope-state transitions were observed in warm-long; final source observations have \`protected=true\`, \`tracked=false\`, queue index −1 and zero observed prefetch errors. This stage is not a measured CPU duration; it means the **scope→projection task map contains an entry**, not necessarily that its Godot worker is still executing.

Other scenarios differ: **cold-forward** source observations are ~68% queued urgent, ~17% projection-inflight, ~15% generation-inflight; **idle** ~73% queued urgent, ~14% projection-inflight, ~13% generation-inflight. Warm-forward has zero first-dispatch focal source observations, even though some missing-focus frames occur in other phases. A/A outcomes have substantial variance outside the stable warm-long attribution and must not be treated as performance improvement.

**Source code reconciliation and unresolved hypothesis:** \`terrain_object_effect_runtime.gd\` sets \`_prefetch_projection_task_by_scope[scope_id]\` when queueing a worker, suppresses duplicate enqueue while that mapping exists, and normally erases it upon processing/publishing the completed result. The protected-window filter can mark an in-flight record as \`cancelled\` when leaving the window. Because the focal source is \`projection_inflight\` while absent from the currently tracked prefetch set, the plausible suspects include **an old cancelled job, pending worker task, completed-but-unprocessed worker task, or stale scope→task mapping**. The DM26 probe did not read task ID, job record's cancelled state, \`WorkerThreadPool.is_task_completed()\`, or actual worker start/finish timestamps. Therefore, do **not** claim that CPU projection computation takes 533 frames or that the task is definitively orphaned. DM22 aggregate source queue 396 vs publications 395 and projection dispatches/completions both 246 per typical warm-long run; aggregate counts do not identify the unmatched source.

**Decision:** \`DM26_SOURCE_STATE_QUALIFIED_PROJECTION_TASK_STATUS_UNRESOLVED\`. No policy promotion. Keep DM18 and the existing protected source authority; DM24-F stays OFF. The source-stage bottleneck is a lifecycle/status question before it is a scheduling-priority question.

### DM27 recommended narrow experiment — task identity, cancellation and completion state

Instrument the *same pending focal scope* in **both arms** with the actual projection \`task_id\`, whether that ID exists in \`_prefetch_projection_jobs\`, \`record.cancelled\`, \`WorkerThreadPool.is_task_completed(task_id)\`, worker \`worker_started_usec\` and \`worker_finished_usec\`, submission age and protected/tracked flags. Also count de-duplication blocked by a task mapping with no backing job and abandoned cancelled jobs while the scope becomes protected again. This must be read-only, bounded, stable per-frame, revision-safe and tested at the same actual focal frame boundary. Follow the enforced **exact → exactly one instrumented primary-trial preflight → smoke → factorial** gate, with equal observer cost. Only then consider a one-variable A/B intervention and parity/latency qualification.
