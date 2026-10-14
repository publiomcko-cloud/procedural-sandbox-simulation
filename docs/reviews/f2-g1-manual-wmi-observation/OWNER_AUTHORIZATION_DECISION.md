# F2 G1 elevated diagnostic: owner-authorization decision record

## Decision state

**PENDING OWNER DECISION — NOT AN AUTHORIZATION.** This record describes one bounded action for an owner to accept or decline after review. No UAC or elevated process is authorized by this document or by the same-token WMI result. Any prior updater or installation authorization does not apply; a fresh, explicit owner authorization must name this exact diagnostic action and reviewed command bytes.

- Same-token WMI gate: reported closed in [the observation receipt](MANUAL_OBSERVATION_RECEIPT.md), based on human-supplied output.
- PR #69 reviewed launch package: `56a34d7899ba31b0d3fe6d3185435bc182ac453f`.
- Runtime implementation: `8c14cf97c9446e11b8afbd64196c3f4558d4c3c9`.
- Exact proposed command artifact: [EXACT_UAC_COMMAND.txt at the immutable PR #69 HEAD](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/blob/56a34d7899ba31b0d3fe6d3185435bc182ac453f/docs/reviews/f2-g1-elevated-diagnostic-launch/EXACT_UAC_COMMAND.txt).
- Exact command artifact Windows checkout-byte SHA-256: `1f1d4f51025b853bc571728258ae220cb689be97bf7c7355a0094393c113706a` (4683 characters excluding its final newline).
- Historical source commit: `396c44965c90c08292ad2835f8317e81b6b9daaf`.
- Historical candidate commit: `7f99bc10f3e2258d2340cea4e7ba1352022cbb6d`.
- Historical candidate manifest SHA-256: `b8596905f42ee429ae2fd3352f9133de8bd4f00da654f856012c02390661f022`.

## The only action that could be authorized

Authorize at most **one** human-consented UAC launch of the exact PR #69 command artifact above, from the documented standard-token `cmd.exe /d /k` entry point and the original requester account, using the exact reviewed checkouts, paths, hashes, and command. The reviewed launcher is expected to make one `RunAs` child launch only after its fixed preflight gates pass. Do not edit, reconstruct, re-encode, or substitute the command. The [PR #69 launch sequence](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/blob/56a34d7899ba31b0d3fe6d3185435bc182ac453f/docs/reviews/f2-g1-elevated-diagnostic-launch/README.md) and [security boundaries](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/blob/56a34d7899ba31b0d3fe6d3185435bc182ac453f/docs/reviews/f2-g1-elevated-diagnostic-launch/SECURITY_BOUNDARIES.md) describe the reviewed operation.

The elevated child is limited by the reviewed PR #69 source to the read-only historical manifest diagnostic: verify its elevated same-requester Administrator token and request identity; read pinned source/candidate/diagnostic inputs; perform four bounded, fixed local Git queries; initialize the small in-memory pipe/token helper; parse the pinned historical candidate manifest; compare its `ReviewedCommitSha` to the pinned historical source commit; and return a bounded, sanitized, nonce-bound result. The command does **not** authorize the protected updater, release transaction, recovery, rollback, installation, live ACL/icacls collection, VM/Hyper-V/G: access, native workloads, or persistent file/registry/network changes.

A diagnostic `PASS` would mean only that the historical candidate manifest parsed and its `ReviewedCommitSha` matched the pinned source commit. It would not prove that the prior elevated failure is resolved, accept any ACL, or authorize a later collection or update.

## Mandatory stop conditions

Do not launch UAC if any of the following occurs:

1. PR #69 is no longer at the reviewed HEAD, any pinned source/command hash differs, or any fixed checkout has an unexpected origin, commit, dirty state, path, reparse point, or required file.
2. The requester is not the original standard-token account, the operator is already elevated/Administrator, or any identity/process check fails.
3. Any path, candidate/source identity, module, launcher, pipe, process, Git executable, or preflight validation is missing, ambiguous, inaccessible, or outside the reviewed bounds.
4. The command differs by even one byte/character from the pinned artifact, or any additional command, retry, account substitution, or privilege bypass is proposed.
5. The UAC prompt is unexpected or requests credentials for a different account. Cancel it. The first UAC prompt/attempt consumes the one-time authorization whether consent is granted, denied, or canceled.
6. The child times out, fails, exits nonzero, reports missing/invalid/conflicting diagnostics, has an exit/result disagreement, or fails cleanup. Preserve evidence and stop; do not retry, recover, roll back, clean up, or remediate.
7. The execution requests or performs any write, ACL change, updater/transaction/recovery action, `icacls`, VM/Hyper-V/G: operation, native workload, network access, or scope change.

## Residual risks for owner review

- The manual WMI test was same-token only. It did not validate the elevated child's command-line representation, UAC behavior, cross-integrity pipe connection, or alternate-account rejection at runtime.
- The actual original elevated failure remains unexplained; the proposed action is diagnostic only.
- The pinned Git core executable hash is checked, but dependent Git DLL hashes, provenance, and modification exposure were not verified.
- The supplied WMI summary is not the original complete JSON/transcript; fields omitted from that summary remain unverified at the record level.

## Owner decision (leave pending until the owner acts)

- [ ] **Authorize** exactly the single action above under all listed conditions.
- [ ] **Decline**; no UAC attempt.

Owner name/date/comment reference: not provided.

This package records a decision request only. An authorization must be separately and explicitly recorded by the owner against the exact reviewed bytes. No automatic or inherited authorization is created here.