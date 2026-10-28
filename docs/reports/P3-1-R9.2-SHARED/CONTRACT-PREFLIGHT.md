# P3.1 R9.2 shared contract preflight

**Scope:** test-only manifest and diagnostic helper validation. No A/B/C/D scenario or candidate mesh build was executed.

**Source:** `bench/p3-1-r9-2-preregistration`, common R9.2 parent `a60d38df4f96b9007162e8fd917b3d14f29dcb0f` (uncommitted preregistration at time of these local runs). **Manifest SHA-256:** `1610c535f98a11e26ca1890c0d99addf4316fbcaa7ec9cdb7dfaa71cf5bb3972`, independently matched to the sidecar. **Engine:** `4.7.2.stable.official.ed1daf0bf`; executable `C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe`; SHA-256 `c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643`.

## Attempts

| Attempt | Result | Evidence |
| --- | --- | --- |
| 01 | Failed before contract assertions: helper called `PackedByteArray.find()` with a byte-array needle; dependent script remained alive after parse/load failure and was interrupted. | `evidence/contract-preflight-01/attempt.md` is explicitly a tool-output transcript, not byte-exact process capture. |
| 02 | Passed the then-current 48-assertion suite after cold import; no candidate scenario. | Complete captures and process record under `evidence/contract-preflight-02/`. |
| 03 | Rejected despite process exit 0: a typed-inference parser error was logged and the required result marker was absent. The typed declaration was corrected. | Full captures under `evidence/contract-preflight-03/`. |
| 04 | Inconclusive process evidence: two concurrent Godot process pairs wrote to the same attempt directory. One marker reports 48 assertions/zero failures, but the per-process exit and attribution are unavailable. The exact headless processes were stopped after their identity was confirmed. | Raw shared output plus `process-observation.json` under `evidence/contract-preflight-04-duplicate/`; do not count as a passing gate. |
| 05 | **Passed cleanly.** Cold editor import exit 0 (7,899 ms); harness `--check-only` exit 0 (952 ms); contract suite exit 0 (908 ms), exactly one marker, 48 assertions, zero failures, expected manifest pin, empty stderr, no parser/runtime error. Each stage was run serially with a unique process record and isolated profile. | Complete stdout/stderr, per-stage process JSON, and `SHA256SUMS.txt` under `evidence/contract-preflight-05/`. |

## What the contract test proves

The suite checked physical manifest bytes and sidecar integrity, schema and unique IDs, 20 frozen rows, exact command-array byte digests, ordered canonical snapshots and revisions, the negative-X/Z variants, expansion of the 25 shared picker rays, the 12 explicitly specified CPU proxy rays, and the sampled-cave node limit. The finite-grid sample count is 8,075. The 48 assertion count is the observed marker count, not an inferred total.

## Limits and next step

This is L2 local engine/harness evidence for the shared test contract only. It does not establish candidate capability, topology, geometry quality, picker/collider parity, performance, or production eligibility. Candidate campaigns and full `scripts/validate.ps1` remain pending on each final candidate source. All R9 geometry and performance budgets remain experimental safety limits, not product acceptance limits. All five F2-G1 holds remain unchanged.
