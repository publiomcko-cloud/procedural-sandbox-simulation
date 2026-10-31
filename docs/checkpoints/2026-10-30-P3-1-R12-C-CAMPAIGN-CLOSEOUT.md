# P3.1 R12-C Campaign Closeout

Date: 2026-10-30
Branch: `exp/p3-1-r12-c-topology-geometry-realization`
Measured C6 source: `4535f4c965db67adab7c93e448492c54be916c92`
Measured-source parent: `289feddccc5a71bd8f9d1f5ff66051d8d4140657`
Measured-source tree: `1c8af8c4050a7b89976331fa1ad20c666d67e3a8`

## Outcome

`P3_1_R12_C_ATTEMPTS_EXHAUSTED_WITH_EVIDENCE`

The finite preregistered campaign has no eligible C slot remaining. Stage 0 reproduced the exact frozen authority graph. C1 was not applicable because the target component has no eligible interior degree-2 roots; it remains unconsumed. C2, C3, C4, C5 and C6 each completed a valid frozen-target geometry attempt and were consumed as `FAILED_TARGET`. No C7 was authorized or created. This does not establish global or mathematical impossibility.

C6 improved the local geometry topology accounting: all 870 required arc obligations round-tripped, with zero internal open edges, missing obligations, nonmanifold edges or winding inconsistencies. However, three triangles remained at/below the frozen `cross_squared > 1e-12` cutoff. Since the equal-LOD gate failed, mixed-LOD, determinism repeat, full E2E and full `scripts/validate.ps1` were correctly not run. No production integration or geometry-contract acceptance follows.

## Exact inputs and source attribution

The execution used Godot `4.7.2.stable.official.ed1daf0bf`, binary SHA-256 `c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643`. Frozen input identities are in [`source-identities.json`](../reports/P3-1-R12-C-CAMPAIGN/source-identities.json), including Candidate D SHA `334db9e3e9dfe3aca4a590845ba6b792629d204c0f1d6a3fc8a3898e7cbb020a`, manifest `1610c535f98a11e26ca1890c0d99addf4316fbcaa7ec9cdb7dfaa71cf5bb3972`, topology fixture `33e04446d25ec8dc21f6794b9509296e7ebcd575c2a8713edefd152f58e1cd0d`, and unchanged cutoff.

C6 source and its parent/tree are listed above. C2–C5 each use a separately pinned source commit, direct parent, tree, Git blob identities and physical SHA-256 for the campaign and realizer. C6's helper and runner identities are also recorded. Documentation and evidence packaging commits made after C6 do not change the measured-source attribution.

## Geometry and gate summary

| Hypothesis | Attempt | Key outcome | Gates |
|---|---|---|---|
| C1 | none | No eligible interior degree-2 transit roots | `NOT_APPLICABLE`, unconsumed |
| C2 | C2GEO006 | 8 cutoff rejects; 19 missing arc obligations; 13 internal opens | Controls 4/6 (negative ROI wiring/runtime errors); ROI rays 0/25; volume PASS |
| C3 | C3GEO001 | 45 cutoff rejects; 33 missing obligations; 20 internal opens; 502 supports | Controls 4/6 (two failed realizer controls with cause UNKNOWN); ROI rays 0/25; volume PASS |
| C4 | C4GEO001 | 18 exact-coplanar proposals all rejected; 8 cutoff/degenerate faces remain | Topology round-trip; controls 6/6; ROI 0/25; volume PASS |
| C5 | C5GEO001 | 4 flips; 4 cutoff/degenerate faces remain; maximum diagonal-midpoint displacement 0.131427302956581 | Topology; controls 6/6; ROI 0/25; volume PASS |
| C6 | C6GEO001 | 5 flips; 3 cutoff/degenerate faces remain; minimum cross-squared 2.77538984903934e-15; maximum diagonal-midpoint displacement 0.125083565711975 | Topology; controls 6/6; ROI 0/25; volume PASS |

The midpoint displacement values are local diagnostics, not a canonical surface-distance metric. No product tolerance is inferred. C2 had one captured Godot `SCRIPT ERROR` in negative-region controls despite process exit 0; the controls are recorded as 4/6, and the later C3+ runner classifies script errors. The full per-attempt metrics, failures, source hashes and UNSCORED timing observations are in [`RESULTS.md`](../reports/P3-1-R12-C-CAMPAIGN/RESULTS.md).

The machine-readable required per-attempt fields, including control cases, process identities, exit status, log hashes, rejection details, gate dispositions and next-hypothesis rationale, are in [`attempt-matrix.json`](../reports/P3-1-R12-C-CAMPAIGN/attempt-matrix.json).

## Preserved raw evidence

The immutable campaign archive contains 311 raw indexed files. Final repository copies:

- `docs/reports/P3-1-R12-C-CAMPAIGN/evidence/r12c_raw_campaign_evidence.zip` — SHA-256 `6550788363d1e0ea23df7ed2f560dbf0558fb6c45d769dc642661516c39b4dcb`, 1,342,535 bytes.
- `docs/reports/P3-1-R12-C-CAMPAIGN/evidence/evidence-sha256-index.txt` — SHA-256 `a876444ef103cd7288894fb35066d1f501a61eb5dc45beaead14d94e6145e2a9`.
- The archive includes the index and its index sidecar. Independent verification matched all 311 indexed raw entries to their archived bytes. The archive sidecar and index sidecar are separately preserved; their physical hashes are listed in `source-identities.json`.

The external execution evidence root was `C:\Users\PUBLI\AppData\Local\Temp\p3_1_r12c_20261030_0a53ac9c6d5245f4a4faffb14089c8be`. No profile/cache data was copied into the archive. Attempts, including preflight failures and recoveries, were retained; no started target attempt was repeated.

## Scope and residual limits

- Experimental GDScript only; no production algorithms, scenes, schemas or saves changed.
- No mixed-LOD, deterministic-repeat, full-E2E, full validation, GPU, presented-frame, or visual-owner acceptance evidence.
- Working-set monitor values near 6.1–6.4 MiB appeared implausibly low and are not relied upon as a memory bound; measured free-commit observations are diagnostic only.
- The exact-root graph authority can be realized with clean edge incidence after bounded flips, but the remaining frozen cutoff defects prevent equal-LOD qualification. Surface error and approved geometry tolerances remain unresolved.
- PR #207–#209, user saves, unrelated worktrees and all five F2-G1 holds remain unchanged.

## Final status and next step

The campaign is exhausted under its preregistered C1–C6 budget. Any further geometry work requires a separately authorized design/experiment scope and must not be described as C7. This checkpoint and report close only the R12-C experimental evidence campaign; they do not authorize production meshing, Issue #108, a geometry contract, merge or release.
