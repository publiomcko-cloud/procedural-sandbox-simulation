# F2 G1 final execution-path preflight — source-only

Status: `READY_FOR_F2_G1_FINAL_EXECUTION_PREFLIGHT_REVIEW`

Ticket / acceptance criteria: Issue #48 comment `6132042537`; correct the reviewed evidence arithmetic/EOL discrepancy and prove the exact future command's local source and candidate paths against reviewed hashes.

Repository / remote: `publiomcko-cloud/procedural-sandbox-simulation` / `https://github.com/publiomcko-cloud/procedural-sandbox-simulation.git`

Review worktree / branch: `C:\Dev\f2-g1-final-execution-preflight-review` / `docs/f2-g1-final-execution-preflight-20261012`

Base SHA: `923c7d39d7fbfe106dea404c386efd4b5844654e`

Candidate SHA: the immutable GitHub commit containing this handoff; see this draft PR's exact head commit.

Parent SHA: `923c7d39d7fbfe106dea404c386efd4b5844654e`

## Corrections and implementation

- Corrected the seven-suite sum in the reviewed handoff to **521**, because `152 + 118 + 41 + 18 + 134 + 20 + 38 = 521`.
- Reconciled `ITERATION_AUDIT.md` against the repository's `*.md text eol=lf` rule. The older PR #62 checkout was reproduced as 4,793 bytes with 22 LF and 3 CRLF line endings (SHA-256 `0c7be08d8d211b893596a34a6f032737b4357421f14dad60336399eb9db36016`). In a new clean worktree at the same reviewed commit, Git checked out the same 4,790-byte Git blob as 22 LF and 0 CRLF; its checkout SHA-256 equals its Git-blob SHA-256 (`51f87ddb15acfad119a406debc4d44d54af6b5f1a998ff5827a497382056e684`). The audit now explains the mixed-EOL cause. The updated audit in this final evidence tree is all-LF, 24 lines, with checkout and Git-blob SHA-256 both `a28ac78c48046afb4a4b5ffe85f3f0f6b238ada34db6355b256f11ccd2b85c64`. The refreshed artifact manifest records current file bytes and staged Git-blob bytes separately.
- Fast-forwarded the exact command's SourceRoot worktree from `8b70a70934445bee660c1e53e71b2e7b20a6191f` to `03882eedf3104fc33aa0cf503ddef9c9a6bec702`. It was clean, detached, and the old commit was an ancestor. The existing source branch/worktree at the reviewed new commit remains intact.
- The launcher also reads its candidate from `C:\Dev\f2-g1-protected-updater`. That checkout had the stale candidate SHA `74d178917fba4f50fdca40505d8c1dc81639f3c60bbb25c0332fd737c681562c`, bound to source `8b70a709...`. To make the already-reviewed command's actual inputs consistent, that clean worktree was checked out detached at reviewed PR #62 HEAD `923c7d39d7fbfe106dea404c386efd4b5844654e`. Its existing `fix/f2-g1-protected-release-updater` branch reference remains at `9e9915e6eb15bcb20cc2f5a1c990791e2a822b90`; no branch was advanced, reset, deleted, or force-updated.
- `git ls-remote` independently confirmed the expected origin refs: production source `03882eed...`, PR #62 review `923c7d3...`, and the preserved PR #59 branch `9e9915e...`. PR #62 remains open and draft at `923c7d...`.
- Updated the source-chain validation helper to allow a detached source checkout only when the pinned `origin/fix/f2-g1-update-diagnostics-source` ref independently equals the expected commit. Production launcher/updater behavior is unchanged; they check clean status, remote URL and exact commit and do not require a local branch name.
- Added `Test-F2G1FixedSourceRootPreflight.ps1`, a read-only Windows PowerShell 5.1 verifier for the exact fixed source and candidate paths, command pins, file hashes, clean checkouts, origins, remote refs, and reparse-free path chains. It does not invoke the launcher, updater, UAC, or protected paths.

## Verified fixed paths and release identity

| Item | Verified value |
|---|---|
| Production SourceRoot | `C:\Dev\f2-g1-protected-updater-source` |
| Source HEAD / parent | `03882eedf3104fc33aa0cf503ddef9c9a6bec702` / `12575f4802f471210c0516b68b5d0d37d2eb8642` |
| Source origin / clean | Expected GitHub origin / clean; detached checkout; matching remote branch ref |
| Candidate review root | `C:\Dev\f2-g1-protected-updater` |
| Review HEAD / clean | PR #62 HEAD `923c7d39d7fbfe106dea404c386efd4b5844654e`; expected origin; clean; matching remote branch ref |
| Launcher Windows SHA-256 | `054e69a4b908c1fe1927e5997bf1c7aca003e8ae21fbaa278323fdf6b5179e68` |
| Updater Windows SHA-256 | `c4dfc71606888555f7b93930671045490ba8e49d20d65f858eab6c084bf620eb` |
| Diagnostic protocol Windows SHA-256 | `f66783ac53ce84c093193fc6e20547e707da7013f4f1406a87b088ab6898654c` |
| Candidate v3 JSON SHA-256 | `ac42f719583ba58b1c122a9318368d34699cf60103787034525be4fbe937ad07` |
| Candidate identity | Schema `f2-icacls-runtime-release-v3`; `ReviewedCommitSha=03882eedf3104fc33aa0cf503ddef9c9a6bec702`; `PackageRoot=C:\Program Files\F2-G1-Icacls\releases\03882eedf3104fc33aa0cf503ddef9c9a6bec702` |
| Seven-file source-pin manifest SHA-256 | `7e05d48ef25e7cff19d84db151395921b5d89b52b1e2f45b94a84a4778a615ce` |

All seven candidate package names and exact Windows checkout SHA-256 values were independently recomputed at the fixed SourceRoot and matched the candidate and source-pin manifest:

| File | SHA-256 |
|---|---|
| `F2AclCapture.Protocol.psm1` | `42ba4dd5e31d1db64198bb1cee16d519f087a40364dfb4d2696b4a5bd844d728` |
| `F2AclIcacls.Corroboration.psm1` | `a52ed86218a0ba0c0801ee6e84a4a5e47c73eda43db78f818b0b12670ad5110b` |
| `F2AclIcacls.Runtime.psm1` | `d1f4697e6fcb04d8707442e7c0579dc1bd0934c0565d48c5527080af462663e4` |
| `Invoke-F2IcaclsCapture.ps1` | `0b9214c3d6f6e96081b9d86aa8d62087c82527443f2c4b3e7ee09a1ca3dae818` |
| `Invoke-F2IcaclsProtectedCoordinator.ps1` | `9b8816c941eebaa87aafd597e6bc326d380c7fbb34321ef97ab0c04a4c1ac515` |
| `F2_ICACLS_SOURCE_PINS.json` | `7e05d48ef25e7cff19d84db151395921b5d89b52b1e2f45b94a84a4778a615ce` |
| `Invoke-F2AclReadOnlyCapture.ps1` | `bea7cc93710c83d48a8ef9e54af306401694f17f611e696caa856938ca71a19b` |

## Exact proposed CMD command — verified, not executed

This is copied byte-for-byte as a line from the reviewed PR #62 handoff. The source-only preflight confirmed its launcher path and all four pins and confirmed the launcher's hard-coded candidate root matches the updated review-root worktree.

```cmd
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "& { $path='C:\Dev\f2-g1-protected-updater-source\scripts\f2-acl\Start-F2ProtectedReleaseUpdate.ps1'; $expected='054e69a4b908c1fe1927e5997bf1c7aca003e8ae21fbaa278323fdf6b5179e68'; $bytes=[IO.File]::ReadAllBytes($path); $sha=[Security.Cryptography.SHA256]::Create(); try { $actual=([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','').ToLowerInvariant() } finally { $sha.Dispose() }; if($actual -cne $expected){throw 'UPDATE_BOOTSTRAP_HASH_MISMATCH'}; $text=[Text.UTF8Encoding]::new($false,$true).GetString($bytes); . ([scriptblock]::Create($text)); $rc=Invoke-F2ProtectedReleaseUpdateLauncher -ExpectedSourceCommit 03882eedf3104fc33aa0cf503ddef9c9a6bec702 -ExpectedLauncherSha256 054e69a4b908c1fe1927e5997bf1c7aca003e8ae21fbaa278323fdf6b5179e68 -ExpectedUpdaterSha256 c4dfc71606888555f7b93930671045490ba8e49d20d65f858eab6c084bf620eb -ExpectedCandidateManifestSha256 ac42f719583ba58b1c122a9318368d34699cf60103787034525be4fbe937ad07; exit [int]$rc }"
```

The command was not run. No launcher/updater function was invoked and no UAC prompt was opened.

## Tests and results

Commands are documented in the attached evidence logs and use the Windows PowerShell 5.1 executable at `%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe`.

The independently retrievable file list, purposes, checkout SHA-256 values, Git-blob SHA-256 values and EOL attributes are in `evidence/REVIEW_PACKAGE_MANIFEST.json`. That manifest excludes its own digest to avoid recursive hashing; the final committed manifest digest is reported with the immutable PR head.

| Validation | Result |
|---|---|
| Seven source-only suites | **521 assertions, 0 failures; 7 child suite exits 0; runner exit 0** |
| Suite assertions | `152 + 118 + 41 + 18 + 134 + 20 + 38 = 521` |
| Exact fixed-path SourceChain validation | PASS; exit 0 |
| Exact command/path/hash preflight | PASS; exit 0 |
| PowerShell parser | 21 files; 0 errors; exit 0 |
| `git diff --check` | PASS; exit 0 |
| Windows GitHub Actions | Linked to this review PR's immutable head commit after publication |

## Changed paths

- `docs/reviews/f2-g1-elevated-child-diagnostics/F2_G1_ELEVATED_CHILD_DIAGNOSTICS_REVIEW.md`
- `docs/reviews/f2-g1-elevated-child-diagnostics/evidence/ARTIFACT_MANIFEST.json`
- `docs/reviews/f2-g1-elevated-child-diagnostics/evidence/ITERATION_AUDIT.md`
- `docs/reviews/f2-g1-elevated-child-diagnostics/evidence/WINDOWS_PS51_REGRESSION.log`
- `docs/reviews/f2-g1-final-execution-preflight/F2_G1_FINAL_EXECUTION_PREFLIGHT_REVIEW.md`
- `docs/reviews/f2-g1-final-execution-preflight/evidence/FIXED_PATH_PREFLIGHT.log`
- `docs/reviews/f2-g1-final-execution-preflight/evidence/PARSER_AND_DIFF.log`
- `docs/reviews/f2-g1-final-execution-preflight/evidence/REVIEW_PACKAGE_MANIFEST.json`
- `scripts/f2-acl/Test-F2G1FixedSourceRootPreflight.ps1`
- `scripts/f2-acl/Test-F2ProtectedReleaseDiagnosticsSourceChain.ps1`

The source-chain test helper's detached-checkout allowance is strict: it rejects any non-empty branch name other than the expected branch, and for the detached case it still requires the expected remote branch ref to point at the exact pinned commit, in addition to exact commit, parent, origin, clean worktree, candidate hash/identity, seven package hashes, source pins and equality of the three production source copies.

## Non-negotiable limits and remaining unknowns

- No Administrator UAC or protected updater execution occurred. The prior one-time authorization was already consumed; this handoff grants no new authorization.
- No Program Files/ProgramData state, parent ACL, installed release, release lock, transaction, VM, Hyper-V, `G:`, live `icacls`, or retained baseline contents were queried here. No ACL or protected file was modified.
- The former elevated child exit 1 still has no confirmed internal failure stage. This preflight resolves source/candidate path mismatch only; it does not establish whether an actual protected update would succeed.
- Cross-integrity named-pipe behavior and elevated C: filesystem/ACL behavior remain untested.
- The next step is independent review of this exact immutable evidence head. Any actual v2-to-v3 update requires a NEW explicit owner authorization and all separately required protected-host gates.

## Required handoff fields

- Architectural impact: no production module or seven-file runtime package changed; only review/test evidence and a read-only source-chain test helper changed.
- Dependencies added / licenses: none.
- Tests not executed: no UAC, protected update, live ACL/`icacls`, C: protected-state inspection, VM/Hyper-V/G: operation, native F2 workload, or baseline read/revalidation.
- Failure/recovery cases: this task performs no recovery or mutation; the exact path preflight is fail-closed on missing roots, non-clean Git status, mismatched refs/pins, invalid candidate, or reparse path.
- Visual reproduction steps: not applicable.
- Rollback: discard this review-only branch if not accepted; keep the independently prepared SourceRoot and review-root detached checkouts only if desired, or restore their prior clean detached/branch checkout states with a separate reviewed action. The original local branch refs remain unchanged.
- Reviewer focus: verify corrected suite sum; byte/EOL provenance; the two prepared fixed paths; candidate/source hash chain; and that the command was not executed.
