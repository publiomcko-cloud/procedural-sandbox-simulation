# Issue #118 — Optional-root API hardening (R1)

Date: 2026-10-25
Repository: `publiomcko-cloud/procedural-sandbox-simulation`
Main/base: `fd431dbcad18685a3aa2c86c3c9b25fbd81303c9`
Reviewed starting HEAD: `6280fac4b7554ba24b880790c3991c01aaa43851`
R1 source commit: `f0164b140009bb797951aa4085bb36001889bc57`
R1 source parent: `6280fac4b7554ba24b880790c3991c01aaa43851`
Branch / PR: `fix/issue-118-mod-discovery-initialization` / [#119](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/119)
Independent finding: [review #5644049681](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/119#pullrequestreview-5644049681)

## Finding and pre-fix reproduction

The independent review found that `discover_and_validate(roots, optional_roots)` checked whether an optional root was authorized and included in `roots`, but did not restrict optional treatment to `user://mods`. A caller could therefore downgrade an authorized required root's `missing_manifest` failure.

This was reproduced before changing source by loading a temporary copy of the reviewed pre-fix loader (`6280fac4...`) in an isolated Godot user-data profile. A disposable authorized root `user://mods/issue118_required_root` contained an immediate child `required-child` with no manifest. Passing that same descendant as both `roots` and `optional_roots` returned `ok=true`, `reason=ok`, exit 0. The empty resulting package set made the downgrade observable.

Pre-fix log: `C:\Users\PUBLI\AppData\Local\Temp\issue118-r1-prefix-648bc5f42f6848e4abf66eb93723a559\repro.log`
SHA-256: `04CBBAC8A26500DE1E1AB43DD54619C1D86CF7331D649FE4C292BDC3288D0EF4`.

No user profile outside the unique isolated test profile or real save was accessed. The tracked project source was not modified for the pre-fix reproduction; the temporary loader/reproduction script were removed after capture.

## Correction

`declarative_mod_loader.gd` now validates optional-root eligibility inside the loader, before enumerating packages. The only eligible root is the exact canonical `user://mods` root after slash/case/path normalization. The eligible root must also appear in the authorized `roots` argument. Required first-party/example roots, arbitrary authorized roots, descendants, and neighboring string prefixes are rejected as `invalid_optional_package_root`. `optional_user_roots()` uses the same eligibility helper. Existing path authorization/reparse checks remain in that path.

Changed source paths:

- `game/scripts/modding/declarative_mod_loader.gd`
- `game/tests/declarative_mod_tests.gd`

New regressions prove the canonical user root remains eligible; callers cannot mark first-party, example, or an authorized `user://mods` descendant optional; prefix and descendant inference are rejected; and missing manifests remain fatal in non-optional roots. Existing tests retain ignored optional folders, malformed declared packages, deterministic discovery order, dependencies, publication, and fallback coverage.

## Validation

Engine: Godot `4.7.2.stable.official.ed1daf0bf`, executable SHA-256 `C8F0A6BC45A19B33541501E57F6F7CD972AB18453743266339D495CBBE846643`.

- Pre-fix downgrade reproduction: returned success as described above.
- Focused `declarative_mod_tests.gd`, ordinary isolated profile: 66 assertions / 0 failures. Log `C:\Users\PUBLI\AppData\Local\Temp\issue118-r1-focused-f4c4102dbae04facb8b2618e29654fc0\mods.log`, SHA-256 `E4A0542D747A1412C0DF4E7776B03BA0D3F53721DEADA5F4C1A18698D5C49E38`.
- Focused procedural-object regressions: 633 assertions / 0 failures. Log `...\objects.log`, SHA-256 `54C4606E8874AB7EC296E02EFC78186A31B2F99472845BB82246837FEF86A999`.
- Focused declarative suite with a prepared junction under the isolated user profile: 67 assertions / 0 failures; the test observed/rejected and removed the junction. Log `...\mods-junction.log`, SHA-256 `FBBA733DFF5753EB44736457F9B6CD587C8DD2E80B7E56ACBB7D818198BAA93C`.
- Complete `scripts/validate.ps1`: exit 0, 19 marker suites, 18,047 assertions / 0 failures. The full run's junction environment variable was unavailable, so its reparse branch used the existing fallback; the actual junction was verified separately by the focused 67-assertion run. Full log `C:\Users\PUBLI\AppData\Local\Temp\issue118-r1-full-75ab7e125d06401f95fca051834c8d6c\validate.log`, SHA-256 `E54324B18F671B965546BA71B97E14271D886FE2591BFB98862549499DB8ACD2`.
- Three non-failing colinear camera target/up warnings remained in full validation; no parser/script errors or failed assertions. `git diff --check` passed.
- Hosted Starter checks passed on final PR HEAD `6280fac4...` before this R1 change; checks for R1 must be read from GitHub after pushing the new commit. Hosted workflow is static and does not replace Godot validation.

All Godot runs used unique `APPDATA`/`LOCALAPPDATA` roots. The main `C:\Dev\sandbox-sim-dev` worktree, its changes, `stash@{0}`, and pre-existing untracked `.gd.uid` files were preserved; PRs #115/#117 were not modified. No merge or owner GUI retest occurred.

## Remaining gates

Independent exact-SHA review and owner GUI retest remain pending. On `res://scenes/terrain_demo.tscn`, verify first-party granite and external basalt, nonzero population rules and visible objects, no package-discovery error, schema readiness, B placement, F6–F9, V visibility, regional revisit and restart persistence. Any schema migration must use a disposable profile/world. No protected host operation or F2-G1 state changed; all five holds remain.
