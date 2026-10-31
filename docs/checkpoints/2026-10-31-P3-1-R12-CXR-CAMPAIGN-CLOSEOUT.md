# P3.1 R12-CXR Campaign Closeout

## Result

`R12_CXR_PARTIAL_WITH_EVIDENCE`

The sole frozen target `R9.2.SEAM.XPLUS_EQUAL.v1` was started exactly once on source `0a967c996476e9bf4376b1e55dbb835cf5a31ee6` and returned `PARTIAL` with process exit 0. It is not a geometric PASS and does not establish that the bounded CXR hypothesis is infeasible. The target cannot be repeated under the authorization used for this campaign.

## Identity

- Branch: `exp/p3-1-r12-cxr-field-support-micropatch`
- Measured source: `0a967c996476e9bf4376b1e55dbb835cf5a31ee6`
- Direct parent: `ebb4e990b71df0ded64939152b273ea092f07e4f`
- Tree: `34fc37357a60a1adfd3e2e5fbd43dbdfc47dc8c5`
- Stacked evidence parent: PR #211 head `209e301fc4576d0b7ef713a1b2ab3f86996f9db3`
- Target attempt: `r12cxr-target-20261031-01`

## What ran

On the measured source and isolated Godot profile: cold import; realizer, campaign and contract `--check-only`; campaign check-only; and the bounded CXR contract suite. The suite passed 56 assertions with zero failures. Only after these gates passed, one target process ran. It had PID 42364, parent PID 37584, process exit code 0 and duration 4029.8958 ms. The resource guard did not warn or abort. Target stdout SHA-256 is `40fffef05c7cf8df1f58b653583458f92c50fba4f6c40375d9a1cd3b2bb8c841`; stderr was empty.

## Finding

The target result contains a concrete implementation incompleteness. At L0, the two-face residual patch generated 492 field-derived candidate attempts and 84 unique retained candidates, but no valid complete support fan. At L1, the expanded patch failed boundary validation with a nonmanifold edge of incidence 3. In `game/tests/prototypes/p3_1_r12_cxr_field_support_realizer.gd` around line 205, invalid boundary handling returns from the cavity search rather than recording the L1 rejection and continuing to the preregistered L2 and L3 levels. The outer realizer also returns on the first failed cavity, leaving the second frozen cavity without diagnostics. Consequently the result records `search_complete=false` and `search_exhaustive=false`; no declared candidate/search cap was reached.

The minimum source correction for a future reviewed attempt is to record a rejected level and continue the finite L0–L3 search, and to capture a terminal diagnostic for every frozen cavity under the existing resource limits. This correction must preserve the frozen geometry, cutoff, and fail-closed gates. No correction was made after the target began, and no target rerun is authorized by this attempt.

Because equal-LOD geometry did not pass, later sequential gates were not run: 6/6 controls, 0/25 ROI ray checks, volume reconfirmation, mixed LOD, deterministic target repeat, full E2E, and `scripts/validate.ps1`. No performance or visual acceptance is claimed.

## Evidence

The full result and interpretation are in [R12-CXR campaign results](../reports/P3-1-R12-CXR-CAMPAIGN/RESULTS.md). Exact Git blob and physical SHA-256 identities are in [source-identities.json](../reports/P3-1-R12-CXR-CAMPAIGN/source-identities.json). The 39-member hash-indexed raw archive is [r12cxr_partial_evidence.zip](../reports/P3-1-R12-CXR-CAMPAIGN/evidence/r12cxr_partial_evidence.zip), SHA-256 `3a7b5d810fa260abf94975ff098e05c3e7bff6587eee9fdc7fd5376950e0c837`; its index was independently checked against every archive member.

The archived C6 Stage 0 fixture and R12-CX residual fixture/manifest identities are pinned in the source identity inventory. A failed earlier contract-fixture run and pre-scenario launcher authoring errors remain in the archive as historical evidence; they are not counted as passing validation.

## Boundaries preserved

No production, persistence, schema, native backend, Issue #108/#154, protected host, or F2-G1 operation was performed. PRs #207–#211 remain untouched and unmerged. Preserve all five holds: `CURRENT_PROTECTED_STATE_UNKNOWN`, `V3_NOT_ATTESTED`, `ACL_REVIEW_REQUIRED`, `G1_BLOCKED_ENVIRONMENT`, and `F2_G1_RELEASE_HOLD`.

## Publication

The evidence is in [draft PR #212](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/212), stacked on the R12-CX evidence branch at base SHA `209e301fc4576d0b7ef713a1b2ab3f86996f9db3`. PR #212 is open, draft, and unmerged. Its first publication head was `e99de6b4863743037e7991c036b07ec41a0748a4`; subsequent closeout metadata commits are documentation-only and leave measured source `0a967c996476e9bf4376b1e55dbb835cf5a31ee6` unchanged.
