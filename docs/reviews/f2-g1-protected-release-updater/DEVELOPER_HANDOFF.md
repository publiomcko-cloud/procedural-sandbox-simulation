# Developer handoff

Status: READY_FOR_INDEPENDENT_REVIEW

Ticket / acceptance criteria: Issue #48 comment `6123499243`; PR #58 review `5490189436`. Implement a source-only, fail-closed protected-release updater with transaction recovery and a reviewed launch boundary.

Repository / remote: `publiomcko-cloud/procedural-sandbox-simulation` / `https://github.com/publiomcko-cloud/procedural-sandbox-simulation.git`.

Worktree / branch: `C:\Dev\f2-g1-protected-updater` / `fix/f2-g1-protected-release-updater`.

Base SHA: `0a4d98ecad4c50ba2f749e4fafe6d28e35794804` (PR #58 branch head at fetch).

Candidate SHA (production release source): `0bda8f6437ad2ddb7ce24d3bf905a18f363df9df`. A test-only fixture portability correction is commit `73d2f7fbdd2f0295ff2cafc29c49d6471b98d6ec` (parent `e7b813a8b67af8081a967a4002e9786f557dbb81`); it does not change the updater or seven packaged release files. The evidence-only commit is a child of the corrected test commit; the immutable SHA is the draft PR head metadata.

Parent SHA (production source): `c95d0e4defc0d840995e69f96982f51dd9be779d`.

Changed paths: `.github/workflows/f2-acl-source-only.yml`; `scripts/f2-acl/F2AclIcacls.Runtime.psm1`; `scripts/f2-acl/F2_ICACLS_SOURCE_PINS.json`; `scripts/f2-acl/Invoke-F2IcaclsProtectedCoordinator.ps1`; `scripts/f2-acl/Invoke-F2ProtectedReleaseUpdate.ps1`; `scripts/f2-acl/Start-F2ProtectedReleaseUpdate.ps1`; `scripts/f2-acl/Test-F2AclEntrypointArguments.ps1`; `scripts/f2-acl/Test-F2AclIcacls.Runtime.ps1`; `scripts/f2-acl/Test-F2AclProtectedReleaseUpdater.ps1`; plus all files under `docs/reviews/f2-g1-protected-release-updater/`. The updater source commit contains implementation and regressions; the test-only descendant makes the old-release fixture self-contained using the pinned Git commit; the evidence descendant carries the candidate manifest, handoff, logs and transaction review.

Implementation summary: v3 versioned package staging and complete preflight; create-new protected paths; a shared runtime/exclusive updater lease and active-manifest barrier; one explicit same-requester UAC boundary; an atomic manifest pointer switch after package verification; retained old files/manifest; hash-chained bounded transaction journal; exact transaction-ID recovery with forward-only completion and no cleanup/rollback.

Architectural impact: switches the active package from the fixed v2 tree to an immutable commit-versioned tree via one external v3 manifest replacement. The old v2 fixed tree and external manifest backup remain. Recovery never guesses or deletes.

Dependencies added / licenses: none. Uses Windows PowerShell 5.1, .NET Framework APIs and existing Git installation.

Tests executed (exact commands): see `F2_G1_PROTECTED_RELEASE_UPDATER_REVIEW.md` and complete command/output logs in `evidence/`; five Windows PowerShell 5.1 suites, PowerShell AST parser sweep and `git diff --check`.

Results / assertion counts: Protocol 152/0; corroboration 118/0; runtime 41/0; entrypoint 18/0; updater 104/0; **433 assertions / 0 failures**. The local Windows PowerShell 5.1 updater rerun after the fixture correction exited 0. GitHub Windows CI run `38253974457`, attempt 2, passed all five suites (433 assertions, five child exit codes 0), parser (13 files / zero errors), and `git diff --check`; details and links are in `evidence/WINDOWS_CI.txt`.

Tests not executed: actual protected installation/update; actual UAC; live `icacls`, host ACL/token or parent ACL inspection; VM/Hyper-V/G: operations; real protected native ACL creation or real host crash testing.

Failure/recovery cases: injected fault after every transaction checkpoint; incomplete stage preserves old active manifest; exact ready package may be promoted forward only; active v3 release is verify-only; unknown paths, modified source/package, DACL, journal, manifest or process status block. No rollback/deletion path.

Benchmark machine and metrics: not applicable; this is an administrative source-only updater.

Known limitations: elevated host behavior remains unverified; parent waiting is bounded but does not terminate an unknown child; noncooperating Administrator tampering is outside the protection model; GitHub CI validates synthetic paths only. Initial PR CI attempt `38253314568` exposed a stale absolute local fixture path; the test now extracts the pinned old commit from the repository object database and verifies all seven installed-byte hashes. The first attempt of CI run `38253974457` reported protocol child exit 5 immediately after `Stage=bounded_partial_pipe_read`; a direct local rerun passed 152 assertions, and rerunning the failed CI job passed. The transient exit-5 cause is UNKNOWN and the failed run remains linked in the evidence.

Visual reproduction steps: not applicable.

Rollback instructions: none is automatic or approved. Preserve the previous fixed-path v2 files and the external v2 manifest backup. If an incomplete or unknown state appears, stop and retain all objects for a new reviewed recovery instruction.

Reviewer focus / open questions: verify all candidate hashes and the CRLF bootstrap/updater hashes; inspect mixed-release boundary, locking, manifest replacement, ACL application, exact journal readiness sequence and recovery fail-closed behavior. Independent review is required before any future protected execution.
