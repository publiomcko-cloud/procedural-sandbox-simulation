# 2026-10-24 — Reconciliation of P1.1C, persistence, P0.3 and P2.0A GUI finding

## Provenance and authority
Documentation-only retrospective record; recorded on a branch from verified remote main `0ea2ad834db5dc2de1110cf0388ea06604cc7715`. Historical checkpoints remain immutable. This is not feature acceptance or permission to merge. Live refs must be checked again before action.

## Verified integrations
| PR | Feature | Actual merge SHA | Evidence boundary |
| --- | --- | --- | --- |
| [#99](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/99) | P1.1B-B1-1 experimental benchmark harness | `784c20712ddcd0a3ecb8554ce0b4bbe08912627b` | Test-only harness; not evidence of production benchmark or native backend qualification |
| [#103](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/103) | P1.1C playable custom LOD0/1 | `bcf19fbcf3c69b79c2a592edb6cb843288a2e1a0` | Codex-reported 16,863 assertions/0 failures; no independent Windows/GPU/owner GUI performance acceptance established here |
| [#104](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/104) | Local persistent terrain saves | `66263baeef2f628c91a6a271dad04e7cd86659e4` | Codex-reported 17,216 assertions/0; schema 1 single-slot terrain seed/version/ledger only |
| [#105](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/105) | Declarative mod foundation and isolation of save-contaminated tests | `0ea2ad834db5dc2de1110cf0388ea06604cc7715` | Codex-reported 17,258 assertions/0; validated first-party and external data-only packages; not arbitrary mod script sandboxing |

These receipts document verified historical merges retrospectively; their existence does not assert missing historical owner decisions or GUI approvals. Review each PR and original feature checkpoint for contemporaneous evidence.

## P2.0A current candidate and new owner GUI observation
[PR #106](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/106), feature HEAD `5166c311ba8d6ac7e8c6eac3b9a097db1e1ef8c1`, direct parent `01c68c7585f1901f6fa9cbf8aa7cae8f302222fc`, base `0ea2ad834db5dc2de1110cf0388ea06604cc7715`, remains draft/open/unmerged at recording. Source review passed for a bounded two-rock prototype, with owner GUI pending; developer-reported Godot 4.7.2 focused 117/117 and full 17,375/0 across 16 assertion groups, CI static PASS.

Owner GUI observation 2026-10-24: rocks visibly resemble overlapping spheres rather than natural rocks; all other tested functions reported correct. Image supplied in conversation; not committed here. Classification: **OWNER_GUI_VISUAL_BLOCKER — NATURAL_ROCK_SHAPE**. This observation supersedes only the pending GUI result, not source findings or unrelated behavior. It does **not** establish visual PASS and does **not** authorize PR #106 merge.

Correction must preserve P0.3 registry/loader, deterministic namespaced content identity, fixed-scope placement records, terrain region publication/unload, save isolation and existing tests. Improve rock silhouette using deterministic irregular/faceted geometry rather than merely overlapping smooth UV spheres; add focused geometry tests and repeat owner visual check. Do not claim export packaging, collision, terrain-following after edits or arbitrary new-mod auto-placement.

## Standing safety and governance
Five F2-G1 holds unchanged: `CURRENT_PROTECTED_STATE_UNKNOWN`, `V3_NOT_ATTESTED`, `ACL_REVIEW_REQUIRED`, `G1_BLOCKED_ENVIRONMENT`, `F2_G1_RELEASE_HOLD`.
PR #100/#101 and existing protected/local working state remain untouched. No Godot runtime executed and no product source modified in this documentation-only reconciliation.

## Next gate
Correct and retest visuals in the existing PR #106 workspace under separate development scope; independent exact-SHA source review, owner GUI PASS, explicit owner merge authorization, then a new post-merge checkpoint recording actual main SHA.
