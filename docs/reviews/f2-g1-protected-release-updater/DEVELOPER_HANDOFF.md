# Developer handoff

Status: READY_FOR_INDEPENDENT_REVIEW

Ticket / review: PR #59 review `5492493517`; Issue #48 finding `6126813885`.

Repository / remote: `publiomcko-cloud/procedural-sandbox-simulation` / `https://github.com/publiomcko-cloud/procedural-sandbox-simulation.git`.

Worktree / branch: `C:\Dev\f2-g1-protected-updater` / `fix/f2-g1-protected-release-updater`.

Base SHA: PR #58 head `0a4d98ecad4c50ba2f749e4fafe6d28e35794804`.

Corrected production source SHA: `691eae48d67789bf798e270cb9cca7790d728d26`.

Parent SHA: `40723492b97983c0c7bc6d441a1bcbace823ffe8`.

Changed production/test paths: `.github/workflows/f2-acl-source-only.yml`; `scripts/f2-acl/Invoke-F2ProtectedReleaseUpdate.ps1`; `scripts/f2-acl/Test-F2AclProtectedReleaseNativeHelper.ps1`. Review/evidence paths are the candidate v3 manifest and files under `docs/reviews/f2-g1-protected-release-updater/`.

Implementation summary: The updater's embedded P/Invoke call now passes `IntPtr.Zero` for the `IntPtr` CreateFile template handle. The new test extracts and compiles the exact production C# here-string in Windows PowerShell 5.1 without invoking the updater, then tests TEMP-only protected directory/file creation, owner/DACL read-back, exact fixture ACE masks/flags, byte write and create-new collision rejection. CI runs this regression as a required workflow step.

Release provenance: Candidate v3 manifest binds `ReviewedCommitSha` and the versioned `PackageRoot` to production source commit `691eae48d67789bf798e270cb9cca7790d728d26`. Candidate manifest SHA-256 is `be98e9101f9171bb1bba59bfa063fc424132e19579b16d75816cec3b345974e2`. The corrected updater SHA-256 is `49afef854aaee2b4501325063ade14e496072aaf74745e1203c2029ce9287744` for Windows CRLF checkout bytes and `47953d6124c021b0b0332a37ab0183ea1b544cfb375a78c9a38081f7ca92e4fd` for LF Git content. The seven release-file hashes and source-pin manifest are unchanged and verified against the candidate.

The Windows CRLF digest was independently measured in a clean detached checkout at that exact production commit: 701 CRLF line endings, zero bare LF, expected hash PASS. See `evidence/WINDOWS_CRLF_HASH_VALIDATION.txt`.

Tests executed: Six direct Windows PowerShell 5.1 suite commands and results are in `F2_G1_PROTECTED_RELEASE_UPDATER_REVIEW.md` and the complete stdout/stderr files in `evidence/`. Results: Protocol 152/0; Corroboration 118/0; Runtime 41/0; Entrypoint 18/0; Updater 104/0; native helper 20/0; total 453 assertions, zero failures, six process exit codes 0. Parser: 14 PowerShell files, zero errors. `git diff --check`: pass. Windows CI run `38269076173` / job `114878539008` succeeded on the source commit; run `38270088078` / job `114881911163` also passed on the final evidence head. Both are linked from `evidence/WINDOWS_CI.txt`.

Native failure reproduction: A fresh Windows PowerShell 5.1 process compiled the exact embedded C# from blocked source `40723492b97983c0c7bc6d441a1bcbace823ffe8`; `Add-Type` failed on `null` passed to the `System.IntPtr` parameter and the child exited 1. No updater entrypoint was called. The sanitized diagnostic is in `evidence/NATIVE_COMPILE_REPRO_BEFORE_FIX.txt`.

Tests not executed: actual Administrator UAC; protected C: installation/update or recovery; live `icacls`, ACL/token/parent queries; G:, VM or Hyper-V operations; native collector/workload. No production updater invocation was made.

Limitations: The native C# source compiles and its create-new/security-descriptor calls work with a current-user-owned TEMP fixture. This does not verify Administrator token behavior, actual C: parent ACLs, protected ownership or DACLs, installer/UAC identity behavior, protected-volume rename semantics, or a real update transaction. Those require a new exact-SHA independent review and fresh owner authorization.

Reviewer focus: verify `IntPtr.Zero` is the only production change; inspect that the test compiles the exact production here-string without updater execution; check current candidate commit/package-root/hash chain; confirm test and CI evidence; retain the privileged-only unknowns above.

No UAC, protected update, live host query, ACL modification, VM operation, native F2 workload or merge was performed.
