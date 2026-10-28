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
