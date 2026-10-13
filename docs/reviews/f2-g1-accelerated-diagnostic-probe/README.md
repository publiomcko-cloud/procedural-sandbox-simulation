# F2 G1 historical manifest diagnostic probe

Status: source-only candidate for independent review. No elevation or protected-host operation was performed.

## Purpose and finding

The probe reconstructs the historical `CandidateManifestValidation` operation from the exact approved historical source and candidate bytes. It executes only the historical manifest parser and the following `ReviewedCommitSha` comparison under Windows PowerShell 5.1 `StrictMode Latest`.

On the exact historical candidate, the parser accepts schema v3 and the comparison accepts `ReviewedCommitSha=396c44965c90c08292ad2835f8317e81b6b9daaf`. The local standard-token run therefore does **not** reproduce the elevated incident failure. The original child PID 43072 report remains `CandidateManifestValidation / UPDATE_UNCLASSIFIED_FAILURE`; the internal exception and exact failing operation remain unknown. A separate synthetic candidate missing `BaselineMailboxId` reproduces `PropertyNotFoundStrict` under StrictMode, but there is no evidence that the historical candidate used by the elevated child was missing that property. It is not attributed as the incident cause.

The probe is a diagnostic, not an updater, recovery tool, or success attestation. A `PASS` means only that the pinned historical parser and commit comparison passed in the token context shown in the record.

## Pinned inputs

| Input | Immutable identity | SHA-256 of Windows checkout bytes |
| --- | --- | --- |
| Historical production source commit | `396c44965c90c08292ad2835f8317e81b6b9daaf` | — |
| Historical source parent | `f58b7fdfaf71e212213d559480e1913ae6c210f8` | — |
| Historical updater | `scripts/f2-acl/Invoke-F2ProtectedReleaseUpdate.ps1` | `d9572f7ea113ab01eaa4c6ab98d0852ce9549642b083719f68c01f02b2a81bb2` |
| Historical launcher | `scripts/f2-acl/Start-F2ProtectedReleaseUpdate.ps1` | `9fc4d574eda4a03ee05bca5ce789bdb10ee0b05f5f6de273839ba0060445bdc9` |
| Historical diagnostics protocol | `scripts/f2-acl/F2ProtectedRelease.Diagnostics.ps1` | `66466fd15ce161fe2b522c77cfd6500845012480fc64890aa8435f54197eedc7` |
| Historical candidate checkout | `7f99bc10f3e2258d2340cea4e7ba1352022cbb6d` | — |
| Historical candidate manifest | `docs/reviews/f2-g1-protected-release-updater/f2-runtime-release-v3.candidate.json` | `b8596905f42ee429ae2fd3352f9133de8bd4f00da654f856012c02390661f022` |
| Review base | PR #67 HEAD `d9a0ffa18e54716dbc8dac577ce2c2979e961a9a` | — |

The test verifies Git ancestry and hashes the Windows-filtered Git-object bytes before parsing. The candidate is read from its separate historical candidate checkout, not from the historical production SourceRoot's later review copy.

## Execution design

```mermaid
sequenceDiagram
    participant T as Standard or already-elevated token
    participant P as Fixed-path probe
    participant M as Hash-pinned diagnostic module
    participant H as Historical source and candidate bytes
    T->>P: Start probe directly; no RunAs path exists
    P->>H: Read only fixed C:\Dev inputs
    P->>P: Check fixed hashes, size bounds, canonical paths, reparse ancestors
    P->>M: Load exact verified module bytes in memory
    M->>H: Parse pinned updater/launcher AST and hash helpers
    M->>M: Allowlist helper AST commands and methods
    M->>M: Extract actual historical child builder output
    M->>M: Execute only exact parser and commit-comparison statements
    M-->>T: Bounded sanitized JSON and process status
```

The wrapper has no parameters. It rejects unexpected arguments inside its protected reporting path. It does not initiate UAC or spawn a child process. It reads only fixed `C:\Dev` source/candidate inputs, verifies their hashes, and loads the module from the exact bytes it hashed. The module API accepts byte arrays and a token classification; it does not accept a runtime path or transaction command.

The module verifies and parses the historical source AST instead of dot-sourcing the full updater or launcher. It extracts the historical manifest/hash helper definitions and historical child-script builder, validates their command and method allowlists, invokes the builder to produce the same encoded child-body text, parses that text, and selects the two exact candidate-manifest statements. Exact statement matching prevents adjacent transaction statements from being selected. Only those parser and comparison statements execute under StrictMode.

## Sanitized result contract

The JSON record is bounded to 4096 bytes and contains a fixed schema, `NON_AUTHORITATIVE_DIAGNOSTIC_ONLY`, status, fixed stage and operation classification, allowlisted exception category, sanitized `FullyQualifiedErrorId`, stable error code, token class (`STANDARD` or `ELEVATED`), pinned public hashes/commit, and Boolean flags stating the updater, recovery, and protected-write paths were not invoked.

Raw exception messages/types, source paths, SIDs, SDDL, credentials, environment values, baseline contents, and arbitrary FullyQualifiedErrorId values are never emitted. Unknown identifiers normalize to `UNLISTED`. The elevated label test is a synthetic input to the module; no elevated token was used.

## Run the source-only checks

From this repository checkout, under Windows PowerShell 5.1:

```powershell
powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\scripts\f2-acl\Test-F2HistoricalManifestDiagnostic.ps1
powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\scripts\f2-acl\Invoke-F2HistoricalManifestDiagnostic.ps1
```

The first command is synthetic and verifies the historical source and candidate using Git objects. The second runs the fixed-path read-only probe under the current token. Do not add arguments. This review package does not provide an elevated launch command. Any future elevated probe run needs its own independent review and explicit authorization.

## Validation

Windows PowerShell 5.1 `5.1.22621.6133` results are recorded in `evidence/WINDOWS_PS51_REGRESSION.txt` with complete suite stdout/stderr files. The required PR-workflow suites total 593 assertions with zero failures; the new probe suite contributes 40. The suite list, per-test process exit codes, parser results, probe outputs, known auxiliary test failures, and CI run reference are recorded in `evidence/`.

The exact CI check must pass on the published immutable PR head. The final PR check page is the authoritative hosted-CI record.

## Security limits and unresolved facts

- The probe does not reproduce the reported elevated failure on the exact historical candidate under the standard token.
- It cannot prove the historical elevated process read the same candidate bytes, used the same PowerShell installation/module environment, or reached the same runtime call path.
- The diagnostic does not attest protected installed state and is not evidence of upgrade success.
- Elevated-token semantics were not executed or simulated as an OS token; only the fixed token-label input was tested.
- No UAC, protected files, ACLs, registry, `icacls`, VM, Hyper-V, `G:`, native F2 workload, recovery, rollback, or cleanup was touched.
- PR #67 and all other existing PRs remain unchanged and unmerged.
