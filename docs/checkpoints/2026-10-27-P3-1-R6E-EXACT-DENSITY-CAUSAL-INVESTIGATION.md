# P3.1 R6-E exact-density causal investigation — 2026-10-27

## Scope

Owner-authorized isolated diagnostic experiment for Issue #145. No production integration, save-schema change, merge, or Issue #108 work.

## Source and environment

- R5-E base: `7646dfdeb2e6cdfe51407f8f25957a61a75abe1b`; R4 ancestor: `051249642611a7fa9cd2006be450bad0e184e4ee`.
- Production reference remains `92b442d7f5b605c7bc9c48fac2aceea9d71813aa`.
- Branch: `bench/p3-1-r6e-causal`.
- Godot 4.7.2 binary SHA-256: `c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643`.

## Findings

R5-E's exact-density failures came from evaluating brush distance using the caller's raw world query after the canonical evaluator had mapped the query to region/local and reconstructed world coordinates. Float32 round trips changed coordinates by ULPs, creating different distances. The first changed operation was sequence 0 `CARVE`; all 16 failing operations were evaluated and none was pruned. Replaying with pruning disabled did not fix the issue. Base field values and frozen snapshot operation arrays matched.

The R6 test prototype now uses the reconstructed canonical world point for both brush delta and distance. The frozen 8,192-operation workload reproduces all 16 old failures and has zero corrected mismatches across 796 probes. A one-command sequence-0 regression also passes bitwise.

## Validation

- Focused R6-E diagnostic: PASS, 796 probes, 16 old failures reproduced, 0 corrected full/no-prune/prune mismatches.
- R5-E regression: PASS, 8,998 assertions, zero failures; exact LOD geometry and density checks remain equal.
- Full `scripts/validate.ps1`: exit 0, 21,464 assertions, zero failures, 523,027 ms. Three existing colinear-camera warnings; no script/parser/runtime errors.
- Full report and raw evidence: [`P3-1-R6E RESULTS`](../reports/P3-1-R6E/RESULTS.md).

## Disposition and holds

`P3_1_R6E_READY_FOR_INDEPENDENT_REVIEW`. This is experimental test-only correctness evidence. R5-E still has unresolved performance regressions and is not approved for production. No GUI, GPU, presented-frame, or collision result is claimed. Preserve all five F2-G1 holds.
