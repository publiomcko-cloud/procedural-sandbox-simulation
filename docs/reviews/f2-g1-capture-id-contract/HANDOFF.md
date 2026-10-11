# Developer handoff — F2 G1 consolidated install readiness

Status: **READY_FOR_CONSOLIDATED_INSTALL_REVIEW**. This handoff covers a source-only correction plus non-elevated read-only checks. It is not protected installation acceptance.

## Ticket and repository

- Ticket: Issue #48, owner finding `6112479445`.
- Repository/remote: `publiomcko-cloud/procedural-sandbox-simulation`, `https://github.com/publiomcko-cloud/procedural-sandbox-simulation.git`.
- Worktree/branch: `C:\Dev\f2-g1-capture-id-contract`, `fix/f2-baseline-capture-identity-issue48`.
- Base: reviewed PR #53 HEAD `9c2e6db22c433d736eff9358e62f20eb8f6b2071`, parent `69947e917f4715298a7985d72448ec8edf3eafcb`.
- Candidate: the final PR #53 tip is identified by the containing immutable GitHub commit; the exact SHA and parent are reported in the PR handoff comment. PR #53 remains draft and unmerged.
- Production source: clean SourceRoot `C:\Dev\f2-g1-capture-id-contract-source`, commit `5741ffe90a3abd02a08563e6431e8a0a9b63eeb1`, parent `4c53f6dd03c6ddc564a45f8c203286595385c46b`.

## Implementation summary

Completed a single consolidated readiness pass for the previously deterministic `INSTALL_PARENT_DACL_UNSAFE` on `C:\`. The production installer now allows exactly the observed Authenticated Users directory `FILE_ADD_SUBDIRECTORY` mask `0x00000004`, with no inheritance flags, only while validating the canonical `C:\` root. It separately requires the exact observed inherit-only root ACE, protected DACL, and an approved system owner. The root exception is not applied at Program Files or ProgramData. ProgramData's observed `0x116` creation/attribute ACE remains exact and duplicate/flag constrained. Protected child installation/staging DACL checks remain unchanged.

The SHA-bound bootstrap now pins the corrected installer while retaining its one-read, hash-then-execute-the-identical-in-memory-bytes property. Windows PowerShell 5.1 regressions exercise the real production root path walker, observed and adversarial root ACL fixtures, non-root parent rejection, collisions, partial publication and installed ACL attestation failures. Hosted Windows CI identified three fixture issues: no `G:` PowerShell drive, strict target-path validation requiring canonical fixture destinations, and a reparse callback comparing a normalized current path against an unnormalized root. The tests now use pure path strings, canonical destination paths, and a captured canonical reparse target. Production retains the fixed G: scope and strict canonical-path and reparse gates.

## Changed paths

- `.github/workflows/f2-acl-source-only.yml`
- `docs/reviews/f2-g1-capture-id-contract/CONSOLIDATED_INSTALL_READINESS.md`
- `docs/reviews/f2-g1-capture-id-contract/F2_G1_INSTALL_REVIEW_UPDATE.md`
- `docs/reviews/f2-g1-capture-id-contract/HANDOFF.md`
- `docs/reviews/f2-g1-capture-id-contract/Install-F2IcaclsProtectedPackage.ps1`
- `docs/reviews/f2-g1-capture-id-contract/Invoke-F2VerifiedInstaller.ps1`
- `docs/reviews/f2-g1-capture-id-contract/REVIEW_MANIFEST.md`
- `docs/reviews/f2-g1-capture-id-contract/TEST_EVIDENCE.md`
- `docs/reviews/f2-g1-capture-id-contract/Test-Install-F2IcaclsProtectedPackage.ps1`
- Five fresh Windows PowerShell 5.1 suite/parser logs under `docs/reviews/f2-g1-capture-id-contract/`.

The production SourceRoot and its seven-file package are unchanged at the pinned source commit. PR #50 remains unchanged at `2c967661163fc157b638fa4f76da86c48aa57ff2`.

## Validation

Windows PowerShell 5.1.22621.6133: protocol 152 assertions/0 failures/exit 0; corroboration 118/0/exit 0; runtime 35/0/exit 0; installer/bootstrap 47/0/exit 0. Total: 352 assertions, zero failures. Parser sweep: 12 PowerShell files, zero parse errors, exit 0. Actual read-only SourceRoot, baseline, package pins and both installation-parent-chain checks passed. `git diff --check` passed locally. Three hosted CI attempts exposed and informed test-fixture corrections; final-SHA Windows GitHub CI must pass before this handoff is review-ready.

## Tests not run and limitations

- No UAC prompt, protected installation, live `icacls`, live token-specific effective-access evaluation, ACL mutation, VM/Hyper-V query or operation, G: access/write, guest start, baseline rewrite, native workload, or PR merge.
- Synthetic tests do not establish Administrator identity/consent or installed-state ACLs.
- The sanitized live parent inspection identified an unresolved capability-style principal with read-only mask `0x001000A1`; identity resolution and token-specific `AccessCheck` were not performed. Immediate destination parents are protected and the installer rechecks the same conditions before/after publication.
- Existing local preparation copies were not updated to unreviewed bytes. They retain known previous hashes. After exact-SHA independent review, fresh owner authorization is required before staging the accepted bootstrap/installer and attempting one UAC installation.
- ProgramData create rights permit pre-creation/denial of service; all collisions fail closed without overwrite.

## Future installation procedure

The complete documented command, preparation path/hash guards, exact source/baseline pins, UAC limit, post-install assertions, and stop conditions are in `F2_G1_INSTALL_REVIEW_UPDATE.md`. Do not run it until independent review and fresh explicit owner authorization. There is no visual test for this host installation task.

## Reviewer focus

- Confirm the `C:\` exception cannot apply to a non-root ancestor or broaden beyond the exact observed ACE profile.
- Confirm protected staging/final child DACLs and SHA-bound verified-byte bootstrap remain fail-closed.
- Confirm the distinction between source/synthetic validation and unperformed elevated installation remains explicit.
