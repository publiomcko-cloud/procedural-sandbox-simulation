# ADR-0002 (PROPOSED): Terrain backend selection and adapter boundary

**Status:** PROPOSED — not owner-approved; not binding.
**Date:** 2026-10-08
**Decision owner:** Project owner.
**Related:** Accepted ADR-0001, `docs/architecture/TERRAIN_ADAPTER_PROPOSAL.md`, `docs/research/P0.1-TERRAIN-BACKEND-COMPARISON.md`.

## Context

The accepted architecture requires smooth volumetric SDF terrain, caves, additive/subtractive/sculpt/material edits, deterministic versioned generation, wide region addressing, revision-checked commands, asynchronous stale-result rejection, persistent changes, shared material properties, and mod compatibility independent of backend types. No terrain implementation has been approved. P0.1 calls for comparing Voxel Tools with a custom SDF alternative before selecting a backend. The baseline must remain unchanged while the experiment is proposed and reviewed.

## Verified facts

- Voxel Tools release page lists a 1.7 GDExtension release labeled for Godot 4.5+ and a separate custom build paired with Godot 4.7.2 stable (`ed1daf0bf`); the GDExtension descriptor currently declares minimum 4.4.1. These are publisher/source compatibility declarations, not a verified run against this project.
- Voxel Tools source repository identifies MIT licensing. Its docs cover smooth SDF/Transvoxel terrain, `VoxelLodTerrain`, edit tools, material channels, block streams/SQLite, and threaded generation/update.
- Its docs state direct LOD terrain editing is limited to the first LOD; async persistence has explicit flush/wait lifecycle concerns. GDExtension is described as newer/less tested than module builds.
- Godot thread-safe API documentation constrains scene/resource use from background threads.
- No package was installed or executed, no terrain benchmark was run, and no candidate has passed project acceptance.

## Proposal for the P0.1 experiment

1. Adopt the candidate-independent adapter contract as the boundary for a reversible dual-candidate experiment, subject to evaluator and owner acceptance.
2. Compare exact Voxel Tools 1.7 GDExtension release (artifact and platform set pinned before experiment) against a minimal custom GDScript SDF backend. Keep custom implementation to bounded fixtures and required P0.1 cases; no optimization or production claim.
3. Keep domain edit journal, generator manifest, stable material IDs, authoritative revisions, and mutation receipts outside either backend. Backend storage may be rebuildable cache only during the spike.
4. Run the same correctness suite and deterministic workload on the pinned Godot 4.7.2 standard build. Performance targets must be set by owner before benchmark result inspection using the declared target machine/workload method in the research report.
5. Make no production selection unless compatibility, legal inventory, correctness, export targets, persistence, measured performance/memory, integration complexity, and maintenance plan are reviewed together.

## Consequences if approved

- A gains mature terrain-specific features sooner, while bringing native binary/export and upstream-version risks, first-LOD editing limits, third-party save-format coupling risk, and MIT notice obligations.
- B preserves direct ownership of canonical data and adapter-specific semantics but shifts algorithm, LOD, collision, storage, and maintenance work to this project; GDScript throughput remains unmeasured.
- Both choices incur adapter, revision, neighbor invalidation, and deterministic compatibility requirements. Mods remain independent of implementation details.
- P0.1 implementation, dependency introduction and backend selection remain separately reviewable; approving this experiment is not blanket approval to install third-party code, ship it, or alter accepted scope.

## Rejected alternatives for this proposal

- Select Voxel Tools on documentation alone: rejected because exact compatibility, edit limitations, integration, persistence, performance and platform coverage remain unverified.
- Select custom SDF on control/avoidance of dependencies alone: rejected because algorithm and implementation costs/performance are unmeasured.
- Expose backend APIs as permanent mod contracts: rejected because that binds content and saves to a replaceable implementation.
- Rewrite ADR-0001: rejected; any change to its accepted SDF/product requirements requires a future superseding ADR and owner decision.

## Missing evidence before a final backend decision

- Independent source review of exact artifact/tag, full transitive license/notices, hashes, platforms and export templates.
- Successful clean import/editor/runtime/export test with exact Godot 4.7.2 and backend binary, if available.
- Same-seed order-independent field hashes; caves, smooth additive/subtractive/material edits; cross-region seam and normal checks; LOD transitions and edit policy.
- Runtime revision reconciliation for mesh and collision under racing edits, loads and unloads.
- Save/reopen/replay evidence, plus P0.2-grade interruption/recovery evidence before production persistence claims.
- Same-hardware timing/memory results and maintainer/dependency update plan.

## Owner decisions requested after independent evaluation

1. Accept/revise/reject the proposed adapter as the P0.1 comparison boundary.
2. Approve or decline a later isolated experiment that may obtain and run the exact Voxel Tools artifact after license/platform review. No dependency installation is authorized by this document.
3. Select target CPU/GPU/RAM/storage/OS and shipping platforms for benchmark acceptance.
4. Confirm project density sign convention, editing behavior against distant LOD, and whether a temporary collision publication lag is acceptable.
5. Set or approve the performance threshold-setting method before any measured results are shown.

## Final decision

**Deferred.** No terrain backend is selected by this proposed ADR. It takes effect only after explicit owner approval, and final backend selection requires a later evidence-backed ADR.
