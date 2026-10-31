# P3.1 R12-CXR Preregistration Checkpoint

Date: 2026-10-31  
Status: `PREREGISTERED / GEOMETRY_NOT_STARTED`  
Branch: `exp/p3-1-r12-cxr-field-support-micropatch`  
Baseline stack: PR #211 head `209e301fc4576d0b7ef713a1b2ab3f86996f9db3`; frozen C6 measured source `4535f4c965db67adab7c93e448492c54be916c92`.

The owner authorized a corrected execution of the original R12-C field-constrained-support hypothesis. The previous CX attempt had zero support candidates and therefore tested only edge flips. R12-CXR will retain C6's 369 roots, 870 arcs, 502 source faces, coordinates, round-trip, Candidate D and volume, frozen controls/rays and strict cutoff. The residual fixture and its frozen digest are unchanged.

Before target execution, deterministic candidate generation, support fan retriangulation, evidence schema and bounded limits were preregistered in [the R12-CXR spec](../specs/P3-1-R12-CXR-FIELD-SUPPORT-PREREGISTRATION.md). Caps: 96 supports per cavity, four selected total, 1,024 candidate triangles per cavity, 16,384 states per cavity / 32,768 total, 10 s per cavity / 20 s total search, 30 s realizer, L0–L3 and 64 source triangles per cavity. Commit safety guard: warn below 3 GiB free commit and abort below 2 GiB.

No geometry execution has occurred on this branch as of this checkpoint. The first valid target execution will be one-shot and its source/input hashes, actual counters, every candidate/rejection, branch/prune counts, limit state and terminal reason must be durable. Any limit hit is `PARTIAL`, not proof of infeasibility. If equal-LOD passes, the frozen gates proceed automatically in order; a failed gate stops the campaign.

This experimental branch is stacked on draft PR #211 and does not modify PRs #207–#211. No production adoption, merge, native component, release, save/schema operation, or Issue #108/#154 work is authorized. Preserve `CURRENT_PROTECTED_STATE_UNKNOWN`, `V3_NOT_ATTESTED`, `ACL_REVIEW_REQUIRED`, `G1_BLOCKED_ENVIRONMENT`, and `F2_G1_RELEASE_HOLD`.