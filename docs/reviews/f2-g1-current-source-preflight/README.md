# F2 G1 current-source preflight verification

**Disposition: `READY_FOR_INDEPENDENT_CURRENT_SOURCE_PREFLIGHT_REVIEW`.**
**Host observation date:** 2026-10-12.
**Scope:** source provenance and read-only preflight only. No UAC, installation, ACL change, VM activity, G: access, `icacls`, or native workload.

## Provenance finding for the prior failure

The failed preflight did not load functions from the approved PR #54 installer. Its recorded dot-source path was the installer copy tracked inside the production checkout:

`C:\Dev\f2-g1-capture-id-contract-source\docs\reviews\f2-g1-capture-id-contract\Install-F2IcaclsProtectedPackage.ps1`

That file’s SHA-256 is `150994560abec579dd50c519222c4a8f80932ab9510e89cb61fbd1408c756cae`. It is present in the clean production checkout at `5741ffe90a3abd02a08563e6431e8a0b9b63eeb1`; its last file-changing commit is `f40ca12415dcdf380fd4b09cf2651c5dcf83343e`. The copy embeds source commit `54b1d0c7a9865d710c19b59cd38c0da670a12536`, source-pin manifest `cee4322fdc4603cdebeccfe3411303a0ea92db946aa920b8ad60cb3152cae3c5`, and runtime module pin `eecec7b86a4bfee7773e73b537ed74ae573ff3d5bfaaa44b9d1bc42c4e1953a7`.

**Cause:** a stale copied helper in the otherwise current production checkout was explicitly dot-sourced. This was not an old checkout HEAD or reused PowerShell session. The previous command named that physical path directly. Its preflight and the follow-up path diagnostic ran in separate PowerShell processes. The follow-up diagnostic’s callback obtained each SDDL by calling the real `Get-F2InstallFileSddl`; it did not inject synthetic ACL data. The successful current-source run below used the production helper without a provider override.

The approved installer is a different physical file in the PR #54 review checkout:

`C:\Dev\f2-g1-install-failure-diagnostics\docs\reviews\f2-g1-capture-id-contract\Install-F2IcaclsProtectedPackage.ps1`

It is from clean PR #54 HEAD `b28dcb3139e6ac37ffdde6d94b205d1adac92c58` (parent `356d3e66acaa0a8062a581f3157c449b053e314e`) and has the approved Windows CRLF checkout-byte SHA-256 `cf8abc7c94186f44044684e77eb432c3a20a20c3cfd8fb099b6e32e4a2ca0118`. The stale and approved copies were not interchangeable; only the latter was used in the successful preflight.

## Verified-byte loading and function provenance

The successful run used one fresh Windows PowerShell `5.1.22621.6133` process with `-NoProfile -NonInteractive`, under the original requester’s standard token. It confirmed PR #54 HEAD and the production checkout HEAD/remote/cleanliness before loading any installer functions. It then verified the approved file as a regular, canonical, non-reparse file, read its bytes once, checked the exact SHA-256 above, checked embedded production commit `5741ffe90a3abd02a08563e6431e8a0b9b63eeb1`, and validated the embedded source-pin manifest hash and every package pin against the production checkout. Only the resulting in-memory script block was dot-sourced.

In that new `-NoProfile` process, each target function was absent before loading, had one unique declaration in the verified installer AST, and appeared as exactly one function after dot-sourcing that verified in-memory block. The installed function body text was found in the verified source. No module or other script was imported or dot-sourced. Function body SHA-256 values:

| Function | Verified in-memory origin | Function body SHA-256 |
|---|---|---|
| `Test-F2InstallParentChain` | PASS | `95ec675d672258f1d2abef4120e06b35202c30fc9f15dbc0a2ce6caab93308d8` |
| `Test-F2InstallSafeParentSddl` | PASS | `db6e8ba4d2de8d06ca0235d89741de97bae0ad0d18a9563a3072a700b5851beb` |
| `Read-F2InstallBaseline` | PASS | `fe5ac5bdc52a18a0d0702ca8e34e628a2fd54ef28de06046ab480946de9a0040` |
| `Get-F2InstallPackageBytes` | PASS | `cd227893302d059b2a0254d373a62e8894a724580344cd9bd2b0a3ad129555ae` |

## Read-only actual-host gate matrix

| Gate | Result | Evidence |
|---|---|---|
| Windows PowerShell / token | PASS | Version `5.1.22621.6133`; standard token, not elevated. Successful verifier PID `40716`; process exit code `0`. |
| Review checkout lineage | PASS | HEAD `b28dcb3139e6ac37ffdde6d94b205d1adac92c58`, clean; expected GitHub origin. |
| Production source lineage | PASS | HEAD `5741ffe90a3abd02a08563e6431e8a0b9b63eeb1`, clean; expected GitHub origin. |
| Approved installer physical source | PASS | Review-checkout path above; regular file, non-reparse, canonical path; SHA-256 matches approved Windows checkout bytes. Embedded production commit matches. |
| Pin manifest | PASS | `F2_ICACLS_SOURCE_PINS.json` SHA-256 `bd0a66a5e81494acaa14facb48b58e4c485acda1c17ead4fdfff220bcef97cd7`; schema and reviewed collector base identity validated. |
| Seven production package files | PASS | Every actual hash matched both the approved installer pin and its applicable manifest entry. Exact values below. |
| Canonical `C:\` ACL policy | PASS | Actual host SDDL was read in memory and evaluated by the verified `Test-F2InstallSafeParentSddl`; no SDDL or SID was emitted. No synthetic ACL provider. |
| `C:\Program Files` parent chain | PASS | Actual host ACLs evaluated by the verified `Test-F2InstallParentChain`; no provider override. |
| `C:\ProgramData` parent chain | PASS | Actual host ACLs evaluated by the verified `Test-F2InstallParentChain`; no provider override. |
| Retained baseline | PASS | Mailbox ID `ecb6deeb424e40feb5354d18908986df`; distinct payload CaptureId `489e7fec-0300-467c-bfbd-a46fb8cf7211`; 11 records; four-ACE requester mailbox contract; payload/integrity digests match pins below. |
| Install destinations | PASS | `C:\Program Files\F2-G1-Icacls` and `C:\ProgramData\F2-G1-Icacls` absent; existing ancestor chains had no reparse points. |
| Staging paths | PASS | No `.F2-G1-Icacls-stage-*` directories under the two reviewed parents. |

The prior `INSTALL_PARENT_DACL_UNSAFE` is **not reproduced by the approved current installer**. Its actual-host root policy returns PASS; both full parent-chain checks also return PASS. No raw SDDL, requester SID, credentials, or baseline contents are included.

## Exact production package hashes

| File | Actual SHA-256 | Installer pin | Manifest check |
|---|---|---|---|
| `F2AclCapture.Protocol.psm1` | `42ba4dd5e31d1db64198bb1cee16d519f087a40364dfb4d2696b4a5bd844d728` | match | PASS |
| `F2AclIcacls.Corroboration.psm1` | `a52ed86218a0ba0c0801ee6e84a4a5e47c73eda43db78f818b0b12670ad5110b` | match | PASS |
| `F2AclIcacls.Runtime.psm1` | `950b8232be2f22412e837d63f7b2fb678fc83871862b6bafc714d303599a71a5` | match | PASS |
| `Invoke-F2IcaclsCapture.ps1` | `fb55240a16f0858980bb38851414b28ce5f403ba26697ff78f227ca22ff804b0` | match | PASS |
| `Invoke-F2IcaclsProtectedCoordinator.ps1` | `3badc19c8ac6ac450f9691258c6ecd2a3754cd665fd5989325c90b64290ae9e2` | match | PASS |
| `F2_ICACLS_SOURCE_PINS.json` | `bd0a66a5e81494acaa14facb48b58e4c485acda1c17ead4fdfff220bcef97cd7` | match | PASS |
| `Invoke-F2AclReadOnlyCapture.ps1` | `bea7cc93710c83d48a8ef9e54af306401694f17f611e696caa856938ca71a19b` | match | PASS |

Baseline payload SHA-256: `1b5eee9aae928a909d4c251a4dd6d2c0898c400e2807e0acc3268d61d5149014`.
Baseline integrity SHA-256: `02d6f07f5b3bb6f47a84e58d7c207c9935481e8a898a3b1f5e1ed273d4d61b34`.

## Verifier execution accounting

The first direct nested-process invocation failed before a child process was created. A subsequent `-Command -` pipe attempt returned exit `0` with no output and no retained PID; it is treated as **inconclusive**, not as a passed check. Three recorded verifier processes then failed before dot-sourcing because of verifier-only issues: PIDs `49560` and `3420` exited `21` with `System.ArgumentException` during file preparation; PID `26324` exited `21` because the verifier helper name `H` resolved to PowerShell’s `h` alias. PID `10956` exited `21` after dot-sourcing the verified bytes but before calling any host-check function; its exact AST-extent equality assertion was too strict. These were not installer/source failures and none launched UAC or changed host state.

The successful fresh process was PID `40716`, PowerShell `5.1.22621.6133`, exit `0`. It used the verified current installer and completed all gates above. It called only the requested read-only helpers plus read-only existence/reparse checks. The only uncertainty is the earlier stdin invocation’s missing output/PID; the final complete run independently revalidated all requested current-source gates.

## Outcome and boundary

All requested current-source preflight gates passed: `AllHostGatesPass=true`. The previous error was caused by selecting a copied historical helper, not by the approved PR #54 executable or current host root policy. This report does **not** authorize or perform installation. The owner’s one-time installation authorization remains unused and applies only to the unchanged reviewed bytes. No source file, ACL, installation path, VM, G: content, network setting, or PR #54 state was modified.
