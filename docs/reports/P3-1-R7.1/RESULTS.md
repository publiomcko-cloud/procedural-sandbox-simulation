# P3.1 R7.1 — Mesh Topology and Collider Causal Results

## Disposition

P3_1_R7_1_BLOCKED_WITH_EVIDENCE

The frozen zero-edit topology gate still fails. This report identifies the causal mechanism but does not apply a production mesh correction, relax the topology oracle, or declare the R7 experiment acceptable. The collider query discrepancy was independently attributed to the test proxy's one-sided concave-shape configuration; the two-sided configuration matches the independent geometric ray oracle. Since topology Gate 1 failed, neither edited cave scenario was started.

## Source and repository identity

- Repository origin: https://github.com/publiomcko-cloud/procedural-sandbox-simulation.git
- Production reference: 92b442d7f5b605c7bc9c48fac2aceea9d71813aa
- Frozen R7 source/base: 078408877bd0b3169a6fff376fc82a26bd00d930
- R7.1 diagnostic source commit: 456adc16b2ecbef4e6342e3f6f8731455eb4a917
- Direct parent: 078408877bd0b3169a6fff376fc82a26bd00d930
- Branch/worktree: bench/p3-1-r7-1-topology-collider at C:\r71
- Source-only commit paths: game/tests/prototypes/p3_1_r7_1_causal_diagnostic.gd; game/tests/prototypes/p3_1_r7_conforming_adaptive_diagnostic.gd; game/tests/prototypes/p3_1_r7_conforming_mesh_fixture.gd
- PR #149 was verified open, draft and unmerged at R7 head 078408877bd0b3169a6fff376fc82a26bd00d930. This R7.1 evidence is published separately in draft PR #151, base bench/p3-1-r7-conforming-adaptive.
- Live main observed during this run: 5997a76d345f45bf86edfe83f690336391e8be27.
- The R7.1 diagnostic and evidence changes do not modify production scripts, save schemas, geometry contracts or gameplay. Issue #108 was not started.

The R7.1 source commit changes only the three test/prototype paths above relative to frozen R7. The subsequent report/checkpoint commit adds documentation and raw evidence only.

## Frozen input and reproduction

The experiment used the original zero-edit scenario P3.1.R7.ZERO_EDIT.v1, seed 131102026, generator version and canonical data from the frozen manifest, ledger revision 0, zero commands, and the canonical 1.75-world-unit vertical cave opening. The frozen manifest SHA-256 is 24f70884cb0ec4c2ea90daad77dd12987d8023deabd144c24ac4235635f0451b. The expected and observed frozen mesh-output SHA-256 for all three R7 approaches is 8007174a6286c6e20fe9cda44ded992bd9a3b3d27132c4b844ea518d95f48f68.

A fresh zero-edit run on the R7.1 source produced 7,118 triangles for each A/B/C method and the same mesh digest. Each result has 14 internal open edges, 354 expected external patch-boundary open edges, 368 total open edges, zero triangles below the frozen degeneracy classification, and zero edges with incidence greater than two. The 14 internal edges occur in coarse cells 1101, 1149, 1150 and 1199. The exact edge coordinates, quantized welded IDs, expected/observed incidences and owner cells are retained in the raw R7_RESULT JSON record.

The focused trace covers those four cells and their direct six-neighbor union: 23 coarse cells and 621 original binary32 samples. It records each sample's little-endian IEEE-754 bits, sign/near-zero class, tetrahedron corner order and ownership, crossing edge, interpolation weight, coordinates, winding and emitted triangles. There were no exact-zero samples, no samples with absolute density at most 1e-5, and no Godot is_zero_approx denominator events among the traced crossings. This evidence makes exact-zero classification and the zero-denominator fallback an unsupported explanation for these particular opens. It does not prove every arithmetic path on every platform bitwise identical.

## Topology causal finding

The unchanged production mesher is game/scripts/terrain/marching_tetrahedra.gd. At line 340, _add_triangle drops a triangle whenever the squared magnitude of its cross product is at most 1e-12. The test-only causal variant rejects only exactly zero cross products and retains eight additional nonzero microtriangles. Their cross-length-squared values range from 4.77887857324583e-14 to 7.63213656770206e-13, so each is below the production cutoff.

Those eight triangles are distributed across the four implicated cells: three in 1101, two in 1149, one in 1150 and two in 1199. In the supplemental incidence count that includes these triangles, internal open-edge count becomes zero, external open edges remain 354, and edge incidence above two remains zero. This establishes that dropping the microtriangles causes the 14 internal boundary incidences in the frozen output.

However, the frozen topology oracle also classifies all eight as degenerate because it uses the same 1e-12 cross-length-squared cutoff. Retaining them yields 7,126 triangles, zero internal opens only when the supplementary incidence analysis includes below-cutoff triangles, and eight degenerate triangles under the frozen acceptance classification. This is not an acceptable pass: it trades one violated invariant for another.

Separate diagnostic variants found:
- Exact denominator interpolation produced the same candidate output as the mirrored-production arithmetic path; no topology correction.
- Rejecting only exact zero retained the eight microtriangles but fails the frozen degeneracy gate.
- Mirroring the X tetrahedron diagonal changed the mesh but retained 14 internal opens under the production drop rule.
- The production and test-only mirrored extraction differ at 50 vertex positions by at most 9.5367e-7 world units and at normals by at most 1.3503e-5. Therefore the test mirror is not presented as a bitwise replacement for engine/production arithmetic.
- The edge-incidence oracle separates the bounded patch boundary from internal edges and reports welded vertex IDs and coordinates. No evidence supports a false opening caused solely by edge quantization.

Conclusion: the reproduced defect is a mesh-extraction/topology failure caused by the current absolute triangle-area cutoff in this frozen fixture. The exact safe polygonizer correction is unresolved. Lowering the cutoff or accepting the eight triangles would weaken the frozen no-degenerate requirement, so neither was adopted. A future correction needs topology-aware removal/retriangulation or another demonstrated extraction change that preserves the frozen field/surface contract, with the same internal incidence and degeneracy checks.

## Collider causal finding

The physics test uses disposable ConcavePolygonShape3D proxies built from the same frozen triangle mesh and an independent two-sided Moller–Trumbore reference over the emitted triangles. Across the original 72 ray queries:
- The default one-sided proxy disagreed with the two-sided geometric reference on 33 queries; all 33 were cave-to-outside, while outside-to-cave had zero mismatches.
- With the shape's backface_collision enabled and query hit_back_faces enabled, the proxy matched the independent reference on all 72 queries.
- A separate 16-case single-triangle factorial probe varied winding, shape backface collision and query hit-back-faces. Setting only the query flag does not make a one-sided concave shape two-sided; winding changes which side is accepted. This isolates the reverse-ray mismatch to disposable collider/query configuration, not proof of a mesh winding correction.

The 36 sphere probes retain the frozen 0.05-unit sweep increment. With the default one-sided proxy, first overlap was at 0.95 units versus a canonical expected center distance near 0.82, giving absolute error p50 0.12999997 and max 0.13000026 world units. With backface collision enabled, first overlap was at 0.85, about 0.03 units from the expected value; discrete sweep-step bias remains. Independent continuous triangle/sphere measurements and all per-probe records are in the raw JSON. Therefore a two-sided setup corrects the ray query semantics but does not remove the discrete sweep error and does not correct the topology failure.

Godot's 4.7 ConcavePolygonShape3D documentation specifies that backface_collision defaults to false and is required for two-sided concave collisions; PhysicsRayQueryParameters3D.hit_back_faces takes effect with such a shape. These are fixture-configuration findings only and do not authorize a production collider change.

## Sequential gates and execution boundary

- Gate 1, zero-edit extracted topology: FAIL for A, B and C; 14 internal open edges each.
- Gate 2, independent collider ray parity: PASS for the explicitly two-sided test-only shape, 72/72; the default one-sided diagnostic retains 33 mismatches.
- Overall zero-edit preflight: FAIL because Gate 1 failed.
- Frozen edited CARVE case: NOT_RUN.
- Frozen ordered FILL/CARVE case: NOT_RUN.
- No broad performance campaign, GUI/GPU test, production collision-provider test, storage test, or geometry-contract adoption occurred.

## Validation evidence

Godot binary: C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe; version 4.7.2.stable.official.ed1daf0bf; SHA-256 C8F0A6BC45A19B33541501E57F6F7CD972AB18453743266339D495CBBE846643.

- Both focused scripts passed Godot --check-only with exit 0.
- R7.1 causal diagnostic: exit 0, 15 assertions, zero failures, 11.356 seconds.
- Exact-source zero-edit gate: exit 1, 9 assertions, three expected topology failures, 7.869 seconds. Stderr is empty.
- Full scripts/validate.ps1: exit 0, 21 suite markers, 21,464 assertions, zero failures, 525.800 seconds. It ran from a disposable archive of source commit 456adc16b2ecbef4e6342e3f6f8731455eb4a917. Only application/config/name was changed in that archive to isolate Godot user data; scripts and test source remained exact candidate bytes. Three existing non-fatal camera target/up colinearity warnings were recorded. No visual acceptance is claimed.
- P3.0D focused baseline recheck: the historical baseline 0867c0c04b857fae1c71b274b8eac44c6e7dba4f import and placement test exited 0; placement suite was 51/51. A prior full-validation record at that baseline reported five P3.0D placement failures. That historical full-suite failure was not reproduced by this targeted test, so disposition remains NOT_REPRODUCED / CAUSE_UNKNOWN; this does not establish that the historical failure is resolved.
- Raw stdout/stderr, command/exit/duration records, environment, original failed attempts and checksums are preserved under evidence/: 123 files totaling 52,283,151 bytes. SHA256SUMS.txt verifies all 123 artifacts except itself; the inventory file SHA-256 is 368A7852870C830C7A0C9E4431C6AE65E41A47800390695214543A9FA9146E07. SOURCE_SHA256SUMS.txt records relevant physical source hashes and Git blobs.

The complete validation assertion markers were: SMOKE 52; SDF 44; BRUSH 612; CHUNK 179; MULTI_REGION 7,637; PERF_BENCH 11; HISTORY 907; WORLD_V2_STORAGE 3,516; DECLARATIVE_MOD 66; PROCEDURAL_OBJECT 638; ENTITY_COMMAND 67; ENTITY_HISTORY 101; ENTITY_COMMAND_HARNESS 19; PLAYABLE_ENTITY_COMMAND 44; P3_0D_PLACEMENT 51; TERRAIN_PICK_HISTORY 713; LOD01_TRANSITION 6,474; TERRAIN_LOD_RUNTIME 53; TERRAIN_E2E_PERF 251; TERRAIN_CONCURRENCY 11; BOOTSTRAP_STRUCTURE 18.

## Integrity and preserved state

The evidence inventory includes the frozen manifest, source/engine identity records, parser checks, all retained R7.1 diagnostic attempts, the final focused output and full-validation logs. The measured production mesher file has physical SHA-256 23FBC6F94BA37D070D34924E85E9BBF1BDBBB26666ABA32345C0140DFC6DFFE3 and identical Git blob 116c38dd2c36df18d3f8d84e106e0f6168f347f8 in production reference 92b442d7f5b605c7bc9c48fac2aceea9d71813aa and R7.1 source. No production file was changed.

The existing R7 worktree remains at 078408877bd0b3169a6fff376fc82a26bd00d930. The designated development worktree remains on feat/p3-1-scalable-terrain-storage; its three pre-existing untracked benchmark .gd.uid files and stash entries 0 and 1 were preserved. R7's diagnostic check files and PR #149 are also preserved. No user saves or protected F2-G1 objects were accessed.

All five holds remain unchanged: CURRENT_PROTECTED_STATE_UNKNOWN, V3_NOT_ATTESTED, ACL_REVIEW_REQUIRED, G1_BLOCKED_ENVIRONMENT, F2_G1_RELEASE_HOLD.

## Minimum next engineering step

Keep this R7.1 evidence as blocked. A separately scoped test-only polygonizer investigation should determine whether a local zero-set-preserving triangulation can eliminate the subthreshold faces while keeping the frozen degeneracy oracle unchanged. It must first pass the exact zero-edit topology gate; only then may the frozen edited cases be considered. The collider result should remain classified as proxy configuration semantics, not a production collision verdict.

No merge, production adoption, geometry contract, save change, Issue #108 implementation, or F2-G1 operation is approved by this report.
