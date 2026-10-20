# P1.1B — Comparative benchmark and backend feasibility: planning handoff (PROPOSED)

**State:** `PROPOSED_FOR_OWNER_REVIEW / NOT_AUTHORIZED_FOR_EXECUTION` (2026-10-20).  
**Baseline:** verified `main` `aca6b6403c455708cacda01c8fbf0bf980d813a2`, after owner-authorized [PR #96](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/96) merger; P1.1A isolated LOD0/LOD1 transition fixture is merged.  
**Binding upstream plan:** [P1.1 R2 owner-approved plan](P1-1-APPROVED-PLAN-R2.md); read it fully rather than replacing its architecture with this handoff.  
**Post-merge checkpoint:** [P1.1A receipt](../checkpoints/2026-10-20-P1-1A-OWNER-AUTHORIZED-INTEGRATION.md).

## Purpose and decision this stage prepares

Make the next architecture decision **evidence-driven**: quantify the custom experimental candidate’s actual CPU/normal sampling/mesh creation/runtime-memory costs and evaluate Voxel Tools feasibility using public documentation/code/licensing and canonical SDF/ledger compatibility. Do **not** treat fixture speed for one cell as a prediction of sustained 3×3 resident-region performance. Do **not** adopt Voxel Tools or implement production LOD until separately approved.

This is a planning document and an owner decision package outline, not a grant of authority to run or write P1.1B software.

## Proposed work packages and authority

| Package | Scope | Evidence expected | Authority |
| --- | --- | --- | --- |
| **B0 — requirements and baseline** | Pin benchmark rig/OS/renderer/driver/Godot revision; review `16,807` developer-reported test baseline and exact P1.1A geometry; list resource/error/fine-feature budgets still missing | Machine manifest, accepted/suggested numerical targets distinguished, objective workload/seed registry, reproducibility & calibration plan | **Planning only**: may prepare documentation, no execution or implementation |
| **B1 — custom backend performance evaluation** | Define independent cold/warm movement, 3×3 bounded streaming, edit replay 0/1/32/128/256, negative seam/corner crossings, LOD0 vs LOD1 unit references and synthesized transitions | p50/p95/p99/peak by event; per-run sample counts, variance, CPU and main-thread publication, real RSS, mesh bytes, GPU/VRAM only where actually measurable, headless-vs-GUI separation | **Future explicit owner approval** before code/test runs outside already approved P1.1A |
| **B2 — Voxel Tools documentary feasibility** | Pin actual upstream tag/release, Godot API compatibility, license/dependencies/SBOM, native safety/provenance, `VoxelLodTerrain` storage/editing rules, unloaded-chunk edits, transition/collision/normal and future mod/multiplayer implications | Linked public-source matrix with version/date, quantitative comparability limits, exact unmet integration requirements and risk register | **Public document/source examination only**; no installation/download/execution of native binary or F2-G1 operations |
| **B3 — decision packet** | Compare bounded custom prototype against documentary Voxel Tools feasibility, flag apples-to-oranges metrics, propose ADR-0002 options without accepting one | Traceable tradeoff matrix, go/no-go evidence gaps, exit gates for P1.1C and rollback strategy | Owner reviews and explicitly selects future scope; no backend change by proposal |

## Pre-registration needed before performance acceptance

Obtain owner decisions on: target Windows machine(s), representative target GPU/VRAM and renderer, target frame period/FPS, worst allowed main-thread frame spike, end-to-end click-to-visible latency budget, resident-region cap, peak RSS/VRAM caps, acceptance windows for geometry residual in world units and projected screen space, permitted normal-angle mismatch, and thin/cave feature preservation. Historical n=12 single-cell samples remain **exploratory** only; do not retroactively fit thresholds to observations.

Per workload, choose fixed seeds and canonical ordered edits; define warmup, repetitions, timing intervals, cold/warm cache, scene vs headless capture and profiler overhead. Do not pool dissimilar workloads into one p99. Record all experimental failures.

## Architecture and security gates

- Do not modify `SdfWorld` v1, single ordered 256-command `SdfBrushEditState` ledger, region/chunk ownership, signed lattice/floor, or existing gameplay controls.
- The P1.1A transition fixture is detached CPU data; it proves neither general multi-cell mosaics nor GPU frame performance. No automatic P1.1C or production scene work follows from this document.
- LOD2 and higher require separate coherent region/chunk grouping or retiling: existing 3-unit Z chunk span is not divisible by h2=2.
- `ADR-0002` is PROPOSED. Voxel Tools is a **native dependency**, subject to provenance/legal/environment checks and **not executed** until new explicit authorization plus release of applicable F2-G1 holds.
- Preserve `CURRENT_PROTECTED_STATE_UNKNOWN`, `V3_NOT_ATTESTED`, `ACL_REVIEW_REQUIRED`, `G1_BLOCKED_ENVIRONMENT`, and `F2_G1_RELEASE_HOLD`.

## Next proposed Codex ticket (planning only)

Read owner-approved P1.1 R2, P1.1A implementation/spec/checkpoints, last exact-SHA source review, current status and this handoff from current `main`. Create an **evidence-backed P1.1B experimental-design and backend-comparison plan**, not code. Inventory existing instrumentation, exact comparability gaps, actual public Voxel Tools sources with pinned revision and license; produce an owner decision table of proposed benchmark datasets, metrics, acceptance thresholds to approve, risks and unresolved F2-G1 blockers. Avoid unapproved benchmarks, native binaries, source edits or merge. Deliver `P1_1B_PLAN_READY_FOR_OWNER_DECISION` or `P1_1B_PLANNING_BLOCKED_WITH_EVIDENCE`.

**No implementation authorization is implied** until the owner explicitly approves a further P1.1B scope.
