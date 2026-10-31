# P3.1 R12-CXR R3 Attempt 02 Dispatcher Freeze

Date: 2026-10-31

## Frozen target identity

The corrected per-cavity source and finite search domain are frozen by the preceding [per-cavity pre-target checkpoint](2026-10-31-P3-1-R12-CXR-R3-PER-CAVITY-PRETARGET-FROZEN.md). This addendum freezes the one-shot launch mechanism before geometry starts. At this checkpoint, `R3_TARGET_20261031_02` remains `NOT_STARTED`.

- Repository: `https://github.com/publiomcko-cloud/procedural-sandbox-simulation.git`.
- Branch: `exp/p3-1-r12-cxr-per-cavity-continuation`.
- Execution checkout HEAD before launch: `e289340bce273234e3722aa87089b2ce38487fc8`.
- Measured code source: `fdab3b8f16b615077aa44a7901b9555aebd3d80d`; source parent: `121f499cf6c03daba0f24f907fd7a6dbeed59659`. The checkout differs from that code source only in documentation/evidence paths; all three pinned executable source paths are byte-identical.
- Draft PR #214 is stacked on open draft PR #213; neither is merged.
- Scenario: `R9.2.SEAM.XPLUS_EQUAL.v1`; phase `r3`; attempt `R3_TARGET_20261031_02`.
- Versioned dispatcher: [`r3_target_dispatcher.ps1`](../reports/P3-1-R12-CXR-R2-R3/evidence/r3_pretarget_02/r3_target_dispatcher.ps1), SHA-256 `da4c5e39cedd7e62388fedef6a1e9b9d308e2a2961dccf9759d11d3b94641033`.

## Dispatcher control and recoverable setup incidents

The dispatcher PowerShell parser reported zero errors. A controlled non-Godot child test passed with exit 0: child exit 23, exact stdout and stderr captured, duplicate reservation rejected, output overwrite rejected, no scenario marker, and start record written. Raw control artifacts are in [`dispatcher_control_02`](../reports/P3-1-R12-CXR-R2-R3/evidence/r3_pretarget_02/dispatcher_control_02/).

Two earlier setup failures are retained rather than erased: the first campaign `check-only` lacked its required environment and exited 2 before target start; the first dispatcher control wrapper put its own redirected logs inside the root required to be empty, and the dispatcher correctly refused it before any reservation or child. Corrected environment and corrected fresh-root control attempts passed. Both incidents are indexed in [`r3_pretarget_02`](../reports/P3-1-R12-CXR-R2-R3/evidence/r3_pretarget_02/evidence-sha256-index.txt). Neither incident launched Godot geometry.

## Launch safeguards and stop conditions

Immediately before process creation, the dispatcher re-verifies repository origin, execution HEAD, measured source SHA, exact hashes for the campaign/realizer/contracts, Stage-0 and residual fixtures, Godot executable hash, and at least 2 GiB free commit. It requires an initially empty unique target evidence directory and durably creates a reservation and launch intent before `Process.Start`. It captures the child PID immediately, drains stdout/stderr concurrently, writes no-overwrite outputs, applies a 45-second hard timeout, and never retries a process that may have started. Each target child receives unique `APPDATA`, `LOCALAPPDATA`, `TEMP`, and `TMP` paths.

The frozen target attempt is one-shot. A process-started state, target-start marker, timeout, incomplete evidence, any limit hit, invalid cavity boundary, or incomplete search is retained and cannot be relabeled as a finite no-solution result. Downstream gates may run only after equal-LOD passes every frozen topology, cutoff and volume invariant. No geometry process has been launched at this checkpoint.

The exact source/gate and dispatcher/control records, stdout/stderr, and SHA-256 inventory are preserved in [`r3_pretarget_02`](../reports/P3-1-R12-CXR-R2-R3/evidence/r3_pretarget_02/). No production code, schemas, saves, Issue #108/#154, PRs #207–#211, or F2-G1 state changed. All five F2-G1 holds remain.
