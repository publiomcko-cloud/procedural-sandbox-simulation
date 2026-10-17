# Checkpoint — P1.0B owner GUI feedback: streaming usable, lighting correction ineffective

**ID:** `CHK-2026-10-17-P1-0B-OWNER-GUI-LIGHTING-CORRECTION`  
**Event:** consequential owner GUI observation and scoped lighting correction request, 2026-10-17.  
**Publication:** `RECORDED_IN_DRAFT_PR / NOT_INTEGRATED` in docs-only [PR #87](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/87). Independent of ongoing Codex feature branch.

## Exact owner feedback and interpretation

After opening the Godot P1.0B scene, owner reported loading progressively, arrow-driven terrain movement unloading distant chunks and slowly populating new ones. No streaming crack/corruption reported in that message. Owner reported that the added camera-aligned light **produced no noticeable improvement** and asked whether constant light over all surfaces might be responsible.

**Gate classification:** `OWNER_GUI_STREAMING_BEHAVIOR_OBSERVED_OK / LIGHTING_VISUAL_REQUIREMENT_NOT_MET`. **NOT** full owner GUI PASS and **NOT** merge authorization; controls, seam and state-retention acceptance have not been individually attested here.

## Verified source identity and diagnosis

- Repo: [publiomcko-cloud/procedural-sandbox-simulation](https://github.com/publiomcko-cloud/procedural-sandbox-simulation); live `main` verified at `7f87c1e9c0cc1e85dd5c5fb612ebf2cd40aeffb0` at event; P1.0B [draft PR #88](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/88) at exact `2e0ecd04aba3bbd1a8c2ba8f915f0c3402ff6a26`, direct parent `main`, unmerged.
- Previous [SHA-specific review](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/88#pullrequestreview-5559876793) returned `PASS_SOURCE_REVIEW_WITH_CAVEATS / OWNER_GUI_PENDING`, **not** runtime/pixel execution by reviewer.
- GUI feedback was [recorded in PR #88](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/88#issuecomment-6240529628) and is now a request for a bounded lighting adjustment on the same PR before GUI acceptance.
- Verified `game/scenes/terrain_demo.tscn`: `Environment.ambient_light_energy=1.5`, oblique `DirectionalLight3D.light_energy=1.3`, camera-child `SpotLight3D.light_energy=0.42`, `spot_range=72`, no spotlight shadows; initial orbit target offset length is approximately 58 world units. High ambient and weak distant headlight are a plausible explanation for insufficient depth modeling; **not** a quantitative optical measurement or pixel comparison.
- Streaming observation does not invalidate developer headless 7,943/7,943 Godot assertions; those assertions only prove script-level tested behavior. Initial fill ~9.96s headless and max 20.55ms slice are developer-reported performance bounds, not guaranteed GUI FPS.

## Next authorized correction, boundaries and evidence

1. On **the same PR #88**, tune existing ambient/key/fill balance conservatively: reduce excessive ambient contribution, use oblique directional light as primary depth cue, keep camera-following light subtle with effective range for 58-unit default camera distance. Evaluate shadow cost where feasible but do not silently expand unrelated rendering scope.
2. Capture **before/after images at the same seed, camera pose and cut C state**, including cave walls and slopes. Obtain renewed owner visual feedback on actual depth contrast. Headless configuration checks do not certify visual effectiveness.
3. Re-run Godot 4.7.2 `scripts/validate.ps1`, report exact candidate HEAD, parent and tests, retain streaming and safe-edit controls; independent source re-review required for any changed SHA.
4. Retain prior potential error-handling caveats (lost load-stage retry if focus unchanged, canonical brush edit vs partial mesh failure divergence) until separately addressed; neither was reported as a reproduced GUI defect.
5. **No merge** for PR #88 until new GUI acceptance and explicit owner authorization. Post-merge docs-only [PR #87](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/87) remains open draft with this new checkpoint; maintain docs/code branch independence and reconcile common documentation before future merges. P1.0C, persistence, networking, native add-ons and F2-G1 protected operations are out of scope.

Current remote status and process permissions cannot be reconstructed from this checkpoint alone; reverify live refs on resumption.
