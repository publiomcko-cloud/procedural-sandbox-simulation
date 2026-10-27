# P3.1 R5-E — Exact Local Projection Results

## Identity and disposition

- Production source baseline: `92b442d7f5b605c7bc9c48fac2aceea9d71813aa`.
- Experimental parent (R4): `051249642611a7fa9cd2006be450bad0e184e4ee`.
- R4 source measured: `83c7c091bcec0d10534d8638225d3d24d94b6334`.
- Branch: `bench/p3-1-r5e-exact-cache`.
- This result is experimental only. No production source, schema, save or runtime path is changed.
- Disposition: **BLOCKED_WITH_EVIDENCE**. The candidate is slower in the measured path and the final expanded exact-density oracle reports 16 mismatches.

## Candidate and exactness evidence

The prototype keeps the full ordered candidate list and attempts to skip only the distance evaluation where a coordinate axis exceeds the current min/max cutoff by a 0.1% guard. It does not radius-filter or reorder commands. The final test used the immutable R4 concentrated 8,192-command fixture (SHA-256 `0b30e1ce2605b3bab504f3f5648c7e63a84c9a22f905721b56defcfe0489f611`). The expanded run reported 8,998 assertions and 16 failures at probe assertions 8965–8971 and 8974–8983. These failures include selected command-center probes and adjacent threshold probes. The candidate is therefore not exact under the tested Godot runtime. No tolerance was introduced. The failure log does not contain the differing float pairs, so the precise arithmetic mismatch remains unresolved; the safe outcome is to reject this optimization.

The run also reports matching LOD1 sampled densities, positions, normals and topology for the mesh callback path. That narrower mesh result does not cancel the independent density-oracle failures.

## Performance evidence

One final headless process, 796 query probes, 8,192 retained candidates:

| Metric | Canonical replay | R5-E candidate |
|---|---:|---:|
| Query p50 | 0.928 ms | 4.073 ms |
| Query p95 | 2.376 ms | 9.881 ms |
| Query p99 | 3.243 ms | 14.247 ms |
| Query maximum | 3.818 ms | 16.125 ms |
| LOD0 CPU build | 2.266 s | 4.286 s |
| LOD1 CPU build | 6.832 s | 24.792 s |

There were 5,425,066 axis skips and 1,095,766 exact-distance evaluations. Despite the arithmetic skips, the added cutoff checks did not improve the measured query or mesh path. These are single-process headless CPU measurements, not presented-frame or GPU measurements. R4 comparison uses its separate five-process campaign and must not be pooled with this one-process R5 result.

## Validation

- Godot: `4.7.2.stable.official.ed1daf0bf`.
- R5-E focused prototype: exit 1, 8,998 assertions, 16 exact-density failures. Raw log: `evidence/final-20261027-095615/test.log`.
- The first run in that directory is preserved: import passed, check-only failed because the newly added cave probe omitted an explicit `Field` preload. This was corrected in the test source only; the later focused run then reached the density oracle and exposed the 16 substantive mismatches.
- Full `scripts/validate.ps1`: exit 0, all 21,464 project assertions passed across L0-L2. It emitted three existing colinear-camera `look_at` warnings and no script/parser/runtime errors. The R5-E experimental test is not part of that validator and remains failed as described above. The persistence regression also reported that the junction fixture was unavailable (`DirAccess.create_link returned Failed`); this is a fixture limitation, not evidence that reparse rejection was exercised.
- SHA-256 inventory: `SHA256SUMS.txt` covers the R5-E source, UID files, preregistration, reports and retained evidence files; the inventory does not include its own hash.

## Recommendation and boundary

Do not use this axis-cutoff evaluator as an exact optimization. The 0.1% guard did not preserve all tested outputs and did not meet the preregistered speed screen. Keep canonical ordered replay as the oracle. A future experiment would need a conservative proof that matches the engine's floating-point evaluation, diagnostic mismatch values, and a measured benefit before it can be considered further. No production integration or geometry-contract adoption follows from this report.
