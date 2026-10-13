# F2 G1 third upgrade failure: candidate-manifest validation

**Status: READY_FOR_INDEPENDENT_SOURCE_REVIEW. This package does not authorize or perform another UAC attempt.**

## Incident and scope

Issue #48 comment `6145144520` reports that the third UAC attempt was consumed; elevated child PID `43072` exited `1`; the authenticated child diagnostic reported stage `CandidateManifestValidation`, code `UPDATE_UNCLASSIFIED_FAILURE`, and request ID `b602e9f5c5754bb69e54dde657a3c4d7`. The reviewed production source at the time was `396c44965c90c08292ad2835f8317e81b6b9daaf`.

This correction is limited to the candidate-manifest validation function and its synthetic regression tests. It does not change Git resolution, ACL policy, the release transaction, runtime package contents, or diagnostic transport.

## Findings

### Confirmed

- The approved read-only postfailure preflight passed all six gates under standard-token Windows PowerShell 5.1. It checked the current v2 manifest and seven installed files, protected owner/DACL and reparse profiles, parent ACL policy, original retained baseline identities/hashes/completeness, and absence of transaction objects. The sanitized machine receipt is `evidence/POSTFAILURE_READONLY_PREFLIGHT.json`.
- The exact reviewed v3 candidate bytes pass the production `Get-F2UpdateManifestObject` function in Windows PowerShell 5.1.
- Before the correction, a disposable candidate-shaped JSON object missing `BaselineMailboxId` caused a StrictMode missing-member exception before the old function had checked for required fields. The child diagnostic normalizer classified that unanticipated exception as `UPDATE_UNCLASSIFIED_FAILURE`. The reproduction used only synthetic in-memory/TEMP data and is recorded in `evidence/PRE_FIX_REPRODUCTION.txt`.
- The production function now validates the JSON root, required identity fields and types, file array and entry shapes, schema, source-pin digest, and v3 package root before consuming them. Failures map to a finite set of stable, allowlisted operation codes. Arbitrary exception text/types/values are not sent to the child diagnostic channel.
- A real non-elevated child-process test exercises the production child-script builder, production parser, and authenticated diagnostic pipe for both valid and malformed candidate fixtures. It uses a no-write updater stub and TEMP-only fixture trees.

### Still unknown

The exact cause of child PID `43072`'s elevated failure is **UNKNOWN**. The observed stage narrows the reported failure to the bootstrap's candidate-manifest validation call and reviewed-commit comparison, before updater invocation. The exact pinned candidate passes the same parser under standard-token Windows PowerShell 5.1, so the synthetic malformed-input reproduction does not prove that malformed input caused the real incident. No elevated rerun or protected-state mutation was performed.

## Source and release identity

- Correction commit: `af9aa616e112e4db4abd7cc607d396fdadb7b76c`
- Parent: `7f99bc10f3e2258d2340cea4e7ba1352022cbb6d`
- Corrected production updater, Windows checkout bytes (CRLF): `88bbc62d9a083c278f2f9ab56fd4507a220234ee266232cf6f1a69f2f9740b02`
- Launcher, Windows checkout bytes: `9fc4d574eda4a03ee05bca5ce789bdb10ee0b05f5f6de273839ba0060445bdc9` (unchanged)
- Diagnostic protocol, Windows checkout bytes: `66466fd15ce161fe2b522c77cfd6500845012480fc64890aa8435f54197eedc7` (unchanged)
- Source-pin manifest SHA-256: `7e05d48ef25e7cff19d84db151395921b5d89b52b1e2f45b94a84a4778a615ce` (unchanged)
- Candidate v3 manifest SHA-256: `f9034e16287006522ece2efd03a0b427a0beec7e3edadbe06d32d49e9cfd2f29`
- Candidate `ReviewedCommitSha`: `af9aa616e112e4db4abd7cc607d396fdadb7b76c`
- Candidate `PackageRoot`: `C:\Program Files\F2-G1-Icacls\releases\af9aa616e112e4db4abd7cc607d396fdadb7b76c`

The seven release member bytes and their pins are unchanged. The machine-readable source-chain test verifies the production commit, parent, clean worktree, origin, executable and module hashes, seven members, candidate digest and candidate-to-production identity.

## Validation

On Windows PowerShell `5.1.22621.6133`, all seven regression suites passed: **553 assertions, 0 failures, each child process exit code 0**. This includes the protocol, entrypoint, corroboration, runtime, native-helper, updater, and diagnostic suites. The diagnostic suite includes the malformed manifest cases and production child/pipe integration. See `evidence/final/` for complete command/output logs.

The existing F2 ACL parser test parsed 21 PowerShell files with zero errors. The additional relevant sweep parsed those 21 production/test files plus the two new review scripts: 23 files, zero errors. The exact-source-chain validation passed. `git diff --check` is recorded after staging the complete review package.

An exploratory sweep of all tracked PowerShell files also found parse errors in two unrelated files, `check_f1_6_notice_text.ps1` and `validate_fixture.ps1`; its complete output is retained as `evidence/final/EXPLORATORY_REPOSITORY_WIDE_PARSER_SWEEP.txt`. They are outside this correction and were not changed. The focused F2 ACL parser suite is clean.

Hosted Windows CI status for the final immutable review commit is linked from the draft PR checks. No test here establishes elevated behavior or actual protected C: upgrade success.

## Safety and next gate

No UAC, protected updater execution, protected C: writes, recovery, rollback, cleanup, ACL change, live `icacls`, VM/Hyper-V/G: access, process termination, native workload, baseline change, or PR merge occurred. The previous three UAC authorizations remain consumed. Independent exact-SHA source review and a new, separate owner authorization would be required before any later elevated attempt.

## Evidence index

- `evidence/PRE_FIX_REPRODUCTION.txt` — sanitized malformed-input reproduction and explicit incident-cause uncertainty.
- `evidence/POSTFAILURE_READONLY_PREFLIGHT.json` — sanitized six-gate postfailure host receipt.
- `evidence/Test-F2G1CandidateManifestSourceChain.ps1` — non-elevated exact lineage/pin check.
- `evidence/Test-F2G1ThirdUpgradeParserSweep.ps1` — scoped Windows PowerShell parser sweep.
- `evidence/iteration-a-before-candidate-repin/` — initial test logs before updating candidate metadata to the correction commit; retained as iteration history.
- `evidence/final/` — authoritative final test logs and parser/source-chain results.
