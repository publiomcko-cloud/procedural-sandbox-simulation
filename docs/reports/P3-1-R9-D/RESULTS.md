# P3.1 R9 Candidate D — bounded result

**Disposition: `R9_D_BLOCKED_WITH_EVIDENCE`**

Candidate D is an isolated revisioned float32 materialized-density volume with fixed marching-tetrahedra extraction. The zero-edit materialization, test-file write/reload, and extraction ran; the first mandatory zero-edit topology gate then failed. No edit/revision, seam, ray consistency, picking, or later frozen case ran.

## Provenance

- Common R9 parent at execution: `a60d38df4f96b9007162e8fd917b3d14f29dcb0f`.
- Candidate source SHA-256: `49f5575983530111301d55930d650927af1cd5cb32fa72d3e6e49dd25598b6cb`.
- Shared helper SHA-256: `a1ca1b958a15985111de71b3750090f8d226c1274e276802bd8236b66b10c671`.
- Frozen manifest SHA-256: `2b44cb52ef091c2527fa2f8b06859752cc7cfaa14bcafe94d4a4c55b0cdd908f`.
- Godot `4.7.2.stable.official.ed1daf0bf`; executable SHA-256 `c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643`.
- Isolated profile and temp roots: `C:\r9d\evidence\profile` and `C:\r9d\evidence\temp`.

The candidate was untracked at the time of its single scenario execution on parent `a60d38d…`; physical source SHA above pins those exact bytes. Import and `--check-only` exited 0. Candidate process exited 1; PID was not captured.

## Zero-edit volume and mesh

- 2,457 float32 nodes, 9,828-byte data payload, 9,935-byte serialized file.
- Materialization: 24,679 µs; MT extraction from the reloaded volume: 39,027 µs. These are one-run headless CPU observations, not a p50/p95 or rendered-performance result.
- Volume SHA-256: `38a5b7544843a719d48ae2a1652bd6d35b9ed0b6ee1236405169074985bd0acb`.
- Mesh SHA-256: `15bef17ae15d32bb77979d54293373d2f8130e5331ae1860a711f4c6d4c304b0`.
- 1,784 triangles; 0 cutoff drops; topology: 1,121 internal open edges, 152 ROI-boundary opens, 355 nonmanifold edges, 0 degenerate triangles, 0 winding inconsistencies.
- Eight assertions ran; two required topology assertions failed. The candidate stopped at this gate.

The serialized file is preserved at [`evidence/zero-volume.bin`](evidence/zero-volume.bin) and its digest is included in the inventory. The corruption assertion only flips a byte in an in-memory copy and confirms its digest differs; it does **not** exercise a corrupt-file reload rejection path. The disposable `user://` profile also retains the original 9,935-byte test file. This was isolated from user saves and is not claimed as durable production storage, crash recovery, or authoritative persistence.

The chosen extraction is MT over stored float32 samples, so volume materialization and extraction are not independently compared with another extractor here. No canonical continuous-surface displacement, root preservation, cave connectivity, seam, PhysicsServer, or GUI result was reached. The ledger remains the input used for materialization, but this prototype does not establish operational authority safety beyond the bounded zero-case experiment.

## Shared project validation

Godot 4.7.2 `scripts/validate.ps1` exited 0 with **21 suites / 21,464 assertions / zero failures** and `VALIDATION_PASS`. This is only common project regression evidence. The log records the unavailable Issue #118 reparse fixture and three non-fatal camera colinearity warnings.

Complete logs, binary volume, and SHA-256 inventory are in [`evidence/`](evidence/). No GUI, PhysicsServer, presented frame, GPU, product tolerance, storage schema, or production path was tested or changed.

## Conclusion

Candidate D is `R9_D_BLOCKED_WITH_EVIDENCE` because its first extracted zero-edit mesh fails exact topology by a wide margin. The volume timing/size are descriptive single-run observations only. This does not establish that materialized volumes are unsuitable; it shows this chosen MT extraction/prototype is not ready to pass the frozen geometry gate. No production adoption, schema change, merge, or Issue #108 work occurred.
