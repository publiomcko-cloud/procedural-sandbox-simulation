# Documentary checkpoint — P1.0B lighting follow-up

**Checkpoint ID:** `CHK-2026-10-17-P1-0B-LIGHTING-FOLLOWUP`

**Event:** Issue #89 lighting correction prepared on `fix/p1-0b-terrain-depth-lighting`, based on `13d08b828553df4a3b2bb9d3eb783b4cc3f45beb`. The lighting-only changes and same-view image evidence are ready for independent source review; owner GUI retest is still required.

**Publication state:** implementation commit `2b29498` is complete on the prepared feature branch; the final review head adds this checkpoint identity update. One draft PR is pending. No merge or release is authorized. The pre-existing local CRLF-only `game/project.godot` worktree state is retained and excluded from both commits.

## Evidence

- Godot 4.7.2 Compatibility captures compare the same seed (`424242`), viewport (`1152×648`), and exterior/cave camera poses. Before/after PNGs and raw JSON are kept in `docs/evidence/p1-0b-lighting/{before,after}`.
- The prior flat close exterior measures 88.0 mean luma / 0 standard deviation; after the correction it measures 133.84 / 7.70. Cave view changes from 91.15 / 10.22 to 82.82 / 14.09, so the cave is darker on average with stronger visible variation. Pixel statistics are useful comparisons, not owner visual acceptance.
- Final scene settings: colored ambient 1.2; directional energy 1.3 at rotation `(48,-28,0)`; camera-aligned fill energy 16, range 72, angle 58°, attenuation 1.0. Terrain albedo/shading and all geometry/generation remain unchanged.
- Directional shadow A/B changed 537,221 of 537,311 classified close-exterior pixels (>1% RGB delta) and reduced luma mean from 133.84 to 112.69. It increased measured mean frame interval by about 0.44 ms in the close exterior view and 0.30 ms in the cave view, and produced visible Compatibility-renderer cave striping. Both scene lights keep shadows disabled.
- Godot `4.7.2.stable.official.ed1daf0bf` import, all headless suites and main-scene startup passed: smoke 52, SDF 44, brush 89, chunk 179, multiregion 7,565, bootstrap 18; total 7,947 assertions, zero failures. Automated startup does not assess GUI pixels.
- Implementation source commit: `2b29498` (parent `13d08b828553df4a3b2bb9d3eb783b4cc3f45beb`). This checkpoint update is documentation-only. No independent review or owner GUI result is implied by this checkpoint.

## Scope

Only lighting settings, lighting-specific checks/capture support, evidence and documentation are in scope. Streaming, SDF generation, chunks, controls, persistence and networking remain untouched. The P1.0B loading-work/time limitations remain applicable.

Preserve `CURRENT_PROTECTED_STATE_UNKNOWN`, `V3_NOT_ATTESTED`, `ACL_REVIEW_REQUIRED`, `G1_BLOCKED_ENVIRONMENT`, and `F2_G1_RELEASE_HOLD`.

## Next gates

Independent source review of the exact draft PR SHA, owner GUI retest of exterior and cave readability, and separate owner merge authorization.
