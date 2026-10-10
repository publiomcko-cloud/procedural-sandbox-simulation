# F2 G1 ACL capture UAC handoff

**Status: READY_FOR_INDEPENDENT_REVIEW** — source-only correction for PR #49. No elevation or live ACL collection occurred.

## Ticket and acceptance criteria

GitHub Issue #48, final bounded worker transport correction. Starting review SHA: `06ad40652f06fa878d7ce65494dbafcd07f2d50f`. Deliver bounded worker process and stdout/stderr draining, preserve diagnostics and fail-closed completion, and retain all identity, source-pin, mailbox, and 11-object controls.

## Repository and Git

- Repository / remote: `publiomcko-cloud/procedural-sandbox-simulation` / `origin`.
- Worktree: `C:\Dev\f2-g1-acl-resolution`.
- Branch: `security/f2-acl-capture-issue48`.
- Base SHA: `06ad40652f06fa878d7ce65494dbafcd07f2d50f`.
- Candidate SHA and parent SHA: see final delivery report and the pushed PR #49 revision.
- PR #49 remains draft and unmerged.

## Changed paths

- `scripts/f2-acl/F2AclCapture.Protocol.psm1` — one monotonic deadline covers the worker process and both redirected readers; termination wait, reader disposal, exception cleanup, and process wait are bounded; `CleanupComplete` and reader errors gate completion.
- `scripts/f2-acl/Invoke-F2AclReadOnlyCapture.ps1` — retain an outer bounded coordinator wait margin and actionable nonzero timeout reporting.
- `scripts/f2-acl/Test-F2AclCapture.Protocol.ps1` — real Windows PowerShell 5.1 children holding stdout/stderr writers, output-producing hang, synthetic disposal failure, completion-validator rejection, and launcher timeout checks.
- `scripts/f2-acl/F2_ACL_SOURCE_PINS.json` — refreshed SHA-256 pins for the exact launcher and protocol module bytes.
- `docs/security/F2_G1_ACL_CAPTURE.md` — describe the complete execution/drain deadline and fail-closed stream cleanup behavior.
- `docs/handoffs/F2_G1_ACL_CAPTURE_PR49_HANDOFF.md` — this handoff.

## Implementation summary

`Invoke-F2AclCapturedPowerShell` starts a `Stopwatch` before process launch and uses its monotonic elapsed time as the absolute deadline for worker exit plus EOF on both redirected streams. It never joins an asynchronous reader after that deadline. At expiry it records timeout and pending-reader failures, attempts to terminate the worker, waits no longer than the configured cleanup grace, then closes redirected handles. All cleanup errors are retained. Actual PID and exit code are recorded when available, along with elapsed time, separate bounded stream bytes and hashes, truncation flags, fatal errors, and lifecycle stages. `OutputComplete` requires successful EOF on both streams, a successful exit before deadline, and clean disposal; the coordinator status validator also requires `CleanupComplete` and a normal `Exited` state. Thus exit code zero cannot override a timeout, a lingering pipe writer, incomplete output, or cleanup error.

The shared process-exit helper no longer calls unbounded `WaitForExit()`. The standard-token launcher allows a finite 60-second margin beyond the requested coordinator duration; on expiry it reports that the elevated coordinator remains running, returns failure, and accepts no evidence. It does not attempt to terminate a higher-integrity process.

## Tests executed

- Windows PowerShell 5.1: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\f2-acl\Test-F2AclCapture.Protocol.ps1` — **136 assertions, 0 failures**, process exit 0.
- Cases include normal production-path worker success; a worker exiting zero while an inherited stdout writer remains open; the corresponding stderr case; an output-producing hung worker; stream disposal failure; and coordinator rejection of zero-exit incomplete diagnostics.
- Parser sweep: **3 tracked PowerShell files, 0 errors**.
- `git diff --check` — pass.
- GitHub Windows CI and independent review are pending for the pushed immutable candidate.

## Limitations and risks

- Pipe-holder integration tests use synthetic Windows PowerShell descendants and validate bounded return and incomplete status; they do not reproduce UAC or the actual VM collector.
- A descendant holding an inherited writer may outlive the worker until its own exit. The coordinator closes its read handles, stops waiting, reports the incomplete stream, and never accepts a baseline. The pinned collector is not expected to spawn descendants.
- No live VM, ACL, registry, disk, Hyper-V setting, or G: file was inspected or changed. No UAC elevation was requested.
- The original live worker failure cause remains UNKNOWN. This correction addresses the confirmed source-level indefinite-drain path; it does not claim to identify the cause of earlier failures.
- Independent review at the final immutable SHA is required before another bounded read-only ACL collection can be authorized.

## Visual test steps

Not applicable. This is a source-only host PowerShell utility; elevation/live collection was expressly outside this task.

## Rollback

Revert this PR #49 source correction as an ordinary commit. Do not reset or force-push. No host or VM state was changed.

## Reviewer focus

- Verify the `Stopwatch` deadline applies while the process is alive and while either or both redirected readers remain pending after process exit.
- Verify no process/read-task wait is unbounded and all termination/disposal failures remain visible and fail closed.
- Verify a zero worker exit plus incomplete output cannot pass the status validator.
- Verify exact source pins, worker PID/exit/hash/stage diagnostics, Kingston and VM checks, protected mailbox controls, and 11-object scope are unchanged.
