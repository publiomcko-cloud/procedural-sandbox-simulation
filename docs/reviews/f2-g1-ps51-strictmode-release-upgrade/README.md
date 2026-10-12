# F2 G1 PS 5.1 StrictMode correction and protected-release upgrade review

Status: **source correction ready for independent review; protected upgrade not authorized or executed**.

## Scope and lineage

This review corrects the confirmed Windows PowerShell 5.1 StrictMode argument-guard failure in the F2 G1 launcher and protected coordinator. It does not alter the accepted production checkout, installed protected package, retained baseline, ACLs, VM, or G: volume.

The source correction is commit `e5a66a7558c027e54b1510e7197d6e3a331cff19`, parent `bd14a1908085065f08d3c62e4dd17fa3203a53ff`, on `fix/f2-g1-ps51-entrypoint-release`. The parent is the reviewed PR #53 release line; the original installed release remains the historical baseline. A candidate external v2 release manifest for the corrected source is included here. It is review evidence, not an installed or externally trusted manifest.

The confirmed defect was direct access to `$args.Count` under `Set-StrictMode -Version Latest`, before the scripts' protected error handling. Windows PowerShell 5.1 raised `VariableIsUndefined` on the launcher's zero-argument path and the coordinator's valid named `-CaptureId` path. The corrected entrypoints inspect `@($MyInvocation.UnboundArguments)` inside their protected `try/catch` blocks and reject unexpected arguments with controlled nonzero exit codes. The coordinator continues to require the exact installed path and one valid 32-character lowercase hexadecimal CaptureId. StrictMode and all downstream identity, Administrator, source, release, and fail-closed checks remain in place.

The synthetic tests execute temporary inert entrypoint fixtures, not either production entrypoint. No actual production launcher/coordinator, UAC, protected installation, live ACL command, VM, G: path, or native workload was executed or queried.

## Changed source paths

The production source correction commit changes exactly:

| Path | Purpose |
|---|---|
| `.github/workflows/f2-acl-source-only.yml` | Run the PS 5.1 StrictMode regression test in Windows CI; omit the obsolete create-only installer suite, whose pins belong to the superseded release. |
| `scripts/f2-acl/F2_ICACLS_SOURCE_PINS.json` | Refresh only the launcher and coordinator pins. |
| `scripts/f2-acl/Invoke-F2IcaclsCapture.ps1` | Use the protected PS 5.1-safe unbound-argument guard. |
| `scripts/f2-acl/Invoke-F2IcaclsProtectedCoordinator.ps1` | Use the protected PS 5.1-safe guard while retaining installed-path and CaptureId validation. |
| `scripts/f2-acl/Test-F2AclIcacls.Runtime.ps1` | Replace live-entrypoint invocation with source-contract assertions. |
| `scripts/f2-acl/Test-F2AclEntrypointArguments.ps1` | New bounded Windows PowerShell 5.1 synthetic invocation regression suite. |

The protocol, corroboration, runtime production module, collector, installer, baseline files and protected installation were not modified. Historical `ReviewedCollectorBaseSha` remains `a62773f0553dff4a05055b18fa10834f7488ae55`; that field identifies collector provenance, not the current package commit.

## StrictMode reproduction and regression

`validation-ps51.log.txt` records the inert reproduction and complete post-change suites. The baseline reproductions observed:

| Synthetic invocation | Before correction | After correction |
|---|---|---|
| Launcher, zero args | Exit 1, `VariableIsUndefined` from `$args.Count` | Exit 0; fixture body reached |
| Launcher, extra positional or named arg | Rejected during parameter binding; process status was not a reliable body-level contract | Exit 2, controlled `RuntimeArgumentsRejected` |
| Coordinator, valid named CaptureId | Exit 1, `VariableIsUndefined` from `$args.Count` | Exit 0; fixture body received the CaptureId |
| Coordinator, extra positional or named arg | Pre-body rejection | Exit 2, controlled `CoordinatorArgumentsRejected` |
| Coordinator, invalid or missing CaptureId | Rejected before reliable protected handling | Exit 2, controlled `CoordinatorCaptureIdRejected` |
| Coordinator at a non-installed path | Path gate rejects | Exit 2, controlled `ProtectedCoordinatorPathRejected` |

The 18-assertion focused suite additionally checks production script parsing, StrictMode, guard placement, no parameter-binder surface expansion, preserved installed-path enforcement, and the fixtures' process results. It creates and removes only its own temporary files with bounded process waits.

## Release hash dependency chain

Hashes below are full SHA-256 values over the Windows checkout bytes used by the PowerShell package verifier. The external release manifest separately pins commit `e5a66a7558c027e54b1510e7197d6e3a331cff19` and `F2_ICACLS_SOURCE_PINS.json`.

| Seven-file package member | SHA-256 |
|---|---|
| `F2AclCapture.Protocol.psm1` | `42ba4dd5e31d1db64198bb1cee16d519f087a40364dfb4d2696b4a5bd844d728` |
| `F2AclIcacls.Corroboration.psm1` | `a52ed86218a0ba0c0801ee6e84a4a5e47c73eda43db78f818b0b12670ad5110b` |
| `F2AclIcacls.Runtime.psm1` | `950b8232be2f22412e837d63f7b2fb678fc83871862b6bafc714d303599a71a5` |
| `Invoke-F2IcaclsCapture.ps1` | `0b9214c3d6f6e96081b9d86aa8d62087c82527443f2c4b3e7ee09a1ca3dae818` |
| `Invoke-F2IcaclsProtectedCoordinator.ps1` | `e965823752518edfcac7ed50bd49bf489f6d924fa404e41138266857ea41b624` |
| `F2_ICACLS_SOURCE_PINS.json` | `0caa7a421a190f11351abadb2f78e3569f1287a1b38f09d62932a0caa8c3b5bb` |
| `Invoke-F2AclReadOnlyCapture.ps1` | `bea7cc93710c83d48a8ef9e54af306401694f17f611e696caa856938ca71a19b` |

`approved-release-v2-candidate.json` has SHA-256 `8ef5920f3c3c3c789b0c9af7314843437dbb57741ad29f78d57beabb43050d96`. Its schema is `f2-icacls-runtime-release-v2`; it binds source commit `e5a66a7558c027e54b1510e7197d6e3a331cff19`, pin manifest SHA `0caa7a421a190f11351abadb2f78e3569f1287a1b38f09d62932a0caa8c3b5bb`, and the seven files above. The actual production disk-loading and source-package validation functions loaded this temporary manifest from disk against a clean checkout of that exact commit; the logged result is `Pass=true`. This candidate JSON is not yet the externally anchored installed release manifest and is not an installation authorization.

The two baseline identities and their immutable digests remain unchanged:

| Identity/evidence | Pinned value |
|---|---|
| Protected mailbox ID | `ecb6deeb424e40feb5354d18908986df` |
| Payload CaptureId | `489e7fec-0300-467c-bfbd-a46fb8cf7211` |
| Payload SHA-256 | `1b5eee9aae928a909d4c251a4dd6d2c0898c400e2807e0acc3268d61d5149014` |
| Integrity-file SHA-256 | `02d6f07f5b3bb6f47a84e58d7c207c9935481e8a898a3b1f5e1ed273d4d61b34` |

## Validation evidence

`validation-ps51.log.txt` contains full console output, test commands, each suite's assertion count and exit status, the parser summary, and `git diff --check` status. `parser-ps51.log.txt` independently runs the tracked-file parser using Windows PowerShell 5.1. `candidate-manifest-validation-ps51.log.txt` records production disk-loader/source-package verification using the exact candidate manifest. Environment: Windows PowerShell `5.1.22621.6133`.

| Suite/check | Result |
|---|---:|
| `Test-F2AclEntrypointArguments.ps1` | 18 assertions, 0 failures, exit 0 |
| `Test-F2AclCapture.Protocol.ps1` | 152 assertions, 0 failures, exit 0 |
| `Test-F2AclIcacls.Corroboration.ps1` | 118 assertions, 0 failures, exit 0 |
| `Test-F2AclIcacls.Runtime.ps1` | 37 assertions, 0 failures, exit 0 |
| Total | 325 assertions, 0 failures |
| PowerShell parser | 10 tracked scripts/modules, 0 errors |
| `git diff --check bd14a1908085065f08d3c62e4dd17fa3203a53ff...e5a66a7558c027e54b1510e7197d6e3a331cff19` | exit 0 |
| Production runtime module loading temporary candidate v2 manifest from disk; source mode against clean exact source checkout | 7 files, `Pass=true`, exit 0 |

The workflow runs all four suites and the parser with Windows PowerShell on `windows-latest`. The legacy installer synthetic test was run once before being excluded from candidate CI; it failed at its own Preflight with `INSTALL_OPERATION_FAILED` because that historical create-only installer has pins for the superseded package. The complete output and process result are retained in `legacy-create-only-installer-synthetic.log.txt`. It used a synthetic temporary fixture and wrote no protected paths. The old installer and test remain unchanged and are not an upgrade mechanism. This failure is documented rather than represented as a passing current-release test.

## Protected-release upgrade proposal (design only)

### Old accepted release and proposed new release

The accepted installed release is source commit `5741ffe90a3abd02a08563e6431e8a0b9b63eeb1`, with external v2 release-manifest SHA-256 `b5f01570cf8937324f0c763f72a8d05b5532472156d4e5b0fcfbd180dc7abbe9` and pin-manifest SHA-256 `bd0a66a5e81494acaa14facb48b58e4c485acda1c17ead4fdfff220bcef97cd7`. Its accepted installation receipt records launcher SHA-256 `fb55240a16f0858980bb38851414b28ce5f403ba26697ff78f227ca22ff804b0` and coordinator SHA-256 `3badc19c8ac6ac450f9691258c6ecd2a3754cd665fd5989325c90b64290ae9e2`; the unchanged package file hashes are listed in the candidate release-pin documents. The new candidate is the seven-file package and manifest described above, at source commit e5a66a.

Both releases use fixed active roots (`C:\Program Files\F2-G1-Icacls\scripts\f2-acl` and `C:\ProgramData\F2-G1-Icacls\approved-release.json`). The runtime has no active-release pointer or side-by-side selection contract.

### Option comparison and selection

| Option | Benefit | Limitation/risk | Disposition |
|---|---|---|---|
| Side-by-side active release roots | Preserves old bytes and enables clean staging; straightforward rollback | Requires a reviewed runtime path-selection/activation mechanism and new trust-anchor behavior, outside this correction | Safest long-term architecture but not feasible without redesign |
| Controlled same-path upgrade using immutable sibling staging and backups | Keeps current fixed runtime paths and permits full new-package verification before activation | Multiple directory renames cannot form one filesystem-wide atomic transaction; crash may temporarily leave a missing/mixed active release | **Recommended minimal feasible design**, only with a separately reviewed updater, transaction journal, fail-closed runtime checks and no deletion of backups |

### Required updater transaction and recovery contract

No updater or executable command is implemented here. A future dedicated updater must be separately source-reviewed and pinned, then explicitly authorized before execution. It must:

1. Verify exact old release manifest, source/pin identities, all old file hashes, current Administrator owner and protected three-ACE DACL classifications, canonical paths, no reparse points, safe parent ACLs, and absence of active collector/coordinator processes. Any mismatch stops before writes.
2. Verify all new package source hashes and the externally anchored new release manifest before creating anything. Use unpredictable create-new sibling staging and backup names under the existing Program Files and ProgramData parents. Never use the old create-only installer; it refuses occupied destinations.
3. Build and verify the complete new package in protected staging. Apply only the already-reviewed protected owner/DACL contract to new objects. Do not modify root/parent ACLs, existing unrelated files, G:, or requester baseline data.
4. Write a protected transaction journal with a random transaction ID, exact old/new manifest digests, exact canonical paths, completed rename state, and integrity digest. The journal is diagnostic/recovery input, not success proof.
5. Activate via checked same-volume directory renames. Program Files package and ProgramData release manifest are separate paths, so the sequence is not atomically paired. Between renames or after a crash, the existing runtime's source/hash/schema checks must fail closed before UAC or ACL reads. A missing/mixed state is outage, not success.
6. Retain old backups. Independently verify all active directories/files/manifest, exact hashes and pins, Administrator ownership, protected DACLs, no reparse points, journal state, and absence of incomplete stages. Success requires full external attestation.
7. On any failure, do not delete or overwrite unexpected state. A separately reviewed recovery mode may restore only the exact validated old backups through checked renames; if identities or paths differ, quarantine and stop for owner review. Never broaden ACLs or automatically clean partial artifacts.

Minimal eventual elevated write scope: create-new staging, immutable backup and journal objects as direct children beneath the already-approved package/release parents; checked same-volume renames for the exact two active roots; no parent/root ACL change, no unrelated writes, no ACL relaxation. One ordinary human-consented UAC maximum. The future installer must refuse a different effective Administrator SID if the requester/ACL contract requires the original identity.

### Threat model and remaining unknowns

The transaction addresses tampered source, occupied paths, reparse/path alias substitution, unsafe or drifted ACLs, package/manifest mix-and-match, concurrent active process use, partial writes, interruption between renames, forged journal claims, and untrusted partial diagnostic output. Each gate is fail-closed; the journal and child JSON cannot establish success by themselves.

No elevated owner/DACL/readability state, rename behavior under actual Windows sharing/antivirus conditions, or crash-recovery behavior has been newly tested. Those are privileged/runtime-only unknowns. Independent post-upgrade filesystem attestation remains authoritative. The accepted old release is untouched.

### Proposed command status

There is **no executable upgrade command** in this review. The previous reviewed command invokes the old create-only installer and is explicitly unsafe for occupied destinations. A future command may take this shape only after a separately reviewed updater exists and its hash is pinned:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\Dev\f2-g1-protected-install-prep\Invoke-F2VerifiedUpgrade.ps1" -ExpectedUpgradeSha256 <independently-reviewed-full-sha256>
```

This is a non-runnable placeholder, not approval to create or execute that file. The next implementation/review must publish the complete updater, its tests, exact command, pins, failure recovery and CI; then a fresh owner authorization is required. No UAC or protected update occurred for this PR.

## Explicit remaining gates

- Independent review of this immutable source correction, candidate manifest, evidence and upgrade design.
- Fresh explicit owner approval before any protected-release updater is installed or executed.
- Separate authorization and independent review for live ACL corroboration; this source correction does not perform that collection or accept the ACL baseline.
- The production source worktree and installed release remain unchanged until those gates pass.

## Developer handoff

- Branch: `fix/f2-g1-ps51-entrypoint-release`
- Production source correction commit: `e5a66a7558c027e54b1510e7197d6e3a331cff19`
- Parent: `bd14a1908085065f08d3c62e4dd17fa3203a53ff`
- Review artifacts: this directory; candidate release manifest hash `8ef5920f3c3c3c789b0c9af7314843437dbb57741ad29f78d57beabb43050d96`
- Commands/results: see `validation-ps51.log.txt`; exact test commands and exits included.
- Risk/limitation: no privileged installation, UAC, live ACL or runtime verification was performed; future same-path updater is not implemented.
- Visual test steps: not applicable; no visual product change.
- Completion state: **READY_FOR_INDEPENDENT_REVIEW** of the source correction and design only.
