# Current project status — P4 CLOSED (2026-11-08)

## Authoritative post-P4 update

P4 is **CLOSED / INTEGRATED / OWNER ACCEPTED**. P4.0D–P4.0H PRs #269–#273 were integrated into `main` in order, ending at merge `99e83c0bd6fcc28e55e0977dad41a378a00ea2ee`. The integrated runtime tree is identical to final qualified P4.0H source HEAD `3682491cd50f4a2f9a223a47ae94ebbe952043a1`.

Final automated P4.0H qualification run `42519921001` passed the class-cache independence gate, cold-boot parser probe, 81/81 real-scene assertions, PERF_TRACE gates, and the cumulative P4.0G→A suites. The owner then completed the corrected GUI run on Godot 4.7.2/GTX 1050 Ti, reported the game visually good and smooth, and authorized closure. The GUI trace contained no script/runtime errors or warnings and remained within the P4.0H performance ceilings.

P4 now supplies deterministic fixed ticks, pause/step/bounded catch-up, active/aggregate/dormant state, bounded tier routing, mod-first material/environment state, event-driven streaming lifecycle integration, deterministic replay, paired terrain/simulation persistence, content-pin validation and closing performance telemetry.

See [P4 closure checkpoint](../checkpoints/2026-11-08-P4-CLOSURE.md).

**Next:** P5 — V1 environment: climate, rain, moisture and water accumulation/flow. P5 must build on the P4 bounded scheduler/tier/persistence contracts rather than bypass them.

---

# Current project status — P4.0C integrated (2026-11-08)

## Authoritative post-merge update

P4.0C is **INTEGRATED** into `main` through [PR #267](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/267). Merge commit: `e5370cb78d7685ea6439c78e6d753c2c975fb4cb`. The qualification evidence remains the final PR-head successful self-hosted workflow `42500732123` (P4.0C 110/110) and Starter checks `42500732074`. The accepted procedural-object historical failure envelope remains unchanged. Issue #266 is complete. See [integration receipt](../checkpoints/2026-11-08-P4-0C-INTEGRATION.md).

M4.0 and P4.0A/P4.0B/P4.0C infrastructure are integrated. The next development slice is the first mod-first material/environment state domain; visual/interactive testing is required when observable gameplay first changes. No separate P4.0C visual gate is required. The sections below retain historical pre-merge qualification context.

---

# Current project status — P4.0C qualified; integration pending (2026-11-08)

## Authoritative 2026-11-08 update

M4.0, P4.0A and P4.0B are integrated into `main`.

Integrated foundation:

- M4.0 merge: `ca13d91a4917e8061528736e5b6d808dc9b85576`;
- P4.0A merge: `7b18f9fd02b3b2d993127670b4c4d1dde19796cb`;
- P4.0B merge: `25a2dd8687cf513aa414a0469dc1f5de659863e3`;
- current P4.0C base: `5810a5f8b3cad19d90b3e11789b9f4186f92b7d7`.

P4.0C — bounded automatic simulation tier routing policy — is **QUALIFIED / READY_FOR_INTEGRATION** on Issue #266.

Qualified runtime/source:

- `e43893505924cdf0557222193d03eb7ec0dfd933`;
- branch: `feat/p4-0c-tier-routing-policy`;
- Godot: `4.7.2.stable.official.ed1daf0bf`;
- self-hosted runner: `sandbox`, Windows/X64.

P4.0C adds an engine-owned bounded router for explicit `scope_id + distance_mm` observations:

- deterministic integer-distance input;
- active/aggregate/dormant hysteresis bands;
- deduplicated FIFO dirty queue;
- hard per-call decision budget;
- hard tracked-observation capacity;
- preflight before queue consumption;
- revision-gated P4.0B tier commits;
- router snapshot/restore;
- runtime snapshot schema 2 with backward restore from schema 1;
- `simulation_tier_routing_batch` PERF_TRACE telemetry.

The router does **not** scan cameras, players, chunks, terrain, entities or world history. Distance derivation remains outside the policy layer.

Final self-hosted qualification passed:

- P4.0C focused: 110/110;
- P4.0B focused: 67/67;
- P4.0A focused: 74/74;
- M4.0 focused: 31/31;
- declarative mods: 79/79;
- entity commands: 67/67;
- Issue #108 D8: 34/34;
- placement: 53/53;
- smoke: 52/52;
- terrain SDF: 46/46;
- LOD0/1: 6474/6474;
- bootstrap: 18/18;
- main-scene startup: PASS.

The procedural-object suite preserved the exact accepted historical envelope: 671 assertions / 1 known camera-revisit failure / 9 same-revision fingerprint conflicts / 0 `SCRIPT ERROR`.

Architecture remains governed by:

- [ADR-0007 — Generalize the mod-first content core before P4](../decisions/ADR-0007-MOD-FIRST-CONTENT-CORE-BEFORE-P4.md);
- [ADR-0008 — Main-thread budget, derived-work isolation and performance observability](../decisions/ADR-0008-MAIN-THREAD-BUDGET-AND-PERFORMANCE-OBSERVABILITY.md);
- [P4.0A fixed-tick specification](../specs/P4-0A-FIXED-TICK-SCHEDULER.md);
- [P4.0B tier/state specification](../specs/P4-0B-SIMULATION-TIER-FRAMEWORK.md);
- [P4.0C routing specification](../specs/P4-0C-TIER-ROUTING-POLICY.md);
- [P4.0C final qualification checkpoint](../checkpoints/2026-11-08-P4-0C-QUALIFICATION.md).

**Integration state:** P4.0C is qualified; merge requires explicit owner authorization.

**Visual gate:** not required for P4.0C because no rendered/input behavior changes.

**Next after integration:** first mod-first material/environment state domain. Climate/water and organism systems remain later work.


---

# Current project status — runtime mainline integrated (2026-11-05)

## Authoritative 2026-11-05 status

The owner-accepted playable runtime/performance line is now integrated into `main` through PR #228.

Verified integration identity:

- accepted runtime source HEAD: `314edceb618e537b6d7a249330a854aca3113010`
- reconciled PR HEAD: `843f7603d88c1492c2a4bb96e4567c5b98be1831`
- pre-merge `main`: `5997a76d345f45bf86edfe83f690336391e8be27`
- merge commit: `f646a3b1b5d22ee443adb12d7b77634ef4528f17`
- PR: #228 — merged

The integrated runtime includes scalable/materialized SDF terrain editing and persistence, shared-surface playable integration, localized revision-safe remeshing, runtime hardening, asynchronous procedural-object generation/geometry preparation, entity command/history fixes, event-driven LOD work and the F10 free-exploration mode. F10 provides captured mouse look, WASD/arrow flight, Space ascent, Shift descent and Ctrl boost; HUD and placement marker are hidden while active, while terrain editing remains available through center aim.

Merge gates on the reconciled PR HEAD passed:

- Starter checks push run `42129570989`: SUCCESS.
- Free exploration qualification push run `42129570845`: SUCCESS.
- Starter checks pull-request run `42129617089`: SUCCESS.
- P2 GDScript allocation benchmark pull-request run `42129617222`: SUCCESS.
- `FREE_EXPLORATION_MODE_PASS: assertions=17 failures=0`.
- `TERRAIN_LOD_RUNTIME_PASS: assertions=55 failures=0`.
- `RUNTIME_SCALABLE_PLAYABLE_PASS: assertions=33 failures=0`.
- canonical `scripts/validate.sh`: PASS.

Owner GUI acceptance immediately preceding integration reported that free exploration works, terrain editing works while exploring, and no perceptible lag was observed.

The P3.1 R12-CXR R1–R6 chain is no longer an active development path. After merge verification, PRs #213, #214, #215, #216, #217, #219, #220, #221 and #222 were closed as **superseded**, with branches/commits/reports/raw evidence preserved. Do not resume or merge that chain unless the owner explicitly reopens the research direction.

For current work use live `main`, Godot 4.7.2 and `scripts/validate.sh`. Historical `scripts/validate.ps1` references below describe earlier snapshots only and are not current operating instructions.

See [runtime mainline merge and R6/R12 closure receipt](../checkpoints/2026-11-05-RUNTIME-MAINLINE-MERGE.md) and the [pre-merge reconciliation checkpoint](../checkpoints/2026-11-05-RUNTIME-MAINLINE-RECONCILIATION.md).

---

# Historical status snapshots below

# Current implementation candidate — P3.1 Storage R2 (2026-10-25)

## Newer candidate — P3.1 Storage R2 (2026-10-25)

Verified `origin/main` remains the P3.1 baseline `5997a76d345f45bf86edfe83f690336391e8be27`; PR #129 starts from `db1c72fadd24e69f87f0eb2c5091cee1ac1b39da`. Source correction `ea18432c6f9cfc1912e1d4aeb5363bb8f5bc9731` on `feat/p3-1-scalable-terrain-storage` adds conservative spatial/min-max SDF candidate selection and append-only schema-v2 segment reuse without deleting historical generations or changing schema 1. Focused storage tests passed 3,516/0; isolated-profile `scripts/validate.ps1` passed 21 suites and 21,464 assertions with zero failures on Godot 4.7.2. Measurements are exploratory: 8,192 concentrated commands still yield 8,192 local candidates, ~49.1 ms point-query p99, ~63.2 ms ray-picker end-to-end p99 and ~6.45 s LOD1 reconstruction; saves rehash reused segment bytes. The reparse-junction fixture was unavailable on this host, and three camera colinearity warnings were non-fatal. PR #129 remains draft/unmerged; exact source review and owner GUI save/restart checks are pending. See [R2 checkpoint](../checkpoints/2026-10-25-P3-1-STORAGE-R2-CORRECTIONS.md). PRs #128/#130, P3.0D work, stash entries, and three pre-existing untracked `.gd.uid` files were preserved. All five F2-G1 holds remain unchanged.

# Prior implementation candidate — P3.0D (2026-10-25)

## Newer candidate — P3.0D Issue #123 (2026-10-25)

Verified `origin/main`/baseline: `c08267caea3d4c092574c8b4fb1f1e59883923dc`. Source commit `63c4bd4fc30e8ad655cd98f01292b9cf112be9fb` is on `feat/p3-0d-precise-entity-placement`, draft PR [#124](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/124). It changes placement target selection from hard-coded viewport center to the visible pointer, with center fallback for hidden/unavailable cursor; the indicator and command share one SDF hit path, and rounded millimeter coordinates determine floor-based region ownership. Focused placement tests passed 51/51, procedural-object regression 638/638, and full Godot 4.7.2 validation passed 18,204 assertions across 21 suites with zero failures. Main-scene startup passed. These are local headless results, not visual acceptance. Independent exact-SHA source review and owner GUI retest remain pending; PR #124 remains draft/unmerged. Schema 3, Undo/Redo, identity, content pins, persistence and existing controls remain in scope; Issue #108 remains deferred. PRs #115/#117/#120/#122, both stashes and pre-existing untracked `.gd.uid` files were preserved. All five F2-G1 holds remain unchanged. See [P3.0D checkpoint](../checkpoints/2026-10-25-P3-0D-ENTITY-PLACEMENT.md) and [placement contract](../specs/P3-0D-PRECISE-ENTITY-PLACEMENT.md).

Verified integration baseline/main is `d391e09c1a7aac2116de2004c80d7f58bdb54986` and includes merged Issue #118 PR #119. P3.0C is implemented on `feat/p3-0c-transactional-undo-redo`, draft PR [#121](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/121); exact remote head is verified at closeout. Full Godot `4.7.2.stable.official.ed1daf0bf` `scripts/validate.ps1` passed **18,153 assertions across 20 assertion-marker suites**, zero failed assertions; main-scene startup passed. Three non-fatal colinear target/up-vector warnings and the host's unavailable junction fixture are recorded in the [P3.0C checkpoint](../checkpoints/2026-10-25-P3-0C-IMPLEMENTATION.md). Independent exact-SHA source review and owner GUI retest remain pending. No merge is authorized. P3.0C spec: [transactional persistent undo/redo](../specs/P3-0C-TRANSACTIONAL-PERSISTENT-UNDO-REDO.md); proposed [ADR-0006](../decisions/ADR-0006-PERSISTENT-ENTITY-UNDO-REDO.md). PRs #115/#117/#120 and Issue #108 were not changed. Preserve `CURRENT_PROTECTED_STATE_UNKNOWN`, `V3_NOT_ATTESTED`, `ACL_REVIEW_REQUIRED`, `G1_BLOCKED_ENVIRONMENT`, and `F2_G1_RELEASE_HOLD`.

> **Latest 2026-10-25 Issue #118 R1 candidate:** `main` remains `fd431dbcad18685a3aa2c86c3c9b25fbd81303c9`; source `f0164b140009bb797951aa4085bb36001889bc57` (parent `6280fac4b7554ba24b880790c3991c01aaa43851`) hardens PR #119 so only the exact canonical `user://mods` root can receive optional treatment. A pre-fix reproduction showed an authorized descendant root with a missing child manifest returned success when caller-marked optional; post-fix focused and full Godot validation passed 18,047 assertions/0 failures. Draft PR #119 is open/unmerged at documentation HEAD `948bfabb9890364b6aad8e6f9b4b211b35c082d7`; both exact-HEAD Starter checks passed (runs `40211032023` and `40211034290`, static only). Independent R1 review and owner GUI retest remain pending. See [R1 checkpoint](../checkpoints/2026-10-25-ISSUE-118-OPTIONAL-ROOT-API-HARDENING.md), [spec](../specs/ISSUE-118-MOD-DISCOVERY.md), and [proposed ADR-0005](../decisions/ADR-0005-MOD-DISCOVERY-OPTIONAL-USER-ROOT.md). PRs #115/#117, P3.0C workspace, stash and F2-G1 holds remain unchanged.

> **Prior 2026-10-25 P3.0B candidate:** main baseline `5b8cf36108ce48476095f14b35426e7e8ab4bfe8`; source commit `6ce65bbe2f1a54bd1436416b5cb6102c75a09769`. Full Godot 4.7.2 validation passed 18,022 assertions/0 failures; source review and owner GUI retest were pending. This work remains separate. See [P3.0B checkpoint](../checkpoints/2026-10-25-P3-0B-IMPLEMENTATION.md). All five F2-G1 holds remain unchanged.

> **2026-10-24 live integrated update:** P2.0C PR #112 merged at main `38021b0e72b30f4b868e49c870bf43f402dd0fce`. Owner reports visual and perceived streaming PASS; source review and hosted CI PASS. [Post-merge checkpoint](../checkpoints/2026-10-24-PR112-P2-0C-MERGE.md). P2 exit review and P3 planning next; issue #108 deferred. Earlier candidate/draft wording is historical.

> **2026-10-24 P3.0A implementation candidate:** live `main` and required baseline verified at `b874991bb0f2cc698e41dd8709f3b0325d73c855`. Source commit `ca2273953d3b578cf349990f487fcac25336db6b` (parent exactly that baseline) is on existing branch `feat/p3-0a-entity-command-contract`, draft PR [#114](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/114). Godot 4.7.2 `scripts/validate.ps1` passed 17,950 assertions across 17 groups; isolated command harness passed 67 assertions and headless startup. These are developer-run headless results only. Independent exact-SHA source review and owner GUI evaluation remain pending; PR #114 is open/draft/unmerged. P3.0A payload schema-upgrade, revisions, receipt policy, architecture and limitations are recorded in the [spec](../specs/P3-0A-TRANSACTIONAL-ENTITY-COMMAND-CONTRACT.md), proposed [ADR-0003](../decisions/ADR-0003-TRANSACTIONAL-ENTITY-COMMANDS.md) and [checkpoint](../checkpoints/2026-10-24-P3-0A-IMPLEMENTATION.md). P2.0C is integrated; issue #108 remains deferred. The five F2-G1 holds remain unchanged.

> **2026-10-25 P3.0A owner GUI failure and correction candidate:** owner reported that Delete did not make the selected entity disappear on source `c8a91eb387f037beb7c8db7670aed4186d37c496`. The defect was reproduced through the actual viewport input route for a physical-key-only event and corrected in source `3da4bc6f7272ed838da7438c43312227e32ae59e` (parent `c8a91eb387f037beb7c8db7670aed4186d37c496`) on draft PR #114. Full Godot 4.7.2 validation now passes 17,969 assertions/18 groups, zero failures, including a 19-assertion scene regression. This is developer-run headless evidence; actual OS focus and owner GUI retest remain pending. Exact cause, behavior and retest steps are in the [correction checkpoint](../checkpoints/2026-10-25-P3-0A-ENTITY-DELETE-GUI-CORRECTION.md). PR #114 remains open/draft/unmerged; no merge is authorized. All five F2-G1 holds remain unchanged.

> **Historical 2026-10-24 P2.0B owner GUI result:** six interaction and persistence checks PASS on PR #110 source HEAD `819e18c8ac299c2569e4d7f3b8aeefc384bde0b2`; independent source review PASS [#5639809147](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/110#pullrequestreview-5639809147). PR #110 was subsequently merged before the current `b874991b` baseline. [Acceptance checkpoint](../checkpoints/2026-10-24-P2-0B-OWNER-GUI-ACCEPTANCE.md); see the P2.0C integration checkpoint for later state. Issue #108 remains deferred.

# Historical P2.0B implementation status snapshot — superseded 2026-10-24

The required live main baseline for the current task is `d23f5ee37f8e13b3bb5c6b7b5dbbe16997a0b499`. P2.0B latest source correction `85d3b9bd2a95f8dfbcd83d2ef04c68793912f232` is on `feat/p2-0b-persistent-object-state`, draft PR [#110](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/110). Full Godot 4.7.2 validation passed 17,529 assertions in 16 groups, zero failures; focused object tests passed 269/269. PR remains open/draft/unmerged; refresh exact final PR head from GitHub. Independent source review and owner GUI retest are pending. Contract, storage behavior, evidence and limits are recorded in [P2.0B spec](../specs/P2-0B-PERSISTENT-OBJECT-STATE.md), [implementation checkpoint](../checkpoints/2026-10-24-P2-0B-IMPLEMENTATION.md) and [identity-bound correction checkpoint](../checkpoints/2026-10-24-P2-0B-IDENTITY-BOUND-CORRECTION.md). No merge or visual approval is asserted. All five F2-G1 holds remain unchanged.

---

## Earlier live verified status snapshot — 2026-10-24

Integrated main: `52ed9601c70ddade80e75ee9faccd45ec8d2e9a3` after PR #106. PRs #99, #103, #104, #105 and #106 integrated; exact receipts in [post-merge checkpoint](../checkpoints/2026-10-24-PR106-MERGE-AND-NEXT-P2-0B-HANDOFF.md). Owner accepted rock shapes; visual terrain/rock intersection persists and is deferred in issue #108, not resolved or denied. P2.0B is next separately scoped candidate; no code yet. Five F2-G1 holds, ADR-0002 proposed and non-automatic authorization preserved. Check live GitHub refs before relying on snapshot. Every significant event must have new immutable checkpoint, index update and pertinent status/doc reconciliation.

---

# Project current status — checkpoint 2026-10-21

**Snapshot, not a live branch monitor.** Evidence baseline: repository `publiomcko-cloud/procedural-sandbox-simulation`, verified `main` at **`665c5c883ae88b949f4030f7affc786064999f61`** on 2026-10-21 after verified owner-authorized PR #97 documentation integration (first parent `aca6b6403c455708cacda01c8fbf0bf980d813a2`, second parent `4cc18693d9f01e759b272c6302de2663ffc42a1e`). PR #96 P1.1A experimental integration and PR #95 documentation remain previously merged. P1.0C source and the owner-approved P1.1 R2 plan remain integrated. **Always check live GitHub `main`, feature PR and working tree before acting.** Earlier P1.0A and P1.0B checkpoints remain frozen; the [P1.0C implementation checkpoint](../checkpoints/2026-10-17-P1-0C-IMPLEMENTATION.md) records its authorized source slice.

## 2026-10-21 — P1.1B B0 owner approves R4 + R4a experimental inputs ONLY

**NEW owner decision:** after the final independent [B0 R4a source-only PASS](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/97#issuecomment-6314241218), owner explicitly authorized **approving B0 R4+R4a as an experimental input/methodology contract and registering that decision online**. See [binding narrowed owner contract](../specs/P1-1B-B0-OWNER-APPROVED-CONTRACT.md), [source R4](../specs/P1-1B-B0-R4-SOURCE-PROPOSAL.md), [R4a overriding addendum](../specs/P1-1B-B0-R4A-ACCEPTED-ADDENDUM.md), [review record](../reviews/2026-10-21-P1-1B-B0-R4A-INDEPENDENT-SOURCE-REVIEW.md) and [immutable decision checkpoint](../checkpoints/2026-10-21-P1-1B-B0-R4A-OWNER-INPUT-APPROVAL.md).

**APPROVED INPUTS, not execution:** canonical radius-0.58 isolated replay, event-based streaming including atomic diagonal 9→14 and three-step 9→12→15→16 *after successful publications*, detached LOD0/LOD1 signed fixtures, fully defined synthetic tunnels and fixed seam/reload inputs. **EXCLUDED / NOT_FROZEN:** repeated real viewport clicks, remote-picker click cases, edited revisit and unproven edited LOD contour scoring. The R4a addendum has precedence for its three corrections.

**NOT AUTHORIZED:** B1-1 harness implementation, benchmark execution (even `UNSCORED`), code changes, any native Voxel Tools acquisition/use, backend selection/ADR-0002, P1.1C, production LOD and protected F2-G1 operations. Product performance/geometry thresholds, target hardware and permitted GPU/memory tools remain `OWNER_TO_DEFINE`; no test/GUI data was obtained by this planning decision. The **next permitted step** is decision collection and bounded B1-1 *proposal only*, not Codex code or runs.

This event is documented on a separate docs-only PR based on the verified `665c5c...` `main`; historical earlier checkpoint statements below are preserved as time-scoped evidence and must not override this later approval. The future documentation PR merge is not asserted until GitHub readback verifies it. All five F2-G1 holds remain.

## Accepted integrated functional results

| PR | Owner decision and independently reviewed deliverable | Exact merge commit | Evidence boundary |
| --- | --- | --- | --- |
| [#78](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/78) | SDF single-region terrain, cave section, orbit/zoom, green lighting; visual PASS | `ff6eae5407321261a59d47ab0151230ded0993bb` | Corrective head `44d920c9bcbdf9d602512a48f83e1c8fa4f3643a`; local Godot tests reported; hosted CI static |
| [#80](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/80) | Ordered transient carve/fill, viewport picker, C/R/X, mesh regeneration; visual PASS | `455fe9e7eecce0fd365b4c7da5eefa6f26fbf18f` | Reviewed head `f2a16d7fe9dc6e564e91bc6c4b4dee3bfb8ec774`; **186** developer-reported assertions |
| [#82](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/82) | 4×4 = 16 finite-region chunks, localized rebuild, boundary tests; visual PASS | `817fc72cd85d5de66932d2aa722d1b077d55bf92` | Reviewed head `be5ac506e4ac4a10f8fd683a72a766cac7134b07`; **375** developer-reported assertions |
| [#85](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/85) | Durable status/checkpoint/recovery documentation | `a7391fa7eafe55c9b38888249b3eaafbf03da9a9` | Documentation-only merge; no product runtime evidence |
| [#86](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/86) | P1.0A 3×3 region ownership, 144 chunks, negative coordinates and seam tests | `7f87c1e9c0cc1e85dd5c5fb612ebf2cd40aeffb0` | Reviewed feature head `27b911e32ea396be6c66436542473093123e1b54`; 7,917 developer-reported Godot assertions; owner GUI/merge evidence is recorded in its PR/checkpoints |
| [#88](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/88) | P1.0B bounded camera-driven region streaming | `13d08b828553df4a3b2bb9d3eb783b4cc3f45beb` | Source reviewed and owner GUI gate recorded separately |
| [#90](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/90) | P1.0B terrain depth lighting correction | `2f86c42503cfa3a334215b1ff5b9bf9658263440` | Lighting checkpoint is integrated; visual result applies to its recorded owner retest |
| [#92](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/92) | P1.0C global ordered edits across streamed region boundaries; 256-op transient ledger and revision-safe meshing; owner GUI PASS | `9452cefe5788bbbd3a38fedb55773d10ebafb0d2` | Reviewed source head `531bae3d…`, 10,366 developer-reported asserts, performance caveats and full docs reconciliation |
| [#96](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/96) | **P1.1A** detached CPU LOD0/LOD1 transition-cell fixture, face/edge/corner references and validation | `aca6b6403c455708cacda01c8fbf0bf980d813a2` | Independent review [#5588342762](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/96#pullrequestreview-5588342762) PASS for experimental scope, Codex-reported 16,807 assertions/0 failures; GUI/GPU/performance acceptance not claimed |

[SHA-specific source-review and owner GUI evidence index](../reviews/2026-10-17-P0-1-FUNCTIONAL-ACCEPTANCE-EVIDENCE-INDEX.md) records the exact GitHub review/comment links for PRs #78, #80 and #82.

Owner explicitly authorized each merge after source and GUI approval. Runtime counts and timing are developer-provided; ChatGPT inspected source and reports, **not** an independent Godot Windows execution. GitHub "Starter checks" only checks project structure. At PR #82 local benchmark, seven-run median full mesh ~525–537 ms and localized ~44/88/194 ms for 1/2/4 affected chunks; not a full-frame or scaling guarantee.

## P1.0C — integrated; P1.1A experiment subsequently integrated

- **PR #92 MERGED:** exact owner-authorized head `7e484c2912de04448726d0a63fbaed39d4fd7b3c`, merge `9452cefe5788bbbd3a38fedb55773d10ebafb0d2` on remote `main`, parents and tree verified. [Post-merge checkpoint](../checkpoints/2026-10-20-PR92-P1-0C-MERGE.md) documents the event in a separate docs-only draft PR.
- **Evidence:** independently source-reviewed feature HEAD `531bae3d5d5770b67e4b7fa4c5c44a8c13249284` [review #5578386601](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/92#pullrequestreview-5578386601) PASS with performance caveats; Godot 4.7.2 `scripts/validate.ps1` 10,366 assertions/0 failures developer-reported, not independently executed; owner GUI PASS recorded for sustained edits, simultaneous movement, borders/corners, X/C/R, unload/reentry and no persistent stream errors. The CI hosted check was static only.
- **PR #87:** historical docs-only PR now **closed without merge** at head `6fad428a22a149624da245e88a5e608d09ed7dd3`, observed GitHub close event 2026-10-20T10:12:11Z; 13 unique checkpoint blobs were already fully preserved in the merged PR #92. Do not re-merge stale status or infer who authorized its closure.
- **P1.1:** [owner-approved plan R2](../roadmap/P1-1-APPROVED-PLAN-R2.md) is integrated via PR #92; the [post-merge checkpoint](../checkpoints/2026-10-20-PR92-P1-0C-MERGE.md) is integrated by PR #95 at the verified `main` SHA above. The owner has now separately authorized P1.1A implementation. The P1.1A experimental fixture has subsequently **merged in PR #96**; see the separate P1.1A integration record below. No Voxel Tools runtime, production LOD or P1.1B/C execution authorization.


## Spatial contract retained after P1.0A

Version 1 `SdfWorld` logical regions are 16×12 world units, divided into 4×4 chunks with half-open cell ownership and shared sampling planes. P1.0A is merged in PR #86; the generator contract and global Z=6 visualization cut remain unchanged. P1.0B supplies bounded streaming; P1.0C adds one globally ordered in-memory edit ledger whose commands replay in any affected resident region. No disk persistence or networking is part of P1.0C.

## Decisions and deferrals

- Binding product scope: [PROJECT_CHARTER](../PROJECT_CHARTER.md), [ADR-0001](../decisions/ADR-0001-BASELINE.md). [ADR-0002](../decisions/ADR-0002-TERRAIN-BACKEND-PROPOSED.md) is **proposed**, not adopted. No final terrain backend has been selected and full Phase 0 gates (comparative backend, durable save, mods, simulation) have not passed.
- Multiplayer: future architectural compatibility desired (stable region keys, canonical ordered edits, rendering not authoritative), but multiplayer **not part of initial release or active slice**. No networking is implemented.
- Persistence, LOD, collision, entity/simulation/mod contracts and cross-platform bit-identical replay remain unproven. P1.0C now uses bounded CPU worker meshing with main-thread-only ArrayMesh construction/publication; this does not claim a GPU upload completion time or a frame-time guarantee.
- F2-G1 protected-host/native-addon operations remain **on hold** pending independent environment/protected-state validation; no implied elevation, ACL updates or VM access from this functional track. PRs [#75](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/75), [#76](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/76), [#77](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/77) were not part of any of these merges. The 2026-10-08 F2 report is archived at [historical snapshot](archive/2026-10-08-F2-PREPARATION-STATUS.md), **not** current live environment certification.

## Next authorized action and handoff

**Verified live integration:** P1.1A PR #96 merged at `aca6b6403c455708cacda01c8fbf0bf980d813a2` (prior main `f42f9dbdd54809df202a81b4aa59ed0d1f377a2e`, reviewed head `cfdc0d3f48636c3567ac38a45de2a2935345d833`, Git tree `53387aed4b8fdef99fa824d24083c9635d6b00f9`). The owner expressly authorized this integration. The exact-SHA source PASS, reported Godot results and strict experimental-only scope are recorded in [new post-merge checkpoint](../checkpoints/2026-10-20-P1-1A-OWNER-AUTHORIZED-INTEGRATION.md) and [permanent review record](../reviews/2026-10-20-P1-1A-FINAL-EXACT-SHA-INDEPENDENT-REVIEW.md). These are **proposed in a separate docs-only draft PR** until independently integrated.

**Next planning task:** [P1.1B handoff](../roadmap/P1-1B-PLANNING-HANDOFF-PROPOSED.md) is ready for owner review. It authorizes **no new code, benchmarks, backend adoption, third-party native execution or protected-host actions**; only a proposed, source-backed P1.1B experimental design/decision package. No geometry/performance budgets have been approved. A future authorized Codex action must reconcile `C:\Dev\sandbox-sim-dev`, preserve `stash@{0}`, reread actual remote refs and maintain all five F2-G1 holds. P1.1C and production LOD remain unapproved.


## 2026-10-20 — P1.1 owner-approved R2 plan integrated with PR #92

At the time of approval, the owner accepted [P1.1 R2](../roadmap/P1-1-APPROVED-PLAN-R2.md) with global LOD0/1 lattice, watertight mixed-LOD transitions, gated backend qualification and per-scenario profiling. The plan was part of merged PR #92. The [approval checkpoint](../checkpoints/2026-10-20-P1-1-OWNER-PLAN-APPROVAL.md) and [post-merge receipt](../checkpoints/2026-10-20-PR92-P1-0C-MERGE.md) distinguish design acceptance from execution. The separate P1.1A authorization and current implementation state are recorded below. P1.1B/C, native dependencies, production materials/persistence/collision and ADR-0002 finalization remain unapproved.

## 2026-10-20 — P1.1A adjacent-reference placement correction

The final adjacent-mesh oracle finding in review #5584564076 was corrected on the existing draft PR #96. The LOD0 reference builder's full 1×1×1-unit domain now starts two half-unit LOD0 lattice indices beyond/before the transition cell, rather than using the overlapping negative -1-index placement. Tests independently prove AABB contact/nonoverlap and matched tangent extents for both LOD levels and all six face orientations, then compare nonlinear-field face/edge/corner contours and normals against independently built neighbors. Godot 4.7.2 validation passed **16,807 assertions across 12 suites, zero failures** on source/test commit `2929a01c7d38dde59fdb6e1a4902e2e9183e6a59`; the new fixture suite is 6,441/6,441. This remains single-cell experimental evidence, with no GUI/GPU acceptance or approved performance budgets. The [new checkpoint](../checkpoints/2026-10-20-P1-1A-ADJACENT-ORACLE-CORRECTION.md) records the defect reproduction and bounded evidence. Historically this event was prepared on draft PR #96; **subsequently**, independent final exact-SHA source rereview [#5588342762](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/96#pullrequestreview-5588342762) passed and owner-authorized merge `aca6b6403c455708cacda01c8fbf0bf980d813a2` completed. All five F2-G1 holds remain in force.

## 2026-10-20 — P1.1A experimental transition fixture and review correction

P1.1A source and test work is recorded on the unmerged feature branch `feat/p1-1a-lod01-transition-fixture`, based on `f42f9dbdd54809df202a81b4aa59ed0d1f377a2e`; see the [original implementation checkpoint](../checkpoints/2026-10-20-P1-1A-IMPLEMENTATION.md), the [review-correction checkpoint](../checkpoints/2026-10-20-P1-1A-REVIEW-CORRECTIONS.md), and [fixture specification](../specs/P1-1A-LOD01-TRANSITION-FIXTURE.md). Review #5584314194's alignment, snapshot, nonfinite-sample, and independent-neighbor-seam findings were corrected on the same branch and PR #96. The full Godot 4.7.2 suite passed 16,174 assertions/0 failures on source correction commit `9669a03ec691532862e9aee1251f15e15f06b690`. This remains an isolated CPU fixture; performance/geometric thresholds are exploratory/pending and there is no visual/GPU acceptance. Historically the experiment awaited rereview; that gate later passed at reviewed head `cfdc0d3f48636c3567ac38a45de2a2935345d833` and owner-authorized merge `aca6b6403c455708cacda01c8fbf0bf980d813a2` occurred. All five F2-G1 holds remain unchanged.


## Additional documentation decision, 2026-10-17 — checkpoint cadence

The owner explicitly requires **a documentary checkpoint after every merge or other significant project interaction**. The protocol was merged in PR #85 (`a7391fa7eafe55c9b38888249b3eaafbf03da9a9`). The later P1.0A merge and P1.0B authorization are recorded in the [P1.0B checkpoint](../checkpoints/2026-10-17-P1-0B-AUTHORIZATION.md) and [checkpoint index](../checkpoints/INDEX.md).

## 2026-10-24 — P2.0A rock geometry correction on draft PR #106

The owner-reported overlapping-sphere appearance has a bounded source correction on `feat/p2-0a-mod-first-procedural-objects`, commit `29b0935336d084461b680b00eb0f4e020962098a` (parent `5166c311ba8d6ac7e8c6eac3b9a097db1e1ef8c1`). The shared adapter now produces a seed-varied, closed, angular 320-triangle body from each registered recipe envelope. The focused test passed 135 assertions and full `scripts/validate.ps1` passed 17,393 assertions across 16 groups on Godot 4.7.2. These are headless results only: independent source review and owner GUI retest are still pending, so PR #106 remains draft and unmerged. See the [new correction checkpoint](../checkpoints/2026-10-24-P2-0A-ROCK-SHAPE-CORRECTION.md). PR #107 is a separate docs-only draft; this appended status event does not alter its branch. All five F2-G1 holds remain.

## 2026-10-24 — P2.0A geological rock generator follow-up

The radial/deformed lobe representation has been replaced in the same PR #106 by versioned `geological_halfspace_v1` granite and basalt recipes, with four independently derived seeds and closed low-poly half-space meshes. Source implementation commit `098fca0d6082cc3bd55ad2e8d58231d85a6ec6e1` is parented by `1f9fadd1e51cb956c31ac0c5fc8fb3d1cc9bcf8d`; final PR head includes the associated checkpoint/index reconciliation and is reported separately. Godot 4.7.2 full validation passed 17,468 assertions across 16 assertion groups; focused geometry 208/208 and isolated CPU-preview gallery 57/57. These results supersede only the prior #106 source/geometry description. PR #106 remains open/draft/unmerged; independent review and owner GUI retest are pending. The gallery is not a Godot renderer capture or art approval. PR #107 remains untouched/open/draft at its separately observed head. All F2-G1 holds remain unchanged.

## 2026-10-24 — P2.0C modular static population candidate

Verified task baseline: `main` and `feat/p2-0c-modular-static-population` were at `84bb7c3e573e7aa5a07608aac7834735aeb2c84f`; origin matched `https://github.com/publiomcko-cloud/procedural-sandbox-simulation.git`. P2.0B PR #110 is integrated in that baseline. PR #111 remains open/draft at `26ec183684453ae14dfb87fd7ea421c9df8d7e48`; its branch and files were not edited in that branch. The P2.0C implementation source commit `057536f1680d5118e9c9990c137e1812f8cc8244` is parented directly by the baseline and is published in draft PR #112. Documentation in this PR records the implementation, tests and GUI steps.

Godot `4.7.2.stable.official.ed1daf0bf` `scripts/validate.ps1` passed with **17,883 assertions across 16 groups; zero failures**. P2.0C object tests: 621/621; terrain brush: 613/613. Exploratory population generation/publication timings are recorded in the spec; they are not product budgets. Full renderer appearance, GPU timings, OS memory, art quality and owner GUI behavior are not validated here.

P2.0C provides schema-1 declarative distribution rules through the P0.3 data-only package loader, deterministic positive/negative-region candidates and identities, pinned persistence semantics, bounded combined static meshes, and bounded region-publication queues. The two P2.0B compatibility representatives remain unchanged as an additive transition; no silent migration is performed. Terrain save schema 1 remains untouched. Issue #108 terrain/rock conformance, physics, collision, time simulation, undo/redo, multiplayer and networking remain out of scope.

**Next gate:** independent exact-SHA review of PR #112 and owner GUI retest using the P2.0C specification. Merge requires a separate owner decision. Preserve `CURRENT_PROTECTED_STATE_UNKNOWN`, `V3_NOT_ATTESTED`, `ACL_REVIEW_REQUIRED`, `G1_BLOCKED_ENVIRONMENT`, and `F2_G1_RELEASE_HOLD`; no protected-host operation or F2-G1 change occurred.
