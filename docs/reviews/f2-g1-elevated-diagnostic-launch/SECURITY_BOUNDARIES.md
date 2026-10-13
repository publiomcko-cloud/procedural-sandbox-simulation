# F2 G1 elevated diagnostic launch: security boundaries

## Allowed operation set

The elevated child may:

1. Verify it is Windows PowerShell 5.1 and has an elevated Administrator token whose user SID is identical to the original requester SID.
2. Read and verify the launch, source, candidate, wrapper, diagnostic module, historical updater, historical launcher, protocol and candidate manifest at the fixed paths and exact pins.
3. Run only fixed, local Git `rev-parse`, `config --local --get remote.origin.url`, and `status --porcelain` queries using the pinned `C:\Program Files\Git\cmd\git.exe`, with system/global configuration disabled, hooks disabled, optional locks disabled, fsmonitor disabled, and bounded stdout/stderr/deadlines.
4. Compile the embedded pipe/token helper and communicate one request and one bounded response over a local named pipe.
5. Parse the exact historical manifest-validation call and compare the returned `ReviewedCommitSha` with its expected source commit.

The executed PowerShell/native source has no call path to the protected updater entrypoint, recovery, transaction or rollback code, `icacls`, ACL-changing commands/APIs, Hyper-V/VM commands/APIs, disk/volume writes, registry writes, protected installation paths, `G:`, or native F2 workloads. The test suite parses the production launch/probe scripts and rejects the forbidden operation set; it separately checks the C# helper for write-capable APIs and constrains process creation to the fixed Git query wrapper.

No persistent file, registry, ACL, VM, disk, or protected-installation write is part of the production launch. The named pipe is a transient kernel IPC object. The tests write disposable files only under TEMP and remove their fixtures.

## Source and TOCTOU controls

- The outer command contains the reviewed bootstrap text. It does not dot-source a mutable bootstrap file.
- Before source execution, it resets `PSModulePath` to `$PSHOME\Modules`, checks the standard token and exact launch checkout, and reads the launch module through a bounded read-only handle. It verifies the SHA-256 and imports that same byte array with `New-Module`.
- It reads the requester launcher once, checks its exact checkout-byte SHA-256 and parses/builds the ScriptBlock from those same bytes.
- The requester checks the launch/source/candidate repository roots, origin, commit, clean state and reparse chains immediately before opening the pipe and reaching the UAC call. It also verifies all historical inputs and the wrapper/module/child hashes.
- The child loader resets `PSModulePath` before its first module-capable cmdlet, validates the child file chain, opens the file read-only with sharing restricted to readers, enforces a 256 KiB bound, hashes the bytes and executes a ScriptBlock made from those exact bytes.
- The elevated child repeats token, repository, fixed-path, reparse and input-hash checks. It loads the launch module and diagnostic module from pinned bytes, and gives the diagnostic wrapper the same verified diagnostic-module byte array in memory.
- The pinned Git binary and all script inputs are re-hashed at use boundaries. A mismatch, missing path, dirty checkout, alternate origin, unexpected reparse point or unavailable identity information fails closed.

`FileShare.Read` and in-memory execution prevent later path replacement from changing the bytes already verified for execution. Reparse checks protect path traversal. A malicious local Administrator or code already running inside the requester/elevated PowerShell process is outside this boundary; the plan is not a defense against a fully compromised host.

## One-shot pipe authentication

The requester creates a cryptographically random `F2D_<32 hex>` pipe name with `FILE_FLAG_FIRST_PIPE_INSTANCE` and `PIPE_REJECT_REMOTE_CLIENTS`. Its protected DACL grants access only to the requester SID, built-in Administrators and SYSTEM. Messages have a four-byte length prefix and a strict 8 KiB maximum.

`PipeOptions.CurrentUserOnly` is intentionally not used: on Windows the option also requires the same elevation level, so it does not fit a medium-integrity requester/high-integrity child. Instead, the peer is tied to the kernel-reported pipe PID, process creation time, exact image and encoded command line, process user SID, and a `RunAsClient` token check. The child independently checks the named-pipe server PID, creation time and SID. A random request nonce and request ID, exact field sets, source hashes, identity and process IDs are validated on both sides. A malformed, duplicate, oversized, replayed or conflicting frame fails closed.

Local administrators can still cause denial of service by racing/connecting to the random pipe; the peer checks reject that connection and no fallback or retry occurs. This is an availability limitation, not a path to run unverified commands or write files.

## UAC and identity policy

There is one `Start-Process -Verb RunAs` call site, after every deterministic requester-side preflight has passed. The code makes no automatic second launch. If a different Administrator account supplies credentials, the child SID will differ from the requester SID and the request is rejected. The owner must give ordinary, visible Windows consent for the same account's elevation; consent is never automated.

The code prevents a second launch within its single invocation. There is no durable cross-invocation attempt ledger: rerunning the exact command manually can present another UAC prompt. A separately granted one-time authorization must therefore be treated as consumed on the first UAC prompt, regardless of the result. The operator must not rerun it after that point.

The human consent UI itself is not on a tool-controlled deadline. After `Start-Process` returns, pipe connect and complete-child deadlines are bounded. On a timeout the parent reports the actual exit code when available and `ChildMayRemain`; it never terminates the elevated process. A remaining diagnostic-only child requires owner-directed process review before any later attempt.

## Output and failure reporting

- Standard output is one fixed-schema JSON result bounded to 8 KiB.
- The authenticated child carries a bounded diagnostic JSON record (maximum 4 KiB) plus up to 16 sanitized PowerShell `FullyQualifiedErrorId` values from a finite allowlist. Raw exception messages, paths, SIDs, SDDL, credentials and environment data are not serialized.
- The parent validates the nested schema, values, exact hashes, nonce, process identity and exit agreement. `PASS` requires the parser diagnostic PASS and child exit 0; it still means parser success only.
- `Start-Process -Verb RunAs` uses the ShellExecute parameter set, which cannot use the redirected-stream parameters from the redirected-start parameter set. Therefore the launch does not claim to capture arbitrary OS stdout/stderr. The child sends its bounded result through the authenticated pipe. If PowerShell fails before connecting, the parent reports a missing/invalid record and the real process exit when available; it does not trust hidden-window text or infer an internal stage.
- Child initialization failure after the authenticated connection yields a fixed stage/error classification. Errors before any trusted sender is available remain `UNKNOWN` with a missing record.
- Output overflow, incomplete framing, timeout, cleanup/reader failure, child-claim mismatch, false success flags or nonzero/conflicting exit never yield PASS.

## Difference from the unexplained historical elevated updater

The old incident was an elevated update process that could proceed through source/parent/installed-release checks and toward transaction-lock creation. This proposed probe runs a verified wrapper in an isolated PowerShell runspace and stops after the historical manifest parser call plus `ReviewedCommitSha` comparison. Its elevated identity, module path and standard-module search path are explicitly checked, but its runspace/scope, wrapper input-byte injection, pipe handshake, and intentionally absent updater transaction state differ from the historical updater execution context. A PASS or different failure here cannot prove the original PID 43072/6468/43072 behavior is fixed or diagnosed.

## Real-host conditions still UNKNOWN

- Windows UAC medium-to-high named-pipe behavior for the real requester and elevated child has not been exercised. The integration test uses ordinary same-token processes; the cross-token contract is supported by the explicit ACL/PID/SID/token checks but remains a real-host gate.
- The exact `Start-Process -Verb RunAs` command-line representation and WMI `Win32_Process.CommandLine` visibility in the target host have not been tested. An unavailable or differently represented value fails closed.
- Same-account UAC consent and rejection of alternate-account credentials have only synthetic token-policy coverage, not actual UAC validation.
- Protected/real host state is not read by this package; no live VM, ACL, `icacls`, `G:`, or protected installation state was queried here.
- No historical elevated process or updater entrypoint was run. The unexplained elevated failure remains UNKNOWN.

## Microsoft API references

- [Start-Process parameters](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/start-process?view=powershell-5.1) documents the separate `-Verb` and redirected-stream parameter sets.
- [PipeOptions](https://learn.microsoft.com/en-us/dotnet/api/system.io.pipes.pipeoptions?view=netframework-4.8.1) documents `CurrentUserOnly` behavior and its Windows security semantics.
- [GetNamedPipeClientProcessId](https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-getnamedpipeclientprocessid) supplies the kernel-reported client PID used for peer binding.
