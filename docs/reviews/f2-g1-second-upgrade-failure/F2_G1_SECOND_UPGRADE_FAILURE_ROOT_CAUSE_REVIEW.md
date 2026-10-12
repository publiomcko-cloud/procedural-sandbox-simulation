# F2 G1 second protected-upgrade failure: root-cause review

**Disposition:** READY_FOR_INDEPENDENT_ROOT_CAUSE_REVIEW

**Conclusion:** The owner-reported failure is localized to the updater's pre-lock CandidateAndSourceValidation span, but its specific operation and exception are not present in the validated requester diagnostic. I re-ran the reviewed production read-only validators under Windows PowerShell 5.1 with a standard token; all passed. The elevated failure was not reproduced, so this evidence does not attribute it to Git, ACLs, the manifest, or any other particular dependency.

## Scope and safety

This review used PR #62 production source 923c7d39d7fbfe106dea404c386efd4b5844654e and PR #63 execution-preflight source 3dc05f98831924160474bfb5b554b2963d9a137b. The production checkout is C:\Dev\f2-g1-protected-updater-source at 03882eedf3104fc33aa0cf503ddef9c9a6bec702; the candidate checkout is C:\Dev\f2-g1-protected-updater at the PR #62 HEAD. Both were clean and had the expected GitHub origin when checked. PRs #62 and #63 remain draft and unmerged.

The standard-token validation verified the candidate v3 manifest, source commit and origin, clean worktree, seven source-package members and their pin manifest; the C: parent ACL policy; the active v2 manifest and seven installed v2 files; protected directory/file ACL classifications and no-reparse checks; the retained mailbox's distinct four-ACE contract, pinned payload/integrity identities and 11-record completeness; and absence of release lock, update, backup, release, transaction or staging objects.

Reviewed executable and candidate identities:

| Artifact | SHA-256 / identity |
|---|---|
| Production updater source commit | 03882eedf3104fc33aa0cf503ddef9c9a6bec702 |
| PR #62 updater, Windows checkout bytes | c4dfc71606888555f7b93930671045490ba8e49d20d65f858eab6c084bf620eb |
| PR #62 launcher, Windows checkout bytes | 054e69a4b908c1fe1927e5997bf1c7aca003e8ae21fbaa278323fdf6b5179e68 |
| PR #62 diagnostic protocol, Windows checkout bytes | f66783ac53ce84c093193fc6e20547e707da7013f4f1406a87b088ab6898654c |
| v3 candidate manifest | ac42f719583ba58b1c122a9318368d34699cf60103787034525be4fbe937ad07 |
| v3 source-pin manifest | 7e05d48ef25e7cff19d84db151395921b5d89b52b1e2f45b94a84a4778a615ce |
| Active v2 manifest | b5f01570cf8937324f0c763f72a8d05b5532472156d4e5b0fcfbd180dc7abbe9 |

The v3 candidate's seven pinned source-package members passed the live read-only production validator:

| File | Candidate SHA-256 |
|---|---|
| F2AclCapture.Protocol.psm1 | 42ba4dd5e31d1db64198bb1cee16d519f087a40364dfb4d2696b4a5bd844d728 |
| F2AclIcacls.Corroboration.psm1 | a52ed86218a0ba0c0801ee6e84a4a5e47c73eda43db78f818b0b12670ad5110b |
| F2AclIcacls.Runtime.psm1 | d1f4697e6fcb04d8707442e7c0579dc1bd0934c0565d48c5527080af462663e4 |
| Invoke-F2IcaclsCapture.ps1 | 0b9214c3d6f6e96081b9d86aa8d62087c82527443f2c4b3e7ee09a1ca3dae818 |
| Invoke-F2IcaclsProtectedCoordinator.ps1 | 9b8816c941eebaa87aafd597e6bc326d380c7fbb34321ef97ab0c04a4c1ac515 |
| F2_ICACLS_SOURCE_PINS.json | 7e05d48ef25e7cff19d84db151395921b5d89b52b1e2f45b94a84a4778a615ce |
| Invoke-F2AclReadOnlyCapture.ps1 | bea7cc93710c83d48a8ef9e54af306401694f17f611e696caa856938ca71a19b |

The seven active v2 files were separately verified against the reviewed updater's old-release pins: F2AclCapture.Protocol.psm1, 42ba4dd5e31d1db64198bb1cee16d519f087a40364dfb4d2696b4a5bd844d728; F2AclIcacls.Corroboration.psm1, a52ed86218a0ba0c0801ee6e84a4a5e47c73eda43db78f818b0b12670ad5110b; F2AclIcacls.Runtime.psm1, 950b8232be2f22412e837d63f7b2fb678fc83871862b6bafc714d303599a71a5; Invoke-F2IcaclsCapture.ps1, fb55240a16f0858980bb38851414b28ce5f403ba26697ff78f227ca22ff804b0; Invoke-F2IcaclsProtectedCoordinator.ps1, 3badc19c8ac6ac450f9691258c6ecd2a3754cd665fd5989325c90b64290ae9e2; F2_ICACLS_SOURCE_PINS.json, bd0a66a5e81494acaa14facb48b58e4c485acda1c17ead4fdfff220bcef97cd7; and Invoke-F2AclReadOnlyCapture.ps1, bea7cc93710c83d48a8ef9e54af306401694f17f611e696caa856938ca71a19b.

No updater entrypoint or transaction function was invoked. No UAC, protected write, cleanup, ACL change, icacls, process termination, VM/Hyper-V/G: query, or native collector execution occurred. The second UAC grant remains consumed; this report does not authorize another attempt.

## Incident evidence

Issue #48 comment [6132774514](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/issues/48#issuecomment-6132774514) reports one UAC launch, elevated child PID 6468, actual exit 1, and a validated but non-authoritative diagnostic:

| Field | Owner-reported value |
|---|---|
| UAC launches | 1; authorization consumed |
| Child process | PID 6468 |
| Actual child exit | 1 |
| Diagnostic transport | VALIDATED, transport error NONE |
| Request ID | 3307daf65cb2462bb48b7e80c03116a2 |
| Coarse stage | CandidateAndSourceValidation |
| Child error code | UPDATE_UNCLASSIFIED_FAILURE |
| Diagnostic record SHA-256 | 128b5830cfb0ef0711042c40baa82aa007d0e57be998f1c3cc80915e3a7a0219 |
| Installation result | v3 not attested; v2 remains active per subsequent read-only checks |

The raw exception, exception type, failing sub-operation, and exception text were not returned to the requester. Diagnostic.ErrorCode=NONE describes transport validation, not updater success.

## Post-failure read-only state

All observed post-failure state checks passed:

| Gate | Result | Evidence |
|---|---|---|
| Production source lineage | PASS | Exact commit, origin, clean state, source pins and seven package members passed through the reviewed validator |
| Candidate manifest | PASS | Pinned v3 bytes, schema, production commit, expected package root and identities passed |
| C: parent policy | PASS | Actual Test-F2UpdateParentChains and native read-only SDDL helper passed for the system root, Program Files and ProgramData policy |
| Existing installation | PASS | Actual Test-F2UpdateInstalledOldRelease passed for the active v2 manifest, seven files, four protected directories, owner/DACL classifications and reparse checks |
| Transaction objects | PASS | No release lock, update root, backup root, release root, journal, transaction directory or stage was observed; exact child-set validation passed |
| Retained baseline | PASS | Mailbox identity and distinct payload CaptureId matched their separate pins; payload/integrity hashes, four-ACE mailbox profile and 11-record completeness passed |
| Protected-state consistency | PASS | No mismatch or unexplained partial object was observed |

The raw validator output is [read-only-production-validation.stdout.txt](evidence/read-only-production-validation.stdout.txt). It reports only sanitized gate names and completion markers. The original failed harness run is retained separately as [read-only-validation-attempt1-harness-error.stdout.txt](evidence/read-only-validation-attempt1-harness-error.stdout.txt); its failure was in this review script's volume-GUID pattern, before it evaluated mailbox records, and was corrected without touching protected state.

The test script [Test-F2G1SecondFailureReadOnly.ps1](evidence/Test-F2G1SecondFailureReadOnly.ps1) verifies the updater file hash before parsing and dot-sourcing only its definitions. It then calls the reviewed read-only validation functions individually. Its output explicitly confirms that the updater entrypoint and transaction were not invoked.

## Exact pre-lock source path

The reviewed updater's Invoke-F2UpdateTransaction in scripts/f2-acl/Invoke-F2ProtectedReleaseUpdate.ps1 begins with stage CandidateAndSourceValidation. Before it advances the stage to AcquireReleaseBarrier, it performs:

| Order | Operation | What the reviewed implementation checks | Read-only reproduction |
|---:|---|---|---|
| 1 | Candidate validation (Test-F2UpdateCandidate) | Manifest byte size/hash, JSON, v3 schema, release identities/baseline pins, seven-member file set, expected source commit and versioned PackageRoot | PASS; actual function called with the pinned candidate bytes |
| 2 | Source validation (Get-F2UpdateSourceBytes) | Source path/reparse chain; Get-Command git.exe; Git HEAD, origin and clean state; seven file bytes/hashes; source-pin manifest hash/provenance and internal package pins | PASS; actual function called; Git resolution and all checks succeeded under this standard token |
| 3 | Parent validation (Test-F2UpdateParentChains) | Canonical C: locations and ACL policy for C:\, Program Files, ProgramData; uses the native helper to read SDDL | PASS; actual function called, no ACL writes |
| 4 | Old-release validation (Test-F2UpdateInstalledOldRelease) | Exact existing v2 tree shape, file hashes, owner/protected DACL profiles, active manifest hash/schema/commit/member pins, reparse status, and any recognized transaction subtree shapes | PASS; actual function called |
| 5 | Inline collision/type checks | Existing releases, updates, backups and release-lock paths must be of approved types, profiles and child sets; unknown children/collisions fail closed | PASS for current state: the reviewed exact-child validation and separate path inventory found these paths absent |
| 6 | Barrier acquisition | Only after the preceding operations does source change stage to AcquireReleaseBarrier; normal release-lock creation is later in this stage | NOT INVOKED; no transaction replay |

The line-level order was inspected in the exact reviewed source. The inline collision checks were not reached by calling the transaction function; their absence/type consequences were validated read-only using the exact installed-tree checker and separate inventory. This distinction avoids presenting a transaction simulation as a live execution.

## Root-cause finding

**Confirmed:** The reported child returned exit 1 with a valid diagnostic locating the coarse stage at CandidateAndSourceValidation. The current post-failure protected installation is internally consistent and remains on v2.

**Not confirmed:** Which statement failed in the elevated process. The standard-token rerun passed all individually callable read-only validators, but it cannot establish elevated-token environment equivalence. In particular, Get-Command git.exe and Git subprocess behavior may vary by account environment, PATH, working directory, credential configuration, or process environment. That is a possibility, not evidence that Git caused this failure. Similarly, a standard-token ACL read passing is not proof of every elevated-only access behavior.

**Why the existing diagnostic is insufficient:** The stage is held constant across multiple validation operations. The updater catches unexpected exceptions and returns a generic safe code; the diagnostic transport does not carry the internal FailureType. A direct CommandNotFoundException during the coarse source stage is explicitly normalized to UPDATE_SOURCE_GIT_UNAVAILABLE, so the observed generic code does not prove that particular missing-Git case. It also does not identify any ACL, manifest, native-helper, or file operation.

## Minimal future source-only correction proposal

No production source was changed in this review. Before any new protected attempt, prepare and independently review a narrowly scoped diagnostics-only source update:

1. Keep ErrorCode on the existing finite allowlist and keep diagnostic records non-authoritative. Do not transmit exception messages, exception types, paths, SIDs, SDDL, environment values, or baseline contents.
2. Reuse the existing Stage field, but set it to a small finite substage immediately before each pre-barrier validation operation. Suggested entries: CandidateManifestValidation, SourceGitValidation, SourcePackagePinValidation, ParentAclValidation, InstalledV2Validation, and TransactionCollisionValidation. If additional granularity is needed inside source validation, use only similarly fixed allowlisted labels.
3. Add those exact labels to the diagnostics module's stage allowlist. Unknown labels must still normalize to UpdaterInvocation; never pass arbitrary strings through.
4. Preserve existing stable error-code normalization. On an unclassified exception, report only the allowlisted substage plus UPDATE_UNCLASSIFIED_FAILURE. Do not infer a specific error from exception text.
5. Add PS5.1 synthetic tests that inject a failure at each operation boundary, verify the expected substage and safe code, and reject malicious/unlisted stages, raw exception text, paths, SIDs, duplicate/missing/corrupt diagnostics, and any diagnostic-only false-success claim. Retain the exact child exit and all existing identity/source/ACL gates.
6. Validate the exact child/launcher communication path non-elevated; publish new executable hashes, source/candidate lineage and Windows CI; obtain independent exact-SHA review and fresh explicit owner authorization before a future single UAC attempt.

This is a diagnostic-resolution proposal only. Do not add a new privilege channel or broaden the record schema unless independent review shows the existing bounded channel cannot carry the allowlisted stage.

## Remaining risks and next gate

- The actual elevated exception remains UNKNOWN; no specific defect has been demonstrated.
- The standard-token checks establish current read-only state, not successful execution under an elevated token.
- No v3 installation has been attested. Active v2 files and baseline evidence remain unchanged according to this read-only pass.
- Any changed executable bytes require a new independent source review and fresh owner authorization. The consumed second authorization cannot be reused.

**Next action:** independent review of this report and the proposed allowlisted operation-stage diagnostic change. Do not execute or retry the updater under the current authorization.
