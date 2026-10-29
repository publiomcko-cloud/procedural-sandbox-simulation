# P3.1 R9.6-D — Candidate D Corrective Disposition

Date: 2026-10-29  
Issue: [#196](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/issues/196)  
Status: **P3_1_R9_6_BLOCKED_WITH_EVIDENCE**

## Exact candidate and scope

- R9.6 branch baseline / prior Candidate D evidence HEAD: `464087947da00a45090a289ade4917882ce0ada5`.
- Measured Candidate D source commit: `6ea04229b5ff06090f346c8749c1f5a53994227c`; the source commit parent is `51744eebf17646ca52612936146adeb0f9db001b`.
- Candidate implementation blob: `33ac8bd1f7942ddd71610bd2e2b66f583fdbf3fd`.
- Physical SHA-256: `a33b464ea569f54fb39b72d2198fa971796c0cb5370a64a9696362cd0313f2a6`.
- Frozen R9.2 manifest SHA-256: `1610c535f98a11e26ca1890c0d99addf4316fbcaa7ec9cdb7dfaa71cf5bb3972`.
- Cutoff unchanged: `cross_squared > 1e-12`.

R9.6 did not modify Candidate D's volume materialization, float32 values, revision/hash/reload behavior, corruption rejection, or extractor. No production, save, or schema paths changed.

## Attempt ledger

**Implemented geometry attempts: 0/3.** The shared R9.6 topology ledger is diagnostic-only and was not integrated into D. No D candidate revision was executed or consumed.

| Attempt | Pinned candidate source | Hypothesis / implementation | Result |
|---|---|---|---|
| None | N/A | No D source revision was made. The shared Godot import gate failed before materialization or extraction could run. | `CENSORED` before Attempt 1; 0 attempts used |

## R9.5 evidence carried forward (not a new R9.6 run)

R9.5 attributed D's 13 X+ internal openings to eight three-root triangles rejected by the frozen cutoff. The 7- and 3-edge loops had best existing-vertex triangulation minima `4.86268358953069e-15` and `9.40420376120688e-13`, both below `1e-12`. Retriangulating only those existing vertices cannot close the loops under the unchanged threshold.

R9.5's equal-LOD X+ contour segment sets matched, but D's full ROI still had 13 internal opens. The mixed-LOD proxy had 10 vs 22 segments with unmatched contours and no actual transition surface. The corrected 25-ray ROI oracle remained 0/25 hit/miss disagreements; distance deviations are unscored. D matched the R9.3 test-only reference on identical reloaded volume bytes, which is not canonical truth.

No R9.6 materialization, extraction, repair, interface timing, topology, new-vertex residual, ray-distance, corruption, or full validation result exists. The inherited R9.4 21-suite/21,464-assertion validation applies to the unchanged source only.

## Gate and next action

Three Godot 4.7.2 editor-import attempts on the shared pinned R9.6 source terminated with `-1073741819` / `Parameter "mem" is null`. The focused topology script invocation then hit a PowerShell `OutOfMemoryException`/stack overflow without process attribution. At the host snapshot only 89,908 KB of virtual-memory commit was free; `vmmemWSL` held 26.19 GB private bytes. Full raw import logs and the environment-correction sidecar are retained in the shared R9.6 oracle report.

Candidate D remains `BLOCKED_WITH_EVIDENCE`, not `EXPERIMENTAL_GEOMETRY_TARGET_PASS`. After the shared diagnostic gate can run, D Attempt 1 must leave materialization byte-for-byte unchanged and record the extractor's topology before cutoff. Attempt 2 may refine only the local patch with vertices derived from the canonical field and a preregistered residual; Attempt 3 may introduce one face-owned interface object. Measure storage/materialization, extraction, repair, and interface independently. Never lower the cutoff or use altered volume values.

No production integration or approval is requested. The five F2-G1 holds remain unchanged.
