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

## 2. Trust bootstrap and receipt verification (proposed normative gates)

### 2.1 Root of trust is NOT the receipt

**No implementation or provisioning currently exists.** The security dependency order is: (1) independently trusted OS/firmware boot and Windows code-integrity policy established outside this repository; (2) preprovisioned, signed bootstrap executable plus its expected identity and protected policy, installed and approved through an independent operator-controlled channel; (3) bootstrap validates a separately installed verifier and immutable pinned public-key material; (4) verifier validates a candidate receipt; (5) verifier queries an independent online approval authority for signer status, trusted time and replay reservation. A receipt containing a hash of its verifier is only a **consistency assertion** checked after steps 1–3, not an identity proof of steps 1–3. No code, certificate, receipt, key or provisioning service is represented as existing in this design.

Proposed deployment prerequisite: Windows code integrity (for example, an independently configured/enforced WDAC policy) and protected ACLs prevent substitution of the bootstrap, verifier, policy and trust keys. Platform boot integrity, effective policy enforcement, approved OS version, administrator attack assumptions and machine attestation must be tested independently; Authenticode presence or a SHA-256 comparison sourced from the candidate is NOT sufficient. If the trusted OS/policy, protected verifier, key or bootstrap cannot be attested independently, return **REJECT_BEFORE_WRITE**. A higher-privileged compromised OS is outside the proposed assurance boundary and must be declared an explicit residual risk.

**Candidate signature design for owner selection, not an existing choice:** ECDSA P-256 with SHA-256 through a separately pinned Windows-compatible verifier; raw signed byte envelope with a strictly versioned deterministic encoding and strict parsing, including rejection of duplicate keys, unknown critical extensions, signature algorithm substitution, ambiguous Unicode, noncanonical encodings and parser disagreements. The owner must approve exact signature wire format, public-key fingerprint and verifier vectors before code. The signer private key remains in separately administered protected custody; public-key enrollment, dual-approval, rotation and revocation require audited out-of-band operator authorization. Keys and trust policy must be provisioned before any candidate receipt can be accepted.

### 2.2 Online authority baseline; no offline approval shortcut

**Proposed safe baseline:** require a separately operated approval authority (mutually authenticated and endpoint-pinned) accessible before any privileged mutation or privileged recovery. It supplies authenticated trusted time, key-status/revocation decisions, and an atomic monotonic ledger. No offline acceptance, cached revocation, wall-clock-based expiry, self-declared time, or local-only ApprovalId database is authorized by this proposal. Network unavailable, authority unreachable, revoked/unknown signer, stale epoch or nonmonotonic sequence ⇒ REJECT_BEFORE_WRITE before local mutation; after uncertain local state ⇒ HOLD_PRESERVE. Alternative air-gapped schemes must be designed, independently reviewed and owner-approved separately.

The authority must maintain an append-only durable per-environment ledger outside the installer's writable local filesystem, with monotonic per-environment Generation and distinct ApprovalId and TxId uniqueness constraints. Receipt and ledger are independent authorities. An operator must prove that authority history cannot be rolled back by restoration of older local files; a local hash chain alone is insufficient. If the authority is compromised/unavailable or fails to prove monotonic durable state, no transaction proceeds.

### 2.3 Exact signed approval envelope and replay contract

Every future detached signature must bind **exactly one** transaction tuple and operation:

- ReceiptSchema, ReceiptFormatVersion, AlgorithmId, SignerKeyId, ApprovalId (globally unique), TxId (32 lowercase hex), EnvironmentBoundaryId, AllowedOperation (INSTALL / RECOVER_FORWARD / FINALIZE_POST_SWITCH / ROLLBACK each distinct), AllowedActor, TargetVolumeIdentity and PackageDestinationRoot.
- TransactionProtocolSchema = f2-protected-update-transaction-v4; future InstallableManifestSchema (proposed f2-icacls-runtime-release-v5); raw exact InstallableManifestSha256, SourceCommitSha, canonical PackageInventorySha256, all member byte hashes, build provenance and exact approved target package root.
- Exactly one verified expected Predecessor tuple (Schema, ManifestSha256, ReviewedCommitSha, complete installed inventory) per approval. The v2 manifest hash b5f01570cf8937324f0c763f72a8d05b5532472156d4e5b0fcfbd180dc7abbe9 and historical commit 5741ffe90a3abd02a08563e6431e8a0b9b63eeb1 are known reference values, **not evidence that v2 is currently installed**. Draft v3 is not an allowed predecessor without independent proof.
- UpdaterSha256, LauncherSha256, RuntimeEntrypointSha256, CoordinatorSha256, CollectorSha256, ReceiptVerifierSha256, provisioned BootstrapPolicyId, ExpectedSignerKeyId, and precise permitted post-switch state for finalization.
- ExpectedAuthorityGeneration, anti-replay nonce, owner-scoped ApprovalEpoch, validity interval assessed using authenticated authority time, and an explicit authorization policy version.

Signer metadata, digest, TxId, ApprovalId, key, operation, predecessor, authority generation, source or target cannot be inferred from a mutable branch, self-hash, untrusted local clock or candidate. Install approval does NOT permit RECOVER_FORWARD, FINALIZE_POST_SWITCH, ROLLBACK, CI, elevation, deletion or a different TxId.

**Remote atomic reservation:** before the first local write, submit exact signed tuple, expected authority Generation and TxId/ApprovalId to the authority. A compare-and-swap reservation succeeds once, increments monotonic authority state and returns a signed reservation certificate bound to this transaction and immutable tuple. A repeated ApprovalId for a different TxId, or same TxId with changed operation/digest/environment, is REPLAY_REJECTED. An identical retry may request **read-only observation only**, not another write. Recovery requires a **new signed operation-specific receipt** linked to the same original TxId and authority ledger, with separate consumable ApprovalId and monotonic operation sequence. A local restored older journal/head must be compared to the external anchor and never silently accepted. If remote reservation succeeds but local genesis is absent, record REMOTE_RESERVED_NO_LOCAL; it is a hold state, not an automatic retry or deletion.

Independent signer provisioning, network authority, signature vectors, exact wire encoding, expiry/revocation semantics and any operation authorization remain owner approval gates. The source-only tests' self-generated Git hash is not a signer attestation.

## 3. Package, installed-state and quiescence gates

- Freeze current accepted ten-member source-only v4 (Status SOURCE_ONLY_NOT_RELEASE_APPROVED); it is **not** an installable package. Propose a separately reviewed installable v5 manifest and new source-pin generation. Freeze exact cardinality, case-sensitive paths, Windows checkout EOL policy, individual SHA-256, canonical sorted inventory encoding, max sizes, destination identities and predecessor tuple after production source is reviewed. Old v1/v2 manifests/pins remain byte-identical.
- Installation must use already authenticated signed/verifier toolchain; **no privileged Git command**. Sealed package is independently re-read byte for byte under elevation; forbidden UNC, network/mapped/removable/G:/reparse/device paths and cross-volume moves, unexpected installed files, owner/DACL mismatches or extra package members ⇒ reject before writes or hold after partial staging.
- All transaction, stage, backup, package and active-manifest directories must be on independently verified **same fixed local volume GUID** (not only same drive letter) with reviewed NTFS/ReFS semantics. Reject ambiguous mount points, reparse ancestors and volume identity changes.
- Inventory includes launcher entrypoints (Start-F2ProtectedReleaseUpdate.ps1 and all registered direct/script invocations), collector (Invoke-F2AclReadOnlyCapture.ps1 and Invoke-F2IcaclsCapture.ps1), runtime (F2AclIcacls.Runtime.psm1), coordinator (Invoke-F2IcaclsProtectedCoordinator.ps1), updater (Invoke-F2ProtectedReleaseUpdate.ps1), Windows PowerShell child workers, scheduled tasks/services, inherited handles, memory-cached manifests and any operator-initiated direct PowerShell path. This list is an **initial discovery checklist**, not proof that every possible launcher is known. Freeze executable SHA and process identity predicates after full enumeration.
- **v2 cutover gate:** the historical v2 runtime lacks the shared lease; therefore an app-level lock or two process inventories cannot prevent a late v2 launch. Default **NO LIVE v2 -> v5 CUTOVER**. Only a separately authorized, independently verified maintenance execution context with authenticated online approval-authority connectivity and OS-enforced prevention of legacy launches for the entire interval may be evaluated. Maintenance means legacy launch isolation, NOT disconnection from the approval authority. If uncooperative direct launches remain possible, stay HOLD_PRESERVE. v3 online cutover also remains blocked until *all* launch paths are forced through an OS-enforced trusted broker plus the lease/barrier, and late starts are demonstrably denied throughout the switch.
- Once launch inhibition is enforced, acquire exclusive release lease and active-manifest barrier, inventory all relevant processes including inaccessible metadata, verify all known file handles are quiescent, and revalidate at the switch edge. **Inaccessible process details, unknown child ancestry, handles that can cache old manifest, or failure to inhibit new direct readers ⇒ HOLD_PRESERVE**. The lock must remain held through readback and terminal evidence; no forced termination of unrelated processes.
- Windows manifest file sharing/barrier semantics must be specified and tested with the exact v2/v3 reader handle modes. A barrier alone does NOT block a late process already running uncooperative v2 code. The release strategy must prove no legacy executable can read/cache a changed active manifest during the cutover.
- Any consent to write protected paths, enable WDAC, install a broker or enter maintenance is **outside** this document's authorization. These are blocking owner decisions, not tasks granted to a code agent.

## 4. Transaction v4 durable state and atomicity

### 4.1 Explicit durability scope

Define separate crash classes: (A) process/PowerShell exception or termination; (B) OS reboot/crash; (C) sudden power loss or storage controller failure. File flush and same-volume rename semantics alone **do not prove** B/C crash-consistent durability. Owner must select supported Windows filesystem and storage durability guarantee, write-through/flush and directory metadata persistence mechanisms, and independent fault-injection evidence. Until B/C semantics are demonstrably supported, an ambiguous post-crash state is HOLD_PRESERVE; no successful transaction claim is warranted. Do not assume File.Replace and Directory.Move guarantee power-loss atomicity. Production implementation may narrow its formally supported crash tier only after owner explicitly accepts the residual risk.

### 4.2 First local write, journal byte protocol, and external anchor

- **External prerequisite (no local mutation):** authority CAS reserves signed ApprovalId+TxId tuple and anchors expected first Sequence and manifest identities before any local transaction-root creation.
- **First local write:** create an absent exact transaction directory under preverified protected updates root, only after remote reservation. If local root creation fails or process crashes before journal creation, recover by comparing remote RESERVED_NO_LOCAL marker and actual root; HOLD_PRESERVE. Never recreate or overwrite an existing transaction directory automatically.
- **Genesis:** create transaction.v4.ndjson with first schema-locked GENESIS record (Sequence 1) and exact remote reservation certificate/hash before creating stage directories; write exact canonical UTF-8 no BOM, LF delimited bytes; flush file and filesystem metadata as required by approved crash tier; obtain an independently anchored remote checkpoint head before advancing. If root exists but journal does not, HOLD_PRESERVE.
- Each record must contain strict allowlisted keys Schema, TxId, Sequence, State, PreviousHash, ReceiptSha256, AuthorityReservationId, AuthorityGeneration, PredecessorManifestSha256, TargetManifestSha256, UtcFromAuthority, EventHash. Define a deterministic fixed-order serializer, explicit integer bounds, strict path-free enum values and byte-domain separation. Hash exact serialized record payload bytes (not parsed JSON reserialization). EventHash cannot be recursively included in the hashed payload: compute it over a domain-tagged fixed-field payload **excluding EventHash**, then serialize and append EventHash; PreviousHash is the prior complete canonical-record byte hash under a separately specified domain. No duplicate/extra fields, noncanonical JSON, malformed UTF-8, BOM, truncated or unflushed record, duplicate Sequence/State, mixing legacy records, missing LF or inconsistent tuple.
- Every locally durable state transition must be reconciled to a monotonic remote committed head/Sequence. Authority outage or local head older than the remote anchor ⇒ HOLD_PRESERVE with no new local write. If a journal is valid only against itself but its trusted external checkpoint/head does not match, treat as UNTRUSTED_TRANSACTION, never recover through a local rewritten prefix.
- Fixed maxima for journal bytes, record count, record length and file set must be selected before parser implementation. Unknown limits are **not licensed defaults**.

### 4.3 Closed normal transition sequence

The table defines explicit intent before every externally visible mutation. Each INTENT record must be flushed/checkpointed before the corresponding action, and an OBSERVED state is only recorded after exact byte, ACL, backup, active-manifest and volume readback:

| Sequence state | Preconditions / durable operation | Failure classification |
|---|---|---|
| REMOTE_RESERVED_NO_LOCAL (external only) | Authority reserves exact receipt tuple before local root | HOLD_PRESERVE if no local root/genesis |
| GENESIS | New absent transaction root created then canonical first record flushed and externally anchored | HOLD_PRESERVE on root/journal failure |
| STAGE_INTENT | Approved paths, lease, verified source/target identities and zero conflicting files | HOLD_PRESERVE if staged path creation uncertain |
| STAGE_CREATED | New stage directory/files present with exact allowlisted names | HOLD_PRESERVE on incomplete stage |
| PACKAGE_VERIFIED | All target member bytes, pins, DACL and no extra paths match | HOLD_PRESERVE on mismatch |
| PUBLISH_INTENT | Stage and final package root same volume; destination absent | HOLD_PRESERVE on rename interruption |
| PACKAGE_PUBLISHED | Exact same-volume directory rename/move to side-by-side final root, complete reread | HOLD_PRESERVE if target identity unclear |
| BACKUP_INTENT | Active predecessor exact bytes confirmed under lock/barrier, backup path absent | HOLD_PRESERVE on backup create |
| BACKUP_DURABLE | Publish exact predecessor backup by independently verified same-volume temp write+flush+rename, reread SHA and DACL; **before active switch** | HOLD_PRESERVE on ambiguity |
| SWITCH_INTENT | Exact backup, package, remote reservation, no late readers, destination candidate, same volume, secondary replace-backup path absent | HOLD_PRESERVE; no inferred active |
| ACTIVE_MANIFEST_SWITCHED | Atomic same-volume File.Replace of staged candidate into active pointer with distinct secondary rollback-backup path; read back both actual active and both predecessor backups; flush and checkpoint evidence | HOLD_PRESERVE on unknown active |
| POSTCHECK_VERIFIED | Independently verify active/backup target/old package, DACL, no mixed readers, remote checkpoint | HOLD_PRESERVE on mismatch |
| COMMIT_DURABLE | Final local terminal flush and remote durable completion acknowledgement, retained predecessor; no cleanup inferred | OBSERVE_ONLY |

Before SWITCH_INTENT, the predecessor backup is already independently durable and exact. File.Replace backup-output path must be **distinct** from the previously published predecessor backup and must start absent. The two backup artifacts must independently verify exact old bytes; the replacement operation must never truncate/overwrite the durable predecessor backup. A reviewer must prove whether File.Replace, flush and directory metadata behavior meet the selected Windows filesystem crash-tier guarantee. If not, block implementation pending a better primitive. Neither journal intent nor state label is itself evidence of completed file operation.

Every root creation, local record write, journal flush, stage directory/file create, package-publish rename, backup temporary write/rename, active-pointer replacement, both backup checks and remote checkpoint acknowledgement requires an independently reproducible synthetic fault point. Old release packages and backups are never automatically deleted.

### 4.4 Authorized post-switch finalization WITHOUT a second pointer switch

Crash can occur after the active-manifest replacement while local journal still ends at SWITCH_INTENT. Recovery MUST inventory exact active pointer independently of the journal and preserve all artifacts. If target manifest is exactly active, target package matches approved signed receipt, independent predecessor backup and replace-generated backup are BOTH present and exact, chain prefix and external checkpoint match, machine is quiescent, protected DACLs match and there is no conflicting transaction, return NEW_ACTIVE_VERIFY_ONLY_CANDIDATE; default mutation HOLD_PRESERVE.

A distinct, **new signed operation receipt** AllowedOperation=FINALIZE_POST_SWITCH, referring to original TxId, ApprovalId, exact original install receipt, expected target/old manifest and external ledger Generation, is required. Remote authority atomically reserves this **separate** operation. Under the same exclusive barrier and launch inhibition, recheck all identities and append only new v4 RECOVERY_POST_SWITCH_VERIFIED, POSTCHECK_VERIFIED and COMMIT_DURABLE evidence with remote anchoring. **It MUST NOT call File.Replace or change approved-release.json, publish/delete packages, rewrite backup, reinterpret v3 journal or re-execute INSTALL.** Incomplete or inconsistent evidence remains HOLD_PRESERVE indefinitely until separately reviewed; no attempt to manufacture missing backup is permitted.

If old exact predecessor remains active despite SWITCH_INTENT, a *different* new signed RECOVER_FORWARD authorization is required, and it must recheck exact backup/package, launch inhibition and no actual prior switch before one future controlled activation. ROLLBACK has no approved implementation; it requires an independent protocol and signed operation receipt, not an implicit compensation action.

## 5. Closed recovery observations and classifications

The **single field** expected_classification is the default **non-mutating disposition**, one of REJECT_BEFORE_WRITE, HOLD_PRESERVE, OBSERVE_ONLY. The independent field inspection_state is descriptive and carries any candidate eligibility; it NEVER grants a write. These same fields are used in the acceptance matrix. No FORWARD_CANDIDATE_ONLY or VERIFY_CANDIDATE_ONLY action classes exist; those are descriptive states, not authority.

| Exact observed state | Allowed inspection_state | expected_classification | Operational action |
|---|---|---|---|
| Verified v2 predecessor installed, no transaction, independently approved receipt missing | PREDECESSOR_OBSERVED | OBSERVE_ONLY | None |
| Old exact active with partial staging or incomplete backup | OLD_ACTIVE_PARTIAL_STAGING | HOLD_PRESERVE | None |
| Old active, published target exact, valid checkpoint and SWITCH_INTENT | OLD_ACTIVE_FORWARD_ELIGIBILITY_CANDIDATE | HOLD_PRESERVE | None; separate RECOVER_FORWARD may later be evaluated |
| New active exact, both backups exact, journal before postcheck and external anchor valid | NEW_ACTIVE_VERIFY_ONLY_CANDIDATE | HOLD_PRESERVE | None; separate FINALIZE_POST_SWITCH may later be evaluated |
| New active and exact backups, terminal journal with durable remote completion | NEW_ACTIVE_COMPLETE_OBSERVED | OBSERVE_ONLY | None |
| New active with missing/invalid backup, missing target or unclear filesystem crash tier | AMBIGUOUS_NEW_ACTIVE | HOLD_PRESERVE | None |
| Active equals neither exact predecessor nor target | UNKNOWN_ACTIVE | HOLD_PRESERVE | None |
| Broken, older-prefix, colliding or v3 legacy journal supplied as v4 | UNTRUSTED_TRANSACTION | HOLD_PRESERVE | None |
| Remote approval reserved, local transaction root absent or journal genesis missing | REMOTE_RESERVED_NO_LOCAL | HOLD_PRESERVE | None |
| Untrusted signer/unsupported version or duplicate receipt JSON field before any write | REJECTED_RECEIPT | REJECT_BEFORE_WRITE | None |
| Inaccessible process info or unproven launch barrier | QUIESCENCE_UNPROVEN | HOLD_PRESERVE | None |
| Valid sealed source-only v4 contract, no installer | SOURCE_ONLY_ACCEPTED | OBSERVE_ONLY | None |

When observations disagree, use the **least-permissive** classification and preserve evidence. No classification is a capability token. A recovery *operation* requires a separate signed/remote-reserved authorization, and no such write path is implemented.

## 6. Boundary assurance, no circular pins, and proof gates

- Strictly retain historical old v1/v2 pins, v2/v3 manifests and legacy transaction.ndjson; prevent any v4 resolver from importing the legacy parser, or vice versa. New production code needs a separately frozen pin generation and installable manifest (proposed v5), NEVER relabel the already reviewed ten-member source-only v4 as installable.
- Freeze operator-approved package inventory and authenticated bootstrap/key/authority ledger before any code. The ledger proves replay state independent of locally restored old transaction files; if it cannot, no production cutover. Signed operation-specific recovery uses a distinct ApprovalId and the same immutable TxId.
- Enumerate every known launch and reader process path; v2 needs a proved OS-enforced maintenance/launch-inhibited cutover or must remain unsupported. v3 may be eligible for online migration only if all late launches are mediated; do not assume v3 is installed.
- Independent Windows reviewers must audit real filesystem semantics, exact File.Replace backup effects, directory metadata durability, process handle/share modes, replay after restoration, remote partition/crash, all 38 prior matrix scenarios plus the expanded ones, and fault injection at each mutating boundary.
- The original CI #85 (FULL_SEQUENCE_INCONCLUSIVE, intermittent receiver) is NOT resolved by this design. No CI, PR, merge, UAC, protected recovery, updater execution or release is authorized here.

**Status: PROPOSED_R2_NOT_CODED / ARCHITECTURE_REVIEW_PENDING / RELEASE_HOLD.** The trust bootstrap, signature/key operations, ledger service, OS enforcement and storage crash tier remain unimplemented and require owner decisions. This specification is a **candidate for independent design review**, not production approval.
