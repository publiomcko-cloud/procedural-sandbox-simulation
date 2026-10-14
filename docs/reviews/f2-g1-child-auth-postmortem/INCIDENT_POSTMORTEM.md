# F2 G1 historical-manifest diagnostic incident postmortem

**Disposition: SOURCE_DEFECT_CONFIRMED for failure classification only. The consumed attempt’s underlying exception remains UNKNOWN.**

This source-only analysis uses the immutable PR #69 reviewed launch source. It cannot reconstruct an exception that was not captured. The reported result proves only that an exception inside ChildAuthentication did not match the launcher’s safe-code allowlist.

## Preserved incident evidence

These are the exact fields and values supplied, in their reported order. The original serialized byte stream was not separately attached.

    {
      "Status": "FAIL",
      "Stage": "ChildAuthentication",
      "ErrorCode": "LAUNCH_UNCLASSIFIED_FAILURE",
      "UacAttempted": true,
      "ChildPid": 39732,
      "ChildExitCode": null,
      "ChildMayRemain": true,
      "DiagnosticStatus": "MISSING_OR_INVALID",
      "UpdaterEntrypointInvoked": false,
      "RecoveryEntrypointInvoked": false,
      "ProtectedWritePerformed": false
    }

The later human-operated standard-token PID result, preserved exactly:

    PROCESS_NOT_VISIBLE_AT_CHECK_TIME

No timestamp, command transcript, WMI row, or child exit result was supplied. Codex did not perform that query. It cannot show whether PID 39732 had exited, whether WMI could see it, or what the process was doing at the time of failure.

The one UAC attempt is consumed. This task performed no UAC/RunAs, process inspection or termination, protected operation, updater/recovery invocation, VM/Hyper-V/G: access, ACL change, or baseline change.

## Immutable source and stage boundary

- Reviewed launch HEAD: 56a34d7899ba31b0d3fe6d3185435bc182ac453f
- Launch implementation parent: 8c14cf97c9446e11b8afbd64196c3f4558d4c3c9
- Repository: https://github.com/publiomcko-cloud/procedural-sandbox-simulation.git
- Files: scripts/f2-acl/Start-F2HistoricalManifestDiagnostic.ps1; scripts/f2-acl/F2HistoricalManifestLaunch.psm1; scripts/f2-acl/Invoke-F2HistoricalManifestDiagnosticChild.ps1

In the reviewed launcher, the Start-Process result’s Process.StartTime is read at line 145 while the stage is UacLaunch. ChildAuthentication is set only after EndWaitForConnection at line 155. That earlier StartTime read is not a source explanation for this recorded stage unless the result came from different bytes.

The stage lasts through response framing and child-exit wait; it changes to ResultValidation at line 184. Operations in order:

| Order / reviewed lines | Throwing operation and possible classification |
|---|---|
| 1. Launcher 156; module 38, 57 | GetNamedPipeClientProcessId failure makes ClientPid throw Win32Exception. It is not allowlisted and can become generic. Microsoft documents failure via return 0/GetLastError; there is no evidence of the actual return/error here. |
| 2. Launcher 157; module 549–553 | GetProcessById, StartTime, and MainModule.FileName are unwrapped. They can fail for unavailable/exited processes; StartTime documents Win32Exception/InvalidOperationException and MainModule documents InvalidOperationException/Win32Exception. Unlisted errors become generic. |
| 3. Launcher 158; module 311–323 | Test-F2LaunchProcessCommandLine catches query/record exceptions and returns false. That normally becomes explicit LAUNCH_CHILD_COMMAND_MISMATCH at the next peer-facts check, not generic. |
| 4. Launcher 159–160 | False identity facts give an explicit mismatch. Unexpected binding/conversion or Path.GetFullPath failures can escape to generic. |
| 5. Launcher 161–163; frame reader 53–64; hello test module 343–349 | Timeout, EOF, and bad frame size have explicit codes. Other read/decode errors and malformed JSON can be generic. False hello validation gives explicit PEER_MISMATCH; malformed numeric fields can throw. |
| 6. Launcher 165–173 | RunAsClient documents InvalidOperationException, ObjectDisposedException, and IOException cases. Callback token/native calls may also fail. These are unwrapped and can become generic. |
| 7. Launcher 174–175 | Missing/mismatched token facts give explicit TOKEN_MISMATCH; unexpected property, conversion, or token-query errors can be generic. |
| 8. Launcher 176–180 | Serialization, frame creation, pipe write/read, strict decode, and response JSON parsing can throw. Existing frame/timeout errors are safe; unlisted exceptions can be generic. |
| 9. Launcher 181–183 | Normal timeout is explicit EXIT_TIMEOUT. Unexpected WaitForExit or ExitCode errors can be generic. |
| 10. Launcher 188–200 | Outer catch maps any unlisted FullyQualifiedErrorId to LAUNCH_UNCLASSIFIED_FAILURE. Catch-time process-status lookup failure is swallowed and leaves ChildMayRemain true. Finally disposal is unwrapped, but the supplied result was emitted. |

The child sends a hello only after initial pipe/requester checks (child lines 107–136); the parent authenticates hello and token before sending the request. A parent-side failure before the authenticated exchange can leave DiagnosticStatus=MISSING_OR_INVALID. The supplied data does not reveal whether the child connected, sent hello, or exited.

## Findings

### CONFIRMED

1. The reviewed source has a deliberate safe-code allowlist, but several ChildAuthentication operations can throw ordinary .NET or native exceptions that are not mapped to operation-specific codes.
2. The native client-PID wrapper throws Win32Exception; process identity access and RunAsClient are not wrapped; malformed JSON and some frame/stream failures can also escape. Synthetic tests below reproduced classifier behavior without calling those APIs.
3. The WMI command-line helper catches its errors and returns false. Under the reviewed call sequence, that normal false result leads to an explicit command-mismatch code, not the observed generic code.
4. The observed JSON has no exception category, FullyQualifiedErrorId, per-operation marker, or authenticated child diagnostic. It cannot identify the failing operation.
5. ChildMayRemain=true is a conservative catch-time status. It means the launcher did not confirm exit at that point; it is not a later process-state assertion.

### STRONGLY SUPPORTED, NOT CONFIRMED FOR THIS ATTEMPT

- A process exit, stale/reused PID, pipe disconnect, inaccessible process property, token-query failure, malformed frame, or other operation failure could enter the generic catch path.
- Cross-integrity metadata availability is a plausible uncertainty. Microsoft documents that UAC can affect WMI results generally, but Win32_Process is not among the specific class/property omissions listed on the cited page. That does not prove the command-line query was denied or incomplete here.
- PROCESS_NOT_VISIBLE_AT_CHECK_TIME is compatible with the child exiting before inspection, but also with a visibility/query limitation. It does not distinguish them.

### UNKNOWN

- Which ChildAuthentication operation threw, and the actual exception category or FullyQualifiedErrorId.
- Whether GetNamedPipeClientProcessId, Process.StartTime, Process.MainModule, WMI, pipe framing, JSON parsing, RunAsClient, or token retrieval failed.
- Whether PID 39732 was still running at the later inspection or was no longer visible for another reason.
- Whether the UAC token used same-account consent or different-account credentials; no identity evidence for this attempt was supplied.
- Whether ChildMayRemain reflected a live child or a status-query exception.

## API assessments

### QueryFullProcessImageNameW

This is a reasonable narrower path for obtaining the peer executable path than enumerating Process.MainModule. Microsoft documents that it returns an image path from a process handle opened with PROCESS_QUERY_LIMITED_INFORMATION or PROCESS_QUERY_INFORMATION. GetProcessTimes, which can supply the creation time used in the existing PID-reuse binding, documents the same rights. Reusing one handle for image path and creation time would tie the facts to one process object.

This is a design recommendation, not a claim that access is guaranteed across medium/high integrity. OpenProcess still checks the process DACL. Failure to open/query must remain a hard authentication failure; PID, creation-time, expected image-path, command-line, requester SID, and elevated-token checks must remain enforced. No API substitution was made because the original exception is unknown and cross-integrity behavior was not tested.

### WMI command-line visibility

The launcher requires exactly one Win32_Process row with expected PID, image, and exact encoded command line. Test-F2LaunchProcessCommandLine catches query errors and returns false; the caller rejects that result with an explicit mismatch. Microsoft UAC guidance establishes that WMI access/data may differ under filtered versus elevated tokens, but does not establish that Win32_Process.CommandLine is unavailable between these same-host tokens. The human result was collected later and cannot establish what WMI returned during the attempt.

## Narrow source correction prepared for review

A separate candidate correction adds Invoke-F2LaunchChildAuthOperation around each fallible operation in this stage. It maps otherwise-unclassified failures to a fixed ValidateSet of operation-specific safe codes, preserves existing allowlisted errors such as timeout/EOF/frame errors, and emits no exception text, path, SID, SDDL, or environment value. Existing false/mismatch checks remain failures; authentication conditions, WMI requirements, source pins, bounds, pipe policy, and entrypoint ordering are unchanged.

The candidate wrapper is at `scripts/f2-acl/Start-F2HistoricalManifestDiagnostic.ps1:74-87`; the bounded operation wrappers are applied at lines 171-206. The regression that exercises the production classifier functions and operation wrappers is `docs/reviews/f2-g1-child-auth-postmortem/Test-F2ChildAuthenticationClassification.ps1`.

This improves future failure localization. It does not identify or resolve the consumed attempt’s underlying cause and authorizes no execution. PR #69 remains unchanged at its reviewed HEAD; this correction is a separate draft proposal.

## Synthetic source-only validation

Command:

    C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\docs\reviews\f2-g1-child-auth-postmortem\Test-F2ChildAuthenticationClassification.ps1

Windows PowerShell 5.1.22621.6133: 34 assertions, 0 failures, exit 0. The test extracts only selected production function definitions through the PowerShell AST, injects synthetic exceptions and a mocked WMI query failure, verifies safe classification and call-site coverage, and parses the pinned launcher/module. It started no test child process and attempted no UAC. It did not call Win32 process APIs, WMI on the host, a named pipe, RunAsClient, or the diagnostic entrypoint.

git diff --check passed. Hosted CI and the complete inherited suites were not run for this narrow correction.

## Follow-up: operation wrapper value preservation and CI failure triage

**Confirmed additional source defect:** the production operation wrapper at `scripts/f2-acl/Start-F2HistoricalManifestDiagnostic.ps1` stored the operation output in `$result` and returned it with `return $result`. Under Windows PowerShell 5.1, that function return enumerated a framed `System.Byte[]` into `System.Object[]`. An in-memory reproduction against the production wrapper and the actual `ConvertTo-F2LaunchFrame` function observed:

    FrameDirect=System.Byte[];count=15
    FrameWrapped=System.Object[];count=15
    StreamWrapped=System.Object[];count=15
    FrameDirectEq=True
    StreamEqual=True

The `MemoryStream.Write` call accepted and converted the object array in this fixture, and its bytes matched. This proves a production return-type contract defect; it does not prove that the type change caused a real named-pipe failure or the consumed incident. The minimal correction is `return ,$result`, which preserves arrays as one pipeline value. The wrapper's ValidateSet, safe-code allowlist, error mapping, pipe framing and authentication checks are unchanged.

The focused regression now extracts the actual wrapper, `Get-F2LaunchUtf8`, and `ConvertTo-F2LaunchFrame` from the production AST and checks Boolean, String, PSCustomObject, byte-array, MemoryStream write/read, no-output, known-error and unknown-error behavior. Windows PowerShell 5.1.22621.6133 reports 48 assertions, zero failures, exit 0, with `CHILD_PROCESSES_STARTED=0` and `UAC_ATTEMPTS=0`. Full output and the exact command are in `TEST_RESULTS.txt`.

### CI log comparison

- Failed PR #71 run: [38559236368](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/38559236368), job `115835905572`. The diagnostics step first diverged at “real child script retains exact exit when protocol bootstrap fails before a trusted sender is available” after the preceding child fixtures passed. Every subsequent real-child/cross-process case logged a failure; multiple diagnostics explicitly reported `TIMEOUT`, `UPDATE_DIAGNOSTIC_TIMEOUT`, and no child exit code. Final `WrongClientResult` was `TimedOut=true`, `ActualChildExitCode=null`; total was 68 assertions, 28 failures, process exit 1.
- Successful PR #69 run: [38471926228](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/38471926228), job `115552904354`. The same step and unchanged test source completed 68 assertions, zero failures, process exit 0.
- Both logs report Windows Server 2025 build `10.0.26100`, runner `2.337.0`, and image `windows-2025-vs2026` version `20260925.250.1`. That rules out a different reported runner image, but does not establish equivalent transient resource state.
- The PR #71 candidate changes `Start-F2HistoricalManifestDiagnostic.ps1` and its review documents/tests. The failed step invokes `Test-F2ProtectedReleaseDiagnostics.ps1` as a separate PowerShell process; that test loads the protected-release diagnostics module/updater and does not import, dot-source, or reference the changed launcher or `Invoke-F2LaunchChildAuthOperation`. The workflow/test bytes are unchanged from PR #69. Therefore the PR #71 source change is not reachable from the failed suite by the inspected source call graph.
- The repeated timeout pattern supports a shared child/pipe/exit-wait symptom after the first divergence. The logs do not identify its cause. They contain no runner resource telemetry or discriminating setup error. Runner/resource exhaustion, fixture behavior, process startup, and pipe/test-harness failure remain hypotheses; none is confirmed. No workflow rerun was performed.

This correction does not explain the failed PR #71 CI step and does not identify the historical `ChildAuthentication` exception. The historical cause remains UNKNOWN. Because the required CI failure remains unexplained, the candidate is not correction-ready for final acceptance.

## Next gate

The source correction requires independent source review. No fourth UAC authorization exists. Any later execution requires newly approved exact source bytes and fresh explicit owner authorization. This postmortem is not a readiness report and makes no claim a later attempt would succeed.

## Microsoft API references

These references support the documented API contracts and exception possibilities; they do not identify the exception from this incident:

- [`GetNamedPipeClientProcessId`](https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-getnamedpipeclientprocessid) reports failure with a zero return and directs callers to `GetLastError`.
- [`Process.StartTime`](https://learn.microsoft.com/en-us/dotnet/api/system.diagnostics.process.starttime) and [`Process.MainModule`](https://learn.microsoft.com/en-us/dotnet/api/system.diagnostics.process.mainmodule?view=net-5.0) document process-state and Win32 exception cases relevant to the unwrapped accessors.
- [`NamedPipeServerStream.RunAsClient`](https://learn.microsoft.com/en-us/dotnet/api/system.io.pipes.namedpipeserverstream.runasclient?view=net-8.0) documents pipe-state and I/O exceptions that can escape the callback call site.
- [`UAC and WMI`](https://learn.microsoft.com/en-us/windows/win32/wmisdk/user-account-control-and-wmi) documents that UAC filtering can affect WMI results and enumerates affected classes/properties. It does not list `Win32_Process`, so it is not evidence that this query failed.
- [`QueryFullProcessImageNameW`](https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-queryfullprocessimagenamew) and [`GetProcessTimes`](https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-getprocesstimes) both accept handles with `PROCESS_QUERY_LIMITED_INFORMATION` or `PROCESS_QUERY_INFORMATION`; [`process access rights`](https://learn.microsoft.com/en-us/windows/win32/procthread/process-security-and-access-rights) explains that the process DACL is still checked. This supports considering a narrower image-path/creation-time query, not assuming cross-token access will succeed.
