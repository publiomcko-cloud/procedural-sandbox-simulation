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
