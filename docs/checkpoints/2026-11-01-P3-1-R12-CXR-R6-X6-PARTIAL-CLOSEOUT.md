# P3.1 R12-CXR R6-X6 partial closeout

**Checkpoint ID/date and timezone:** R6-X6 partial closeout; 2026-11-01 22:54 America/Sao_Paulo (2026-11-02 01:54 UTC)
**Event type:** blocker / major handoff
**Publication state:** recorded on draft docs PR #222; not integrated
**Immutable once integrated:** yes; later events require a new checkpoint.

## Verified repository identity

- Repository: `publiomcko-cloud/procedural-sandbox-simulation`.
- Live `main` at event time: `5997a76d345f45bf86edfe83f690336391e8be27`; tree `40181fe289a6f70f88e4a39a06db0c353c91e268`. No merge occurred.
- Functional branch: `exp/p3-1-r12-cxr-r6-realization-map-cavity`, source `896e78b9614f0a4bf4dad51dddaee31b2ced7d99`, parent `c89b78fd9650f9a8fb2b4aeb7b8a2c347a76068f`; exact source was pushed to open draft PR [#219](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/219).
- Concurrent docs PRs #220 (head `27b28b2c78176cef1ce5884de4d3eb713b7f2bdf`) and #221 (head `660dfafdc96e22c45627967a5eb793f69a17aede`) were inspected and left untouched. A new docs-only branch/PR is used for this closeout.
- Changed source paths at `896e78b9614f0a4bf4dad51dddaee31b2ced7d99`: `game/tests/prototypes/p3_1_r12_cxr_r5_support_synthesizer.gd`, `p3_1_r12_cxr_r6_campaign.gd`, `p3_1_r12_cxr_r6_contract_tests.gd`, `p3_1_r12_cxr_r6_realizer.gd`.

## Decision and approval ledger

- Owner-authorized test-only scope: Issue [#218](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/issues/218), R6 geometry realization and cavity work under the supplied procedure.
- The user explicitly directed continuation through remaining hypotheses and all downstream gates when their gates permit. No merge, release, production adoption, or protected-state activity was authorized.
- No ADR changed. ADR-0001 remains immutable; ADR-0002 remains proposed.
- No owner GUI PASS/FAIL or independent source review is recorded. No merge authorization was given.

## Evidence ledger

**Pinned executor:** Godot `4.7.2.stable.official.ed1daf0bf`, executable `C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe`, SHA-256 `c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643`.

- **L1 process/import:** cold import passed on exact source with `--headless --editor --path game --quit`; campaign and contract check-only passed; evidence writer check passed.
- **L2 structured:** R6 contracts 96/96, including solver regressions and the directed same-tetra axis-bracket fixture; retained R5 contracts 348/348; CXR contracts 216/216.
- **L3 exact-source deterministic reproduction:** X6 targeted support synthesis completed twice with identical fingerprint `878f546fbe61eb402305f00443e471d2f380797f7945c3612ec8ece747ec23ee`.
- **L4 benchmark/OS:** no benchmark claim. Resource preflight recorded memory, temporary-drive availability, and the fixed 30,000,000-usec synthesis cap.
- **L5 independent execution/review:** not performed. These are implementation-agent results only.
- **Terminal attempt:** `R6-X6-REPRESENTABILITY-20261102-01`, source `896e78b9614f0a4bf4dad51dddaee31b2ced7d99`, parent `c89b78fd9650f9a8fb2b4aeb7b8a2c347a76068f`; result SHA-256 `dd2413009300d13bb84472096a1648016475d34daf9c948261d274d674d6eb55`. Attempt consumed; cumulative valid target attempts 6/6 (baseline, X1, X2, X3, X4, X6). X5 was not run because the complete graph audit recorded all 870 topology-path reachability records reachable, so its path-specific hypothesis was not supported.
- X6 preserved the selected seven-face manifold alternative cavity and the three zero-option boundary obligations. Its changed candidate representation searched each projected witness along full same-tetra binary32 axis intervals, with the existing field residual and barycentric epsilons, cutoff, ROI, roots, arcs, Candidate-D volume and topology authority unchanged.
- Raw targeted evidence: [X6 evidence archive](../reports/P3-1-R12-CXR-R6/evidence/x6-2026-11-02/R6-X6-20261102-evidence.zip), 564,261 bytes, SHA-256 `97df9cde3f2361cb014947e688c4cf8163c27c617ce49f5f7391f9c51cc8eb25`. The archive includes preregistration, exact process captures, structured scientific result, full candidate audit, tooling-failure addendum and SHA manifest.
- Exact R6-X6 result: 1,370 finite critical candidates across 142 arrangement regions for three target pairs; finite target enumeration complete and deterministic; 765 representability corrections attempted, 656 passed the unchanged field/barycentric gates, and 109 remained field-invalid. No target support was emitted. The raw rejection histogram and witness records are in the archive.
- The selected candidate graph was complete at 3,029 legal triangles (SHA-256 `cb386008a8f1ce5dd81336d00cf197bd4e3761d349f6828c1c0e819f874b57bf`); solver status `UNSAT_COMPLETE`, exhaustive, with `required_edge_has_no_remaining_candidate: 1`. This is bounded to the selected finite graph.
- **R6-D:** selected seven-face cavity passed its recorded manifold/single-boundary audit. **R6-E:** targeted support set yielded zero supports; inherited X3 synthesis remains incomplete at `R5_MAX_CRITICAL_CANDIDATES_TOTAL` after 4,084 critical candidates. **R6-F:** complete solver returned UNSAT for the resulting finite graph. Overall status remains `R6_X6_REPRESENTABILITY_PARTIAL`.
- The diagnostic raw-evidence capture was non-consuming and reproduced the scientific targeted fingerprint. Tooling/preflight failures are separately retained: five prior failures plus six preflight/evidence events (11 total) in `tooling-failure-addendum.json`, then one archive invocation error (12 total) in the [post-archive addendum](../reports/P3-1-R12-CXR-R6/evidence/x6/postarchive-tooling-addendum.json), SHA-256 `a0c6b19ef2483f74ebb32850d5d239995509091688400b56850762ebfb3ae1f2`; these events consumed no scientific attempt.

## Downstream gates and limitations

No SAT mesh exists. Equal-LOD, controls, ROI rays, volume reconfirmation, mixed LOD, downstream deterministic repeat, full E2E, and `scripts/validate.ps1` were not launched because the R6-F solver gate returned UNSAT. The X6 targeted finite set is exhausted, but `analytic_feasible_support_domain_exhausted=false`; multi-coordinate binary32 combinations, the incomplete inherited X3 support set, other cavities outside the bounded search, and continuous/global feasibility remain unproven. Do not describe this as global geometric infeasibility.

## Architecture and recovery

- Current functional state is test-only; no product code adoption or architecture selection.
- Reproduce with the pinned Godot executable and the R6, R5 and CXR contract commands recorded in `attempt-preflight.json`; full invocation environment and logs are in the evidence archive.
- Known limits: six valid target attempts consumed; the X3 inherited support domain hit its 4,096-candidate cap; X6 only explored axis-aligned binary32 intervals for the recorded critical witnesses. No additional attempt is authorized by the six-attempt procedure.
- Next action: independent exact-SHA review of PR #219 and review of this bounded partial evidence. Any broader support-domain continuation requires explicit scope/attempt authorization if it exceeds the current procedure.
- Docs updated on this new draft documentation branch: README, CURRENT_STATUS, AGENT_RECOVERY, checkpoint index and this checkpoint. DECISION_REGISTER and CHANGELOG are unchanged because no architecture decision or merge occurred.

## Event significance and decision

The X6 attempt and complete finite-graph UNSAT result are verified at exact source `896e78b9614f0a4bf4dad51dddaee31b2ced7d99`; the inherited support-domain cap prevents a terminal global claim. The blocker is evidence-backed and bounded: no supports in the complete targeted X6 witness set, plus an uncompleted cavity-wide support domain and no SAT mesh. Publication is recorded on draft docs PR #222 (open, unmerged). This checkpoint is not integrated, owner-accepted, or merge-authorized.
