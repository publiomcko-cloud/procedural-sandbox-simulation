# 2026-10-24 — P2.0A geological procedural rock generator

## Provenance and disposition

Repository: `publiomcko-cloud/procedural-sandbox-simulation`. Work was performed in the existing `C:\Dev\sandbox-sim-dev` workspace on `feat/p2-0a-mod-first-procedural-objects`, starting from requested PR #106 HEAD `1f9fadd1e51cb956c31ac0c5fc8fb3d1cc9bcf8d` (parent chain based on main `0ea2ad834db5dc2de1110cf0388ea06604cc7715`). The implementation commit is `098fca0d6082cc3bd55ad2e8d58231d85a6ec6e1`, parent `1f9fadd1e51cb956c31ac0c5fc8fb3d1cc9bcf8d`. Subsequent documentation reconciliation is on the same feature branch and PR #106. At final verification PR #106 remains open, draft, and unmerged. PR #107 remains a separate open documentation-only draft at `d1dd5cdeb9c19e4049ddae9f2d5346628edcc525`; its branch was not modified.

The pre-existing `stash@{0}` and three unrelated untracked benchmark `.gd.uid` files were preserved. A new UID file for `procedural_rock_gallery_capture.gd` is committed with that new test. No F2-G1 action was performed; all five holds remain unchanged.

## Change summary

- Replaced the fixed radial/lobe mesh with `geological_halfspace_v1`: asymmetric convex primary solids created by deterministic oriented half-space intersections, separate fracture and wear planes, selective coherent corner/edge relaxation, and bounded local-coordinate multiscale noise. Each mesh is triangulated as a closed shell and validated for finite values, winding, positive volume, nondegeneracy, connectedness and two-face edge incidence.
- Added strict definition schema 2 recipes and two explicit profiles: weathered massive granite and anisotropic fractured basalt. Definition schema 1 plus `stacked_spheres_v1` retains its old registry evaluation only; the current runtime mesh path rejects it explicitly. No automatic recipe reinterpretation or migration was added. The required installed definitions must use the supported schema/profile/algorithm.
- Derived independent structure, fracture, wear and detail seeds from the existing recipe seed. World seed, object/definition IDs, region placement, streaming, save schema, SDF and terrain controls were not intentionally changed.
- Added geometry/topology/seed/schema/runtime regression tests and the isolated 12-granite/12-basalt gallery capture. Gallery images use a deterministic CPU triangle rasterizer because the headless dummy renderer provides no root viewport texture. They are not Godot renderer screenshots, shadow/GPU measurements or owner art approval.

## Verification evidence

Engine: `4.7.2.stable.official.ed1daf0bf`, executable `C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe`, SHA-256 `C8F0A6BC45A19B33541501E57F6F7CD972AB18453743266339D495CBBE846643`.

- Focused procedural object/runtime suite: **208 assertions, 0 failures**.
- Isolated gallery generation and integrity suite: **57 assertions, 0 failures**.
- Full `scripts/validate.ps1`: **17,468 assertions, 0 failures across 16 assertion groups; exit 0**, including editor import, legacy terrain and persistence regressions, updated declarative mod tests, object runtime/streaming tests and main-scene startup. This headless suite does not exercise owner GUI approval.
- The first full run correctly exposed two obsolete `declarative_mod_tests.gd` expectations for `lobes` in the migrated schema-2 example. Those assertions were replaced with checks for explicit schema/algorithm/profile/parameters and four independent stage seeds. The updated focused declarative suite passed **44/44**, and the full suite was rerun successfully. The first run and its evidence were preserved at `C:\Users\PUBLI\AppData\Local\Temp\p2-0a-validation-796bb835f27f49368dc08721b2039983.log`.
- Final successful full-suite log: `C:\Users\PUBLI\AppData\Local\Temp\p2-0a-validation-rerun-d809be7e4b864265aa7acfceeedfcde8.log`, SHA-256 `EC17831DB727C043BD0F9EE30D9C2D37107E738989AC85F0E5DF3CDBBE68416E`.

Gallery summary from fixed seed base `700100`: 12 samples/profile, three fixed oblique views and light configuration; **312–408 triangles/object**, median **360 granite / 384 basalt**. Adapter build time on this developer host was median/p95 **13.955/19.650 ms granite** and **14.711/17.052 ms basalt**. These are exploratory CPU construction figures only: they exclude scene publication, GPU/renderer, shadows and gameplay frame cost; no budget or performance acceptance has been established. Metrics are in `../artifacts/p2-0a-geological-rock-gallery/gallery_metrics.json`.

Artifact SHA-256:

| File | SHA-256 |
| --- | --- |
| `gallery_metrics.json` | `4F396580C23E45748A357327AABC24D95BA4DB03A435A2873D11343C9F762F2E` |
| `rock_gallery_oblique.png` | `20D65AB2A0D6841524361A8EF34FFFA40781E0CCC1ABBC844B8497DA2C8817C5` |
| `rock_gallery_rear_oblique.png` | `74EA4CB553DA488DE082680B57F9C214D4429B0BACCBC3AEEEA164FCA190062D` |
| `rock_gallery_side_oblique.png` | `1BEE098F502852F7D43DEA6375EED26E5F242FDD3664DA47EB0099AAF8E4CB5F` |

## Limits and next gates

The CPU preview shows the intended family distinction in these sample seeds; it cannot establish material appearance or lighting in the actual Godot scene. Owner GUI retest must inspect both families in the playable world at close, medium and region-traversal views, including grounding, silhouette, granite wear, basalt anisotropy, faceting and absence of sphere-like lobes. Independent exact-SHA source review remains required before that retest. PR #106 stays draft/unmerged until its separate gates and owner decision. No claim is made that the stylized profiles reproduce geological processes or that mesh performance meets an approved budget.

F2-G1 markers preserved: `CURRENT_PROTECTED_STATE_UNKNOWN`, `V3_NOT_ATTESTED`, `ACL_REVIEW_REQUIRED`, `G1_BLOCKED_ENVIRONMENT`, `F2_G1_RELEASE_HOLD`.
