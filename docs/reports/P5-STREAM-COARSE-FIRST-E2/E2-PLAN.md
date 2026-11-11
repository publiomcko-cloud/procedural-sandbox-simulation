# P5 streaming E2 — coarse-first with revision-gated definitive replacement

Status: **EXPERIMENT / DO NOT MERGE**. Owner authorized E2 on 2026-11-11 after E1.1 showed lower scheduler cost but no definitive performance win. Branch `exp/p5-stream-coarse-first-e2` forks `exp/p5-0f-adaptive-stream-budget` at `f6fbfa844ebf283ad9ff83684e4018f0c3faf1bd`. This avoids inheriting the unaccepted dependency-aware E1 scheduler. `adaptive-skip` remains the control.

## Intended behavior

- New opt-in profile `adaptive-skip-coarse` starts from existing adaptive-skip's unchanged definitive 16-chunk terrain mesh pipeline and bounded 9x9 effect-source window.
- Once a pristine `load` region enters the visible 3x3, a single low-priority worker approximates the versioned seed-driven base surface using a regular 8x6 height grid (96 triangles). At most one preview CPU job and one preview GPU upload per frame are allowed. The main thread owns ArrayMesh and MeshInstance3D creation.
- Preview nodes live only under `TerrainChunks`, not in `active_regions` or `chunk_nodes`. They have no collision, no placement, object publication, simulation scope, storage, water authority, or terrain editing eligibility. They remain visibly approximate and ignore caves and procedural-object SDF effects.
- Defensive exclusions: disabled whenever *any* brush edits exist in the global ledger; during full rebuild, edit transactions, cave cutaways, or for existing active/partial regions. This conservative E2 prototype therefore does **not** cover edited-world loading.
- Each preview is pinned to the stage token, seed, generator version, global brush revision, effect revision and visible focus radius. A mismatch, window exit, replacement stage, retry or stage failure removes it. The definitive 16-chunk commit creates the original canonical scene nodes first and then removes the provisional overlay; no preview can count as a definitive commit.
- A changed world authority always causes preview revocation, never preview promotion. The preview cannot be saved or used as source state.

## Measurements

- `terrain_region_coarse_visible`: queue-to-first-coarse timing, token, revisions, 96 triangle count, worker time and upload time.
- `terrain_region_coarse_replaced` / `terrain_region_coarse_discarded`: definitive replacement and revocation.
- Budget windows preserve the legacy F10 gap counters (definitive regions only) and add `f10_perceived_missing_regions_total`, `f10_coarse_covered_region_samples` and `f10_perceived_focus_missing_frames`. This prevents misreporting perceived preview coverage as faster definitive source/marching jobs.
- `scripts/perf/run-p5-stream-profile.ps1 -Profile adaptive-skip-coarse` produces comparable JSON metrics for coarse visual p50/p95, perceived coverage, definitive load p50/p95, frame spikes and main CPU overhead.

## Validation and acceptance gate

1. Pinned Godot 4.7.2 editor import, `terrain_demo.gd --check-only` (explicitly added after the E1.1 blank-screen failure), focused 96-triangle/seam/revision negative tests, and a real-scene headless smoke that requires a coarse-visible PERF_TRACE event.
2. Full inherited P5.0F and P4 suites on self-hosted Windows runner, exact candidate HEAD; CI green is *not* visual acceptance.
3. Owner GUI inspect base terrain, water shoreline, procedural-object transitions, F10 moves in both directions, stale stage supersession, edit prohibition and unload/reload; upload complete A/B evidence.
4. Compare `adaptive-skip` and `adaptive-skip-coarse` on the same seed, same startup and same route (ideally ABBA order) at 18m/s and 54m/s. Primary: p50/p95 first **visible** surface, moving perceived 3x3 missing regions/frame, frame >20ms and >33ms, CPU, correctness; separate definitive p50/p95.
5. Reject if seams/shoreline visibly degrade unacceptably, preview stale persists, revisions or interactions leak, F10 gaps do not improve or frame >20ms rises by >1 percentage point without accepted tradeoff.

This experiment cannot prove an authoritative coarse mesh. It is a visual placeholder for pristine terrain only. Do not merge into parent or main without independent source review and explicit owner verdict.
