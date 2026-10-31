# P3.1 R12-CXR R3 Per-Cavity Pre-Target Freeze

Date: 2026-10-31

## Status and authorization boundary

R3 geometry attempt 01 is consumed and retained as `R12_CXR_PARTIAL_WITH_EVIDENCE`. The corrected per-cavity implementation is frozen for exactly one new attempt, `R3_TARGET_20261031_02`, on `R9.2.SEAM.XPLUS_EQUAL.v1`. The target has not started at this checkpoint. This remains test-only geometry research: no production adoption, save/schema change, Issue #108/#154 work, merge, or release is authorized. Preserve `CURRENT_PROTECTED_STATE_UNKNOWN`, `V3_NOT_ATTESTED`, `ACL_REVIEW_REQUIRED`, `G1_BLOCKED_ENVIRONMENT`, and `F2_G1_RELEASE_HOLD`.

## Repository and measured source

- Origin: `https://github.com/publiomcko-cloud/procedural-sandbox-simulation.git`.
- Continuation branch: `exp/p3-1-r12-cxr-per-cavity-continuation`.
- Parent evidence PR: #213, open, draft, unmerged; this continuation is based on its head `121f499cf6c03daba0f24f907fd7a6dbeed59659`.
- Exact code/test source: `fdab3b8f16b615077aa44a7901b9555aebd3d80d`, parent `121f499cf6c03daba0f24f907fd7a6dbeed59659`, tree `42877cc35bccb72ea569e1c5758ca52dea3282ff`.
- The source change is limited to the R12-CXR experimental realizer and its contract tests. R1 and R2 search behavior is preserved; deterministic cavity ordering is applied only to R3.
- The original R3 attempt 01 and all of its raw evidence remain unchanged at [`r3_target_attempt_01`](../reports/P3-1-R12-CXR-R2-R3/evidence/r3_target_attempt_01/). The new attempt will not reuse its attempt ID or evidence path.

## Corrected hypothesis and frozen cavity partition

The R3 procedure requires field-constrained support vertices to be tested separately for the two original overlapping-defect groups, not for a synthetic joint cavity. Residual rows are validated for dictionary shape, nonempty unique IDs, then the original overlap partition is retained. R3 canonicalizes only the inner IDs and outer group order so discovery order cannot affect execution. The frozen partition is:

1. `e89d7e6444ead8c6` — the two connected residual rows from the original first cavity.
2. `aefae75e246e6d28` — the single residual row from the original second cavity.

Each cavity independently searches its connected L0-L3 dual-graph patch, derives the oriented boundary from surviving C6 edge incidence, and generates bounded support candidates from the frozen field on the original residual faces. Support vertices remain geometric realization only; the 369 topology roots, 870 arcs, 502 source faces, source ownership, topology round-trip, Candidate D, frozen volume, controls, ROI oracle, and strict `cross_squared > 1e-12` cutoff remain authoritative. If selected cavity patches overlap, this run must report an incomplete alternative-search requirement rather than claim exhaustion or silently merge cavities.

## Frozen limits

The limits are taken from the measured R3 realizer at the code source above and are unchanged for this continuation:

- Maximum cavities: 3; this fixture contains exactly 2 original groups.
- Dual-graph radii: L0-L3 per cavity; at most 64 source triangles per patch.
- Candidate-generation attempts: 8,192 per cavity; support candidates: 256 per cavity; selected supports: at most 4 per cavity; support distance at most 0.5 world units.
- Candidate triangles: 65,536 per cavity and 131,072 total.
- Search states: 32,768 per cavity and 65,536 total.
- Retained solutions: at most 32 per cavity.
- Search time: 10 seconds per cavity and 20 seconds total; complete realization time: 30 seconds.
- Barycentric and frozen-field residual epsilon: `1e-7`; degeneracy cutoff remains strict `cross_squared > 1e-12`.

Any reached cap, invalid provenance, missing metric, invalid cavity boundary, unrun level, or incomplete search is `PARTIAL`. A finite local no-solution claim requires each valid finite cavity domain to be completely and exhaustively searched. Invalid boundary construction is not triangulation exhaustion. Missing measurements must remain `UNKNOWN_NOT_CAPTURED` or `NOT_RUN`, never be reported as zero.

## Exact pre-target validation

Godot is `4.7.2.stable.official.ed1daf0bf`; executable SHA-256 is `c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643`.

- Fresh-profile editor import on the measured source passed, exit 0, no stderr or parser/runtime error.
- The bounded R12-CXR contract suite passed 141 assertions, zero failures, exit 0. This is source/contract evidence, not geometry acceptance.
- Campaign `check-only` passed on the measured source with `R3_CHECK_20261031_05`, exit 0. It verified the exact campaign/realizer hashes, C6 campaign and realizer pins, stage-zero topology fixture, residual fixture, manifest, Candidate D and authority source identities, and the geometry preflight.
- A preceding `check-only` invocation, `R3_CHECK_20261031_04`, exited 2 with `cx_preflight_environment_invalid` because required `R12CXR_*` environment variables were not supplied. It emitted no target marker and did not start geometry. The complete environment was then supplied and the corrected check-only passed; both attempts are retained under [`r3_pretarget_02`](../reports/P3-1-R12-CXR-R2-R3/evidence/r3_pretarget_02/).
- `git diff --check` passed before the source commit. No scenario was launched during these gates.

Raw gate output, stderr, process records and hashes are retained in the evidence directory linked above. Pinned frozen-input identities include: campaign `1b3a73845ef5bafec6d16fe2a7928ee3599c5e70ba5310070cb845af3687145b`; corrected R3 realizer `927cf631c430f817ba0b460840ba54d31b4df2dfdda79c3bee6b7ceab93694e1`; contract tests `759cbaaa88e9e63f1f98e408279cb136b372e6f1a7cda35c49cb3dd0b5af8712`; C6 campaign `9a695705c47ad6473b773bbfaeaf35d88306cee6804113a0b1a71c6faca2f348`; C6 realizer `31947e1944a017442ad14cc4f098e67db800d4f5e196d07e047b93dc0fe9d2ac`; Stage-0 fixture `33e04446d25ec8dc21f6794b9509296e7ebcd575c2a8713edefd152f58e1cd0d`; residual fixture `ad000594b25a82459da824b7488b2a553392a86e117eb64535b182463847ff23`; topology source `4ecbb2496fb34f1cf3c05a60192f76bdce7a52ec3148d02ba041510b804a8c95`; frozen volume `ecf86bce57e82cd0949d4576e7b7ebe4d1ef8d0633ac7f6d540fd56df6573be2`; payload `2ff3685296a8d035967a8c723bc42cb8320a9500dc699538a731490d089203d0`; manifest `1610c535f98a11e26ca1890c0d99addf4316fbcaa7ec9cdb7dfaa71cf5bb3972`.

## One-shot target and downstream gates

The only target invocation frozen here is `R9.2.SEAM.XPLUS_EQUAL.v1`, phase `r3`, attempt `R3_TARGET_20261031_02`, with source identity `fdab3b8f16b615077aa44a7901b9555aebd3d80d`. It must use a fresh, unique evidence root, exclusive reservation, isolated Godot user profile, and a bounded process timeout. Once process creation may have occurred or the target-start marker appears, do not rerun this attempt. Classify timeout, missing data, any cap, invalid cavity, or incomplete search as partial.

Only if equal-LOD fully passes exact topology round-trip, all topology obligations, zero internal opens/nonmanifold/winding/degenerate/cutoff rejects, strict minimum cross-product cutoff, and frozen volume may the campaign advance automatically through the already frozen sequence: controls 6/6, ROI rays 0/25, volume, mixed LOD conforming, deterministic repeat, full E2E, and `scripts/validate.ps1`. Stop at the first failed gate; preserve all evidence and do not weaken thresholds. Timing remains unscored. No presented FPS, production geometry contract, or protected-state claim is made.
