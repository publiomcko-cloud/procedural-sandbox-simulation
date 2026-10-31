# P3.1 R12-CXR R3 Prelaunch Fixture-Path Correction

Date: 2026-10-31

The R3 target remains **NOT_STARTED**. This checkpoint records one recoverable pre-scenario launcher failure after the R3 pre-target freeze; no geometry attempt was consumed.

## Exact failed step

On execution checkout `24c2497465eb6a455c0ba95be756664f95912df6` and frozen code source `64ce92c909c0b5871303a787baeba84e28477c77`, the frozen dispatcher `a452f1ce09125a2886881725b4edd9e8b97face06800050d09396be2c3267033` rejected its supplied Stage-0 path before writing a reservation or process-start intent. The mistakenly supplied file was the fixture generator script `game/tests/prototypes/p3_1_r12_c_stage0_fixture.gd`, SHA-256 `83da52c770a16c6fb89dc7708553b7e6df7276865cefb1e2065483cedd1be988`; it is not the frozen fixture data.

## Correction and non-consumption evidence

The correct immutable fixture is `docs/reports/P3-1-R12-CXR-R2-R3/evidence/r2_attempt_01/r12c_stage0_topology_fixture.json`, SHA-256 `33e04446d25ec8dc21f6794b9509296e7ebcd575c2a8713edefd152f58e1cd0d`, exactly matching the source pin. The failed launch root was created uniquely and remained empty (zero files); there is no reservation, process-start intent, process PID, Godot stdout/stderr, or `R12CXR_TARGET_INVOCATION_BEGIN` marker. The target scenario and attempt ID `R3_TARGET_20261031_01` are therefore unconsumed and remain the one planned execution.

The complete transcribed preflight diagnostic, path/hash comparison, no-start facts, and two-file checksum index are retained in [`r3_prelaunch_recovery_01`](../reports/P3-1-R12-CXR-R2-R3/evidence/r3_prelaunch_recovery_01/). This was a host-side input-path error only; no project source, frozen contract, campaign input or acceptance criterion changed. The corrected argument will use the already pinned archived JSON fixture. The earlier pre-target freeze remains immutable and authoritative for the experiment's code, inputs, limits and gates.

Before the one-shot target, reverify origin, draft PR #213, current execution HEAD, the three frozen R3 source hashes, both fixture hashes, Godot binary identity, an empty unique result root, and at least 2 GiB free commit. Do not rerun R2, any contract suite, or any other geometry scenario as part of this correction. The five F2-G1 holds remain unchanged.
