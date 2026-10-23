# P0.3 Declarative Mod-First Foundation

## Identity

- Baseline: `66263baeef2f628c91a6a271dad04e7cd86659e4` (verified `origin/main`).
- Feature branch: `feat/p0-3-declarative-mod-foundation`.
- Implementation commit: `ab46214aaa5eb320ab22563d17340a8da857b4bf`.
- Scope: declarative packages and shared content registry; no playable terrain, SDF, ledger, streaming, or save schema changes.
- PR: draft, created after the implementation commit; not merged.

## Implemented

- Added a schema-1 data-only package loader with exact engine compatibility (`4.7.2`), strict dotted mod IDs and semantic versions, exact dependencies, deterministic topological ordering, path traversal and reparse rejection, and bounded package/definition counts and bytes.
- Added a node-independent transactional content registry. First-party and external definitions share validation, registration, namespaced lookup, and deterministic recipe evaluation.
- Added `stacked_spheres_v1`, a seeded integer-millimeter procedural-rock recipe, plus content pin creation/validation helpers for future save integration. Existing terrain save schema 1 remains unchanged.
- Converted `mods/examples/procedural-rock` from an illustrative manifest into a loadable external data package. Added the bundled first-party package at `game/mods/first-party/core-rocks`.
- Added 42 focused assertions and added the suite to `scripts/validate.ps1`.

## Validation evidence

Godot: `4.7.2.stable.official.ed1daf0bf`, executable `C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe`, SHA-256 `c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643`.

- Editor import: PASS.
- P0.3 declarative tests: `42 assertions, 0 failures`.
- Existing persistence suite: `321 assertions, 0 failures`.
- `git diff --check`: PASS.
- The canonical `scripts/validate.ps1` suite was run twice during development; the post-stabilization run exited 1 with the same four terrain test groups failing (27 assertions total):
  - `terrain_brush_tests.gd`: 611 assertions, 5 viewport/edit failures.
  - `terrain_multiregion_tests.gd`: 7,637 assertions, 4 streaming/edit failures.
  - `terrain_history_tests.gd`: 842 assertions, 17 sequential edit/supersession failures.
  - `terrain_end_to_end_perf.gd`: 234 assertions, 1 visible-edit failure.
- Other suites in the final validation run passed: smoke (52), SDF (44), chunks (179), terrain perf (11), persistence (321), P0.3 mods (42), picker history (713), LOD transition (6,473), playable LOD runtime (53), concurrency (11), bootstrap structure (18), and main-scene startup.

Those four failing suites concern terrain behavior and their files were not changed by P0.3. No comparison run was made against the baseline in this task, so this checkpoint does not classify them as baseline failures. Headless benchmark output is diagnostic only; it is not performance acceptance or visual evidence.

## Demonstration

From the repository root, run:

```powershell
godot --headless --path .\game --script res://tests/declarative_mod_tests.gd
```

The test discovers the external example and first-party package in reverse root orders, validates dependencies, registers both through the same registry, looks up their namespaced definitions, evaluates an explicit seed twice for deterministic output, rejects malformed packages and verifies a failed package attempt leaves disposable schema-1 save bytes unchanged.

## Limits and disposition

- This is a source-tree foundation; exported package installation/bundling has not been validated.
- No script execution, signing, download/install flow, entity instantiation, gameplay scene integration, hot reload, migration, or mod-state persistence is implemented.
- Content pins are registry helpers only; terrain saves do not yet contain mod references.
- Exact engine version and schema version are required.
- PR remains draft and unmerged. Independent source review and owner runtime/visual acceptance remain pending.
- Preserve `CURRENT_PROTECTED_STATE_UNKNOWN`, `V3_NOT_ATTESTED`, `ACL_REVIEW_REQUIRED`, `G1_BLOCKED_ENVIRONMENT`, and `F2_G1_RELEASE_HOLD`.
