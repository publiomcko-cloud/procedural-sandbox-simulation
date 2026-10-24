# 2026-10-24 — P2.0B identity bounds and validation closeout

## Event and source identity

Follow-up correction on owner-authorized P2.0B draft PR [#110](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/110), branch `feat/p2-0b-persistent-object-state`. Source correction commit: `85d3b9bd2a95f8dfbcd83d2ef04c68793912f232`, parent `8a01fe0415005d81b7fe5055e328b1fb10d99381`. It follows the P2.0B source implementation `f090cf50fd32d6c9b8497a1d9fe3c1a659593577`, whose parent is required baseline `d23f5ee37f8e13b3bb5c6b7b5dbbe16997a0b499`. The additional correction confines world IDs, world seeds, generator versions and signed region coordinates before snapshot/identity normalization. A valid-but-out-of-range positive region coordinate could otherwise wrap through `Vector2i` and alias a negative-region identity; regression coverage now rejects this and rejects path-like world IDs.

The earlier P2.0B implementation checkpoint remains unchanged. This checkpoint supersedes its source SHA/test-count summary for the current PR candidate, not its event history. Documentation/spec/status reconciliation is committed afterward; refresh exact current PR head before independent review.

## Validation

Godot: `4.7.2.stable.official.ed1daf0bf`, executable `C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe`.

- Focused procedural-object suite: **269 assertions, zero failures**.
- Final complete `scripts/validate.ps1`: **17,529 assertions across 16 groups, zero failures**, exit 0, `VALIDATION_PASS: L0-L2`, editor import and main-scene startup pass, final stderr empty. The updated object suite is 269/269.
- A preceding complete run had two timing-sensitive viewport brush assertions fail (`every reported dirty chunk replaces its mesh` and `unaffected chunk mesh objects remain unchanged`). The same brush suite passed immediately in isolation at 611/611, and the subsequent full suite passed at 611/611. No existing test oracle was changed for that event.
- The first implementation checkpoint also records a stale-field assertion correction; its failed first run is retained there as historical evidence.
- Final logs retained under `C:\Users\PUBLI\AppData\Local\Temp\p2-0b-validation-7edd5db2bf34403494a4ccea32a09c6d\`: `objects-identity-final.stdout.log`, `objects-identity-final.stderr.log`, `terrain-brush-isolated.stdout.log`, `terrain-brush-isolated.stderr.log`, `full-validation-identity-final.stdout.log`, `full-validation-identity-final.stderr.log`, `full-validation-final2.stdout.log`, `full-validation-final2.stderr.log`.

The test total is 52 smoke; 44 SDF; 611 brush; 179 chunk; 7,637 multiregion; 11 terrain performance; 842 history; 321 terrain persistence; 44 declarative mods; 269 procedural objects; 713 viewport picker; 6,473 experimental LOD fixture; 53 playable LOD; 251 end-to-end; 11 concurrency; and 18 bootstrap structural assertions.

## Current limits and next gate

This source correction does not expand P2.0B behavior. It preserves the P2.0A identity/content pins, seed partitions and region ownership, and rejects malformed identity inputs before normalization. SHA-256 remains accidental-corruption detection rather than authenticity; cross-process locking and power-loss-grade fsync are not implemented. No visual acceptance is inferred from headless tests. PR #110 remains draft and unmerged; independent source review and owner GUI retest are pending. The development workspace, stash and three pre-existing untracked `.gd.uid` files remain preserved. All five F2-G1 holds remain unchanged.
