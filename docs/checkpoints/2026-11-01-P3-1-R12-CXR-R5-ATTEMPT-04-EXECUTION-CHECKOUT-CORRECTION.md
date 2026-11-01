# 2026-11-01 — R12-CXR R5-4 execution checkout correction

## Correction and status

This append-only correction supersedes only the executor/checkout and execution-ID fields of the [R5-4 pretarget freeze](2026-11-01-P3-1-R12-CXR-R5-ATTEMPT-04-PRETARGET-FROZEN.md). Its source, frozen inputs, algorithm, caps, target, and gate definitions remain unchanged. The target `R9.2.SEAM.XPLUS_EQUAL.v1` remains **NOT_STARTED**; R5 slot 4/5 remains unused.

The first launcher precheck was correctly rejected before invoking the launcher because the documentation commit made the active branch `HEAD` `f4476df...`, while the measured code SHA is `8e5211e...`. No Godot process, launch intent, reservation, enumeration marker, target output root, or target result was created. A later evidence-assembly command also stopped on a PowerShell boolean-literal typo while writing a diagnostic record; it did not launch Godot. Both are pre-target operational failures, are preserved as `prelaunch-guard-failure-r2.json`, and consume no scientific slot.

R5 now uses a detached worktree at exactly the measured source `8e5211e0665b6f57839d5c7eeae51c28c64325f6` (parent `0543cd1ca3c438b68f58799e1eb5f49963bbf09f`, tree `1531f2e5c2085f500437f38e0c8be22e63376e0b`) at `C:\r12cxr-r5-target-8e5211e-20261101`. Origin matches the repository. The detached checkout has no tracked changes. Cold import generated 128 `.gd.uid` files in that isolated checkout; they are preserved and not staged. The feature branch remains at its documentation publication head and is not switched or reset.

## Repeated exact-checkout gates

On the detached exact source, Godot `4.7.2.stable.official.ed1daf0bf` / SHA-256 `c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbbe846643` passed cold editor import, R4 realizer check-only, R5 campaign check-only, synthesizer check-only, R5 contract check-only, R5 contracts **348/348**, R12-CXR contracts **216/216**, and cavity freeze/regeneration. Every process exited 0 with empty stderr. The frozen cavity regenerated to SHA-256 `a54a407ac84b3fd7d64108f41457d5ecc7ff335abaee6899819de579ebeae6a6`. The pinned manifest remains `1610c535f98a11e26ca1890c0d99addf4316fbcaa7ec9cdb7dfaa71cf5bb3972` with matching sidecar.

The exact-checkout preflight log bundle, script, summary, cavity artifact, resource sample, and source inventory are in [`pretarget-detached-20261101`](../reports/P3-1-R12-CXR-R5/evidence/pretarget-detached-20261101/). An isolated CreateNew test rejected duplicate creation and left the first artifact hash unchanged. At `2026-11-01T14:58:59Z`, free commit was 8,180.0 MiB, physical available memory 30,820.8 MiB, C: free 114.01 GiB, and no Godot process was running. Warn/stop levels remain 3,072/2,048 MiB free commit.

## Corrected one-shot dispatcher freeze

- Measured code source: `8e5211e0665b6f57839d5c7eeae51c28c64325f6`; execution working directory is the detached path above.
- Target: `R9.2.SEAM.XPLUS_EQUAL.v1`; R5 valid slot 4 of 5; exactly one invocation.
- **Exact execution ID:** `r5target2026110104a91e4f3e7c8f4f9a`. This is the literal in the corrected dispatcher and launch-intent record; it corrects the transcribed ID in the previous checkpoint.
- Dispatcher: `docs/reports/P3-1-R12-CXR-R5/evidence/pretarget-detached-20261101/launch_scientific_05_r2.ps1`, SHA-256 `49dcfac759834002a7da04ab645b182e1e1c059970f164afc4541793e769949c`; PowerShell parser reports zero errors. It requires a detached `HEAD`, exact source, correct origin, clean tracked state, exact Godot hash, absent unique result root, validated argument vector, durable CreateNew launch intent, and the unchanged resource/time stop-loss.
- Unique target output root `C:\Users\PUBLI\AppData\Local\Temp\r12cxr_r5_20261101_a1\scientific-05` remains absent as of this correction.
- The pretarget bundle containing both no-launch guard records is hash indexed under the path above. Original R3/R4 evidence and the earlier pretarget bundle remain unchanged.

After this checkpoint is pushed and the live PR identities are rechecked, run the corrected dispatcher exactly once. If a valid enumeration marker occurs, never rerun. A zero-legal-triangle finite result remains PARTIAL and skips D3; it is not continuum exhaustion or structural infeasibility. If a legal graph appears, the existing D3 solver and the preregistered downstream sequence apply unchanged.

PR #217 remains open/draft/unmerged on the R5 branch; PR #216 remains unchanged/open/draft/unmerged. No production change, save access, schema change, merge, release, or F2-G1 operation occurred. All five F2-G1 holds remain unchanged.
