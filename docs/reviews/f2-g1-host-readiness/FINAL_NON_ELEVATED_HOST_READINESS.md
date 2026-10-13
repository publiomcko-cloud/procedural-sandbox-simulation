# F2 G1 final non-elevated host-readiness assessment

**Disposition: BLOCKED_WITH_EVIDENCE**  
**Assessment date:** 2026-10-13  
**Scope:** Non-elevated, read-only host readiness for the PR #69 diagnostic launch. No UAC/RunAs launch, diagnostic execution, protected update, ACL change, VM/Hyper-V/G: action, native workload, or PR merge occurred.

## Immutable source references

- Repository: `publiomcko-cloud/procedural-sandbox-simulation`
- PR #69: [open, draft, unmerged](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/69)
- Reviewed PR #69 HEAD: `56a34d7899ba31b0d3fe6d3185435bc182ac453f`
- Executable implementation commit: `8c14cf97c9446e11b8afbd64196c3f4558d4c3c9`
- Implementation parent: `1f0ddfd26554f1302fc5815084d2adb3b24ea857`
- PR #68 base: `c3d1280f9905730eda8cff40865e8afbbb642367`
- Origin verified in checkout: `https://github.com/publiomcko-cloud/procedural-sandbox-simulation.git`
- Review branch: `feat/f2-g1-diagnostic-elevation-plan-issue48`
- Exact branch remote ref points to the reviewed HEAD; worktree was clean before and after the focused test.

## Fixed-path and source-pin gates

| Gate | Result | Evidence |
|---|---|---|
| Expected review checkout `C:\\Dev\\f2-g1-diagnostic-elevation-plan-review` | **FAIL** | Path absent. |
| Expected executable checkout `C:\\Dev\\f2-g1-diagnostic-launch-runtime` | **FAIL** | Path absent. |
| Available review checkout `C:\\Dev\\f2-g1-diagnostic-elevation-plan-source` | **PASS** | Canonical path; exact reviewed HEAD; clean; expected origin. This is not either required fixed path. |
| Expected implementation commit object | **PASS** | Commit `8c14cf97c9446e11b8afbd64196c3f4558d4c3c9` resolves and is the PR #69 HEAD parent. |
| Exact published command | **PASS as reviewed bytes / FAIL for current fixed-path readiness** | File is present only in the fallback review checkout. The encoded bootstrap binds to the absent review path, so the published command cannot currently be run from the documented setup without preparing that path. |
| Checkout-byte source manifest | **PASS** | 15 of 15 entries match actual Windows checkout-byte SHA-256 values. Manifest file SHA-256: `742d55ad06bc12da80f834f29c3d5a86fc1f3fefbde5775fb3ee4b391aa42f69`. |
| Command size and CMD quoting | **PASS** | `EXACT_UAC_COMMAND.txt`: 4,683 characters excluding final newline; <= 8,191; no CMD metacharacters in the line. SHA-256: `1f1d4f51025b853bc571728258ae220cb689be97bf7c7355a0094393c113706a`. It was not executed. |

### Reviewed checkout-byte manifest (all 15 entries PASS)

| File | SHA-256 |
|---|---|
| `.gitattributes` | `9f854725b234ef50f87beee3b2ddc8ce410c3da3ba82857b39d19faeb8f676fa` |
| `.github/workflows/f2-acl-source-only.yml` | `4649f99d7babc88664a15307c50b9e23df7fc831ab2621944d7d6cf96f069d6d` |
| `docs/reviews/f2-g1-elevated-diagnostic-launch/CMD_ENTRY_BOOTSTRAP.ps1` | `436aecdab7c4baaa7f80d93c95f2d15257f366e4a83beff78e3ae4753c993156` |
| `docs/reviews/f2-g1-elevated-diagnostic-launch/OUTER_BOOTSTRAP.ps1` | `e1eea999392510d05ea69578377d8476e70ba4df3ed152417cecef55c3acf6a9` |
| `docs/reviews/f2-g1-elevated-diagnostic-launch/README.md` | `eab4950d6b4f837febbea6d5d13d7e21bba9c6a532c59f2b91aa81f29c5f34c7` |
| `docs/reviews/f2-g1-elevated-diagnostic-launch/SECURITY_BOUNDARIES.md` | `d492c10a693ae3ffd6df5062d793731d4f9f2515142aaa06a3d7f480bf29e3d4` |
| `docs/reviews/f2-g1-elevated-diagnostic-launch/DEVELOPER_HANDOFF.md` | `b7afbf78c3d702aa489ea91c1f9938adae47c572e5e08548b8c3d110cbcd4053` |
| `docs/reviews/f2-g1-elevated-diagnostic-launch/VALIDATION_RESULTS.md` | `690facd2714c1d5f99efac369cacf6a9ac071e567d258e48f05d70c250bb9608` |
| `docs/reviews/f2-g1-elevated-diagnostic-launch/EXACT_UAC_COMMAND.txt` | `1f1d4f51025b853bc571728258ae220cb689be97bf7c7355a0094393c113706a` |
| `docs/reviews/f2-g1-elevated-diagnostic-launch/TEST_RUN_RESULTS.log` | `daca2fa696682451ffd33d0152610aaf43ba5f8f1ea2e9b06307e7b431bb5677` |
| `scripts/f2-acl/Invoke-F2HistoricalManifestDiagnostic.ps1` | `99505626679c75511e16d524c39dfd0ff0cbd27b3a0bd36d631cbadf2c1c9536` |
| `scripts/f2-acl/F2HistoricalManifestLaunch.psm1` | `06f117c6be29e3e150149087cb19323e83df20601b8d134f0bb02ec7335867d2` |
| `scripts/f2-acl/Invoke-F2HistoricalManifestDiagnosticChild.ps1` | `78c8ea2a51d3eece2914ea87f18b46186f604a357671fb0607393801bca5609e` |
| `scripts/f2-acl/Start-F2HistoricalManifestDiagnostic.ps1` | `48b3f12dbc784e593a4ee5b468b3f005e6b6e1a53b1c09d542d0bfc2f9cdd83a` |
| `scripts/f2-acl/Test-F2HistoricalManifestLaunch.ps1` | `ff81e288eb12e52b6b77f2c6977f1b823ad70c293bb852e3cd9d0e84806db11b` |

The module's embedded wrapper pin matches the wrapper hash above. The outer bootstrap's implementation-commit, launch-module, and launcher pins match the verified commit and checkout-byte manifest. The child script's module and wrapper pins, and the standard launcher’s wrapper and child pins, also match. Historical parser/runtime/baseline source pins were not changed.

## Child command-line observation

The focused Windows PowerShell 5.1 suite was run:

```
powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\scripts\f2-acl\Test-F2HistoricalManifestLaunch.ps1
```

Result: **128 assertions, 0 failures, exit code 0**. The suite executes the production child-command builder through a harmless same-token ShellExecute fixture and checks a synthetic command-line record.

The production validator queries `Win32_Process` and expects the actual command line to be exactly shaped as:

```
"<SystemRoot>\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand <exact-base64>
```

The requested live observation of the harmless child’s actual `Win32_Process.CommandLine` was **not obtained**: a one-off process-creation attempt was rejected by the command execution boundary before a child was created. No alternate launch path was attempted. Therefore the WMI representation-versus-validator comparison is **UNKNOWN**. Synthetic object tests and the successful ShellExecute fixture do not satisfy this host-observation gate.

## Pinned Git for Windows dependency assessment

Read-only inspection covered the pinned core executable, its local DLL dependencies, canonical paths, reparse status, signatures, version metadata, and applicable standard-user allow ACEs.

| Component | SHA-256 | Authenticode / version | Result |
|---|---|---|---|
| `mingw64\\bin\\git.exe` | `1a0043555d254618f2d56c936c3d9a1fbfb878bc878416a133c346bc7835eda9` | Valid signature; Git 2.55.0.windows.3; signer Johannes Schindelin | **PASS** |
| `libiconv-2.dll` | `7a282a854e01be726c6cccfe46f548c716aa45b3014818468253aaa4efbcd067` | Not signed; version 1.19; metadata says Free Software Foundation | **UNKNOWN provenance** |
| `libintl-8.dll` | `0537c3dd2378218508ebe3cc416d72a99ee2d24ae1c5525e23458f32544ef861` | Not signed; version 1.0; metadata says Free Software Foundation | **UNKNOWN provenance** |
| `libpcre2-8-0.dll` | `c135a87ed0f11eae8ffc4cb469671ff0b3f5d71fab5fb024e9b1e7241ca25b52` | Not signed; no publisher/version metadata | **UNKNOWN provenance** |
| `zlib1.dll` | `93e9243a44c29200eeacaf9658efe2558581770e4b11ca4b500e18e424a6e3b5` | Not signed; no publisher/version metadata | **UNKNOWN provenance** |

Static PE import inspection found these four local dependencies in Git's `mingw64\\bin`, with Windows API imports resolving from System32; no PE delay-import table was found. No separately verified Git for Windows package/catalog manifest was available to authenticate the unsigned DLLs. Their observed paths are under Program Files, have no reparse points, and the inspected DACLs show no applicable standard-user allow grant intersecting the write/control mask on Program Files, the Git directories, the core executable, or these DLLs. Program Files has a protected DACL; the C: root’s separate child-creation ACE does not appear in the Program Files DACL. This is a read-only ACE/path assessment, not a kernel effective-access evaluation or publisher proof. The four DLLs remain an explicit unresolved dependency trust boundary.

## Prior-attempt and live-process check

- This assessment did **not** invoke UAC, RunAs, the diagnostic, or its elevated child. UAC authorization remains **NOT GRANTED**.
- The accessible UAC Operational log has 25 retained records and zero matches for the diagnostic markers searched.
- Security process-creation event 4688 is **INACCESSIBLE** to the standard token. The accessible log and retention window cannot prove that no earlier attempt ever occurred; historical prior-attempt status is **UNKNOWN**.
- A current `Win32_Process` inventory found only the current PowerShell host; no other visible PowerShell-family process had a relevant diagnostic signature, and no visible process lacked a command line. This establishes no relevant visible child at assessment time, not the absence of an unobservable elevated process or a past attempt.

## Focused validation and limits

- Focused PS 5.1 test command above: **PASS**, 128 assertions, 0 failures, exit 0.
- All 15 committed checkout-byte manifest entries: **PASS**.
- PR #69 reports Windows CI run [38471926228](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/38471926228) passing on the exact reviewed HEAD; this assessment did not rerun CI or unrelated acceptance suites.
- PR #69 remains draft and unmerged. No repository source was modified by this assessment; test-created TEMP fixtures were handled by the test suite.

## Gate decision and stop conditions

This is **BLOCKED_WITH_EVIDENCE**, not authorization to run the command. The fixed-path check fails; actual WMI command-line comparison is incomplete; unsigned Git runtime DLL provenance and historical no-attempt status remain unknown.

Before any request for explicit owner authorization, the execution setup must be reconciled at the exact documented review and runtime paths without overwriting unknown files, the same-token fixture must capture and compare the real `Win32_Process.CommandLine`, and the dependency-provenance uncertainty must be independently resolved or accepted by a separate reviewer. Any mismatch requires a source correction and a new exact-SHA independent review.

No UAC, diagnostic launch, protected action, ACL modification, baseline change, VM/G: operation, or PR merge is authorized by this assessment.
