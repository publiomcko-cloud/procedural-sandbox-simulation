# R6-D4 — Boundary option completion: PARTIAL

Date: 2026-11-04
Branch: `exp/p3-1-r12-cxr-r6-realization-map-cavity`
Tooling source: `27d5330bffe4873e3e585d708e998f9d40d502b3` (parent `451a43b1e86844471eb8c18c3f88ae297a088028`)
D4 campaign input source: `451a43b1e86844471eb8c18c3f88ae297a088028`
Godot: `4.7.2.stable.official.ed1daf0bf`, executable SHA-256 `c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643`

## Verified disposition

`R6_D4_CANDIDATE_PARTIAL_WITH_RESUMABLE_PROOF_FRONTIER`

The selected D2 candidate signature is `234ebf1520e00ee52ab93281d07b542ca4561f33e17f720f81baaed61ce0a1e6`, with coverage `6/9`. Boundary obligations 2, 3, and 4 remain open. The authoritative D4 result records respectively 37, 81, and 78 analytic witness candidates, all rejected by the canonical required-arc gate. Those finite witness rejections establish neither continuous-domain emptiness nor binary32 exhaustion.

The exact authoritative D4 JSON is preserved byte-for-byte at [evidence](../evidence/r6-d4/R6D4-authoritative-boundary-option-completion.json): 111,536 bytes, SHA-256 `6f70a61b7ed3fb7f602832ca29b7d1d922a98b8ea3cef98ec565880ffa2466cc`. Its selected candidate, frozen-input identities, six existing legal options, and partial classifications were parsed and checked against the pinned result.

The corrected inventory runner reconstructed and hashed all 117 clipped zero-facet regions, SHA-256 `811a1de43ca389b3a2d0a6946654f6c55c0676ab8cddbc373ff5ee7d8456f319`. The resumable keys remain obligation-specific and deterministic:

- `R6D4|R6-D-CAUSAL-ARC-CROSSING-20261103-01|451a43b1e86844471eb8c18c3f88ae297a088028|226bdbbc9fa61692548d0d38eb5eb0a1f2a96802c4a97049d5f30206f15272f3|234ebf1520e00ee52ab93281d07b542ca4561f33e17f720f81baaed61ce0a1e6|5d2b5ffddfbf4000f501df7647469679227ef3115501d64be8a8f66a1ae7d604|CONTINUOUS_REGION_RECONSTRUCTION`
- `R6D4|R6-D-CAUSAL-ARC-CROSSING-20261103-01|451a43b1e86844471eb8c18c3f88ae297a088028|226bdbbc9fa61692548d0d38eb5eb0a1f2a96802c4a97049d5f30206f15272f3|234ebf1520e00ee52ab93281d07b542ca4561f33e17f720f81baaed61ce0a1e6|388cbab08bbb9c1c3103c4f52b6c3202a31da8d24bad1ef05d5798c1fff00755|CONTINUOUS_REGION_RECONSTRUCTION`
- `R6D4|R6-D-CAUSAL-ARC-CROSSING-20261103-01|451a43b1e86844471eb8c18c3f88ae297a088028|226bdbbc9fa61692548d0d38eb5eb0a1f2a96802c4a97049d5f30206f15272f3|234ebf1520e00ee52ab93281d07b542ca4561f33e17f720f81baaed61ce0a1e6|78660adb925ad93d0df44b01eb0127b6b0384c1b210eb7b9dae99f1fc065a21f|CONTINUOUS_REGION_RECONSTRUCTION`

Each key resumes before region index 0 with 0/117 regions processed. The inventory is geometric reconstruction only; required-arc subdivision has not started and binary32 exhaustion is false. No support was added, no cavity was promoted, no candidate graph was built, the frozen solver did not run, and no scientific target attempt was consumed. The six existing legal options remain unchanged. D4 narrows the active work to obligations 2/3/4 of this D2 candidate; it says nothing about other cavities or global infeasibility.

## Tooling correction and validation

The first inventory execution emitted a GDScript runtime error at the JSON boundary: an untyped `Array` returned by `JSON.parse_string` was assigned to `Array[Dictionary]`. The raw 492-byte failed log is preserved. The runner now accepts the deserialized array through a small untyped adapter, and a focused contract covers JSON arrays, dictionary rows, and non-array rejection. Its summary marker also now counts only the three unresolved obligations rather than all nine obligation records.

The correction and its expanded contracts were committed and pushed before relying on the corrected inventory: commit `27d5330bffe4873e3e585d708e998f9d40d502b3`. The exact-source Godot editor import completed; R6 contracts passed `150 assertions, 0 failures`; campaign `check-only` passed; and the inventory runner reproduced 117 regions with obligations `[2,3,4]`. The contracts process also printed renderer/ObjectDB resource-leak warnings on exit; the process exited successfully and the contract marker reported zero failures. `git diff --check` passed before the source commit.

The original inventory attempt was stopped after about 495 seconds and had no result artifact. Its error log is retained as a tooling failure, not a scientific finding and not a proof of infeasibility.

## Evidence inventory

All raw logs, the pinned D4 JSON, the corrected inventory result, byte counts, and SHA-256 values are in [evidence/r6-d4](../evidence/r6-d4/). See its `SHA256SUMS.txt`. The authoritative JSON's Git attributes disable text conversion so its original bytes survive repository storage.

## Next action

Continue as D5 from the three persisted deterministic keys. Process regions independently and checkpoint each terminal or partial result. Do not search new cavities or promote this candidate unless all three obligations receive legal graph options and the frozen graph/solver gates then pass.
