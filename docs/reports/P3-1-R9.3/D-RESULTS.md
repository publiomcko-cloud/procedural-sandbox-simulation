# R9.3-D — materialized-volume independent extractor findings

Candidate source commit: `6a42469e5c9feac351137c3255988d62b8712e6f`; parent: `e9511dd33716f8cd7f27a998199e6414c9703696`. Baseline evidence head: `ac9357766736751b40b6afab69e48538063b5c59`. Frozen R9.2 manifest SHA-256: `1610c535f98a11e26ca1890c0d99addf4316fbcaa7ec9cdb7dfaa71cf5bb3972`.

## Reference extractor

R9.3 adds a test-only angle-ordered tetrahedral extractor consuming the exact float32 array re-read from the disposable serialized volume. It uses canonical lattice-edge root identities, point de-duplication for exact-zero endpoints, a tetrahedron-local affine gradient to orient each polygon, and the same unchanged `1e-12` squared-cross-product rejection cutoff. The diagnostic reports both the original Candidate D output and reference output over the same materialized bytes. The independent extractor does not reuse Candidate D's polygon assembly. Its analytic harness verifies a plane, sphere and saddle, repeat hashes, finite vertices/normals, zero degeneracies, winding and internal topology. `Core.topology` is shared only as the topology measurement oracle; independence of the extractor is not proof of canonical continuous-SDF geometry.

Analytic results: plane 128 triangles, zero analytic residual, 0 internal openings, 0 nonmanifold; sphere 636 triangles, maximum sampled analytic residual 0.0534064 world units, 0 internal openings/nonmanifold; saddle 420 triangles, maximum residual 0.015625, 0 internal openings/nonmanifold. Mesh hashes repeated exactly. ROI-boundary openings are reported separately (32/0/48 respectively), not treated as interior defects.

Focused frozen comparisons (same reloaded volume):

| Case | Candidate D internal opens / nonmanifold | R9.3 reference internal opens / nonmanifold |
|---|---:|---:|
| zero | 214 / 67 | 0 / 0 |
| CARVE | 219 / 71 | 0 / 0 |
| FILL/CARVE | 272 / 86 | 0 / 0 |
| neighbor pair | 567 / 183 | 0 / 0 |
| X+ equal seam | 446 / 136 | 13 / 0 |
| X+ mixed LOD | 446 / 136 | 13 / 0 |
| X− displacement | 799 / 249 | 0 / 0 |
| triangle 3103 | 6 / 0 | 0 / 0 |

In all eight, candidate and reference triangle counts matched; vertex order/connectivity hashes differed as expected from alternate polygon assembly. The X+ interface retains 13 reference internal openings, so the reference does not cure seam conformity. The results isolate a major Candidate D extraction/topology defect from the storage volume, while leaving canonical surface fidelity and seam behavior unresolved.

## Validation and limitations

Godot `4.7.2.stable.official.ed1daf0bf`; pinned executable SHA-256 `c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643`. The R9.2 contract suite passed 160/160; analytic extractor tests passed 400/400; focused probe completed 8/8 scenarios. Full `scripts/validate.ps1` on the D source commit completed with exit 0, 21 suites, 21,464 assertions, zero failures. Full validation log SHA-256: `9a351da4d31dcc90d55ffffd362b0525f197de6382d1aa24f24a117350b1cde2`.

The initial reference parse attempt produced a GDScript indentation/parser error; it is retained in `candidate-d-reference-attempt-01`. The first probe rejected FILL/CARVE because cube-wide average orientation could cancel; the correction uses each tetrahedron's affine gradient and its passing result is retained in attempt 03. No actual R9.2 20-row E2E campaign, separate local-edit restart campaign, physics/collider run, extracted cave-connectivity oracle, GUI/GPU/FPS study, or production source change was performed in this continuation. Corruption behavior is exercised only if the frozen D harness corruption row runs; the focused probe did not constitute that test.

## Disposition

`PARTIAL_CORRECTION`: the independent comparison demonstrates the original D extraction defect on the same float32 storage output and supplies a verified analytic control. The candidate's own extracted meshes remain defective; the X+ reference seam still has openings. The volume/storage authority is not promoted and neither extractor is accepted for production.

## Final frozen E2E campaigns (2026-10-28)

The measured independent-extractor source commit is `6a42469e5c9feac351137c3255988d62b8712e6f` (parent `e9511dd33716f8cd7f27a998199e6414c9703696`); the campaign/evidence branch head, including subsequent documentation and source inventory commits, was `5741107cd077942326df87f6e6533ff339446d3f`. The campaign source identity pins this branch head, and the frozen input manifest SHA-256 is `1610c535f98a11e26ca1890c0d99addf4316fbcaa7ec9cdb7dfaa71cf5bb3972`.

Two independent Godot processes were captured and independently audited: `R9.3.D.1.6fdf5c84f98b4fa59561137da84e32fc` and `R9.3.D.2.14f25a8e031f4477b640fde3cd9f1b0d`. Each emitted 44 valid ordered JSONL records and completed all 21 D-scope cases, including the D-only corruption scenario. Both process exits were 0 with no stop reason; audit status was `PASS_EVIDENCE_STRUCTURE_AND_EXECUTION`. Sampled process-tree peaks were 106,414,080 and 106,520,576 bytes; elapsed time was 12,049.79 and 11,961.33 ms.

The E2E Candidate D extractor topology is not repaired: zero remains 214 internal opens/67 nonmanifold; CARVE 219/71; FILL-CARVE 272/86; neighbor pair 567/183; X+ equal/mixed 446/136; X− 799/249; triangle 3103 6/0. The separate R9.3 angle-ordered reference extractor, on the same reloaded float32 samples, had zero internal openings/nonmanifold for zero, CARVE, FILL-CARVE, neighbor, X− and triangle 3103; X+ equal/mixed still had 13 internal openings. Its separate algorithm and incomplete seam result mean it remains an experimental diagnostic, not canonical truth or an adopted extractor.

| Scenario | D1 p50 / nearest-rank p95 µs | D2 p50 / nearest-rank p95 µs | Candidate D topology |
|---|---:|---:|---:|
| zero | 44,243 / 48,431 | 39,037 / 41,555 | 214 internal opens / 67 nonmanifold |
| CARVE | 38,873 / 41,579 | 39,770 / 42,448 | 219 / 71 |
| FILL-CARVE | 46,088 / 51,614 | 46,346 / 51,561 | 272 / 86 |
| neighbor pair | 98,985 / 100,022 | 100,884 / 113,507 | 567 / 183 |
| X+ equal seam | 78,373 / 80,021 | 78,333 / 96,217 | 446 / 136 |
| local edit rebuild | 140,673 / 165,219 | 138,584 / 147,082 | 837 / 270 |

Each listed distribution contains five within-process build samples; nearest-rank p95 is not pooled. The real disposable disk-corruption probe ran in both campaigns: corrupted bytes were read back from disk and rejected with `volume_disk_hash_mismatch`; expected digest `4286469c51ea734432397f43530eaac1e266f83416f4e2647de0af878421ac6b`, corrupted digest `e09fa0c3c2f5f20ade45c950e361f956af07083d06ad44c2202de65a6c6998c7`. This establishes the bounded fixture's checksum-rejection path, not production recovery safety.

Godot `4.7.2.stable.official.ed1daf0bf`, executable SHA-256 `c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643`. Full `scripts/validate.ps1` on measured source `6a42469e5c9feac351137c3255988d62b8712e6f` exited 0: 21 suites, 21,464 assertions, zero failures, 513.02 s; three nonfatal existing camera-vector warnings and no parser/script errors. Raw E2E and validation evidence with hashes is committed under `evidence/`.

**Disposition remains `PARTIAL_CORRECTION`.** The corruption check is now confirmed; the Candidate D extraction defects are unchanged, and the reference extractor still has an X+ seam defect. Volume authority, exact continuous-SDF equivalence, cave topology, production streaming, GUI/GPU/PhysicsServer behavior and production acceptance remain unproven.
