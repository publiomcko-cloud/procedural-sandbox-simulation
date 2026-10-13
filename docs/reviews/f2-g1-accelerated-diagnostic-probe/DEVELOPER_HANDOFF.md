# Developer handoff

Status: READY_FOR_INDEPENDENT_REVIEW

Ticket / acceptance criteria: Issue #48; accelerated read-only historical candidate-manifest diagnostic probe.
Repository / remote: `publiomcko-cloud/procedural-sandbox-simulation`; `https://github.com/publiomcko-cloud/procedural-sandbox-simulation.git`.
Worktree / branch: `C:\Dev\f2-g1-accelerated-diagnostic-probe-source`; `feat/f2-g1-accelerated-diagnostic-probe-issue48`.
Base SHA: PR #67 HEAD `d9a0ffa18e54716dbc8dac577ce2c2979e961a9a`.
Implementation commit: `dfc715b7a758a49876c5d27d2e7339c2b8ac5313` (parent `fcea89928d3c24b0714c274ca6007522cee02fa2`). The final evidence-publication commit is the immutable draft PR head recorded by GitHub; a commit cannot contain its own SHA.
Parent SHA: `fcea89928d3c24b0714c274ca6007522cee02fa2` for the SID-free fixture correction; the implementation branch is based on PR #67 HEAD `d9a0ffa18e54716dbc8dac577ce2c2979e961a9a`.
Changed paths: `.gitattributes`; `.github/workflows/f2-acl-source-only.yml`; `scripts/f2-acl/F2HistoricalManifestDiagnostic.psm1`; `scripts/f2-acl/Invoke-F2HistoricalManifestDiagnostic.ps1`; `scripts/f2-acl/Test-F2HistoricalManifestDiagnostic.ps1`; `docs/reviews/f2-g1-accelerated-diagnostic-probe/**`.

## Implementation summary

The new probe verifies and parses pinned historical source/candidate bytes, reconstructs the old generated child body, then executes only the actual historical parser call and `ReviewedCommitSha` comparison under Windows PowerShell 5.1 StrictMode. It emits a bounded sanitized record and never invokes update, recovery, or transaction entrypoints. Full pin and result details are in `evidence/SOURCE_PROVENANCE.md` and the adjacent test records.

Architectural impact: adds a separate diagnostic-only PowerShell module and fixed-path wrapper. No runtime package/API or protected installation behavior changes.
Dependencies added / licenses: none.

## Tests executed

Exact command form for every regression:

```powershell
powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\scripts\f2-acl\Test-F2AclCapture.Protocol.ps1
```

The same command form was run for all eight suites in `evidence/WINDOWS_PS51_REGRESSION.txt`, substituting each recorded filename. Results: 593 assertions, 0 failures; PowerShell parser: 24 files, 0 errors. The actual probe no-argument run exited 0; the unexpected-argument run exited 1 with its safe JSON result. `git diff --check` and Windows CI results are linked from the final draft PR checks and included in the evidence package.

Tests not executed: no elevated-token execution, live protected-state inspection, actual historical updater, live `icacls`, VM/Hyper-V/storage query, or native F2 workload. Two optional legacy scripts were attempted and failed for stale/unrelated expectations; see `evidence/WINDOWS_PS51_REGRESSION.txt`.

Failure/recovery cases: source/module/candidate tamper, bad module/candidate input, malformed JSON, missing required identity, wrong commit, unlisted exception id, unsafe AST, unexpected runtime argument, and child-process output are exercised. No recovery path is present.

Benchmark machine and metrics: not applicable.
Known limitations: the original elevated incident remains unexplained. Standard-token behavior is verified; elevated-token execution semantics remain unverified. Probe output is non-authoritative.
Visual reproduction steps: not applicable.
Rollback instructions: this is a separate draft branch/PR; close the draft without merging to discard the candidate. No existing branch or PR was changed.
Reviewer focus / open questions: verify historical AST extraction is exact and non-executable outside the two allowed statements; verify hash/filter lineage; review the documented residual uncertainty and optional legacy test failures.
