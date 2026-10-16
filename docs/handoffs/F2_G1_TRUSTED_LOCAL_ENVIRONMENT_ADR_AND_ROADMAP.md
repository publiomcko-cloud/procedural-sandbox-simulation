# F2 G1 — ADR: Trusted Local Environment and Proportionate Read-Only Acceptance

**Status:** OWNER THREAT-MODEL DECISION RECORDED / PROPOSED IMPLEMENTATION ROADMAP / CONSOLIDATED REVIEW REQUIRED. **DOCUMENTATION ONLY.** This document grants no protected-host operation, implementation, merge, or release permission.

**Decision date:** 2026-10-16. **Scope:** F2 G1, the historical Windows host C: package/ACL/evidence verification associated with the user's isolated local Hyper-V VM. This ADR is not a general reduction in security requirements for other phases, repositories, production systems, or arbitrary machines.

**Provenance:** Repository `publiomcko-cloud/procedural-sandbox-simulation`. Base: rejected R4 design v2 `53238a38338f37f5b2804a9c6bf9ea8b0e9295f4`; rejected R4 v1 `e0b21bb5ea6e854d90dac2385f2efbba2951a1a3` is its parent. Accepted **synthetic-only** R3.3 `3a1fd6fb65c12484e237c829837fccf2b0a9e5e8` and accepted **fail-closed source-only** R2 `48ac3e8551127451d1b0d3861a98c3b075f2c4f6` remain ancestors. This ADR changes the intended threat model and future engineering plan; it does not retroactively change the independent review verdict of R4 v1/v2 or qualify an executable.

## 1. Owner decision and system boundary

For F2 G1, adopt a **trusted local environment** with the following explicit operational assumptions, supplied by the owner:

1. The Windows host is owned/managed by the owner and is assumed uncompromised.
2. The VM is isolated, with access to host directories and disks limited to what is necessary.
3. The inspection uses a known, reviewed version of source from the repository.
4. Potentially destructive operations require separate explicit owner authorization.
5. Inspection is read-only; any material inconsistency, partial evidence or inaccessible required object blocks a positive conclusion.
6. The purpose is preventing accidental changes, corruption and incorrect results, **not** resistance to a privileged attacker on the Windows host.

**Assumptions are NOT observations.** No host integrity, VM isolation, running process inventory, ACL, path state, guest state or installed release state has been examined to verify these premises. If the assumptions are untrue or cannot be responsibly maintained at execution time, stop this track and revisit the threat model before touching protected state.

**Boundary clarification:** The protected `C:\Program Files\F2-G1-Icacls` and `C:\ProgramData\...` objects are on the **Windows host**, not automatically inside the VM. Hyper-V isolation and guest checkpoints do not revert changes to those host paths. A VM snapshot/checkpoint is not a host backup. An actual guest checkpoint, VM operation or host backup is not authorized by this ADR.

## 2. Threats in scope; threats explicitly not in scope

**Must protect against:** wrong target/path, mistaken elevated or destructive operation, unexpected file types/reparse links, accidental alias/traversal outside fixed C: scope, missing/extra historical artifacts, truncated reads, stale/mismatched hashes or evidence, ordinary concurrent changes detectable during capture, inadequate privilege, partial success misreported as complete, source revision mistakes, unsanitized log/report output, and accidental changes to host/guest data.

**Not required for the selected model:** defeating a malicious local Administrator/SYSTEM process; compromised Windows kernel, hostile filesystem filter/driver or VM escape; hostile owner-browser impersonation; cryptographic single-use grant/replay resistance; a formal proof of all bytes mapped into a Windows process or system DLL dependencies; adversarial concurrent hard-link/ADS mutation; transactionally atomic snapshots of NTFS. These are excluded **risk assumptions**, not solved security properties.

If there is a credible hostile local actor, unmanaged shared host, compromised OS, outside-party execution, machine-scoped release, or need for adversarial forensics, this ADR no longer qualifies the plan. Restore a stronger threat model with a separately approved trust/loader mechanism and independent implementation review.

## 3. Decision: necessary controls versus deferred high-assurance controls

### Mandatory safety/accuracy controls for a future one-time read-only inspector

- **Fixed allowlist and no argument-driven scope expansion.** Inspect only the already reviewed historical C: package, manifest, mailbox, parent ACL and immediate-child inventories. The user must separately authorize the specific host, exact candidate SHA, scope, and single intended operation before a real read.
- **Known source and reproducible invocation.** Use a clean pinned repository commit plus reviewed static entrypoint; record source-file SHA-256 and document the exact command/dependencies in a handoff. The owner verifies the checkout against the expected SHA by an independent normal Git workflow. Do **not** claim Git/PowerShell self-hash is cryptographic proof of mapped executable bytes or authenticated owner intent. No import/execute of installed protected package scripts.
- **Least privilege and explicit mode.** Default cannot read any protected path. Require a dedicated, separately reviewed read-only mode, an explicitly approved invocation and a standard (not elevated) Windows token. Fail closed if insufficient read or metadata permissions; no automatic UAC, Administrator rerun, backup/restore privileges or policy/ACL repairs.
- **Read-only evidence collection.** Bounded file reads, expected SHA-256 and length checks, owner/DACL metadata observations, object type and reparse guard, exact parent/child inventory, stable-enough before/after identity/metadata checks, cross-file evidence checks, explicit partial-failure reporting. No creation, rename, deletion or cleanup under protected C: roots.
- **No accidental path escape.** Canonicalize the fixed paths, reject lexical aliases and reparse targets, and verify returned object identity/attributes before and after observation. Under the trusted-host/no hostile writer assumption, native handle-only traversal of every component is a possible hardening choice, **not a mandatory proof against malicious TOCTOU**. If the chosen API cannot ensure a particular required observation refers to the expected object, return BLOCKED, never silently substitute path-based results.
- **Sanitized outputs.** Do not export raw ACLs, private SIDs, secrets, full original file bytes or sensitive VM state. Report only the permitted diagnostic categories, evidence digests, object counts and limitations; bound memory and output.
- **Fail closed.** Missing, unreadable, changed, inconsistent, or unsupported *required* evidence always results in `BLOCKED_WITH_EVIDENCE`, not a successful attestation. Failures do not trigger retries with elevation or alternate scope.

### Deferred / removed as *architectural release gates* under this model

- The R4 v2 `D4.TRUST` external pin authority, independently distributed binary signing/attestation and proof of exact Windows image/each dependency actually loaded is **not a prerequisite** of this narrowly bounded trusted-host inspection. Source provenance/verified checkout remains mandatory.
- Machine-verifiable one-use authorization and resistance to forged approval UI by local malware are **not required**. An explicit fresh human approval with documented exact SHA, machine and scope is required, but is a procedural control, not cryptographic authentication or anti-replay.
- Universal adversarial no-follow relative handles and resistance to privileged concurrent replacement are **not mandatory**. Prefer stable, read-only opened handles where practical; match identity/metadata before and after and block observed drift. Do not claim an atomic filesystem snapshot.
- Low-level `FILE_STREAM_INFO` malformed-buffer fuzzing and `NumberOfLinks` unavailable/fault injection from R4 v2 are **not blockers for accepting the architectural design**. If a future implementation chooses to assert the absence of named ADS or multiple hard links, it MUST implement and test the exact checks before making **that particular** claim. If these attributes are not fully qualified, the future report must explicitly say `LINK_ADS_NOT_ATTESTED`, and cannot claim their absence. Evidence hashes cover the opened default stream only; do not infer absence of hidden named streams.
- The R4 v2 policy of strictly one hard link/no named ADS remains documented as a **prior proposed high-assurance policy**, not silently proven true of historical objects. A new, separately reviewed implementation contract must decide whether their absence is a *required acceptance predicate* under the newly scoped preservation objective. Until that contract is accepted, no operational positive verdict may infer their status or waive a requirement that the accepted implementation explicitly marks mandatory.

**Principle:** Do not delete necessary safety checks just to pass a review. Reclassify tests by the actual claim and threat model, and validate against the implementation being approved instead of treating all conceivable future tests as current architecture blockers.

## 4. Frozen historical scope and allowed conclusions

Preserve the R2/R3.3 canonical historical object inventory: exactly **23 named C: objects** (8 directories: 3 parent ACL-only, 4 installed package directories and 1 evidence mailbox; 15 files: 7 installed package members, 1 approved-release manifest and 7 mailbox files).

- Required package roots: `C:\Program Files\F2-G1-Icacls`, its `scripts` and `scripts\f2-acl`, and `C:\ProgramData\F2-G1-Icacls`.
- Manifest: `C:\ProgramData\F2-G1-Icacls\approved-release.json`.
- Mailbox: `C:\ProgramData\F2-G1-ACL-Evidence-ecb6deeb424e40feb5354d18908986df`.
- The **five** immediate-child inventory checks remain limited to those 4 package directories plus mailbox; reject unknown children, and require absence of `release.lock`, `updates`, `backups`, `releases`, `journals`, `stages` at their two historically specified package roots.
- Retain all **seven** historical installed-file hashes and the historical manifest/payload/integrity/capture IDs from R2 at exact ancestor `48ac3e8551127451d1b0d3861a98c3b075f2c4f6`; **never replace expected pins from host observations**.
- The **eleven** G: guest/VM paths referenced in the baseline payload are historical **strings to compare**, not paths to visit or objects to scan. No G: volume/Hyper-V/VM API access.
- Existing bounded file sizes, owner/DACL checks, required evidence files, fixed historical record count and completeness/cross-file integrity requirements remain indispensable.
- Preserve separation between measured **historical V2 artifact integrity at inspection time**, descriptive ACL metadata, and **unproven effective-token rights, current G: VM state, V3 qualification and release readiness**.

Any future `PASS_READ_ONLY_C_POSTFAILURE_ATTESTATION` could mean *only* that the specifically reviewed required C: historical objects and evidence matched on that one bounded read under the selected threat assumptions. Such a PASS cannot be issued from this ADR or a synthetic fixture. It is not `PASS_RESTRICTIVE_ACL`, a broad security audit, host-compromise detection, current VM status or a production/release approval.

## 5. Revised roadmap — evidence first, one consolidated design gate

**LT-0 — Owner threat-model decision (this ADR; documentation only).** Fix assumptions, objectives, residual risks, object scope and precedence. Obtain a **single consolidated independent architecture review** assessing the proportionality and internal consistency of the new plan. Editorial/anticipated low-level test-case changes are tracked as implementation acceptance criteria, not repeatedly elevated to architecture-wide HIGH findings absent a demonstrated safety/accuracy gap.

**LT-1 — Minimal read-only source design and synthetic prototype (separate owner authorization required).** Create a **new** isolated source-only branch and entrypoint contract; do not add `-Live` to R2 or R3.3. Design a standard-token preflight, fixed path allowlist, bounded capture, reparse/path guard, inventory, evidence hashes, unchanged historical policy and sanitized report. Exercise them using **only disposable synthetic Windows CI fixtures**. No trusted bootstrap, no protected host/G: access, and no auto-install/update. A mock result is `SYNTHETIC_FIXTURE_PASS` only.

**LT-2 — Implementation-focused validation and consolidated independent source review (separate scope authorization).** Use Windows PowerShell 5.1 CI to verify both positive fixtures and required negative cases: wrong token mode, changed/missing/reparse file, path escaping the fixed scope, extra/incomplete inventory, wrong hash/content, wrong ACL profile, evidence corruption, timeouts, bounded output and cleanup/fail-closed behavior. Add hard-link/ADS positive/negative parser tests **if** the final contract asserts their absence. Review exact source SHA, real privilege boundaries, zero mutations and complete expected-object coverage. A reviewed source is **not** permission to run against actual host C:.

**LT-3 — Explicit protected-host read-only owner grant (separate, fresh approval, NOT this ADR).** After the exact LT-2 candidate passes independent review, require a new deliberate owner decision specifying commit/source hashes, fixed C: objects, machine identity, one bounded Windows PowerShell 5.1 standard-token run, evidence/output redaction, and failure/stop rules. At the start of any such operation re-confirm the trusted-host assumptions and operator intent. No reuse of spent approval references. If permission is denied, abort rather than elevate. Backup/rollback plan for the host must be separately considered before **any future modification**, and a guest checkpoint alone never serves as host rollback.

**LT-4 — One-time observation and disposition (hypothetical future execution, NOT authorized now).** Execute only LT-3's exact approved read-only operation, publish sanitized evidence with identity and limitations and seek separate review of the observed results. Do not repair, change ACLs, install V3, touch G:/VM or clear environment/release holds merely because the inspection succeeded.

**Stop / escalate** at any stage on a suspected compromised host, unexpected privileged mutator, absent owner consent, path escape, requested host write, mixed-up source identity, incomplete baseline, or inability to meet an explicitly required observation.

## 6. Review and change-control rules

The reviewer for **this documentation-only ADR** checks: the selected local-trust assumptions are explicit; host versus VM scope is understood; removing high-assurance gates does not conceal missing integrity claims; all 23 objects and historical pins remain fixed; the new LT-1/LT-2 gate still prevents host access; and the five release/environment holds remain. Return `PASS_INDEPENDENT_LOCAL_TRUST_MODEL_DESIGN_REVIEW` or `BLOCKED_WITH_EVIDENCE`. A design PASS authorizes nothing further.

A later implementation review tests the actual invariant and negative cases; it need not demand a cryptographic trust root that the approved threat model explicitly excludes. Conversely, any implementation that asserts a stronger property must prove it. Reopen the architecture only for **material** trust/scope changes, not isolated low-level test-list wording.

**Precedence:** This ADR, once independently accepted, supersedes **R4 v1/v2's broader adversarial threat assumptions and proposed D4.1–D4.TRUST–D4.2 gating sequence** for this F2 G1 local operation only. It does **not** change historical source facts, object hashes, tests already accepted for R3.3, review records, R2 live-disabled code, or the actual protected state. Until its own independent design acceptance, R4 v1/v2 remain formally `BLOCKED_WITH_EVIDENCE`; this document is an owner decision and a proposed narrower plan, **not** a retroactive PASS.

**Persistent state:** `CURRENT_PROTECTED_STATE_UNKNOWN`; `V3_NOT_ATTESTED`; `ACL_REVIEW_REQUIRED`; `G1_BLOCKED_ENVIRONMENT`; `F2_G1_RELEASE_HOLD`.

**No actions granted:** No protected C:/G: read, UAC, `icacls`, VM/Hyper-V operation, source modification, production deployment, ACL mutation, updater, installation, PR, merge or release is authorized by this ADR.
