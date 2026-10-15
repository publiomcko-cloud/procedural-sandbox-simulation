# F2 G1 — v4 transaction protocol contract (design candidate)

**Classification:** SOURCE-ONLY DESIGN / PROPOSED / RELEASE_HOLD. Not executable code, installation guidance or an approved security control.
**Immutable design-review parent:** `b044e517c46e8f8d95bb5d8d4bc1225f6459fe84`.
**Normative interpretation:** requirements prefixed MUST / MUST NOT / SHOULD are **proposed acceptance conditions**, not claims that production implements them. Any unclear observation resolves to `HOLD_PRESERVE`, never an authorized write.
**Decision:** ADR-0004; accompanying negative scenario oracle: `ACCEPTANCE_MATRIX.json`.

## 1. Boundaries and non-interchangeable versions

| Domain | Observed existing source | Proposed future role |
|---|---|---|
| Historical installed baseline | v2 manifest, SHA-256 `b5f01570cf8937324f0c763f72a8d05b5532472156d4e5b0fcfbd180dc7abbe9`, commit `5741ffe90a3abd02a08563e6431e8a0b9b63eeb1`; seven pinned bytes | Read-only exact predecessor check and preserved rollback evidence |
| Draft v3 updater/manifest | v3 runtime dispatch, exact seven-member set, `transaction.ndjson` with `PREPARED` / `OPERATION:*` and `RECOVERED_COMMIT` | **Legacy-only.** Must not be parsed as v4 journal and is not presumed installed |
| Accepted v4 source-only | `f2-icacls-runtime-release-v4`; ten exact source files including v1/v2 pins; `SOURCE_ONLY_NOT_RELEASE_APPROVED` | Offline source inspection only, always `InstallAuthorized=false` |
| Future installable target | No implemented or approved manifest | Proposed **v5 installable manifest** (name subject to owner architectural approval) with independently reviewed new pin generation and frozen inventory after source changes |
| Transaction protocol | No implemented v4 transaction | Proposed independent `f2-protected-update-transaction-v4` across separately approved predecessor and target identities |

The installed executable package **cannot be inferred to remain ten members** after v4 production code changes. A new source-pin generation cannot silently replace historical v2 files. If an owner chooses another installable schema, revise this document and matrix **before** implementing production.

## 2. Required independent trust anchors and approval envelope

The **release signer** and verification scheme are currently **UNSELECTED**. No production installation may be enabled until a specific signature suite, trusted keyring, verifier binary hash, expiry/revocation strategy and offline validation vectors are independently approved. The installer MUST NOT infer signer identity or approved digest from the package being installed, a mutable Git branch, locally computed hashes, or caller claims.

Future externally signed approval envelope MUST bind, at minimum, all of:

- `ReceiptSchema` (distinct version), `ApprovalId` (immutable replay-resistant identity), `TransactionProtocolSchema=f2-protected-update-transaction-v4`, `InstallableManifestSchema`, `InstallableManifestSha256` (raw exact UTF-8 bytes), `SourceCommitSha` (full exact Git SHA), `PackageInventorySha256` (canonical ordered member-path/byte-digest inventory) and `PackageDestinationRoot` (canonical fixed-local protected location).
- `AllowedPredecessors` with exact `Schema`, `ManifestSha256`, `ReviewedCommitSha` and required installed-file inventory. The known v2 tuple is eligible **only if independently verified present**. A v3 predecessor is NOT implicitly allowed and cannot be inferred from an unmerged PR.
- `UpdaterSha256`, `LauncherSha256`, `RuntimeEntrypointSha256`, `CoordinatorSha256`, `CollectorSha256`, `ReceiptVerifierSha256`, `ExpectedSignerKeyId`, `AllowedOperation`, `EnvironmentBoundaryId`, `ApprovalEpoch`/anti-replay identifier, and any applicable validity window.
- Exact detached signature and pinned key source **outside** the candidate and mutable repository. The envelope's own hash is NOT authentication. A locally supplied equal hash is only an integrity comparison.
- Exact role/operation restrictions: receipt authorizing `Install` DOES NOT authorize `RecoverForward`, `Rollback`, `CI`, `Elevate`, or deletion; separate owner/signer scope is required as applicable.

Receipt/manifest/package MUST be frozen **after** production code and new source pins are reviewed. If any member or signed input changes, regenerate a candidate and demand a new independent review; never edit a signed receipt or re-pin the old historical manifest.

### Package and path gate

Canonical byte policy and package inventory MUST specify exact path case, path segments, member count, Windows checkout EOL normalization, per-member SHA-256, size maxima, forbidden reparse/UNC/mapped/network/removable/G: roots, owner/DACL baseline, and deterministic ordering. Reject extra/missing/duplicate/unexpected members. Manifest output is external to the source commit it pins, avoiding a self-referential SHA cycle.

Privileged installation MUST NOT run `git.exe`. It must verify its own pinned implementation and the receipt via an independently trusted verifier, re-read every sealed package byte with bounded limits, and fail before writes on unexpected installed identity, path, process, ACL, receipt or origin conditions. The read-only Git preflight is not a trust root for the elevated process.

## 3. Protected state and exclusivity (PROPOSED)

Protected root inventory remains conceptually separate:

- Executable packages: `%ProgramFiles%\F2-G1-Icacls\releases\<reviewed-sha>\scripts\f2-acl\...` (old versions preserved).
- Active pointer: `%ProgramData%\F2-G1-Icacls\approved-release.json` (exact active manifest; no in-place JSON patching).
- Transaction v4 artifacts: `%ProgramData%\F2-G1-Icacls\updates\<txid>\transaction.v4.ndjson`, sealed receipt and staged candidate; prior v3 journal `transaction.ndjson` remains unchanged.
- Backups: `%ProgramData%\F2-G1-Icacls\backups\<txid>.approved-release.predecessor.<schema>.json` preserving the **exact** observed predecessor manifest bytes and hash, not assuming v2 in every transaction.
- Staging: a unique absent sibling of the final version directory (for example `.f2-v4-update-<txid>.new`), never overwrite/merge an existing version root. Constrain paths to fixed same-volume protected directories without reparse ancestry.
- Lease/barrier: the shared release lease, held active-manifest barrier, process inventory and second quiescence check at the switch edge. No cached legacy reader or v3-only coordinator may be allowed to interpret the new manifest during cutover.

Every directory/file identity, size, ACL/owner and allowed child name must be validated before and after privileged operations. No symlink traversal, fallback root or broad recursive cleanup. Unsupported installed version, unexpected left-behind transaction, competing lease, or mixed historical state ⇒ `HOLD_PRESERVE`.

## 4. Atomic transition protocol and durable journal

Define an **independent** journal schema `f2-protected-update-transaction-v4`. It MUST NOT reuse the old `transaction.ndjson` parser or legacy `OPERATION:*` acceptance list. Each new record MUST have an exact allowlisted key set including: `Schema`, `TxId` (32 lowercase hex), `Sequence` (strict integer starting at 1), `State`, `PreviousHash` (empty only for genesis), `ReceiptSha256`, `PredecessorManifestSha256`, `TargetManifestSha256`, `Utc`, and `EventHash` or a separately externally anchored head. Define a deterministic byte serializer with **fixed field ordering**, strict UTF-8 without BOM, LF line delimiter, no free-form path/error strings and specified escaping; hash **exact serialized record bytes**, not JSON reserialization of a parsed object. Journal chain alone is NOT a signature or anti-truncation guarantee.

Proposed state graph (one monotonic forward transition each, except explicitly modeled recovery terminal records):

```text
NO_TRANSACTION (read-only, no writes)
  -> HELD_QUIESCENT (lease+manifest barrier, source/predecessor/receipt checked)
  -> PREPARED (durable genesis, prior to package staging)
  -> STAGING
  -> PACKAGE_VERIFIED (all bytes, inventories, DACLs)
  -> PACKAGE_PUBLISHED (atomic same-volume side-by-side directory move)
  -> SWITCH_INTENT (durable journal marker, both manifests verified, barriers held)
  -> ACTIVE_MANIFEST_SWITCHED (atomic replace of active manifest, predecessor backup)
  -> POSTCHECK_VERIFIED (active pointer, target files/DACLs and predecessor backup)
  -> COMMIT_DURABLE (terminal evidence, old release retained)
```

**Ordering guarantees:** before any phase capable of mutating target data, persist a journal record describing the intended phase and flush the record to stable storage. Before active pointer replacement, flush `SWITCH_INTENT`; after replace, validate **both** active manifest and independently retained predecessor backup. Flush postcheck/terminal journal before claiming success. Report a successful transaction only if all required records, DACLs, exact content identities, barriers and required cleanup/retention invariants are proven. There is no implicit deletion of a staged package or the predecessor on failure.

**Crash window:** a crash between active-pointer swap and `ACTIVE_MANIFEST_SWITCHED` recording is inherently possible. The observed active manifest is **an independent state input**, not inferred from journal phase. A missing post-swap marker does not imply the old release remains active. Caller cancellation, timeouts and exceptions likewise do not imply rollback.

Journal bound requirements to specify/test before coding: max records, max line bytes, strict UTF-8 encoding, no duplicate sequence/state, valid transition graph, exact receipt/predecessor/target tuple on each record, head anchored in a trusted checkpoint or independently signed closure record, refusal on truncation, torn UTF-8, malformed JSON, chain mismatch, unexpected files, reused TxId or nonmonotonic phase.

## 5. Read-only recovery decision matrix

Recovery first acquires the same lease/barrier under an explicitly approved read-only diagnostic scope and inventories exact active bytes, target package, backup, durable journal, release processes and DACL/owner state. A **read-only result** never grants an operational token. Only future separately signed, owner-authorized, time-bounded operation may mutate.

| Observed state | Journal state | Permissible inspection result | Default operational action |
|---|---|---|---|
| Old exact manifest active, staging incomplete or absent | Before `PACKAGE_PUBLISHED` | `OLD_ACTIVE_PARTIAL_STAGING` | `HOLD_PRESERVE`; no deletion or automatic retry |
| Old active, new full package published, valid receipt | `PACKAGE_PUBLISHED` or `SWITCH_INTENT` | `OLD_ACTIVE_FORWARD_ELIGIBILITY_CANDIDATE` | `HOLD_PRESERVE`; a later explicit forward authorization and revalidation required |
| New exact manifest active, backup exact, all target bytes valid | At/after `SWITCH_INTENT`, with or without post-swap marker | `NEW_ACTIVE_VERIFY_ONLY_CANDIDATE` | `HOLD_PRESERVE` until durable postcheck/commit authority; no automatic rewrite |
| New exact manifest active, but backup missing/invalid or package incomplete | Any | `AMBIGUOUS_NEW_ACTIVE` | `HOLD_PRESERVE`, manual security incident review |
| Active manifest equals neither exact predecessor nor target | Any | `UNKNOWN_ACTIVE` | `HOLD_PRESERVE`, no forward or rollback |
| Torn/missing/rewritten journal, broken chain, colliding TxId | Any | `UNTRUSTED_TRANSACTION` | `HOLD_PRESERVE`, no inferred repair |
| Valid terminal postcheck and commit; predecessor backup retained | `COMMIT_DURABLE` | `NEW_ACTIVE_COMPLETE_OBSERVED` | Read-only verification; no cleanup implied |
| v3 legacy transaction record supplied to v4 resolver | Legacy state | `WRONG_TRANSACTION_SCHEMA` | `HOLD_PRESERVE` and delegate only to old pinned legacy code under separate authorization |

An explicitly authorized `RESUME_FORWARD` MUST re-authenticate the receipt and caller, obtain lease/barrier and quiescence again, verify exact old active pointer, published package and absence of existing backup collision, then perform one atomic switch, reverify backup/active/ACLs and append a **v4-only** recovered commit. `ROLLBACK` must have its **own** signed operation receipt, pinned predecessor bytes and package, barriers, eligibility proof, atomic replace, verified new backup, durable audit record and separately designed rollback-of-rollback semantics; **no rollback implementation is approved in this design**. Never conflate old manifest still active with a completed rollback.

## 6. Failure taxonomy, idempotency and exactly-once constraints

- Identity/receipt/signature mismatch ⇒ `REJECT_BEFORE_WRITE`, with no transaction artifacts.
- Lease conflict/process uncertainty ⇒ `HOLD_PRESERVE`; no forced termination of unknown processes.
- Missing byte, ACL disagreement, unexpected object or reparse ⇒ `HOLD_PRESERVE` after inventory, never silently repin or fix ACL.
- Journal append failure or unclear persistence ⇒ `UNKNOWN_JOURNAL_COMMIT` and `HOLD_PRESERVE` (no advancing state).
- Active pointer replacement failure ⇒ `UNKNOWN_ACTIVE_SWITCH` until independent readback establishes which exact signed manifest is active.
- Post-switch mismatch or missing exact predecessor backup ⇒ `AMBIGUOUS_NEW_ACTIVE`, `HOLD_PRESERVE`.
- Duplicate request/TxId, restart or replay ⇒ return prior proven read-only outcome or hold; never stage over existing root or swap twice.
- Process.Start / subprocess descendant uncertainty in earlier non-elevated preflight ⇒ not asserted safe; privileged stage may not depend on it.
- No auto-fallback to v2/v3 on a v4/v5 schema mismatch: fail closed while leaving historical files unchanged.

## 7. Acceptance matrix and future proof obligations

The adjacent `ACCEPTANCE_MATRIX.json` enumerates proposed deterministic cases. It is an **oracle, not a test runner**, and cannot establish safety of actual filesystem operations. Before any integration, independent Windows PowerShell 5.1 tests MUST exercise those vectors with synthetic protected-file abstractions and bounded fault injection at **every write and journal boundary**, including reboot/crash windows. Beyond that, separately authorize and test in an isolated approved protected environment. The original CI #85 failures and diagnostic receiver timeout remain open and are not resolved by transaction design.

Required implementation/review sequence, **each with fresh owner scope**:

1. Owner review/choose final installable manifest schema and pin generation; freeze expected package set; approve concrete trust signature design and key ownership.
2. Implement independent pure receipt/manifest/transition validators and run synthetic Windows reviewer tests. Do not import into production.
3. Implement transaction v4 staging/journal and explicit recovery decision-only side-by-side, with full synthetic failure matrix.
4. Migrate collector/runtime/coordinator/updater/launcher under exact new pins while keeping old installed v2/v3 readers/version dispatch immutable; review mixed-version cutover.
5. Independent security review of fixed package, protected DACL, elevated signer, process quiescence, journal durability and fault recovery; resolve or isolate diagnostics.
6. Only then consider explicitly owner-approved CI, PR/merge, UAC, protected release rehearsal and final release. No step automatically confers authority for the next.

**Design status:** `PROPOSED_NOT_CODED`; no receipt exists, no source pin generation or installable manifest has been frozen, no rollback has been implemented, and **RELEASE_HOLD** remains in effect.
