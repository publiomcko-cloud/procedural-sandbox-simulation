# P3.1 R8.2 evidence package

This is a bounded test-only provenance investigation for Issue #161. The measured production source is the exact R8.1 candidate `d81f29237d47361139b02849a8215c30424be873`; the report/evidence branch is separate and based on R8.1. Nothing here adopts geometry, changes production, or approves a release.

## Contents

- [Results and causal analysis](RESULTS.md) — exact input identities, source-to-triangle traces, interface reconstruction, ray/mesh comparison, attempt classification and validation limits.
- [Source SHA-256 inventory](SOURCE_SHA256SUMS.txt) — both R8.2 diagnostic scripts, pinned production/reference scripts, validation script and Godot executable.
- [Evidence SHA-256 inventory](evidence/SHA256SUMS.txt) — all 140 published diagnostic outputs, process records and raw logs. It excludes itself and generated `godot-profile/**` caches/user-data; those profiles remain preserved locally but are omitted from the PR.
- [Immutable checkpoint](../../checkpoints/2026-10-28-P3-1-R8.2-EXACT-GEOMETRY-PROVENANCE.md).

The source inventory contains twelve entries. The seven production/reference source hashes match the R8.2 preflight record. The two experimental GDScripts were executed in the CRLF byte form used by this Windows run; narrow `.gitattributes` rules preserve that physical form on checkout. The physical inventory hashes at preparation time are:

- `SOURCE_SHA256SUMS.txt`: `ba4b2b488a163057019ec6ec8ede673b9d95ed006bf6caf1fa544043991220ab`.
- `evidence/SHA256SUMS.txt`: `cfa3a1d2ba177c8087a58f83cff55bbac79c1dd6793099ecd77052e0148e994c`.
- 140 published evidence files, 5,240,278 bytes, not counting the evidence inventory itself.

To verify after checkout, from the repository root:

```powershell
Get-Content docs/reports/P3-1-R8.2/SOURCE_SHA256SUMS.txt
Get-Content docs/reports/P3-1-R8.2/evidence/SHA256SUMS.txt
```

For each entry, recompute SHA-256 of the named physical file. Paths in the source list are repository-relative (the Godot executable path is absolute); evidence paths are relative to the `evidence` directory. Do not infer successful outcomes from the presence of a raw file: the report classifies each attempt and the original failed records remain intentionally preserved.

## Disposition boundary

`P3_1_R8_2_READY_FOR_INDEPENDENT_REVIEW` means the bounded provenance investigation and requested full validation are complete. The triangle gradient disagreement, missing X+ interface segments, and X− pointwise mesh displacement remain engineering findings. No GUI, renderer, GPU, PhysicsServer, product geometry-tolerance or owner-acceptance result is claimed. All five F2-G1 holds remain unchanged.
