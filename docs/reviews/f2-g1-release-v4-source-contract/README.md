# F2 G1 — release contract v4, source-only specification

Status: DESIGN_CANDIDATE / RELEASE_HOLD. This is NOT an approved release, updater instruction, installer configuration or migration of the historical v2/v3 runtime.

## Lineage and identity

Design parent: `676301fdd6b1ce6c6eda161d1c5e1b2be753feb2`.
Baseline mailbox/capture IDs and payload/integrity SHA-256 stay identical to the retained reviewed evidence. The original v1 collector pin file, original v1 icacls pin file, installed v2/v3 manifests, updater's old-installed-release pins, rollback receipts, and production launch defaults are not modified.

The source-only schema `f2-icacls-runtime-release-v4` requires:
- an externally reviewed exact `ReviewedCommitSha` and canonical `PackageRoot`;
- externally approved `ExpectedManifestSha256` and `ExpectedActivePinsSha256` supplied to the verifier, never computed from untrusted manifest inputs;
- exact ten-file package inventory, independently hashed; both icacls v1/v2 and collector v1/v2 pin files included;
- exact historical baseline IDs/digests and separately checked old source-provenance pins;
- `Status=SOURCE_ONLY_NOT_RELEASE_APPROVED`. This status MUST NOT be accepted by an updater or protected coordinator.

## Noncircular freeze procedure (future authorization)

1. Freeze implementation and source pin files at a reviewed source commit.
2. Independently capture the exact **Windows checkout bytes** of each of the ten package files; verify git attributes and EOLs.
3. Create the candidate v4 manifest **outside that source commit** with fixed file hashes, anchored source-pin digest, reviewed SHA and release package path.
4. Obtain independent manifest-bytes hash and a separate signed/approved receipt. Never derive approval from a hash carried only by the candidate itself.
5. Validate candidate manifest and 10 exact package members in a sandbox with the source-only verifier.
6. Only after a distinct security review and authorization may the collector, runtime, coordinator, launcher, updater, transaction and recovery state machines be adapted and validated end-to-end. Existing v3 dispatch remains unchanged until then.

## Boundary

`F2ReleaseContract.V4.SourceOnly.psm1` exports **read-only validation helpers only**, no mutation, installation, package staging, UAC, VM access, rollback, or recovery functions. Its existence in the repository does not confer runtime authorization. Any present production v3 reader must continue rejecting v4. The v4 candidate is NOT generated here; the future v4 candidate must not be committed into the source tree whose ReviewedCommitSha it pins.

The following are still independent blockers: historical full-sequence diagnostic timeout; intermittent receiver channel failure; Windows PowerShell 5.1 source-only regression and source-security review; production v4 rollout/recovery contract; final source and package pin migration; external manifest approval.

## Actor-by-actor compatibility matrix

| Actor | Current production contract | v4 design gate in this source-only commit |
|---|---|---|
| Collector / worker | v1 `F2_ACL_SOURCE_PINS.json` with exact source and commit verification | Separate v2 collector pin role checked; no collector launch dispatch |
| Runtime | installed release schema v3; seven pinned files | Ten-member v4 manifest validated offline only |
| Protected coordinator | v3 manifest, pinned release path | v4 cannot pass original v3 schema check |
| User launcher | v3 candidate file and reviewed SHA | no v4 command or UAC path enabled |
| Updater | installed v2 old pins + seven-member v3 candidate | v4 staging and recovery not wired; fail closed on v4 |
| Recovery / rollback | historical v2 backup and v3 transaction model | old protected rollback untouched; new v4 recovery design pending |
| Package member set | seven named members in v3 | ten exact members in v4; both source-pin generations retained |

### Source validation boundaries

Source-only tests may read checkout files and calculate **test fixture hashes**. A hash calculated from the same untrusted content must never be used as release approval. The independently authorized v4 receipt must provide an exact, already-reviewed manifest digest and active-pin digest. The current code does not create a release candidate, install, issue UAC prompts, or perform rollback.

The source-only verifier rejects UNC, G:, reparse-point ancestry, unknown files, changed baseline identities, mismatching commit IDs, wrong candidate/active-pin digests, wrong active/retained pin roles and non-source-only status. Any production enablement requires independent tests of these conditions and the existing transaction/recovery state machine before an owner decision.
