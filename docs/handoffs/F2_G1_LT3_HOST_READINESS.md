# F2 G1 — LT-3 host-read readiness, frozen historical contract, and execution gate

**Status:** SOURCE-ONLY PREPARATION CANDIDATE / HOST-READ DISABLED / INDEPENDENT SOURCE REVIEW PENDING. This is **not** a live host inspector and does **not** constitute permission to read protected C:/G: or operate Hyper-V.

**Authorization provenance:** Owner authorized **LT-3 preparation** after `PASS_INDEPENDENT_LT2_SOURCE_REVIEW` at exact LT-2 SHA `fd19fe0ec65897e401bf18c57c1730183aff32c5`. The accepted local-trust threat model remains `29f90ef9b2310044e64d3acd775534559a404425`. Current work is a source-only readiness contract, kept off `main` in `feat/f2-g1-lt3-host-readiness-source-only-v1`. The user did NOT authorize protected host reads or any ACL mutation.

## Why this is a bounded preparation, not a new architecture

The earlier LT-2 validated actual Windows token information and read-only NTFS fixture bytes and ACL metadata. The historic R2 module already specifies original V2 package SHA-256 pins, the manifest/payload/integrity hashes, mailbox IDs, captured expected G: **path strings**, exact object list and parent/package/mailbox owner/DACL profiles. There is no reason to replace those policies or add a cryptographic launcher or hostile-admin defense.

This LT-3 stage freezes the *joining contract* rather than turning the already disabled R2 `-Live` path on prematurely. New source performs no protected host I/O. An exact independently reviewed Windows reader with host paths will require a **separate code change and explicit, fresh execution grant**. Simply supplying a GitHub comment URL, hash string or boolean will never activate it.

## Implemented files

- `scripts/f2-acl/lt3/F2G1LT3.Readiness.psm1`: immutable declared reference contract for **23 C: object names** (8 directories / 15 files), five inventories, seven *exact* historical R2 installed-package SHA-256 values, historical manifest/payload/integrity SHA-256 and mailbox/capture/source identifiers. It validates uniqueness, case-exact names, digests and historical identities in **untrusted metadata declarations only**. It never treats declarations as proof of physically read contents; it always returns `BLOCKED_WITH_EVIDENCE`, even if every declaration matches.
- `scripts/f2-acl/lt3/Invoke-F2G1LT3.Readiness.ps1`: a simple `-Describe` or no-argument interface that only prints bounded, redacted `BLOCKED_WITH_EVIDENCE` readiness status and exits nonzero. It has **no `-Live` flag, no arbitrary paths, no owner-reference activation, no host file provider and no UAC fallback**.
- `scripts/f2-acl/lt3/Test-F2G1LT3.Readiness.ps1`: Windows PowerShell 5.1 syntax/source boundary test; checks historical pins literally against unchanged R2 source; positive metadata reference set *remains blocked*, negative duplicate/omitted/wrong digest/wrong identity/wrong-case cases block; CLI default and `-Describe` each exit blocked with `ProtectedReads=0`.
- `.github/workflows/f2-g1-lt3-source-only.yml`: GitHub-hosted Windows PowerShell 5.1 source-only tests and unchanged LT-2/LT-1/R2 fixture regression. No credential persistence, read-only repository token, no physical protected-host path access.

**No claimed host attestation:** `ProtectedReads=0`, `HostAttestation=NOT_PERFORMED`, `TrustedEvidence=false`, `Code=DECLARATIONS_MATCH_HISTORICAL_REFERENCES_NOT_OBSERVED` and a blocked verdict, even if metadata claims equal all pins. The seven true installed bytes are **not** reconstructed by this module. The historical 11 G: entries remain evidence strings; no G: reads.

## Minimal technical bridge remaining before any real C: read

Prepare a separately reviewed protected-host read-only adapter, built from proven LT-2 observation primitives but **without the disposable CI fixture mapping**, that:
1. Accepts no user-selected paths and targets only the 23 R2 names, the five fixed inventories, and no G: files. Uses read-only handles, object-type and reparse guards, bounded reads and before/after metadata/ACL stability; denies ambiguous observations.
2. Checks the actual Windows process token is non-elevated and medium integrity, including filtered UAC tokens only when genuinely limited and Administrators effective role inactive. No UAC, admin fallback, privileged recovery or writes.
3. Compares **physically read** package bytes to the seven frozen R2 hashes, manifest to `b5f01570cf8937324f0c763f72a8d05b5532472156d4e5b0fcfbd180dc7abbe9`, payload to `1b5eee9aae928a909d4c251a4dd6d2c0898c400e2807e0acc3268d61d5149014` and integrity to `02d6f07f5b3bb6f47a84e58d7c207c9935481e8a898a3b1f5e1ed273d4d61b34`. Keep exact record names/capture ID and compare 11 G: strings only.
4. Reuses R2's reviewed **owner/DACL semantic policy** for three parents, package directories/files and mailbox; all required evidence, framed digest and diagnostics must be complete and cross-consistent. Respect the numeric JSON type safeguards established in LT-2. Actual observed state must not be inferred from a dictionary of caller-provided digests or a fixture PASS.
5. Returns finite sanitized evidence only, never raw SDDL, private SIDs, original contents or hidden live path. Distinguishes `HISTORICAL_V2_READ_ONLY_MATCH` from effective ACL rights, V3 installation state, G: state and production authorization. Any unreadable/mismatched required object blocks; no repair.

**This adapter is NOT implemented and MUST NOT be activated from this preparation.** An actual protected-host read will be the subject of a fresh, explicit, separately authorized execution decision after the exact adapter source has been independently reviewed.

## Minimal human owner-operation prerequisites (NOT approved yet)

The owner must later identify: exact final reviewed Git SHA and source SHA-256; exact Windows machine and account; fixed `C:\Program Files\F2-G1-Icacls` and `C:\ProgramData\...` allowlist; an **explicit one-time read-only command**; standard-token preflight; zero protected writes and no elevation; finite redacted output destination; stop criteria; and a reviewed assessment of what a guest checkpoint can and cannot protect. Guest checkpoint is NOT a backup of the host C: ACL or files.

An acceptance of this LT-3 readiness source means only that the references and operational gate are correctly prepared. It **does not** imply the adapter implementation, operational source approval, LT-4 execution, any ACL repair, release or environment unblock.

**Persistent holds:** `CURRENT_PROTECTED_STATE_UNKNOWN`, `V3_NOT_ATTESTED`, `ACL_REVIEW_REQUIRED`, `G1_BLOCKED_ENVIRONMENT`, `F2_G1_RELEASE_HOLD`. R2's existing live constructor/authorization still deny. No main merge, PR, protected read, Hyper-V operation, UAC, icacls or release.
