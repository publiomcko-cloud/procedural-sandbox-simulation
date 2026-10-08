# Independent P0.1-F2 G1 preparation correction re-review — 2026-10-08

Repository: publiomcko-cloud/procedural-sandbox-simulation
Developer PR: #27, draft/open/unmerged when reviewed
Previous review: PR #28, blocked-environment stop VALID, preparation F2-R1/R2 corrections required at b2aa78463a976211b97d36c2cc55ae67d0609bd8
Corrected reviewed HEAD: 9d7cb325c4b60d84465d568fb67c5dcc45ef9246
Verified HEAD parent: 81e3dec65d0afbff6e3dc18cd7e013e0364af87e
Corrected merge base/live main: b00b4c2eb680fbdea4d5288a64059e828b504918
Scope of authorization: issue #26, G1 sandbox-only native execution permitted only if a compliant guest exists.
Reviewer method: remote GitHub PR/source/commit/CI inspection and independent source-only numeric calculation. No local Windows, PowerShell, guest, Godot, ZIP or native execution.

**Verdict: PASS_PREPARATION / BLOCKED_ENVIRONMENT_VALID. All F2-R1 and F2-R2 review findings resolved at this SHA. THIS IS NOT F2 RUNTIME SUCCESS, ENGINE COMPATIBILITY, VISUAL ACCEPTANCE, OR OWNER PERMISSION TO MERGE.**

## Provenance and scope
- Verified PR #27 draft/open/unmerged/mergeable, HEAD exactly 9d7cb325c4b60d84465d568fb67c5dcc45ef9246, target main b00b4c2eb680fbdea4d5288a64059e828b504918.
- Verified the final HEAD parent through GitHub commit REST metadata as 81e3dec65d0afbff6e3dc18cd7e013e0364af87e.
- Relative to originally reviewed b2aa7846, exactly two additional commits change only five paths: tests/f2_runtime/fixtures/analytic_sdf_v1.json, tests/f2_runtime/validate_fixture.ps1, tests/f2_runtime/README.md, docs/research/P0.1-F2-RUNTIME-PROOF.md, and docs/handoffs/P0.1_F2_RUNTIME_HANDOFF.md. PR total six paths includes proposed docs/status/CURRENT_STATUS.md, no vendor payload/addon/Godot change.
- GitHub Actions Starter checks runs 37834503292 and 37834497243 both SUCCESS at final HEAD. Inspected jobs: both are static expected-file checks only, not PowerShell, sandbox/VM, Godot, native or fixture tests.
- Developer reports a clean worktree, JSON parsing and git diff --check success, synthetic F1 ZIP safety suite 64 assertions/34 cases/0 failures and a new PowerShell fixture validator 21 assertions over seven analytic samples. Reviewer verified the source and counts but did not independently execute PowerShell.

## F2-R1 RESOLVED — analytic field consistency and validation
Reviewed full corrected JSON and validator. Source-defined density:
`density(p) = min(max(-p.y, 5 - length(p - (0,-1,0))), distance_to_segment(p,(-8,-4,0),(8,-4,0)) - 1.25)`
(domain sign: density > 0 solid).
- `(0,0,0)`: plane 0, hill +4, distance to segment 4, tunnel subtraction limit +2.75 => density **+2.75**, solid, **11264** ticks at scale 4096.
- `(0,4,0)`: hill surface at 5 units from sphere center, plane -4, tunnel distance 8 and subtraction limit 6.75 => density **0**, **0 ticks**, a true spherical surface sample.
- `(0,1,0)` density +3, 12288 ticks.
- `(0,-4,0)` density -1.25, -5120 ticks.
- `(0,-4,2)` density +0.75, 3072 ticks.
- `(-0.5,-4,0)` and `(0.5,-4,0)` density -1.25, -5120 ticks at both x=0 boundary sides.
- Independently evaluated all seven JSON sample points using the stated plane, spherical hill, clamped projection onto finite tunnel segment, and union/subtraction; all observed analytic densities and quantized ticks matched expected metadata. Numbers at these probes are exact increments at scale 4096; this is not a claim of cross-architecture bitwise equivalence or in-Godot results.
- New PowerShell tests/f2_runtime/validate_fixture.ps1 reads the JSON, checks seven fixture/formula/count/tick metadata expectations, computes density and nearest-even tick quantization for each of the seven probes and compares them to fixed expected_density/expected_ticks: **7 + 7*2 = 21** assertions. Failure throws. No vendor code is referenced. JSON now accurately describes the radius-5 sphere centered at y=-1 as a hill **protruding above the plane**, not buried.

## F2-R2 RESOLVED — offline guest acquisition/staging protocol
The corrected tests/f2_runtime/README.md has explicit ordered sections:
1. **Host preparation, before guest launch:** obtain only the approved official Godot Windows executable and exact v1.7x ZIP; host checks identity, archive size 54,457,774 and digest 600737572a5e25541ba6f503e842a3717ba19afafa5474510a6ceff995a1d2d8. Hashing the ZIP as inert data is allowed; host extraction/dispatch/native DLL execution is prohibited.
2. Restrict transfer to read-only verified inputs; Windows Sandbox must use a custom `.wsb` with Networking=Disable, rather than the network-on default. Do not mount secrets or writable host worktrees.
3. **Offline guest:** verify effective isolation, copy to unique guest-local workspace, rehash engine/ZIP, run the accepted F1 synthetic adversarial ZIP suite and preflight in guest before extraction, hash descriptor-mapped Windows DLLs and execute ordered A–F only after passing the mandatory environmental gate. No enabling guest networking to fetch anything, host fallback, or unreviewed data export.
This resolves guest-side download ambiguity. It is a **documented protocol, not proof an offline guest exists or that its settings can be enforced**.

## Safety stop and residual blockers (unchanged)
- Developer attempted F2 G1 on Windows 11 Pro 22631 but could not identify `WindowsSandbox.exe` or VM manager cmdlets, and optional-feature state query required elevation. The active hypervisor/vmcompute service does not establish controllable VM isolation.
- No vendor ZIP obtained/extracted in this attempt, no official Godot hash/version measured or Godot started, no native extension staged/loaded, no network-off guest attested, no engine import or SDF/material/edit/collision/revision/LOD outcome. **Probes A–G NOT RUN**. No owner GUI validation performed. F2 remains **BLOCKED_ENVIRONMENT**, not FAIL/UNSUPPORTED vendor behavior and certainly not PASS.
- Guest must be independently provisioned and verified with networking disabled, unprivileged guest process, no writable host shares, bounded process/time/resource controls, safe evidence export and cleanup. In particular, Windows Sandbox default admin-capable guest identity should not be confused with a proven unprivileged account; an appropriate standard-user setup or a dedicated VM may be necessary.
- Exact DLL machine code/transitive runtime dependencies and redistribution notices remain unproven. The F1.6 notice bundle is DRAFT, NOT SHIPPED, NOT LEGAL CLEARANCE. No ADR-0002/backend decision.

## Decision and next steps
**Accept PR #27 as an accurate historical blocked attempt and corrected preparation artifacts, not as completion of F2.** Owner may authorize merging PR #27, previous review #28, and this passing re-review in that order; update canonical status to retain an OPEN F2 runtime gate and issue #26. The reviewer does not merge PRs.
**Owner must separately provision** compliant offline Windows Sandbox or throwaway VM. Existing scoped G1 owner authorization under issue #26 remains conditional on all isolation requirements, not an unconditional right to execute on the host. Once provisioned, re-check guest resources, staging and hashes, resume Probe A with new evidence and create a subsequent SHA-bound developer review. STOP rather than downgrade security/renderer or fabricate results. F3/F4/P0.2, production adoption, license/distribution claims, upstream contact, ADR-0002 and any merge remain outside this verdict.

Final review label: **PASS_PREPARATION — BLOCKED_ENVIRONMENT — A–G NOT RUN**.
