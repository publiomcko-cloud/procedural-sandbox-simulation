# F2 G1 — R4 owner-operated one-time C: postfailure attestation architecture (design v1)

**Status:** `READY_FOR_INDEPENDENT_DESIGN_REVIEW`; **DESIGN ONLY**. NOT implementation, trusted bootstrap acceptance, live authorization, protected-host execution approval, V3 attestation or release permission.

**Repository:** https://github.com/publiomcko-cloud/procedural-sandbox-simulation.git  
**Frozen accepted synthetic ancestor:** R3.3 `3a1fd6fb65c12484e237c829837fccf2b0a9e5e8`, branch `fix/f2-g1-r3-3-drain-cleanup-gate`.  
**R2 fail-closed ancestor:** `48ac3e8551127451d1b0d3861a98c3b075f2c4f6`.  
**R4 design branch:** `design/f2-g1-c-postfailure-r4-owner-operated-v1`. The independent reviewer must pin this document's final SHA/physical hash separately; do not use the ancestry SHA as an R4 executable digest.

## 1. Decision and actual trust boundary

**Selected option B:** owner-operated, one-time, *read-only* inspection, with an independently pinned bootstrap/launcher and a fresh, authenticated human owner confirmation. There is **no server-side signer or reusable Issue URL grant** in this design. The owner must independently authenticate the Issue #48 approval source and immutable owner identity; a string URL, Git ref, environment variable, or caller-provided SHA is NEVER an authorization token.

These are **separate necessary controls**:
1. **Software trust:** a trusted verifier outside the mutable inspector confirms exact *physical bytes that will execute*, full canonical scope and runtime/dependencies against independently owner-approved pins. A commit name alone or a tool self-report does not establish physical execution identity.
2. **Human approval:** after the final implementation receives an independent exact-SHA review, the owner authenticates directly in a separately trusted account/session and checks a **new** approval explicitly binding the final reviewed source commit, packaged executable/bootstrap digests, canonical scope digest, purpose, current machine, one invocation, and non-admin read-only mode. The Issue #48 authorization previously spent (`6196160426`) is never reusable.
3. **Execution/token:** the trusted launcher mediates owner confirmation and independently qualifies the actual process/thread token **before any protected C: open**, then dispatches an immutable, fixed-scope capture engine.
4. **Object trust:** each protected path component is opened relative to an already-held verified parent handle, with no-follow reparse semantics; descriptors, content and inventory are bound to held object identities rather than sequential path lookups.

**Important limitation:** manually checking an authenticated website is an *operational human gate*, not cryptographic evidence that the executable can prove the website owner or one-use consumption. A local malware adversary can impersonate the launch UI or confirmation. Without a trusted owner-presence mechanism, the B design cannot claim machine-verifiable owner identity, anti-replay against hostile local execution, or resistance to owner-account compromise. If the independent reviewer or owner requires those threat properties, return `BLOCKED_WITH_EVIDENCE` and choose a separately reviewed externally authenticated/signature-backed alternative A. Do not silently describe B as an equivalent signing service.

**Threat assumption for B:** a non-compromised, owner-operated Windows workstation, trusted OS/kernel, secure independent verification channel and non-adversarial owner interaction. Untrusted files/links, environmental path substitutions, reparse points, nonprivileged concurrent filesystem writers and accidental operator mistakes are considered failure cases. Privileged/kernel adversaries, compromised OS, malicious drivers, and malicious authenticated owner session are *not* neutralized by ordinary user-mode handles.

## 2. Frozen artifacts and source-execution chain (not implemented)

Define one **small packaged native bootstrap** whose actual reviewed binary SHA-256 and provenance are approved independently, not a PowerShell script that hashes itself. A reviewed build manifest lists **every executable byte** (launcher, capture engine, relevant managed assembly and non-OS dependency) with exact SHA-256, source tree/commit, build settings, architecture and expected OS/runtime identities. Require reproducible-build comparison or independent binary review before first live eligibility; do not assume Git SHA implies binary identity.

**Launch protocol, before C: reads:**
- Owner separately obtains and verifies trusted bootstrap pin and manifest through an authenticated channel independent of the code being launched. The bootstrap is loaded only from a verified immutably protected source location or via a loader that binds the verified source handle to actual loaded bytes; a hash-then-path-reopen is forbidden. Review DLL search order and dependency hijacking.
- Verify the complete canonical scope document against a separately trusted, pinned byte hash, reject unknown schema fields, unexpected defaults/flags, duplicate keys/names, wrong array cardinalities/order and encoding ambiguity. Historical hash constants must come from independently reviewed R2 policy pins, not from a caller's fixture.
- Do not compile or import **installed protected scripts/modules**, and do not load C# from a path after hashing. If managed code is required, consume exactly the buffered/verified source bytes or a pinned assembly through a verified loader. Keep source handles denying write/delete until process exit or prove equivalently strong executed-byte binding.
- No `-Live` switch is added to R2 or R3.3 as a shortcut. A future operational launcher is a separate implementation and independently reviewed entrypoint; **all** existing fail-closed routes remain disabled.

**Unresolved implementation gate:** no trusted launcher binary, independent build/pin distribution, reliable loaded-byte identity mechanism or DLL dependency freeze is presently qualified. The R3.3 `Add-Type -TypeDefinition` check is TEMP-only synthetic evidence, **not** a trustworthy bootstrap.

## 3. Exact authorized target scope (design-time; fixed, no arguments)

Authoritative expected-object/policy source: R2 `scripts/f2-acl/F2G1CPostfailureAttestation.psm1`, plus R3.3 `scripts/f2-acl/r3/F2G1R3.FixedScope.json`. Disagreement is a **blocking specification defect** until an independent review reconciles the exact policy and pins; R3.3's scope JSON is design data, not operational authority.

Read-only C: inventory consists of **23 named objects** and bounded immediate-child checks:

| Class | Exact fixed set | Required checks |
| --- | --- | --- |
| Parent directories (3) | `C:\`, `C:\Program Files`, `C:\ProgramData` | owner / parent-specific DACL profile, type, no reparse, stable identity; do **not** enumerate C: root or these broad parents |
| Installed package directories (4) | `C:\Program Files\F2-G1-Icacls`; its `scripts` and `scripts\f2-acl`; `C:\ProgramData\F2-G1-Icacls` | owner / installed-directory DACL profile, no reparse, identity; immediate inventory only on these 4 directories |
| Active manifest (1) | `C:\ProgramData\F2-G1-Icacls\approved-release.json` | one held file handle, installed-file DACL, size <= 65,536, exact historical SHA-256 and schema |
| Installed package members (7) | Under `C:\Program Files\F2-G1-Icacls\scripts\f2-acl`: `F2AclCapture.Protocol.psm1`; `F2AclIcacls.Corroboration.psm1`; `F2AclIcacls.Runtime.psm1`; `Invoke-F2IcaclsCapture.ps1`; `Invoke-F2IcaclsProtectedCoordinator.ps1`; `F2_ICACLS_SOURCE_PINS.json`; `Invoke-F2AclReadOnlyCapture.ps1` | per-file read-only handle, installed-file DACL, exact pinned SHA-256; size <= 16,777,216 each |
| Historical evidence mailbox (1) | `C:\ProgramData\F2-G1-ACL-Evidence-ecb6deeb424e40feb5354d18908986df` | owner / mailbox 4-ACE profile, exact 7-child inventory, stable held directory |
| Evidence members (7) | `acl-baseline.frame`; `acl-baseline.json`; `coordinator-status.json`; `integrity.json`; `powershell-streams.json`; `worker-stderr.json`; `worker-stdout.json` | non-reparse held file handles, exact names/types/length bounds, historical payload/integrity digests and complete cross-file provenance |

**Exact immediate-child inventory:** package home has `scripts` only; package `scripts` has `f2-acl` only; package `scripts\f2-acl` has the 7 listed members only; protected ProgramData package root has `approved-release.json` only; mailbox has the 7 listed evidence members only. At the package `f2-acl` and ProgramData package root, all names `release.lock`, `updates`, `backups`, `releases`, `journals` and `stages` are explicitly **absent**; any other unexpected name is also rejected. No recursion. A directory read failure or additional child cannot be treated as a clean/empty inventory. Do not treat nonexistent transaction artifacts as objects to open.

Historical IDs/hashes are **expected values, not current-state evidence**: source `5741ffe90a3abd02a08563e6431e8a0b9b63eeb1`, active manifest `b5f01570cf8937324f0c763f72a8d05b5532472156d4e5b0fcfbd180dc7abbe9`, evidence payload `1b5eee9aae928a909d4c251a4dd6d2c0898c400e2807e0acc3268d61d5149014`, integrity `02d6f07f5b3bb6f47a84e58d7c207c9935481e8a898a3b1f5e1ed273d4d61b34`; seven package pins are frozen in R2 lines 12–20. Verify these against R2's exact reviewed policy during independent design review. G: guest/VM paths appearing **inside evidence JSON** are compared as historical strings only; NEVER open `G:\`, query VM APIs or use `icacls`.

Mailbox member upper bounds: `acl-baseline.frame` <= 262,188 bytes; `acl-baseline.json` <= 1,048,576 bytes; each other member <= 65,536 bytes. The mailbox inventory must be exactly 7 unique files. The baseline JSON must contain 11 unique expected historical G: *string records*, complete markers, the reviewed capture ID, VM name/ID as policy data, and matching frame/payload/integrity/coordinator/streams checks. These are assertions about preserved historical evidence bytes, **not direct inspection of G:**.

**Unresolved content semantics to reconcile before implementation:** source R2's parent and mailbox policy checks, optional/required manifest fields, expected requester SID binding, SDDL normalization and ACL inheritance semantics, whether installed files can legitimately have multiple NTFS hard links or alternate data streams, directory case/alias handling, and exact behavior on unexpected transaction artifacts. Fail closed on any unresolved policy mapping; do not invent replacement expected hashes from current host reads.

## 4. Windows handle-only observation contract (not implemented)

- Start from an owner/trusted-bootstrap-resolved volume anchor; reject unexpected volume/device mappings and reparse/mount-point changes. Pin volume serial/unique ID and 128-bit file ID where supported (`GetFileInformationByHandleEx(FileIdInfo)`); a legacy 64-bit file ID may be insufficient on some filesystems. Refuse unsupported identity queries, unsupported filesystem semantics and cross-volume transitions. Treat identity alone as insufficient without stable held handle, name/type and descriptor corroboration.
- For each fixed path component use `NtCreateFile`/equivalent verified native call relative to its already-held parent (`RootDirectory`), `FILE_OPEN_REPARSE_POINT`, and directory/file-type flags. Check returned reparse attributes/tag, volume/file identity and expected fixed component name. Hold **all** relevant ancestor and directory handles until the final report decision. A path-based `Get-Item`/`Get-Acl`/`Get-ChildItem` then later open is prohibited.
- Request only `FILE_READ_ATTRIBUTES`, `FILE_READ_DATA` (files), `FILE_LIST_DIRECTORY` (inventory dirs), `READ_CONTROL` and `SYNCHRONIZE` as necessary. Deny write/delete sharing where supported; fail on sharing conflict, access denied or pre-existing writer incompatible with stable inspection. Do not request `WRITE_DAC`, `WRITE_OWNER`, `DELETE`, backup/restore override or privileges. SACL queries are out of scope.
- Read owner and DACL using **GetSecurityInfo on the held handle**, never name-based `GetNamedSecurityInfo`; read bounded content with the *same held file handle*. Reject object substitution, changed length, truncation, trailing bytes, wrong hash, unexpected hard-link count if forbidden by reconciled policy, and metadata or object identity drift. File/hash checks precede positive conclusions.
- Enumerate only specified immediate children from held directory handles, with bounded enumerations and no traversal beyond required child set. Open required child names **relative to those handles**, then repeat inventories and object identity/descriptor checks while all handles remain held. Any instability, ambiguous casing/alias, unexpected child, reparse, missing object or unreadable metadata is `BLOCKED_WITH_EVIDENCE`.
- Prevent resource exhaustion: exact object count/size bounds, bounded resident-memory/report/stream limits, monotonic deadlines, fail-closed process and pipe cleanup, and no success if a descendant retains uncompleted streams. No filesystem mutation, installation or generated output under protected C: scope.

**Atomicity limitation:** held handles and repeated inventories provide a bounded observation, not a transactionally atomic filesystem snapshot. A privileged or kernel-level mutator, malicious filesystem driver, filter manager, storage fault or hostile hardware may invalidate claims. On a competing change detectable during observation, block. Never claim complete effective Windows access-right equivalence from descriptor checks.

Windows API documentation used for design intent (NOT an implementation validation):
- https://learn.microsoft.com/en-us/windows/win32/api/winternl/nf-winternl-ntcreatefile
- https://learn.microsoft.com/en-us/windows/desktop/api/winbase/ns-winbase-file_id_info
- https://learn.microsoft.com/en-us/windows/win32/api/aclapi/nf-aclapi-getsecurityinfo
- https://learn.microsoft.com/en-us/windows/win32/api/winnt/ne-winnt-token_elevation_type

## 5. Token gate and one-time owner-operated state machine

**Mandatory process order:** `UNTRUSTED` → `SOURCE_BYTES_VERIFIED` → `CANONICAL_SCOPE_VERIFIED` → `OWNER_CONFIRMED_FRESH_GRANT` → `STANDARD_TOKEN_VERIFIED` → `FIXED_HANDLES_OPENED` → `CAPTURE_COMPLETE` → `SANITIZED_REPORT`. Any failure transitions to terminal `BLOCKED_WITH_EVIDENCE`; no retry, elevation or scope expansion within the same invocation.

Owner grant fields to verify manually in an **independent authenticated browser/session**: immutable owner account ID, unique approval identifier, exact reviewed R4 implementation source tree/commit, bundle/bootstrap executable SHA-256, canonical scope bytes SHA-256, read-only non-admin C: fixed list, target machine binding, issuance and expiration, and a **fresh explicit one-use invocation**. Verify the author *account identity*, not merely displayed user name, avatar, URL shape, or text supplied to the program. Original spent Issue #48 approval is not valid. The trusted launcher must require owner presence and an explicit confirmation *after* independently showing verified identities; do not accept `--approved`, arbitrary URL, forged environment variable or persisted reusable approval string.

**Crucial unresolved gate:** specify and independently review how the launcher prevents untrusted code from spoofing the owner's confirmation and what one-use means operationally without a server-side nonce authority. If the answer is only the owner's manual one-time action, label it a human/process control, never cryptographic replay prevention. On environments with a hostile local user/process, design B is insufficient without stronger trusted interaction or option A.

Actual Windows token gate at launch **and again before final report**: use trusted native `GetTokenInformation` or equivalent for `TokenUser`, `TokenGroups` (including deny-only/disabled Administrators SID `S-1-5-32-544`), `TokenElevation`, `TokenElevationType`, `TokenIntegrityLevel`, `TokenPrivileges` and impersonation/effective thread-token state. Reject elevated, linked-admin/limited-admin, administrator member even if filtered/deny-only, SYSTEM/service tokens, high/system integrity, active backup/restore/takeownership/debug rights or privileges forbidden by fixed policy, and unknown/ambiguous token state. Require an independently approved specific standard requester SID and normal medium integrity; no elevation prompts or impersonation. Fail closed on unresolved Windows token edge cases. A standard token passing this gate is **not** proof of effective file access across all kernel policy/filter drivers.

## 6. Evidence capture, policy engine and report boundary

Keep **physical observation** distinct from **historical policy evaluation**:
1. A trusted, fixed-scope capture engine yields a complete typed in-memory bundle: object-kind/name identity, volume + file ID, verified metadata (including owner/DACL), bounded bytes/hash for each of 15 fixed file objects, and immutable before/after directory inventory records. Count: 7 package + manifest + 7 mailbox = 15 files; 8 directories = 3 parent + 4 package + mailbox. No partial successful bundles.
2. A separate independently reviewed *pure evaluator* consumes only this captured bundle and the frozen, canonical historical policy/pins. All 23 required objects must be accounted for. Its validated report is distinct from current R2's synthetic fixture mode. Never pass caller-created `Fixture.Expected` into a production evaluator, never use a `Mode=Live` toggle, and never promote `SYNTHETIC_FIXTURE_PASS` into a protected-host verdict.
3. Compare the manifest and seven package members against the exact R2 historical pins, mailbox/11-record/frame hashes and ACL descriptor profiles; preserve the distinction between raw owner/DACL *observations*, configured ACE policy matching and **unproven effective-token rights**.
4. Output a bounded redacted diagnostic/report with exact machine/source/scope identity **only after the complete capture is validated**. Do not emit raw SDDL, personal/user SIDs, private metadata, secret paths/data or file bytes. Failure output is a sanitized phase/error code plus count of protected reads; do not claim success from file hashes alone.

For a **hypothetically future independently approved, freshly authorized one-time run**, a matching report may attest only `PASS_READ_ONLY_C_POSTFAILURE_ATTESTATION` for preservation of historical V2 artifacts *at the observed instant*. It does not infer `PASS_RESTRICTIVE_ACL`, effective token authorization, present state after the run, V3 completion, G: guest/VM correctness or release readiness. This R4 **design document may not itself issue such a verdict**.

## 7. Future implementation/review sequence — no step is authorized now

**D4.0 (this change):** architecture-only Markdown document on isolated branch, independently reviewed, with no executable production or synthetic code modifications. Only `PASS_INDEPENDENT_R4_DESIGN_REVIEW` can accept the specification.

**D4.1 (separate future authorization):** implement *source-only* trusted bundle/bootstrap candidate and source-byte/owner-confirmation/token-gate contracts; verify against temporary mocks and independent source/binary identity checks. No protected reads; no launch on actual protected host.

**D4.2 (separate future authorization):** implement complete fixed-scope Windows no-follow held-handle capture provider, typed capture bundle and pure historical evaluator **only in synthetic fixtures on disposable isolated Windows CI**. Reject hostile path/fault cases, races, reparse at every level, hard links, aliases, alternate streams, file changes, ACL read denial, truncated/corrupt/extra artifacts, token edge cases and process/pipe anomalies.

**D4.3 (second independent exact-SHA source/binary/security acceptance):** independently verify entire executed bundle, signed/provenance build chain, complete scope mapping, manual grant procedure and every Windows object contract. If any ambiguous gate remains, `BLOCKED_WITH_EVIDENCE`; no fallback to old path-based live provider.

**D4.4 (new OWNER AUTHORIZATION, not inherited):** only after qualified review, seek a **fresh and separate explicit owner grant** naming the exact reviewed executable/source SHA, scope hash, target Windows machine, non-admin one-time read-only C: operation and evidence handling. No prior approval authorizes this step. Owner's manual approval may still be insufficient for hostile threat models.

**D4.5 (hypothetical future host operation):** never automatic; a separately authorized, reviewed launch could perform just that bounded read-only C: inspection. Retain all environment/release holds until an entirely separate protected-state/effective ACL/V3 qualification.

## 8. Design review checklist and unresolved blockers

Independent reviewer must:
- Verify branch parent R3.3, document-only path, clean provenance, Git blob and physical SHA-256.
- Compare **all 23 object names**, exact four package directory inventories plus one mailbox inventory, absent six transaction names at two roots, seven historical package pins, historical manifest/payload/integrity digests and 11 G: evidence *strings* against R2 at the exact base SHA; identify any mismatch.
- Challenge the bootstrap's loaded-byte guarantees, OS runtime/DLL search, build pin custody, immutable source propagation and independently verified owner identity/one-use semantics. Specify what *cannot* be qualified without a new trusted component.
- Review token-gate policy, 128-bit file IDs, held reparse-free ancestors/contents/ACLs, inventory consistency and exception semantics.
- Check that no design statement confuses historical byte preservation with release, current runtime, effective ACL or atomic snapshot.
- Reject hidden requirement to execute protected C:/G: paths, request elevation, alter ACLs, mutate R2/R3, deploy protected scripts, create PR, merge or release.

**Known blockers at this design point:** trusted bootstrap distribution/executed-byte provenance; owner-presence/one-use operational trust; reconciliation of all ACL and object inventory semantics; real standard-token gate; complete no-follow handle implementation; independently qualified byte/descriptor/identity read consistency; absence of atomic snapshot and effective-token proof.

**Verdict allowed for this document only:** `PASS_INDEPENDENT_R4_DESIGN_REVIEW` or `BLOCKED_WITH_EVIDENCE`. A design PASS permits **a future owner decision** about D4.1, not implementation authorization, an on-host read or release.

**Persisted holds:** `CURRENT_PROTECTED_STATE_UNKNOWN`; `V3_NOT_ATTESTED`; `ACL_REVIEW_REQUIRED`; `G1_BLOCKED_ENVIRONMENT`; `F2_G1_RELEASE_HOLD`.
