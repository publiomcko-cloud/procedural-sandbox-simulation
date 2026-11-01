# Developer handoff — P3.1 R12 CXR R6

## Identity

- Repository: `C:\Dev\sandbox-sim-dev`
- Topic branch: `exp/p3-1-r12-cxr-r6-realization-map-cavity`
- Candidate SHA: `836a2cd8e681dfb35f0bbaa5f1f55b1bfcc59b0f`
- Exact parent: `69648002dc961301cbf789107453a718a206ca64`
- R5 base observed: `64a14d7bc8ddf024933129767b6889146d4645c4` (open draft PR #217 at last check)
- Authorized tracking issue: #218
- Current disposition: R6-D finite causal search exhausted; review and owner GUI remain pending; issue remains open.
- Exact changed-path inventory relative to R5 base: [CHANGED-PATHS.txt](CHANGED-PATHS.txt).

## Summary and limits

R6-A through R6-D are implemented and exercised within the specified envelope; R6-E/F are implemented but gated. Four of five valid target attempts were consumed. The fifth valid run ended with `FINITE_CAUSAL_SEARCH_EXHAUSTED`, but no boundary-feasible cavity existed in the enumerated candidates. The evidence supports bounded fixture/search-policy exhaustion only, not global infeasibility. Do not continue to E/F or downstream gates from this result.

See [RESULTS.md](RESULTS.md) and [ATTEMPT-ACCOUNTING.md](ATTEMPT-ACCOUNTING.md) for outputs, limits, and the correction to R6-02 raw accounting. No raw evidence was modified to repair accounting.

## Godot 4.7.2 commands run

Executable: `C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe`  
Version: `4.7.2.stable.official.ed1daf0bf`  
Executable SHA-256: `c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643`

Commands ran sequentially with `--headless --path .`; each exited 0:

1. Cold editor import: `--headless --editor --path . --import --quit`.
2. R6-A audit in `check-only` mode: PASS.
3. R6 campaign in `check-only` mode: PASS.
4. R6 contract suite: 49 assertions, 0 failures.
5. R5 contract suite: 348 assertions, 0 failures.
6. CXR contract suite: 216 assertions, 0 failures.
7. Five R6-A audit exports and four valid target-search attempts (R6-02 to R6-05); R6-01 is a preserved pre-geometry tooling failure and not a valid attempt.

Exact script invocations and all target evidence are preserved in the report artifacts and attempt JSONs. Do not infer tests beyond this list.

## Not run / failing cases

- R6-01 failed before geometry because the R6 corrected zero-vertex inventory was compared with the raw frozen constructor inventory at `(0,0,4)`, tet 0. The tooling issue was corrected before R6-02; R6-01 consumed no target attempt.
- R6-02, R6-03, and R6-04 reached the configured wall-time bound and returned partial search results.
- R6-05 exhausted the finite causal candidate set with no feasible boundary witnesses. This is the terminal blocker.
- R6-E/F synthesis, equal-LOD gate, subsequent controls/rays/reconfirmation/mixed-LOD/repeat gates, full E2E, and `scripts/validate.ps1` were not run because the required D result was absent.
- No Godot GUI or owner visual acceptance was performed. No independent source review or merge was performed.

## Reproducible GUI steps for owner

After independent source review, open the project using Godot 4.7.2 from `C:\Dev\sandbox-sim-dev`, select the R6 realization-map cavity campaign scene/entry point documented by the R6 spec, and follow the exact visual/diagnostic checkpoints in `docs/specs/P3-1-R12-CXR-R6-REALIZATION-MAP-CAVITY.md`. Record the candidate SHA, scene/fixture, observed boundaries and diagnostics, and any failing case. A GUI PASS cannot override the bounded-search result or serve as merge authorization.

## Review gates

Independent source review is required on the exact SHA above. Owner GUI acceptance is still pending. The issue and any PR must remain open until the owner evaluates this handoff. No merge, release, runtime-protection, or global feasibility claim is authorized by this report.

BLOCKED_WITH_EVIDENCE