# F2 G1 protected installation receipt

**Result: COMPLETE_PROTECTED_INSTALLATION**

This receipt records one installation attempt under the existing owner grant (Issue #48 comment [6114759084](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/issues/48#issuecomment-6114759084)). Independent source review: [PR #54 review 5485359228](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/54#pullrequestreview-5485359228). Current-source preflight review: [PR #56 review 5489457323](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/56#pullrequestreview-5489457323). Gate resolution: [Issue #48 comment 6122425754](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/issues/48#issuecomment-6122425754).

## Immutable inputs and preparation

- PR #54 reviewed executable source HEAD: `b28dcb3139e6ac37ffdde6d94b205d1adac92c58` (OPEN, DRAFT, unmerged).
- Production seven-file SourceRoot HEAD: `5741ffe90a3abd02a08563e6431e8a0b9b63eeb1`, clean worktree, expected GitHub origin.
- Launcher (LF): `b044234882d60e17bd14603a9a74e0cd7ade27c8810c9901bfa18b1b73e1c343`.
- Bootstrap (LF): `6f47d802a2cd5d7deb65083c546829de6a71d26356dcf2b71f6cc6f14d81a4a9`.
- Installer (Windows CRLF): `cf8abc7c94186f44044684e77eb432c3a20a20c3cfd8fb099b6e32e4a2ca0118`.
- Seven-file pin manifest: `bd0a66a5e81494acaa14facb48b58e4c485acda1c17ead4fdfff220bcef97cd7`.
- All three prepared files were regular non-reparse files at the approved preparation paths; their exact byte hashes and mixed line endings matched the reviewed values before launch.
- The actual approved installer function source was the PR #54 review copy at `docs/reviews/f2-g1-capture-id-contract/Install-F2IcaclsProtectedPackage.ps1`. It was hash-checked before its exact bytes were loaded in memory. The stale copy under the production checkout's `docs/reviews` was not used.

Seven installed package pins:

| File | SHA-256 |
| --- | --- |
| `F2AclCapture.Protocol.psm1` | `42ba4dd5e31d1db64198bb1cee16d519f087a40364dfb4d2696b4a5bd844d728` |
| `F2AclIcacls.Corroboration.psm1` | `a52ed86218a0ba0c0801ee6e84a4a5e47c73eda43db78f818b0b12670ad5110b` |
| `F2AclIcacls.Runtime.psm1` | `950b8232be2f22412e837d63f7b2fb678fc83871862b6bafc714d303599a71a5` |
| `Invoke-F2IcaclsCapture.ps1` | `fb55240a16f0858980bb38851414b28ce5f403ba26697ff78f227ca22ff804b0` |
| `Invoke-F2IcaclsProtectedCoordinator.ps1` | `3badc19c8ac6ac450f9691258c6ecd2a3754cd665fd5989325c90b64290ae9e2` |
| `F2_ICACLS_SOURCE_PINS.json` | `bd0a66a5e81494acaa14facb48b58e4c485acda1c17ead4fdfff220bcef97cd7` |
| `Invoke-F2AclReadOnlyCapture.ps1` | `bea7cc93710c83d48a8ef9e54af306401694f17f611e696caa856938ca71a19b` |

## Final preflight

A fresh Windows PowerShell 5.1 process ran under the original requester standard token (not elevated). It verified clean review/source worktrees and exact commits/remotes, the three staged hashes and no reparse points, approved installer path/hash/embedded source and pin identities, and loaded only the approved installer's in-memory bytes.

The actual C: root and Program Files/ProgramData parent ACL checks passed before installation. The baseline loader verified the protected four-ACE mailbox, 11 exact object paths, both distinct retained identities and pinned payload/integrity hashes. The actual seven source-package hashes and pin manifest passed. Both installation destinations and matching staging directories were absent.

```text
PASS PS51_STANDARD_REQUESTER
PASS_REVIEW_AND_PRODUCTION_SOURCE_PROVENANCE
PASS_PREP_EXACT_HASHES
PASS_APPROVED_INSTALLER_LOADED_ONLY_FROM_VERIFIED_MEMORY_BYTES
PASS_ACTUAL_C_ROOT_PROGRAMFILES_PROGRAMDATA_ACL_CHAINS
PASS_BASELINE_MAILBOX_IDS_HASHES_AND_11_PATHS
PASS_SEVEN_PRODUCTION_PACKAGE_FILES_AND_PIN_MANIFEST
PASS_DESTINATIONS_ABSENT_AND_NO_STAGE_COLLISIONS
FINAL_PREFLIGHT=PASS
Process exit code: 0
```

Retained baseline pins:

- Mailbox ID: `ecb6deeb424e40feb5354d18908986df`
- Payload CaptureId: `489e7fec-0300-467c-bfbd-a46fb8cf7211`
- Payload SHA-256: `1b5eee9aae928a909d4c251a4dd6d2c0898c400e2807e0acc3268d61d5149014`
- Integrity SHA-256: `02d6f07f5b3bb6f47a84e58d7c207c9935481e8a898a3b1f5e1ed273d4d61b34`

## Exact installation command

This is the exact `-EncodedCommand` line in PR #54 HEAD's `docs/reviews/f2-g1-install-failure-diagnostics/F2_G1_DIAGNOSTIC_INSTALL_REVIEW_UPDATE.md`; it was executed from the original requester standard-token session after the immediate hash/identity/destination checks. UTF-8 command-line SHA-256: `9dd27675f50986fb46e69f24a78c52c86bf8c8d7c6dc734f8d452cc632ec0ba9`.

```powershell
& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -EncodedCommand JABwAGEAdABoAD0AJwBDADoAXABEAGUAdgBcAGYAMgAtAGcAMQAtAHAAcgBvAHQAZQBjAHQAZQBkAC0AaQBuAHMAdABhAGwAbAAtAHAAcgBlAHAAXABTAHQAYQByAHQALQBGADIAVgBlAHIAaQBmAGkAZQBkAEkAbgBzAHQAYQBsAGwALgBwAHMAMQAnAAoAJABiAHkAdABlAHMAPQBbAEkATwAuAEYAaQBsAGUAXQA6ADoAUgBlAGEAZABBAGwAbABCAHkAdABlAHMAKAAkAHAAYQB0AGgAKQAKACQAcwBoAGEAPQBbAFMAZQBjAHUAcgBpAHQAeQAuAEMAcgB5AHAAdABvAGcAcgBhAHAAaAB5AC4AUwBIAEEAMgA1ADYAXQA6ADoAQwByAGUAYQB0AGUAKAApAAoAdAByAHkAIAB7ACAAJABhAGMAdAB1AGEAbAA9ACgAWwBCAGkAdABDAG8AbgB2AGUAcgB0AGUAcgBdADoAOgBUAG8AUwB0AHIAaQBuAGcAKAAkAHMAaABhAC4AQwBvAG0AcAB1AHQAZQBIAGEAcwBoACgAJABiAHkAdABlAHMAKQApACkALgBSAGUAcABsAGEAYwBlACgAJwAtACcALAAnACcAKQAuAFQAbwBMAG8AdwBlAHIASQBuAHYAYQByAGkAYQBuAHQAKAApACAAfQAgAGYAaQBuAGEAbABsAHkAIAB7ACAAJABzAGgAYQAuAEQAaQBzAHAAbwBzAGUAKAApACAAfQAKAGkAZgAgACgAJABhAGMAdAB1AGEAbAAgAC0AYwBuAGUAIAAnAGIAMAA0ADQAMgAzADQAOAA4ADIAZAA2ADAAZQAxADcAYgBkADEANAA2ADAAMwBhADkAYQA3ADQAZQAwAGMAZAA3AGEAZABlADIANwBjADgAOAAxADAAYwA5ADkAMAAxAGIAZgBhADEAOABiADEAYgA3ADMAZQAxAGMAMwA0ADMAJwApACAAewAgAHQAaAByAG8AdwAgACcARgAyAF8ATABBAFUATgBDAEgARQBSAF8ASABBAFMASABfAE0ASQBTAE0AQQBUAEMASAAnACAAfQAKACQAdQB0AGYAOAA9AE4AZQB3AC0ATwBiAGoAZQBjAHQAIABTAHkAcwB0AGUAbQAuAFQAZQB4AHQALgBVAFQARgA4AEUAbgBjAG8AZABpAG4AZwAoACQAZgBhAGwAcwBlACwAJAB0AHIAdQBlACkACgAkAHYAZQByAGkAZgBpAGUAZAA9AFsAUwBjAHIAaQBwAHQAQgBsAG8AYwBrAF0AOgA6AEMAcgBlAGEAdABlACgAJAB1AHQAZgA4AC4ARwBlAHQAUwB0AHIAaQBuAGcAKAAkAGIAeQB0AGUAcwApACkACgAmACAAJAB2AGUAcgBpAGYAaQBlAGQA
```

## Launch and diagnostic results

- Human-consented Administrator UAC attempts: **1**.
- Launcher disposition: `CHILD_EXITED`.
- Elevated installer child PID: `9448`; actual child exit code: **0**.
- Documented launcher process exit code: **0**.
- Launcher summary: `CHILD_CLAIM_ONLY`; the summary was treated as non-authoritative.
- The bounded requester TEMP diagnostic mailbox was nonce-checked by the reviewed launcher. The record was independently re-read after launch: schema `f2-install-diagnostic-v1`, component `Installer`, stage `PostInstallAttestation`, outcome `INSTALL_COMPLETE`, error code `NONE`; nonce is present but not disclosed.
- Diagnostic record length: 185 bytes. SHA-256: `1457e307849067654f710a6d681c71bc5db2603543947be487edc3bd7fd04118`.
- Sanitized mailbox reference: `C:\Users\<requester>\AppData\Local\Temp\F2-G1-Install-<per-attempt-id>\`.

PowerShell emitted first-use progress as CLIXML in the output stream. No error was reported by the launch command. The separate installer child exit code and actual installed state below are the success criteria.

## Independent installed-state attestation

A fresh Windows PowerShell 5.1 read-only verifier independently inspected the actual C: installation tree. It rechecked the existing C: parent ACL policy after installation, then read each installed object with `Get-Acl` and raw descriptor parsing. It did not invoke `icacls`, the installed launcher/coordinator, or VM tooling.

| Object class | Count | Verification |
| --- | ---: | --- |
| Protected directories | 4 | Exact expected paths, Administrators owner, protected DACL, exact three allow ACE profile |
| Package files | 7 | Exact names and SHA-256 pins; Administrators owner, protected DACL, exact three allow ACE profile |
| External release manifest | 1 | Correct v2 schema/identities/pins; Administrators owner, protected DACL, exact three allow ACE profile |
| Staging directories | 0 | No matching partial stage remained |
| Reparse points | 0 | None in the installed tree or checked paths |

The accepted protected DACL classification on each installed directory and file was exactly three allow ACEs: SYSTEM Full Control (`0x001F01FF`), Administrators Full Control (`0x001F01FF`), and Authenticated Users Read/Execute (`0x001200A9`). Directory ACE inheritance flags were exactly ObjectInherit and ContainerInherit; file ACE flags were None. DACL inheritance was protected and no deny, extra principal, write grant for ordinary users, or unreviewed mask was present. Raw SDDL and private SIDs are intentionally not published.

Release manifest:

- Path: `C:\ProgramData\F2-G1-Icacls\approved-release.json`
- Schema: `f2-icacls-runtime-release-v2`
- Reviewed production source: `5741ffe90a3abd02a08563e6431e8a0b9b63eeb1`
- Seven-file source pin manifest: `bd0a66a5e81494acaa14facb48b58e4c485acda1c17ead4fdfff220bcef97cd7`
- Baseline mailbox and payload identities/hashes: match the values above.
- Actual installed manifest SHA-256: `b5f01570cf8937324f0c763f72a8d05b5532472156d4e5b0fcfbd180dc7abbe9`.

```text
PASS_PARENT_ACL_POLICY_RECONFIRMED
ATTESTATION=PASS
DIRECTORIES=4 FILES=7 MANIFESTS=1
ACL=ADMINISTRATORS_OWNER_DACL_PROTECTED_EXACT_3_ACE_ALLOW_PROFILE
RELEASE_SCHEMA=f2-icacls-runtime-release-v2
MANIFEST_SHA256=b5f01570cf8937324f0c763f72a8d05b5532472156d4e5b0fcfbd180dc7abbe9
DIAGNOSTIC_RECORD_SHA256=1457e307849067654f710a6d681c71bc5db2603543947be487edc3bd7fd04118
CHILD_EXIT_CODE=0 UAC_ATTEMPTS=1 DIAGNOSTIC_NONCE_PRESENT=YES
Process exit code: 0
```

## Operational validation notes

- The first non-elevated staging implementation used `File.Replace` without a backup path and stopped with “The path is empty.” It left one temporary file whose hash exactly matched the approved bootstrap. The corrected staging used that hash-verified file and exact approved source bytes; all three destinations were rehashed and no staging residue remained before UAC.
- An initial preflight harness emitted a call-depth error. It was discarded; a fresh PS 5.1 run using direct Git checks and the approved source then completed all gates with exit 0.
- An initial postflight harness expected different diagnostic JSON field names. It stopped at the diagnostic check only; the actual record was inspected without printing the nonce, the verifier was corrected to the documented schema/fields, and the complete read-only postflight then passed with exit 0. No installation retry occurred.

## Scope and remaining gate

No source checkout or PR #54 bytes were changed. No ACL remediation, live `icacls`, VM/Hyper-V or G: action, guest/native execution, or PR merge occurred. Installation is complete; this does **not** accept the VM's ACL baseline. Separate live read-only `icacls` corroboration and independent ACL review remain pending a separate owner authorization.
