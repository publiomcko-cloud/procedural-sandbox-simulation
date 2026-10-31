# P3.1 R12-CXR R1 control corrections — pre-target checkpoint

**Date/time:** 2026-10-31, America/Sao_Paulo
**Event type:** bounded source correction and test evidence
**Publication state:** recorded in isolated feature branch; no PR created yet
**Status:** `R1_SOURCE_CORRECTED / TARGET_NOT_STARTED`

## Verified repository identity

- Repository origin: `https://github.com/publiomcko-cloud/procedural-sandbox-simulation.git`.
- Last verified remote `main`: `5997a76d345f45bf86edfe83f690336391e8be27`.
- Isolated branch: `exp/p3-1-r12-cxr-r1-architecture-convergence`.
- Source correction commit: `e42f309c263a441f026b2c8dec91524dcc6bb45a`.
- Direct parent: `bed9f1d176148e8ec256ad37777c9ba9899dc487`, the verified open/draft/unmerged head of PR #212.
- Existing PR #212 was verified unchanged at that head. PRs #207–#211 were verified open, draft and unmerged at their recorded heads. No PR was modified or merged.
- Other development worktrees, the main development workspace, user saves, `stash@{0}`, `stash@{1}`, and pre-existing untracked UID files were preserved.

## Source correction

Only these three code/test paths changed in the source commit:

- `game/tests/prototypes/p3_1_r12_cxr_campaign.gd` — preserve partial classification when later gates fail; require explicit boolean exhaustive-search evidence before R2 eligibility; distinguish the preregistered result class from campaign disposition; keep missing/unrun metrics explicit; classify realizer time-limit outcomes as partial.
- `game/tests/prototypes/p3_1_r12_cxr_contract_tests.gd` — add bounded regressions for partial candidate evidence, invalid-boundary accounting, malformed/exhaustive search status, terminal class mapping, and the 30-second deadline.
- `game/tests/prototypes/p3_1_r12_cxr_field_support_realizer.gd` — continue L0–L3 after invalid boundaries, continue across cavities except for actual global limits or source/evidence failures, preserve captured evidence on malformed candidate output, avoid recording unrun counters as zero, and enforce the complete-realizer deadline on early and successful return paths.

All original geometric inputs, frozen roots, Candidate D samples, support generation method, topology authority, strict cutoff, controls, ROI oracle, volume and numeric stop-loss limits remain unchanged. The full control clarification is in [the R1 correction addendum](../specs/P3-1-R12-CXR-R1-CONTROL-CORRECTIONS.md).

Physical SHA-256 of source files at this checkpoint:

| Path | SHA-256 |
|---|---|
| `game/tests/prototypes/p3_1_r12_cxr_campaign.gd` | `45DDA6FB322A3286CABDA203F5444CD0DF4C6AC436C0DB2CD4F6861F02ECBA6A` |
| `game/tests/prototypes/p3_1_r12_cxr_contract_tests.gd` | `C2EE715195F107F9791B5DF13C67D677F494FA47F01CB79D9D3A9C7B83F7646D` |
| `game/tests/prototypes/p3_1_r12_cxr_field_support_realizer.gd` | `83E352019ABE5A20ED35A0522FEA24F7B1D96B090AB1E614BF80AE0EDB327AD7` |

## Verification evidence

- Engine: Godot `4.7.2.stable.official.ed1daf0bf`.
- Contract command: `Godot_v4.7.2-stable_win64_console.exe --headless --path <isolated-game-path> --script res://tests/prototypes/p3_1_r12_cxr_contract_tests.gd`.
- Latest result: exit code 0; `R12CXR_CONTRACT_TESTS_PASS`; 91 assertions, zero failures; stderr empty. Stdout SHA-256 `452F5E906ECAA0E03D1D427207FCCCEB0C647523B965C85E188FB03EAD6690C8`; empty stderr SHA-256 `E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855`.
- Earlier parser failures caused by the newly added test calling a non-static helper directly and then assigning the script instance to `RefCounted` were preserved in the unique source-check evidence directory and corrected. The latest 91/0 run follows those corrections.
- This is local Godot contract-test evidence (L2), not independent review, target geometry evidence, GUI acceptance, or production qualification.

## Target status and next gate

No CXR local-patch search marker, R1 target invocation, or geometry attempt was run on this correction commit. The previous R12-C/CX/CXR attempt artifacts remain preserved; no started target is being repeated.

The next authorized operation is a fresh detached exact-source preflight: verify the source and frozen fixture pins, isolated Godot profile, editor import, campaign check-only, realizer/contract checks, and free-commit guard. If those pass, execute the frozen R1 target once with a unique attempt ID and new evidence root. Stop at the first actual target result unless it is a complete/exhaustive no-solution eligible for R2 or an equal-LOD candidate that advances to the frozen downstream gates. A limit or evidence gap is `PARTIAL`, never infeasibility.

No production adoption, merge, release, GUI acceptance, save/schema operation, Issue #108/#154 work, or F2-G1 operation is authorized. Preserve `CURRENT_PROTECTED_STATE_UNKNOWN`, `V3_NOT_ATTESTED`, `ACL_REVIEW_REQUIRED`, `G1_BLOCKED_ENVIRONMENT`, and `F2_G1_RELEASE_HOLD`.
