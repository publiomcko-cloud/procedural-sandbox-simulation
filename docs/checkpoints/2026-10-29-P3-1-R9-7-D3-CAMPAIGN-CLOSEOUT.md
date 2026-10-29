# P3.1 R9.7 D3 Campaign Closeout

Date: 2026-10-29

Event: owner-authorized isolated geometry research completed; bounded hypothesis budget exhausted.
Evidence grade: local Godot 4.7.2 runtime execution captured by the implementation agent; independent source/evidence review pending.

## Identity and publication state

- Repository origin: `https://github.com/publiomcko-cloud/procedural-sandbox-simulation.git`
- Worktree/branch: `C:\r97-d3-20261029`, `exp/p3-1-r9-7-d3-interface-convergence`
- Campaign source HEAD at experiment closeout: `ca48ecdd6c1608118e9f9c6bbac7e2129f5c669a`; direct parent `faccf204a32c1887886e55867f8dcc84394ae215`.
- Remote main observed at `5997a76d345f45bf86edfe83f690336391e8be27`.
- Before publication the experiment branch did not exist on origin and no PR used this head. A draft evidence PR is pending push/creation; no merge or release is authorized.
- The initial D3.1 source is `7d058899abc1663ff7d4175b5a508532367cd5da`, parent `3d0e4c59c0e33e4c21e34bbd54d1771c3db83415`; this is the exact Candidate D baseline required by the attached procedure.

## Result

Terminal campaign status: `P3_1_R9_7_D3_ATTEMPTS_EXHAUSTED_WITH_EVIDENCE`. Five materially distinct geometry hypotheses ran: D3.1–D3.5. All five are `FAILED_TARGET`. The D3.3 branch-diagnostic and retained-mesh replays were instrumentation of the same geometry hypothesis, not new attempts. There was no resource-safety abort; all completed geometry processes exited 0 and reported zero harness assertion failures, which is not geometry acceptance.

| Attempt | Source | Hypothesis | Result and controlling geometry evidence |
|---|---|---|---|
| D3.1 | `7d058899abc1663ff7d4175b5a508532367cd5da` | Existing face contours/direct zipper | Equal LOD 22/22 contour segments match, but 13 internal opens remain away from the interface plane. Mixed LOD 10/22; 0 patch triangles; first candidate has cross-squared `5.31475523787568e-15`, below fixed `1e-12`. |
| D3.2 | `709215e338b079457550265887393c247a6f15e8` | Bounded monotone correspondence search | Equal LOD still 13 opens. Mixed LOD still 10/22, no shared endpoint roots; endpoint distances `0.003799915313` and `0.003979921341`; no patch. |
| D3.3 | `b112384384eee4290d6da6e50abf2f96f4a5c33a` | Connect distinct open roots only along common outer ROI edges | Instrumented same-hypothesis replay exposes 33 vertices/32 triangles, two ROI-edge connectors, eight cutoff-rejected alternatives, minimum emitted cross-squared `2.24618035282731e-09`, one degree-4 boundary root, and 67 combined internal opens. Invalid. |
| D3.4 | `406697793ac57fafe1da5ea64359815ff2d2bed7` | Preserve exact binary32 roots and positions | The branch remains at exact identity `00008041e20e00407107e040`; 33 vertices/32 triangles, eight rejected alternatives, minimum cross-squared `2.30462182670976e-09`, three combined internal opens. Invalid. |
| D3.5 | `ca48ecdd6c1608118e9f9c6bbac7e2129f5c669a` | Bounded multi-cell caps for closed internal loops, existing vertices only | Equal LOD has 13 opens (closed 7- and 3-edge loops plus an open 4-edge chain); cutoff rejects five cap triangles, so zero loops/triangles are capped. Mixed invalid patch leaves three opens; its final cap is below the unchanged cutoff. |

Final status fields:

- Equal LOD: 13 internal open edges; 22/22 face contour segments match.
- Mixed LOD: no valid conforming transition; 10 coarse vs 22 fine segments (32 unmatched segment entries); final diagnostic combined mesh retains 3 internal opens.
- D3.5 diagnostic interface: 33 vertices and 32 triangles, but invalid; patch winding compatibility is false. No accepted interface geometry exists.
- Final mixed topology signature: `7e79fe370ebd7829dbcdf9f8d8d3a4314d7ad41e178c0ca9446cca93e5ded70c`, computed over all three captured internal-open edge keys plus topology counts using sorted-key compact UTF-8 JSON. This is an observed topology-summary fingerprint, not a mesh hash. Equal-LOD fingerprint: `7ade5a19ef14e343635773cfbbba495ebc1f3426bb459ea078d23eb16c23d882`.
- Base Candidate D full-ROI mesh SHA-256: `34c97d8e8145ee9cd6850a8fdc9bfa22087a7068cf5e77705f7bbb6f3bdf596b`; base required-surface topology SHA-256: `1279cbd6a4ab2c65310df57676daec67a4ac07febf12991c7c1416086032eaba`. D3.5 patch mesh payload hash: `4d823de5830b77638da459e6923fcf38e88bf9af74fa42864d10474d286e44bc`. The prototype did not emit a standalone combined-mesh hash.
- Frozen controls 6/6 PASS, corrected ROI ray fixture 0/25 hit/miss disagreements, Candidate D materialized volume identities preserved. These do not override the geometry failure.
- Determinism repeat: not run because no candidate otherwise passed. Full frozen E2E and `scripts/validate.ps1`: `NOT_RUN_NO_SURVIVING_GEOMETRY_CANDIDATE`.

## Runtime and resources

Godot was the pinned `4.7.2.stable.official.ed1daf0bf`, SHA-256 `c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643`. Geometry runs lasted 6.02–6.64 seconds and collected 7–8 resource samples each. Minimum free commit ranged from 3,973,267,456 to 4,700,618,752 bytes, above the 3-GiB warning and 2-GiB hard-abort thresholds. No warning or resource termination occurred. Complete per-process records, parent/child PIDs, streams and monitor hashes are in the linked campaign report/evidence.

## Evidence, scope, and limitations

The full raw evidence tree is retained at `C:\Users\PUBLI\AppData\Local\Temp\P3_1_R97_D3_20261029_5eab760d7ce6486eaef7fb210741416e`; its 730-file inventory SHA-256 is `dc13dcb351c9bef3cfa422744579796a7a0be3ee6daabc06523e03fbada2e5bb`. The curated 156-file review bundle and source/blob pin derivation are under [`docs/reports/P3-1-R9.7-D3-CAMPAIGN/`](../reports/P3-1-R9.7-D3-CAMPAIGN/); the detailed comparison is [`P3-1-R9.7-D3-CAMPAIGN-CLOSEOUT.md`](../reports/P3-1-R9.7-D3-CAMPAIGN-CLOSEOUT.md). The report's checksum inventory covers report and curated evidence, excluding itself.

This did not select a production mesher or geometry contract. The observations point to two distinct defects requiring a separately authorized future experiment: internal Candidate D opens away from the shared face, and mixed-LOD boundary segmentation/connectivity is not conforming. Do not solve either by weakening the cutoff or silently moving roots. No product tolerance has been adopted.

The isolated experiment changed only test/prototype source and documentation. Existing workspaces and both `stash@{0}`/`stash@{1}` were preserved; the pre-publication UID inventory is in the evidence bundle. All five F2-G1 holds remain unchanged: `CURRENT_PROTECTED_STATE_UNKNOWN`, `V3_NOT_ATTESTED`, `ACL_REVIEW_REQUIRED`, `G1_BLOCKED_ENVIRONMENT`, `F2_G1_RELEASE_HOLD`.

Next authorized action: independent review of the draft evidence PR and raw bundle. No production integration, merge, release, Issue #108/#154 implementation, save/schema changes, or protected-host operations.
