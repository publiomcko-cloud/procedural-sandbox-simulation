# P3.1 R10-A Campaign Closeout

Date: 2026-10-29  
Event: bounded experimental campaign completed; six hypotheses exhausted.  
Repository: `publiomcko-cloud/procedural-sandbox-simulation`  
R10 branch: `exp/p3-1-r10-a-topology-authority`  
Measured final source: `da55e6e97bd56c31034b2d84c68a245a2f0973a1` (parent `78efe295c686661330f0f5ec7593e21bb6bbe6b3`)  
Campaign base: R9.7 evidence PR #206 head `2cc2ccc933c4676dd281fce9aa4fc4a31d9f0719`; production baseline `92b442d7f5b605c7bc9c48fac2aceea9d71813aa` is an ancestor.  
Last independently queried `origin/main`: `5997a76d345f45bf86edfe83f690336391e8be27` (GitHub API, 2026-10-29).  
Publication at checkpoint creation: local final source/report prepared; draft evidence PR creation pending.

## Outcome

Terminal status: `P3_1_R10_A_ATTEMPTS_EXHAUSTED_WITH_EVIDENCE`.

Six valid geometry attempts A1–A6 ran. Each equal-LOD candidate ended `FAILED_TARGET`; no mixed-LOD gate ran because the equal-LOD gate never passed. A6 retains 10 internal open edges and 21 missing required adjacencies; nonmanifold count is zero, winding is valid, controls are 6/6, ROI ray agreement is 16/25, and the Candidate D volume identity check passes. No candidate qualified for repeat determinism. Frozen E2E and `scripts/validate.ps1` were correctly not run because there was no surviving geometry candidate.

The final bounded edge-flip attempt preserved all source roots, retained the `cross_squared > 1e-12` emission cutoff, and recorded unresolved triangles instead of suppressing required obligations. It did not close the target. This does not establish impossibility of a legal realization in general.

Full attempt-by-attempt results, exact process records, source hashes, resource data, diagnostics, raw evidence archive and recommendation are in [`R10-A campaign results`](../reports/P3-1-R10-A-CAMPAIGN/RESULTS.md). The raw evidence tree remains at the recorded local Temp path and is included as a compressed archive with a SHA-256 file inventory. All failed/tooling attempts remain retained and classified.

## Boundaries preserved

No production scene, SDF, ledger, storage schema, save, dependency, CI, Issue #108/#154, or prior PR was modified. No merge, release, owner visual acceptance, geometry contract, FPS/GPU/collision claim, or production recommendation is implied. All five holds remain: `CURRENT_PROTECTED_STATE_UNKNOWN`, `V3_NOT_ATTESTED`, `ACL_REVIEW_REQUIRED`, `G1_BLOCKED_ENVIRONMENT`, `F2_G1_RELEASE_HOLD`.

Next step: independent review of the exact source and raw evidence. Any R10-A7 or new topology realization campaign requires separate owner authorization.
