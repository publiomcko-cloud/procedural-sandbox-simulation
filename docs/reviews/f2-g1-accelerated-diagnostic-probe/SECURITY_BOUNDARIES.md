# Security boundaries and threat analysis

## Assets and trust assumptions

The diagnostic trusts only a clean, reviewed source checkout, exact Git object ancestry, fixed local `C:\Dev` paths, the hardcoded historical hashes, and Windows PowerShell 5.1 execution semantics. The probe's source and candidate inputs are read-only. The report is informational and cannot authorize or perform a protected upgrade.

The probe cannot establish what bytes or process environment the historical elevated child actually observed. Its token label is descriptive; it is not a token impersonation test.

## Excluded operations

Production module and wrapper contain no `Start-Process`, `RunAs`, named-pipe, `icacls`, `Set-Acl`, protected-directory, VM/Hyper-V, `G:`, registry, updater, recovery, transaction, file creation, deletion, move, copy, or output-file operation. Output goes only to the caller's stdout. The implementation does not accept caller-controlled paths, candidate hashes, source commits, or operation names.

The regression test statically inspects the probe's AST for disallowed commands/methods and protected paths. It also verifies that an `ELEVATED` token label does not invoke an elevation API or mutation path.

## Allowlist and execution boundary

Before parsing, the module enforces maximum input byte counts and exact hashes for the updater, launcher, diagnostics protocol, and candidate. It parses, but does not execute, the full updater and launcher. It requires unique definitions for the historical parser, hashing helpers, and child builder; function bodies are constrained by command and method allowlists. It invokes those verified definitions only to reproduce how the old child-script body was constructed.

The produced child text is parsed. The module requires exactly one exact parser assignment and one exact `ReviewedCommitSha` comparison and executes only those two statements under `StrictMode Latest`. It rejects any AST shape or statement variation rather than interpreting a broad child script.

## Failure disclosure

Only a fixed stage, operation, finite error code/category, and allowlisted FullyQualifiedErrorId are emitted. The probe never serializes an exception or uses exception text in output. Unknown error identifiers are replaced with `UNLISTED`. Output length is bounded; serialization failure returns a fixed fallback record.

## Negative validation

The Windows PowerShell 5.1 test covers hash tampering, malformed candidate JSON, missing required identity, wrong reviewed commit, parser-source alteration, child-builder extraction and runtime arguments. It verifies that fixed error records do not contain sensitive paths, SID/SDDL strings, baseline identity fields, or raw exception text. AST checks reject process/elevation calls, protected writes, ACL mutation, transaction/recovery calls, and protected target paths. The test also exercises the actual probe in a child process for the valid and unexpected-argument cases.

## Residual risks

This source review cannot establish integrity of the live Windows host, PowerShell installation, Git executable, or files between test time and a later invocation. Exact hash checks reduce source substitution risk but do not make the host trusted. A future elevated-token probe would be a new execution event and requires separate review and explicit owner authorization. No elevated run is authorized here.
