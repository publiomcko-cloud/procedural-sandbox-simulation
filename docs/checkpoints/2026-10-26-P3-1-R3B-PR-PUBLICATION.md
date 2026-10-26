# P3.1 R3B — Evidence PR publication

**Checkpoint ID/date:** `CHK-2026-10-26-P3-1-R3B-PR-PUBLICATION`; 2026-10-26

**Event type:** isolated experiment evidence publication

## Publication identity

- Repository: `publiomcko-cloud/procedural-sandbox-simulation`; origin `https://github.com/publiomcko-cloud/procedural-sandbox-simulation.git`.
- Evidence PR: [#138](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/138), open, draft, unmerged at publication check.
- Base: `feat/p3-1-scalable-terrain-storage` at `92b442d7f5b605c7bc9c48fac2aceea9d71813aa`.
- Branch: `bench/p3-1-r3b-exact-dense-local-cache`.
- Initial published commit: `1956d9bfb1807bba9c13e164144e667e546164ef`, parent `9ec3818e47b4f42027995b12e3d7a40a72cbf7ca`.
- The benchmark source, final 40-process campaign and complete Godot validation are pinned to `9ec3818e47b4f42027995b12e3d7a40a72cbf7ca`; the evidence/report commit adds documentation and raw artifacts only.

## Disposition and limits

The PR publishes the isolated R3B source, frozen Issue #131 inputs, reproducible harness, 40-process raw campaign, checksums, report and validation logs. Exact density and LOD0/LOD1 mesh comparison passed for all final campaign runs, and full Godot validation passed 21 groups / 21,464 assertions with zero failures.

The experiment remains `P3_1_R3B_BLOCKED_WITH_EVIDENCE`: distributed 8,192 LOD1 met the non-regression limit in 3/5 runs (4/5 required), and distributed 2,048/8,192 first cold LOD1 cache overhead was 12.8%/12.9% (10% maximum). These gates are frozen and were not adjusted. PR publication is not independent approval, production integration, schema authorization, Issue #108 authorization or merge approval.

The final PR HEAD after this publication receipt commit is the branch tip and is verified separately in the handoff. PRs #129/#134/#136/#137 remain outside this branch and unmodified. The existing development workspace, stash entries, generated `.gd.uid` files and all five F2-G1 holds remain preserved.

## Next gate

Independent review of exact PR #138 source/evidence and a separate owner disposition of the two failed performance gates. No production work or merge is authorized by this checkpoint.
