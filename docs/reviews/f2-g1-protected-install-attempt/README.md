# F2 G1 protected installation attempt receipt

**Disposition: `BLOCKED_WITH_EVIDENCE` — no UAC launch occurred.**
**Observed:** 2026-10-12 (host local date).
**Scope:** one authorized installation attempt; no protected installation was attempted.

## Authorization and reviewed inputs

- Owner authorization: [Issue #48 comment 6114759084](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/issues/48#issuecomment-6114759084). It authorized one ordinary human-consented Administrator UAC attempt for the exact reviewed inputs; that authorization remains unused.
- Independent approval: [PR #54 review 5485359228](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/54#pullrequestreview-5485359228).
- Reviewed PR #54 source: `b28dcb3139e6ac37ffdde6d94b205d1adac92c58`, parent `356d3e66acaa0a8062a581f3157c449b053e314e`, draft/open.
- Required production source: `5741ffe90a3abd02a08563e6431e8a0b9b63eeb1`, clean checkout, expected GitHub origin.
- The reviewed installation command is in [`F2_G1_DIAGNOSTIC_INSTALL_REVIEW_UPDATE.md` at the reviewed commit](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/blob/b28dcb3139e6ac37ffdde6d94b205d1adac92c58/docs/reviews/f2-g1-install-failure-diagnostics/F2_G1_DIAGNOSTIC_INSTALL_REVIEW_UPDATE.md). It was **not invoked**.

## Preparation and process results

| Gate | Result | Evidence |
|---|---|---|
| Windows PowerShell | PASS | `5.1.22621.6133` was used for preflight; requester token was non-Administrator. |
| PR #54 and production worktrees | PASS | Exact reviewed/source commits above; both worktrees clean and use `https://github.com/publiomcko-cloud/procedural-sandbox-simulation.git`. |
| Approved preparation-source bytes | PASS | Launcher, bootstrap and installer source-file hashes equal all three approved hashes below. |
| Preparation target state | PASS | Launcher destination was absent. Existing bootstrap and installer were the recognized previous versions shown below; neither was replaced. No reparse points were found under the preparation directory. |
| Retained baseline | PASS | Read-only production helper validated the exact mailbox ID and distinct payload CaptureId, both pinned digests, all 11 records, and the original four-ACE mailbox/requester contract. No raw SDDL or requester SID is included. |
| Installation destinations and stage paths | PASS | Both final destinations absent; no matching staging directories. |
| `C:\Program Files` parent profile | PASS | Reviewed production predicate accepted this directory. |
| `C:\ProgramData` parent profile | PASS | Reviewed production predicate accepted this directory. |
| `C:\` parent profile | **FAIL** | `Test-F2InstallParentChain` rejected the volume-root ancestor with `INSTALL_PARENT_DACL_UNSAFE`. The root was the failing component on both parent-chain walks. No ACL change was made. |
| Installer production source pins | **FAIL** | The immutable reviewed installer’s manifest/runtime pins and embedded source commit do not match the separately approved production source. Details below. |

The first complete read-only production preflight process exited **4** with `INSTALL_PARENT_DACL_UNSAFE`. A component-only diagnostic exited **0** and isolated `C:\` as the failed ancestor (`C:\Program Files` and `C:\ProgramData` individually passed). A subsequent source/baseline check validated the baseline, then exited **4** with `SOURCE_PIN_MANIFEST_HASH_MISMATCH`. A final baseline/destination check exited **0**. These are preflight helper process statuses, not an installer child status.

**UAC attempts: 0.** The reviewed launcher was not started, so there is no elevated child PID/exit code, no diagnostic mailbox for this attempt, and no installer JSON. No approved preparation file was replaced or newly staged. No protected directory, package file, release manifest or partial stage was created.

## Approved-byte hashes and existing preparation state

| File | Approved SHA-256 | Source SHA-256 | Existing preparation SHA-256 | Action |
|---|---|---|---|---|
| `Start-F2VerifiedInstall.ps1` (LF) | `b044234882d60e17bd14603a9a74e0cd7ade27c8810c9901bfa18b1b73e1c343` | `b044234882d60e17bd14603a9a74e0cd7ade27c8810c9901bfa18b1b73e1c343` | absent | Not staged |
| `Invoke-F2VerifiedInstaller.ps1` (LF) | `6f47d802a2cd5d7deb65083c546829de6a71d26356dcf2b71f6cc6f14d81a4a9` | `6f47d802a2cd5d7deb65083c546829de6a71d26356dcf2b71f6cc6f14d81a4a9` | `3ae8fee4cfa7c809110a3233f9df2ad8f1fe877c91f1a4067e08541c5e893060` | Preserved known previous version |
| `Install-F2IcaclsProtectedPackage.ps1` (CRLF) | `cf8abc7c94186f44044684e77eb432c3a20a20c3cfd8fb099b6e32e4a2ca0118` | `cf8abc7c94186f44044684e77eb432c3a20a20c3cfd8fb099b6e32e4a2ca0118` | `be622923a5931a1cc1ce8cfff18c72952b836f8f84e403a419254c6c2c778b0e` | Preserved known previous version |

## Deterministic package/source mismatch

The actual source pin manifest in the clean production checkout hashes to the approved manifest SHA-256 `bd0a66a5e81494acaa14facb48b58e4c485acda1c17ead4fdfff220bcef97cd7`. The reviewed installer instead pins manifest SHA-256 `cee4322fdc4603cdebeccfe3411303a0ea92db946aa920b8ad60cb3152cae3c5`, so its actual preflight correctly rejected the package before any privileged launch.

The installer’s seven-file table also differs for the runtime module:

| Package file | Production checkout actual SHA-256 | Reviewed installer pin | Result |
|---|---|---|---|
| `F2AclCapture.Protocol.psm1` | `42ba4dd5e31d1db64198bb1cee16d519f087a40364dfb4d2696b4a5bd844d728` | same | PASS |
| `F2AclIcacls.Corroboration.psm1` | `a52ed86218a0ba0c0801ee6e84a4a5e47c73eda43db78f818b0b12670ad5110b` | same | PASS |
| `F2AclIcacls.Runtime.psm1` | `950b8232be2f22412e837d63f7b2fb678fc83871862b6bafc714d303599a71a5` | `eecec7b86a4bfee7773e73b537ed74ae573ff3d5bfaaa44b9d1bc42c4e1953a7` | **FAIL** |
| `Invoke-F2IcaclsCapture.ps1` | `fb55240a16f0858980bb38851414b28ce5f403ba26697ff78f227ca22ff804b0` | same | PASS |
| `Invoke-F2IcaclsProtectedCoordinator.ps1` | `3badc19c8ac6ac450f9691258c6ecd2a3754cd665fd5989325c90b64290ae9e2` | same | PASS |
| `F2_ICACLS_SOURCE_PINS.json` | `bd0a66a5e81494acaa14facb48b58e4c485acda1c17ead4fdfff220bcef97cd7` | `cee4322fdc4603cdebeccfe3411303a0ea92db946aa920b8ad60cb3152cae3c5` | **FAIL** |
| `Invoke-F2AclReadOnlyCapture.ps1` | `bea7cc93710c83d48a8ef9e54af306401694f17f611e696caa856938ca71a19b` | same | PASS |

The installer sets `ReviewedCommitSha` to `54b1d0c7a9865d710c19b59cd38c0da670a12536`, while the approved production source commit is `5741ffe90a3abd02a08563e6431e8a0b9b63eeb1`. The installer places this value in the v2 release manifest. This is a further provenance mismatch; no manifest was created.

## Diagnostic and installation outcome

- Launch disposition: `NOT_LAUNCHED_PRE_UAC_PREFLIGHT_FAILURE`.
- UAC consent attempts: `0` (authorization remains unused).
- Elevated child PID/exit: none.
- Installer structured result/JSON: not produced.
- Diagnostic mailbox: not created for this attempt; no diagnostic record/hash exists.
- Independent installed-state attestation: not applicable; both protected destinations are absent.
- Actual installed directories/files/manifest: 0 / 0 / 0.
- Partial installation or staging state: none observed.
- Raw ACL/SDDL, private SIDs and credentials: intentionally omitted.

## Required resolution before a new attempt

Do not use the current reviewed installer bytes for the supplied production source. The installer/pin manifest/runtime hashes and embedded source commit need a narrowly scoped source correction and independent exact-byte review. The reviewed parent-chain policy also needs an independently reviewed treatment of the observed `C:\` root profile; do not weaken or bypass the check and do not change the live ACL. After corrected executable bytes receive independent review, the owner must provide fresh explicit installation authorization. The current one-time authorization was not consumed because UAC never started.

No PR was merged, no ACL or system setting was changed, and no VM, `icacls`, G: path or native workload was accessed.
