# F2 G1 elevated diagnostic launch: security boundaries

## Allowed operation set

The elevated child may verify its Windows PowerShell 5.1 version and same-requester elevated Administrator token; read pinned source/candidate/diagnostic inputs; perform four fixed, local Git queries; compile the small pipe/token helper; authenticate one local pipe request; parse the candidate manifest; and compare `ReviewedCommitSha` with the pinned source commit. It cannot reach the updater, recovery, transaction, rollback, `icacls`, ACL changes, Hyper-V/VM, disk/volume writes, registry writes, protected installation paths, `G:`, or native F2 workloads. No production path creates persistent files.

The four Git queries remain `rev-parse --show-toplevel`, `config --local --get remote.origin.url`, `rev-parse HEAD`, and `status --porcelain=v1 --untracked-files=all`. Their command names and arguments are fixed; system/global Git configuration, hooks, optional locks and fsmonitor are disabled. Output, error streams and deadlines are bounded.

## Verified-byte execution and path handling

- The exact CMD entry contains no mutable file execution. It sets `PSModulePath` to `$PSHOME\Modules`, opens the fixed outer-bootstrap file through the embedded handle reader, checks the opened handle's final path against the fixed canonical path, rejects a path whose resolved handle target differs, uses read-only sharing, reads at most 128 KiB once, hashes those bytes, and creates/invokes a ScriptBlock from that same byte array. A directory cannot be read as the required file and fails closed.
- The outer bootstrap repeats no-reparse checks and uses the still-loaded handle reader to obtain the launch module as bytes. It verifies that hash and imports a module made from that exact byte array. It then reads and verifies the requester launcher and executes a ScriptBlock from those exact bytes. It never invokes a source checkout file with `-File` or dot-sources it.
- The requester uses `Read-F2LaunchPinnedFile`, which opens through a handle-based native helper, compares the opened object's final path to the canonical requested path, rejects reparse or directory handles, enforces bounds, hashes the bytes and returns that same array. It performs fresh repository and input checks before the single UAC launch.
- The generated elevated-child bootstrap is a short fixed template. It checks the full child path chain for reparse points, opens with reader-only sharing, bounds and reads the child script once, validates its SHA-256, then creates/invokes a ScriptBlock from those exact bytes. The one-shot child command is generated only from fixed path/hash/identity/nonce inputs and rejected if its complete command line exceeds 3,600 characters. No `-File` or unverified path execution occurs.
- Opening with reader-only sharing prevents a later write or rename while that handle is open. The hash check catches content substituted before open, and only the byte array that passed hashing is executed; changing the path or file after the read cannot change that ScriptBlock. Parent-chain checks and handle final-path checks reject static reparse aliases. Regression tests cover changed bytes and directory-junction aliases. No source checkout can supply alternate paths or hashes at runtime.

These controls protect against accidental mutation and path substitution by ordinary concurrent processes. A malicious local Administrator or code already controlling the same requester/elevated process is outside this boundary. The `powershell.exe` image and Windows loader remain operating-system trust assumptions.

## Git for Windows provenance

The previous `C:\Program Files\Git\cmd\git.exe` pin pointed at Git for Windows' wrapper. The [Git for Windows wrapper documentation](https://gitforwindows.org/git-wrapper.html) explains that `cmd\git.exe` sets environment variables and starts the real program. Its [MINGW/MSYS2 layout documentation](https://github.com/git-for-windows/git-for-windows.github.io/blob/main/content/the-difference-between-mingw-and-msys2.md) locates 64-bit core Git at `mingw64\bin\git.exe`. The code now invokes that actual core binary directly, pins its fixed path and observed SHA-256, clears the inherited environment, supplies a minimal `PATH`, and retains the fixed four-query allowlist.

The core executable can load Git for Windows DLLs from its installation tree. Those dependent binaries are not individually pinned here. The remaining trust boundary is that the installed Git for Windows directory and its required runtime DLLs are genuine and protected from ordinary-user modification; this task did not query or attest their host ACLs or signatures. A mismatch of the core executable itself fails closed. Independent review should decide whether this explicit dependency assumption is acceptable for a diagnostic-only probe.

## One-shot pipe authentication and result validation

The requester creates a random `F2D_<32 hex>` pipe with `FILE_FLAG_FIRST_PIPE_INSTANCE` and `PIPE_REJECT_REMOTE_CLIENTS`. Its protected DACL is limited to the requester, Administrators and SYSTEM. Frames have a four-byte length and an 8 KiB maximum. Peer binding includes kernel pipe PID, process creation time, exact image/encoded command line, SID and token elevation facts. Request ID, nonce, exact fields, fixed hashes, status and child exit are validated in both directions.

The response validator accepts only the exact diagnostic schema and safe enum values. A successful diagnostic must say `TokenClass=ELEVATED`; a `STANDARD`-labeled `PASS` is rejected. A child exit conflict, nonzero exit, missing/tampered/duplicate frame, source mismatch, timeout or incomplete cleanup cannot become PASS. Diagnostic PASS is non-authoritative and does not mean any updater or installation succeeded.

`PipeOptions.CurrentUserOnly` is not used because it checks elevation level as well as account identity on Windows and would prevent the medium-to-high connection. The pipe instead binds actual process and token identities. Local administrators may still cause denial of service by racing the random pipe; there is no fallback or automatic retry.

## Git wrapper evidence and runtime dependency limits

The distinction between wrapper and core binary is documented by Git for Windows, and the local `cmd\git.exe` had wrapper-sized file metadata while the `mingw64\bin\git.exe` used by the launch code was independently SHA-256 checked. No wrapper was executed. The source and test pin only the core executable, not the set of dynamic libraries it loads. A hostile or modified Git installation tree could affect the four Git queries; the source does not attempt DLL inventory or signature validation. This is an explicit trust assumption for independent review, not a claim that the full Git installation was attested.

## UAC policy and limitations

The requester contains one `Start-Process -Verb RunAs` site and no retry. If a different Administrator account is used, the elevated SID differs from the requester and is rejected. Ordinary visible Windows consent cannot be automated. The test harness uses a normal ShellExecute call with no `runas` verb and temporary harmless scripts only; it does not invoke UAC.

The consent UI is not controlled by an automated deadline. After launch, pipe connect and child exit waits are bounded. A timeout reports the actual process status when available and whether the child may remain; the code does not terminate it. There is no durable cross-invocation UAC attempt ledger, so any future owner authorization is consumed at the first prompt and the exact command must not be rerun after that prompt.

## Remaining real-host unknowns

- A real UAC cross-integrity pipe handshake and the actual `Start-Process -Verb RunAs` command-line representation remain untested.
- Real elevated command-line visibility through `Win32_Process.CommandLine`, same-account consent, and rejection of alternate-account credentials remain untested.
- Git runtime DLLs and protected parent paths have not been inspected on the host.
- No protected state, VM, Hyper-V, ACL, `icacls`, `G:`, or baseline data was queried in this task.
- No historical elevated updater process or updater entrypoint was run; the earlier elevated failure remains UNKNOWN.

## Microsoft interfaces referenced

- [Start-Process parameters](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/start-process?view=powershell-5.1)
- [PipeOptions](https://learn.microsoft.com/en-us/dotnet/api/system.io.pipes.pipeoptions?view=netframework-4.8.1)
- [GetNamedPipeClientProcessId](https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-getnamedpipeclientprocessid)
