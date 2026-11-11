# 2026-11-11 — P5 E2 exact-head Windows technical qualification

**Event:** completed exact-head automated qualification and source/console evidence review.

- Repo: `publiomcko-cloud/procedural-sandbox-simulation`
- Experimental branch: `exp/p5-stream-coarse-first-e2`, [draft PR #284](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/284)
- Experimental base: `f6fbfa844ebf283ad9ff83684e4018f0c3faf1bd`
- Candidate HEAD: `266ee118a64ee07b0853b78d043ad9d6289ccbf2`; immediate parent `00970e470d761dce8ceb6d8bc6c5d522791480ef`
- Main verified at previous E2 checkpoint: `2dca19d125309f3b70c858df1acdf22324c31c17` (no merge, not claimed live forever)
- Exact-head [Windows Godot 4.7.2 run 43103571456](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/43103571456), **completed success**; job `130800989579`.
- Test steps in GitHub job logs: `E2 editor-import PASS`, `E2 terrain-main-parse PASS`, `E2 coarse-worker-revision-tests PASS` (marker `P5_STREAM_COARSE_PREVIEW_PASS:`), `E2 headless-runtime-smoke PASS` (required actual `terrain_region_coarse_visible` trace event), `SELF_HOSTED_P5_0F_QUALIFICATION_PASS`, `SELF_HOSTED_P5_STREAM_E2_QUALIFICATION_PASS`.

**Historical envelope caveat:** the inherited P4.0A qualification intentionally accepts one pre-existing procedural-object failure (`PROCEDURAL_OBJECT_FAIL: assertions=671 failures=1`, `camera-driven revisit republishes the original region`) alongside a strict count of nine effect fingerprint conflicts. This exact known result is also present in the successful pre-E2 reference run [43079607052](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/43079607052). It is not a new E2 regression and must not be presented as an all-tests-zero-fail clean slate. All other automated gates in the prescribed inherited envelope returned success.

**Qualification classification:** Windows self-hosted Godot 4.7.2 source import, parser and focused/real-scene automated PASS, within the **explicitly documented historical baseline failure envelope**. Owner GUI and reproducible equal-route A/B metrics are **not executed**, so there is no accepted visual-performance verdict or permission to merge. Source preview is intentionally approximate for pristine worlds only; edits, caves and non-base procedural object effects may cause differences or disable previews.

**Next authorized action:** owner fetches exact E2 branch to the existing workstation, visually verifies coarse surface appears before definitive 16-chunk publication and is replaced without stale artifacts, then runs matched `adaptive-skip` vs `adaptive-skip-coarse` F10/CTRL+F10 A/B sessions (18/54m/s). Compare `coarse_first_visual_p50_ms`, `f10_perceived_missing_regions_per_frame`, definitive `region_load_p50_ms`, frame >20/33ms, process CPU, seam, water and object visuals. Independent source review and owner verdict still required. **DO NOT MERGE**.

Documentation is a separate draft PR [#285](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/285). Previous E2 experimental checkpoint remains immutable.
