# Developer handoff — F2 G1 launch-topology correction

Status: READY_FOR_INDEPENDENT_REVIEW (source-only; no UAC or protected update).

Ticket: Issue #48 comment 6128611541; PR #59 review 5493687988.

Repository: `publiomcko-cloud/procedural-sandbox-simulation`
Remote: `https://github.com/publiomcko-cloud/procedural-sandbox-simulation.git`
Worktree / branch: `C:\Dev\f2-g1-protected-updater` / `fix/f2-g1-protected-release-updater`
Reviewed base: `d14aa0f6c9a1e358afa5b2a04a17e27a9bff22ed`; parent `d63b51db7c2de8b8e1197ebede653f4d762cae9a`.
Final immutable review SHA: the exact commit at the open draft PR #59 head; see PR metadata and final handoff report.
Production SourceRoot remains `8b70a70934445bee660c1e53e71b2e7b20a6191f`; no production source changed.

## Changed paths

- `scripts/f2-acl/Test-F2AclProtectedReleaseUpdater.ps1`: adds the three-process rejection, two-process acceptance, requester PID/SID/time and all source/hash pin negatives, and TEMP-only CMD quoting/exit propagation and file-share tests.
- `docs/reviews/f2-g1-protected-release-updater/F2_G1_PROTECTED_RELEASE_UPDATER_REVIEW.md`: replaces the unusable PowerShell-parent command with exact CMD launch steps and copyable quoting/exit-code commands.
- `docs/reviews/f2-g1-protected-release-updater/F2_G1_PROCESS_QUIESCENCE_REVIEW.md`: records the process topology proof, exclusion rule and synthetic results.
- `docs/reviews/f2-g1-protected-release-updater/evidence/`: full six-suite stdout/stderr, parser/diff results, harness diagnosis, EOL/hash reconciliation, Windows CI link/log and artifact manifest.

The updater, standard launcher, native helper, candidate v3 manifest, seven packaged release files and source-pin manifest are byte-for-byte unchanged. Existing production Windows CRLF hashes remain updater `d26eb89a424e3f268099e0ac1d3ffd674dde1128321567df3a0702abb591f75e`, launcher `8278bbff8e5b7cdb313235bcc271fa31a947ca384d7496053650c3097af19720`, and candidate manifest `74d178917fba4f50fdca40505d8c1dc81639f3c60bbb25c0332fd737c681562c`.

## Security behavior

The old PowerShell caller remains rejected; no ancestor exception was added. The proposed future procedure exits all PowerShell hosts normally, opens a fresh CMD from Explorer's Win+R dialog, and launches only the exact pinned requester PowerShell. During the UAC child, the inventory should then contain only the requester and updater. Unrelated, inaccessible, legacy, encoded or direct runtime PowerShell activity still blocks. Manifest barrier acquisition and both process scans retain their previous ordering. The production executable hashes and all seven payload hashes remain unchanged.

## Validation

Windows PowerShell 5.1 suites: Protocol 152, Corroboration 118, Runtime 41, Entrypoint 18, Updater 133, Native helper 20; **482 assertions, zero failures; six child exit codes 0**. The updater suite's inert CMD fixture propagated synthetic exit code 37. PS5.1 parser sweep: 14 files, zero errors. `git diff --check`: pass. Hosted Windows CI final run and complete logs are linked from the PR and retained under `evidence/`.

An initial Start-Process test harness inherited the PowerShell 7 `PSModulePath` into its Windows PowerShell 5.1 child and failed to auto-load `Get-FileHash`. This was reproduced and recorded; direct Windows PowerShell 5.1 invocation with separate stream capture passed the suite. The initial aggregate summary predicate also misread Protocol's trailing case-list line; actual child exits and per-suite assertions were checked individually. See `WINDOWS_TEST_HARNESS_DIAGNOSTIC.txt`.

## Risks and limitations

The process table was synthetic only. Elevated WMI owner/time visibility, real UAC process topology, actual C: NTFS share/replace and protected DACL behavior remain unknown or not run. The invocation is a proposed future command, not permission to execute. No process termination, UAC, protected update/recovery, live ACL/icacls, VM/Hyper-V/G: access, baseline change, native F2 workload or PR merge occurred. Independent exact-SHA review and fresh owner authorization remain mandatory before an update.

Visual test steps: not applicable. Rollback: none performed; do not execute recovery from this source-only handoff.
