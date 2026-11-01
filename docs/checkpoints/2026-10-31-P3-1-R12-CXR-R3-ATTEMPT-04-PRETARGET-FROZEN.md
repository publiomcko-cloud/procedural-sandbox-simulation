# P3.1 R12-CXR R3 attempt 04 pretarget freeze

Date: 2026-10-31 (America/Sao_Paulo); process records use UTC.

## Identity and disposition

- Repository origin: `https://github.com/publiomcko-cloud/procedural-sandbox-simulation.git`
- Last verified `main`: `5997a76d345f45bf86edfe83f690336391e8be27`
- Source branch: `exp/p3-1-r12-cxr-per-cavity-continuation`
- Exact source under test: `2964bd55b5691081bfe4db9c421f3b982fee167b`; direct parent `27c88a78aff8aef0af8a69c041f90ddcf2ac502e`
- Execution checkout: `C:\r12cxr-attempt04-2964bd5`, detached at the source SHA; campaign, realizer and contract test bytes match the frozen source.
- PR #214 remains OPEN, DRAFT, UNMERGED at the exact source SHA. PR #213 (`121f499c...`) and PR #212 (`bed9f1d...`) remain OPEN/DRAFT/UNMERGED.
- `stash@{0}` and `stash@{1}` remain present. Existing generated/untracked `.gd.uid` files were not staged or removed.

## Bounded correction being evaluated

This commit records only the pretarget state; it does not change the R3 implementation. Source commit `2964bd55` changed the R3 contract test and field-support realizer. It adds deterministic connected patch-subset selection inside the already frozen L0-L3 neighborhoods, keeps the frozen residual seed IDs, derives boundary edges from surviving C6 incidence, and treats two surviving owners as a closed internal interface. Search nodes continue to consume the existing per-cavity and total caps. The frozen limits remain 32,768 nodes per cavity, 65,536 total, 10 seconds per cavity, 20 seconds total, and maximum patch size 64. No topology, degeneracy, geometric, interface, resource, or acceptance threshold was relaxed. This is experimental code only; production sources remain untouched.

## Pre-target gates on exact source

Godot executable: `C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe`; version `4.7.2.stable.official.ed1daf0bf`; SHA-256 `c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643`. User data was isolated at `C:\Users\PUBLI\AppData\Local\Temp\r12cxr_r3_preflight04_profile_2964bd55`.

1. Editor import completed, exit 0, with no parser/script errors.
2. `p3_1_r12_cxr_contract_tests.gd` completed, exit 0: 149 assertions, 0 failures, marker `R12CXR_CONTRACT_TESTS_PASS`.
3. Campaign `--check-only` completed, exit 0, marker `R12CXR_CAMPAIGN_CHECK_ONLY_PASS`; attempt ID `R3_CHECK_20261031_08`; selected scenario `R9.2.SEAM.XPLUS_EQUAL.v1`. Frozen source/input hashes were verified by that check.
4. No geometry target scenario has run. No full `scripts/validate.ps1` has run. Those gates remain conditional on the equal-LOD geometry result.

The complete stdout/stderr, commands, exit codes, source/input hashes and summary are under [pretarget evidence](../reports/P3-1-R12-CXR-R2-R3/evidence/r3_pretarget_04/). `pretarget-summary-v2.json` is the corrected summary. A first summary-writer helper-name collision is preserved as `pretarget-summary.json` (four-byte JSON null) and documented in `pretarget-summary-serialization-note.txt`; it occurred after all three gates, did not launch a scenario and did not alter their results. It is not silently replaced. The evidence SHA-256 inventory is `evidence-sha256-index.txt`.

## Target reservation and gate

The only next authorized target in this continuation is the frozen equal-LOD interface scenario `R9.2.SEAM.XPLUS_EQUAL.v1`, using attempt ID `R3_TARGET_20261031_04` and the committed dispatcher `r3_target_dispatcher.ps1` (SHA-256 `697f6593bf1fdce4640123248518857d480689803ec188123768feea9b5d86b9`). The dispatcher passed a controlled non-Godot child-process test: exact stdout/stderr and exit code 23 were captured, duplicate reservation and output overwrite were denied, and process termination was confirmed. This control did not start the target.

At this checkpoint, `R3_TARGET_20261031_04` is **NOT_STARTED**. Attempt 03 remains preserved and will not be repeated. The dispatcher must durably reserve the new attempt and record launch intent before process creation. Once a Godot target process may have started, do not rerun this attempt. Continue downstream geometry gates only if the exact frozen target reports the required pass; do not run downstream gates after a failed/partial target.

## Holds and scope

This remains a test-only research continuation. No production adoption, persistence/schema changes, Issue #108, PR merge, or release is authorized. Preserve `CURRENT_PROTECTED_STATE_UNKNOWN`, `V3_NOT_ATTESTED`, `ACL_REVIEW_REQUIRED`, `G1_BLOCKED_ENVIRONMENT`, and `F2_G1_RELEASE_HOLD`.