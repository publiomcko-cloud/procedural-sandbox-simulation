# P3.1 R9 Candidate A — bounded result

**Disposition: `R9_A_BLOCKED_WITH_EVIDENCE`**

Candidate A is an isolated, test-only root-aware Marching Tetrahedra prototype. It did not pass its first mandatory zero-edit build gate. No X+ transition, edited case, topology gate, performance campaign, PhysicsServer, GUI, or visual test was reached. This result is a resource stop-loss, not a conclusion that conforming Marching Tetrahedra is impossible.

## Identity and exact input

- Common experimental parent at execution: `a60d38df4f96b9007162e8fd917b3d14f29dcb0f` (R9 preregistration branch, including shared R9 test helper).
- Candidate A source was an untracked worktree file at the time of its one execution; physical SHA-256: `6029890cc090fc10373c885a26f8439ec06f1c012dd6471773105f7bae91499d`.
- Shared test-only helper: SHA-256 `a1ca1b958a15985111de71b3750090f8d226c1274e276802bd8236b66b10c671`.
- Frozen R9 JSONL input: SHA-256 `2b44cb52ef091c2527fa2f8b06859752cc7cfaa14bcafe94d4a4c55b0cdd908f`.
- Godot: `4.7.2.stable.official.ed1daf0bf`; executable SHA-256 `c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643`.
- Run profile was isolated under `C:\r9a\evidence\profile`; temporary files were confined to `C:\r9a\evidence\temp`.

The candidate file is included in this report branch, so reviewers can inspect the exact bytes by comparing its file hash above. The raw execution occurred before the report commit and did not have a Git commit containing that candidate source; the commit plus physical source hash is the accurate provenance boundary.

## Execution record

The final script parse and editor import after the shared helper became available both exited 0. The candidate was invoked exactly once after those gates. The process exited 1 and emitted one structured terminal record:

```json
{"algorithm":"root-aware marching tetrahedra with explicit 0.5 face grid ownership","assertions":3,"candidate":"A","duration_usec":525821,"failures":["zero_root_mt_build_within_stop_loss"],"gui":"NOT_RUN","manifest_sha256":"2b44cb52ef091c2527fa2f8b06859752cc7cfaa14bcafe94d4a4c55b0cdd908f","physics_server":"NOT_RUN","product_tolerance":"NONE_APPROVED","reason":"unique_sample_stop_loss","status":"BLOCKED"}
```

The bounded ROI has 9 × 21 × 13 = 2,457 initial grid nodes, under the 10,000-node limit. Root bisection requests additional canonical samples; the unique sample cache crossed the 10,000-node stop-loss while building the zero-edit mesh. The harness did not include the exact observed cache size in the terminal record, so that count is **unavailable** and is not inferred. The candidate correctly stopped before topology extraction or later scenarios. It was not rerun and no limits, inputs, or acceptance criteria were changed.

There were earlier pre-helper parser attempts which failed because the helper file had not yet been merged into this worktree. Those attempts are preserved separately and are not candidate geometry evidence. Once the helper was present, editor import and standalone parser check passed.

## Shared regression validation

After the candidate run, the exact worktree source (including the untracked Candidate A file) completed `scripts/validate.ps1` with exit code 0. The raw log contains **21 suite markers, 21,464 assertions, and zero failures**, including `LOD01_TRANSITION_PASS: assertions=6474 failures=0`, and ends with `VALIDATION_PASS: L0-L2; GUI visual test remains an owner task`.

This confirms the shared project regression baseline only; it does not override the Candidate A stop-loss. Non-fatal limitations in the log: the Issue #118 reparse fixture was unavailable (`DirAccess.create_link returned Failed`) and three camera target/up colinearity warnings occurred. No GUI, rendered pixels, PhysicsServer, GPU, or product geometry tolerance was validated.

## Evidence inventory

Complete raw logs and SHA-256 inventory are in [`evidence/`](evidence/). The candidate terminal output is `candidate-a-single-run.stdout.log`; full validation is `full-validate.log`. The inventory is `evidence/SHA256SUMS.txt`. Earlier parser failures are retained as `candidate-pre-helper-attempt.stdout.log` and `candidate-pre-helper-parse.log`.

## Conclusion and next work

Candidate A is blocked under the preregistered node budget. The next R9 candidates B, C, and D remain independently eligible and must use the same frozen inputs and stop-loss limits. Candidate A's result is not a geometric rejection, not a production recommendation, and not evidence that other conforming approaches fail. Any future A revision would need separate authorization or a new candidate specification; this report does not alter the frozen limit.
