# F2 G1 protected release updater

**Status: SOURCE-ONLY; awaiting independent review. No protected upgrade has been run.**

PR #59 current review-package HEAD: `3a3383c6fd08b87dada4e3e4c1e9421657afba7c` (parent `8b70a70934445bee660c1e53e71b2e7b20a6191f`). The production SourceRoot remains the clean commit `8b70a70934445bee660c1e53e71b2e7b20a6191f` (parent `5d231f4697673569de526c03cedf61c72e769e07`); the follow-up commit adds only more actionable synthetic-test diagnostics. Windows checkout pins: updater `d26eb89a424e3f268099e0ac1d3ffd674dde1128321567df3a0702abb591f75e`; standard launcher `8278bbff8e5b7cdb313235bcc271fa31a947ca384d7496053650c3097af19720`; candidate v3 manifest `74d178917fba4f50fdca40505d8c1dc81639f3c60bbb25c0332fd737c681562c`. The seven installed release file hashes and `F2_ICACLS_SOURCE_PINS.json` remain byte-for-byte unchanged. The process map, exclusion rule, ordering proof, test cases, and limitations are in [F2_G1_PROCESS_QUIESCENCE_REVIEW.md](F2_G1_PROCESS_QUIESCENCE_REVIEW.md).

This package implements a one-time updater for the occupied F2 G1 installation. It uses a versioned package directory and a single external release-manifest replacement to switch the active release. It never reruns the historical create-only installer against occupied destinations.

## Reviewed lineage and fixed identities

- Upstream release-correction review: PR #58 review `5490189436`; accepted source correction `e5a66a7558c027e54b1510e7197d6e3a331cff19`.
- Updater branch base: PR #58 branch `fix/f2-g1-ps51-entrypoint-release`, commit `0a4d98ecad4c50ba2f749e4fafe6d28e35794804`.
- Corrected production source commit: `8b70a70934445bee660c1e53e71b2e7b20a6191f` (parent `5d231f4697673569de526c03cedf61c72e769e07`). This commit preserves the accepted `IntPtr.Zero` native-helper correction and adds the process-quiescence gate described below.
- The earlier source correction resolved PR #59 review `5492493517` / Issue #48 finding `6126813885`: it replaced the invalid C# `null` argument to a non-nullable `IntPtr` with `IntPtr.Zero` and added an exact-production-source native-helper regression. This follow-up resolves PR #59 review `5493067444` / Issue #48 finding `6127688692` by adding the process-quiescence policy and activation ordering below. The accepted native helper and its regression are unchanged.
- The seven release-package file hashes and their source-pin manifest are listed in `f2-runtime-release-v3.candidate.json`. The Windows checkout SHA-256 of `F2_ICACLS_SOURCE_PINS.json` is `7e05d48ef25e7cff19d84db151395921b5d89b52b1e2f45b94a84a4778a615ce`.
- Existing v2 release: source commit `5741ffe90a3abd02a08563e6431e8a0b9b63eeb1`; external manifest SHA-256 `b5f01570cf8937324f0c763f72a8d05b5532472156d4e5b0fcfbd180dc7abbe9`.
- Retained baseline mailbox ID `ecb6deeb424e40feb5354d18908986df`; payload `CaptureId` `489e7fec-0300-467c-bfbd-a46fb8cf7211`; payload SHA-256 `1b5eee9aae928a909d4c251a4dd6d2c0898c400e2807e0acc3268d61d5149014`; integrity SHA-256 `02d6f07f5b3bb6f47a84e58d7c207c9935481e8a898a3b1f5e1ed273d4d61b34`.

The seven-file candidate preserves both distinct baseline identities and all existing VM/storage scope checks. No raw ACL/SDDL, private SID or credentials are included in this review package.

## Executables and hash binding

The production source commit contains the complete updater and the standard-token launcher. `.gitattributes` specifies CRLF checkout bytes for PowerShell scripts. These are the hashes the future Windows launcher pins after a clean checkout with the repository's attributes applied:

| File | Windows checkout SHA-256 | LF Git content SHA-256 |
|---|---|---|
| `scripts/f2-acl/Invoke-F2ProtectedReleaseUpdate.ps1` | `d26eb89a424e3f268099e0ac1d3ffd674dde1128321567df3a0702abb591f75e` | Git-content digest recorded in `evidence/ARTIFACT_MANIFEST.md` |
| `scripts/f2-acl/Start-F2ProtectedReleaseUpdate.ps1` | `8278bbff8e5b7cdb313235bcc271fa31a947ca384d7496053650c3097af19720` | Git-content digest recorded in `evidence/ARTIFACT_MANIFEST.md` |
| `scripts/f2-acl/Test-F2AclProtectedReleaseUpdater.ps1` | `56c4ee4688a401d249ec67a65187b1dac762226ea7a2a582bf51b5c43c07c046` | Git-content digest recorded in `evidence/ARTIFACT_MANIFEST.md` |
| `scripts/f2-acl/Test-F2AclProtectedReleaseNativeHelper.ps1` | `5e899f1d2a763955e5db49b092570ea0fa2f9e7956722b7c039b326d4fbb507e` | `d250a1b3ad40f6f78be75dc135857f022ae3eef3b4202aa7988b8ea8d2b894f1` |
| `docs/reviews/f2-g1-protected-release-updater/f2-runtime-release-v3.candidate.json` | `74d178917fba4f50fdca40505d8c1dc81639f3c60bbb25c0332fd737c681562c` | `74d178917fba4f50fdca40505d8c1dc81639f3c60bbb25c0332fd737c681562c` |

The candidate JSON has a path-scoped `-text` attribute so its pinned bytes stay identical on Windows and GitHub. A detached Windows checkout of the production commit reproduced both Windows script hashes and verified the runtime/coordinator source pins. The outer future command separately hashes the standard-token bootstrap before dot-sourcing its in-memory bytes. The elevated child reads the updater and candidate once each, verifies each full SHA-256, and executes the exact verified updater byte sequence as a `ScriptBlock`; it does not reopen the updater as a script path.

The process-quiescence updater and launcher hashes were measured from the clean detached Windows source checkout at commit `8b70a70934445bee660c1e53e71b2e7b20a6191f`: updater 789/789 CRLF, launcher 141/141 CRLF, zero bare LF in each. The updater SHA-256 is `d26eb89a424e3f268099e0ac1d3ffd674dde1128321567df3a0702abb591f75e`; the launcher SHA-256 is `8278bbff8e5b7cdb313235bcc271fa31a947ca384d7496053650c3097af19720`. The measurement and the full source hash chain are in `evidence/WINDOWS_CRLF_HASH_VALIDATION.txt` and `evidence/ARTIFACT_MANIFEST.md`.

## Transaction and launch boundary

### Preconditions

The elevated updater performs all gates before creating transaction objects:

1. Same-user elevation: the standard launcher captures the original requester SID without printing it; the elevated child must be Administrator and have that exact SID. Alternate-account UAC credentials fail closed before protected writes.
2. Source provenance: exact clean Git origin and commit, no tracked/untracked changes, seven package byte hashes, source-pin manifest digest and each internal source pin.
3. Candidate: external full SHA-256, v3 schema, exact source commit, versioned package path, exact seven-file name set, baseline IDs and retained payload/integrity digests.
4. Installed v2 release: exact external manifest SHA and identity, seven old file hashes, original directories/files, owner and protected three-principal DACL profile, exact current child sets, and no reparse points.
5. Parent chain: fixed Program Files and ProgramData roots, safe current root/parent DACL classes, canonical C: paths, and no reparse points. Existing transaction, staging, version or backup objects outside the exact expected state block the update; none is overwritten.
6. Runtime launch exclusion: acquire an exclusive release lease and a delete-share-only handle on the active manifest, then inventory every `powershell.exe`, `powershell_ise.exe` and `pwsh.exe` process. Permit only the current elevated updater and exactly one requester process bound by PID, creation time, requester SID and the exact outer launcher/updater/candidate pins. Every other PowerShell process blocks, including direct module and encoded invocations. Repeat the inventory at the activation edge. The full path map and ordering proof are in `F2_G1_PROCESS_QUIESCENCE_REVIEW.md`.

The seven release hashes in the candidate and the current manifest/pins are checked before any protected staging path is created. The active old package remains at its existing path throughout; it is not rewritten.

### Fixed C: object layout

- Versioned package stage: `C:\Program Files\F2-G1-Icacls\releases\.f2-update-<32-hex-txid>.new`.
- Activated package: `C:\Program Files\F2-G1-Icacls\releases\<reviewed-source-commit>\scripts\f2-acl\`.
- Journal and candidate manifest: `C:\ProgramData\F2-G1-Icacls\updates\<txid>\transaction.ndjson` and `approved-release.new.json`.
- Retained old-manifest backup: `C:\ProgramData\F2-G1-Icacls\backups\<txid>.approved-release.v2.json`.
- Active pointer: `C:\ProgramData\F2-G1-Icacls\approved-release.json`.
- Lease: `C:\ProgramData\F2-G1-Icacls\release.lock`.

All names and roots are fixed in source; there are no arbitrary destination/path parameters. Newly created directories and files are create-new and receive their reviewed protected DACL at creation. The updater verifies each resulting owner/DACL. It does not change a parent ACL, use `Set-Acl`, invoke `icacls`, delete an object, or clear/replace an unknown path.

### Activation and mixed-release prevention

The complete seven-file tree is created under the transaction-specific staging directory, individually hash/DACL checked, then moved with a same-volume `Directory.Move` to its unique commit path. An existing commit path is a hard collision. Only after the package is complete does a same-volume `File.Replace` atomically replace the external v2 active manifest with the v3 candidate and retain the old manifest as the transaction backup.

Activation is not claimed atomic across Program Files and ProgramData: the package is first made complete and immutable side-by-side; the active manifest is the single switch. Before that switch the old manifest and untouched old files remain active. After it, the manifest names the already-verified versioned tree. The v2 runtime rejects v3 before UAC; the v3 runtime validates the installed seven-file package before UAC. The v3 runtime's shared lease and the updater's exclusive lease serialize v3 processes. The held manifest barrier denies new v2 reads. A v2 process that cached the old manifest before the barrier remains a live PowerShell process and blocks the inventory; if it spawns a coordinator later, that new coordinator cannot read the manifest. The updater inventories once after acquiring both handles and again immediately before `File.Replace`. No process is terminated. These guarantees cover the supported `powershell.exe`, `powershell_ise.exe` and `pwsh.exe` paths; arbitrary code hosting PowerShell or carrying a copied manifest is outside the supported interface and remains an explicit limitation.

The updater postchecks the new active manifest bytes and ACL, all seven activated file hashes, and the old manifest backup bytes/ACL while the held manifest handle still provides the original bytes. It retains the original fixed-path v2 files, the new immutable version directory, journal, and old-manifest backup. Nothing is automatically removed.

## Failure and bounded recovery contract

The journal is capped at 64 records and 256 KiB. Each record binds a transaction ID and previous-record SHA-256. Recovery accepts only the exact ordered ready-state prefix and the exact GUID-derived paths/children. It validates the old release, candidate bytes, source provenance, final version directory, seven hashes, DACLs, old-manifest backup, lease and process quiescence.

| Observed state | Permitted behavior |
|---|---|
| Old v2 manifest active; staging incomplete or journal incomplete | Report old active; preserve every object. Forward recovery rejects incomplete state. No rollback or cleanup. |
| Old v2 manifest active; final version package and candidate are complete; journal has the exact ready prefix | With a separate future authorization, recovery may finish forward by one atomic manifest replacement. It retains the v2 manifest backup and all transaction records. |
| New v3 manifest active; exact package, old backup, old fixed-path files and journal validate | Read-only `VERIFY_ONLY` result. No rewrite or cleanup. |
| Unknown/modified manifest, invalid DACL/owner, extra object, path/reparse mismatch, missing file, malformed/hash-chain/state journal, busy/unknown process or lock failure | Stop and preserve all evidence. No guessed rollback, overwrite, ACL relaxation or deletion. |

Recovery is not an automatic retry. `-ResumeForward` is separately explicit, transaction-ID constrained, still uses the same single human-consented UAC boundary, and must not be run without a new exact-SHA review and fresh owner authorization. It can only finish a fully staged, exact transaction; it never deletes or overwrites. A failure after manifest activation can leave the new v3 manifest active while returning failure; in that case recovery only verifies the new release and retained v2 backup. A failed postcheck does not trigger an unsafe rollback.

## Exact proposed command — NOT EXECUTED

Prerequisites for any future execution: independent review of the final immutable SHA; a fresh owner authorization specific to that source/candidate hash; a clean SourceRoot at commit `8b70a70934445bee660c1e53e71b2e7b20a6191f` at `C:\Dev\f2-g1-protected-updater-source`; this reviewed package checked out under `C:\Dev\f2-g1-protected-updater`; and a normal consented UAC prompt under the original requester account. The launcher permits one UAC attempt only. This task ran none of the following command.

Run from the original standard-user PowerShell session. The outer Windows PowerShell 5.1 process hashes and dot-sources the exact bootstrap bytes from memory; its last statement propagates the returned child exit code:

```powershell
& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command '& { $path="C:\Dev\f2-g1-protected-updater-source\scripts\f2-acl\Start-F2ProtectedReleaseUpdate.ps1"; $expected="8278bbff8e5b7cdb313235bcc271fa31a947ca384d7496053650c3097af19720"; $bytes=[IO.File]::ReadAllBytes($path); $sha=[Security.Cryptography.SHA256]::Create(); try { $actual=([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace("-","").ToLowerInvariant() } finally { $sha.Dispose() }; if($actual -cne $expected){throw "UPDATE_BOOTSTRAP_HASH_MISMATCH"}; $text=[Text.UTF8Encoding]::new($false,$true).GetString($bytes); . ([scriptblock]::Create($text)); $rc=Invoke-F2ProtectedReleaseUpdateLauncher -ExpectedSourceCommit "8b70a70934445bee660c1e53e71b2e7b20a6191f" -ExpectedLauncherSha256 "8278bbff8e5b7cdb313235bcc271fa31a947ca384d7496053650c3097af19720" -ExpectedUpdaterSha256 "d26eb89a424e3f268099e0ac1d3ffd674dde1128321567df3a0702abb591f75e" -ExpectedCandidateManifestSha256 "74d178917fba4f50fdca40505d8c1dc81639f3c60bbb25c0332fd737c681562c"; exit [int]$rc }'
```

At a later, separately authorized recovery, use the same hash-bound command and add only `-RecoveryTransactionId "<32 lowercase hex from the sanitized update result>"`; add `-ResumeForward` only if the exact reviewed journal/package state satisfies the recovery table. No recovery command was run.

## Windows PowerShell 5.1 source-only validation

Exact direct commands from the repository root:

```powershell
$ps51="$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
& $ps51 -NoProfile -ExecutionPolicy Bypass -File .\scripts\f2-acl\Test-F2AclCapture.Protocol.ps1
& $ps51 -NoProfile -ExecutionPolicy Bypass -File .\scripts\f2-acl\Test-F2AclIcacls.Corroboration.ps1
& $ps51 -NoProfile -ExecutionPolicy Bypass -File .\scripts\f2-acl\Test-F2AclIcacls.Runtime.ps1
& $ps51 -NoProfile -ExecutionPolicy Bypass -File .\scripts\f2-acl\Test-F2AclEntrypointArguments.ps1
& $ps51 -NoProfile -ExecutionPolicy Bypass -File .\scripts\f2-acl\Test-F2AclProtectedReleaseUpdater.ps1
& $ps51 -NoProfile -ExecutionPolicy Bypass -File .\scripts\f2-acl\Test-F2AclProtectedReleaseNativeHelper.ps1
```

The five existing suites and the added native-helper suite passed under Windows PowerShell 5.1: Protocol 152, Corroboration 118, Runtime 41, Entrypoint 18, Updater 121, and native helper 20 assertions (**470 assertions, zero failures**); all six child exit codes were 0. The final run used the reviewed test sources at PR #59 test/evidence commit `3a3383c6fd08b87dada4e3e4c1e9421657afba7c` and production updater/launcher bytes from SourceRoot commit `8b70a70934445bee660c1e53e71b2e7b20a6191f`; exact commands, timestamps, assertion summaries and complete stdout/stderr are retained in `evidence/WINDOWS_POWERSHELL51_FULL_SUITE.txt` and the corresponding `Test-*.stdout.txt`/`Test-*.stderr.txt`. The updater suite adds synthetic process inventories for source/installed runtime paths, direct and encoded PowerShell, missing command lines, process-query errors, cached-old-manifest process state, PID reuse, and a process appearing between scans. The native-helper test compiles the exact C# here-string extracted from the production updater, then exercises protected directory/file creation, owner/DACL read-back, exact ACE masks/inheritance, and create-new collision rejection under a disposable TEMP directory. It does not invoke the production updater or touch protected installation paths. The PowerShell parser sweep covered 14 files with zero errors; `git diff --check` passed.

The original defect was independently reproduced in a fresh Windows PowerShell 5.1 process against the exact blocked source at `40723492b97983c0c7bc6d441a1bcbace823ffe8`: the `Add-Type` compiler rejected the `null` argument to the `IntPtr` template parameter and the probe process exited 1. The sanitized diagnostic and source-only corrected regression are retained in `evidence/NATIVE_COMPILE_REPRO_BEFORE_FIX.txt` and `evidence/Test-F2AclProtectedReleaseNativeHelper.*.log`.

The updater test is entirely synthetic under a new TEMP directory. It exercises old/new manifests, exact file hashes, source provenance, requester identity, parent/child ACL profiles, reparse rejection, locking, manifest replacement, no-overwrite collisions, process inventories, source-checkout path recognition, direct/encoded invocation blocking, cached-old-manifest blocking, activation-edge late-spawn handling, process-inventory errors, path and identity mismatches, staged ACL failures, malformed/incomplete journals, each material-operation checkpoint, and both eligible forward-recovery checkpoints. Its old-release fixtures are sourced from Git commit `5741ffe90a3abd02a08563e6431e8a0b9b63eeb1` and each exact Windows installed-byte hash is checked before use. The test injects failures; it does not execute the production elevated updater or query protected host state.

Windows CI status for the corrected production source is recorded in `evidence/WINDOWS_CI.txt`, including the first hosted failure and the diagnostic same-source retry. CI runs the six suites, parser sweep and whitespace validation on Windows. Any unresolved CI failure remains a review blocker and is reported rather than suppressed.

The v3 candidate's `ReviewedCommitSha` and commit-versioned `PackageRoot` bind to `8b70a70934445bee660c1e53e71b2e7b20a6191f`; its SHA-256 is `74d178917fba4f50fdca40505d8c1dc81639f3c60bbb25c0332fd737c681562c`. The seven package member hashes and source-pin manifest remain byte-for-byte unchanged and all seven were rechecked against a clean Windows checkout of the new source commit.

## Security boundaries and limitations

- Source-only validation is not an actual C: installation or ACL attestation. The native Windows create-with-security-descriptor calls, actual C: parent ACLs, existing installation, account token, UAC behavior and real rename semantics remain unverified on the owner host in this task.
- The updater reads only fixed Program Files/ProgramData installation paths and the exact source/review checkout paths. It never reads or writes G:, queries Hyper-V/VM state, or accesses the retained baseline payload; the two baseline content digests and identities are only compared as pins.
- Program Files/ProgramData parent safety is a source-level profile check. This is not new host evidence and does not replace independent verification before a future UAC run.
- The transaction assumes protected administrator ownership and no concurrent malicious Administrator. Ordinary users cannot alter the protected transaction objects; an Administrator can bypass local protections.
- The updater's 600-second standard-parent wait is bounded but does not kill a timed-out elevated child. `UPDATE_CHILD_STATUS_UNKNOWN` means do not retry; inspect the exact transaction state under a separately authorized procedure.
- If a file-system operation or process inventory returns an unknown condition, the updater blocks and preserves all extant objects. There is no automatic rollback, deletion, cleanup or ACL repair.
- A future actual upgrade and live ACL corroboration each require separate independent review and fresh explicit owner authorization. No PR is merged by this work.

## Reviewer focus

1. Validate the v2-to-v3 switch and v2-launcher failure boundary against the exact seven pinned production files.
2. Audit the exclusive lease plus manifest delete-share barrier and the legacy-process quiescence window.
3. Audit CREATE_NEW ACL application, exact child-set checks and the non-atomic multi-directory crash states.
4. Audit recovery journal sequence/hash checks, transaction ownership and strict no-delete/no-rollback policy.
5. Verify the candidate bytes, Windows line-ending hashes, test logs and exact proposed command at the final immutable GitHub commit.
