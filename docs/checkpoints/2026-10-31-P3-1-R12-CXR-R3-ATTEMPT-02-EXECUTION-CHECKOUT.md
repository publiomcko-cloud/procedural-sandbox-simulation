# P3.1 R12-CXR R3 Attempt 02 Execution Checkout Addendum

Date: 2026-10-31

This addendum supersedes only the prospective execution-checkout-head field in the [dispatcher freeze](2026-10-31-P3-1-R12-CXR-R3-ATTEMPT-02-DISPATCHER-FROZEN.md). That checkpoint recorded `e289340bce273234e3722aa87089b2ce38487fc8` before the dispatcher/control artifacts were committed. The code measured for the target remains the exact source commit `fdab3b8f16b615077aa44a7901b9555aebd3d80d`; the follow-on commits add evidence/checkpoint files only. The launch dispatcher verifies byte-identical campaign, realizer, and contract-test paths against that source with `git diff --quiet` immediately before process creation.

At launch, the dispatcher will record the then-current execution checkout HEAD in both the durable launch intent and process-start record. Its source check requires byte-identical campaign, realizer, and contract-test paths to the frozen source; the operator's immediate prelaunch gate additionally verifies a clean tracked worktree, expected repository origin, frozen inputs, and binary. The campaign receives `R12CXR_SOURCE_SHA=fdab3b8f16b615077aa44a7901b9555aebd3d80d`, not the documentation-only execution-checkout HEAD. Any failed identity check prevents reservation/process creation. This is an evidence-only execution-checkout adjustment; no executable input, threshold, fixture, or acceptance criterion changed.

Target `R9.2.SEAM.XPLUS_EQUAL.v1`, attempt `R3_TARGET_20261031_02`, remains NOT_STARTED at this checkpoint. All five F2-G1 holds remain unchanged.
