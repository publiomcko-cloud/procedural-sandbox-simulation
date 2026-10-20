# Accepted project integration ledger
This ledger reports verified merge actions; consult GitHub refs for current HEAD. Detailed SHA-bound evaluations remain in docs/reviews/.

## 2026-10-08 — P0.0 integrated
- PR #1 charter and continuity: f71d4e4596eb3b00ce5729ad5781043a70f2302e
- PR #3 initial independent technical review: 9f927d146adc04d9cbb654257080e3ab905e1164
- PR #4 owner F5 gray-screen failure record: 3ce616bc4170b54881427655c930e91360281e38
- PR #5 correction technical review and cube visibility confirmation: 2a47bffc9e60b6305e933a0f520e7c33dba6e193
- PR #2 P0.0 implementation/camera fix: b8bd49b325b9a33e320442211736cf8b85c23b12
- PR #6 canonical post-P0.0 status: 581ce8f0c34cab84e1f0296a83f0ef14422f0038
Outcome: P0.0 merged/accepted for basic bootstrap, deterministic fixture and owner-observed cube visibility. No claim of complete Phase 0 or independent Windows runtime execution.

## 2026-10-17 — P1.0A ownership integration and recovery documentation merged
- PR #85 recovery/checkpoint/status documentation merged as `a7391fa7eafe55c9b38888249b3eaafbf03da9a9`.
- PR #86 P1.0A half-open 16×12 region ownership, 3×3 preview, 4×4 chunks per region, negative-coordinate and continuity coverage merged as `7f87c1e9c0cc1e85dd5c5fb612ebf2cd40aeffb0`; reviewed feature head `27b911e32ea396be6c66436542473093123e1b54`. PR reports 7,917 Godot assertions on its head; these were developer-reported, not independently re-executed here.
- The owner subsequently authorized the bounded P1.0B camera-focused dynamic load/unload slice and auxiliary view light on 2026-10-17. Its authorization and scope are recorded at [CHK-2026-10-17-P1-0B-AUTHORIZATION](../checkpoints/2026-10-17-P1-0B-AUTHORIZATION.md); implementation and acceptance remain pending.
- This integration does not establish persistence, cross-region edits, networking, a final terrain backend choice, or protected-host/F2-G1 acceptance. All five F2-G1 operational holds remain in force.

## 2026-10-08 — P0.1 research and review integrated
- PR #7 research, candidate-independent adapter proposal, benchmark plan, proposed ADR-0002: b27b4e90ca19d7e83f34003de488d063f00399eb
- PR #8 independent research review with conditions: a1171450e4178399f3130790368dc093be176c65
Outcome: PASS_RESEARCH_WITH_CONDITIONS. ADR-0002 remains PROPOSED/DEFERRED; no backend selected or package authorized. Owner authorized preparation and non-installing feasibility planning. See docs/specs/P0.1-COMPATIBILITY-GATE.md.


## 2026-10-08 — P0.1-F0 compatibility inventory and reviews integrated
- PR #10 corrected v1.7x release/adapter API/source inventory, reviewed head e8af422c4c29fc86e1e3ba63fed766ffc69e9c95, merged as 3c2c50f3b19f162711aee22dd3421a687064ba5c.
- PR #11 first independent F0 review (SQLite inventory and safe ZIP extraction procedure missing), merged as eef5d53fe9d14a97f324631e133441729ea728bb.
- PR #12 independent corrected F0 PASS_TECHNICAL (documentation only), merged as c39edf72e1ff8d660eb4b96ac305771f7f64daa8.
- Owner then explicitly authorized F1 download/ZIP hash verification and safety-tested static inspection on Windows x64. F1 not executed by ChatGPT and no vendor binaries loaded.
- The F1 authorization scope and executable test gate are specified in docs/specs/P0.1-F1-STATIC-ARTIFACT-INSPECTION.md. F2 Godot/DLL execution, dependencies in active game and final backend selection remain unauthorized. Original and correction reviews are retained.


## 2026-10-08 — P0.1-F1 static artifact inspection integrated
- PR #14 reviewed head d86755e4623fa018db7c7096c74ac4316e961d00, archive/hash manifest and corrected PowerShell safety suite, merged a30329d6cac071bfa1b281aea3e6b297a4314fae.
- PR #15 original F1 independent review with three corrections, merged 7161efb39cf8f47091c9ba4562f8c9f9666a1628.
- PR #16 passing SHA-specific F1 re-review, merged 166de84a411cef9c7727653c6b5cdb3143374fce.
- F1 acceptance covers static archive inspection and developer-reported 64 assertions/34 test cases; GitHub CI only covered static expected-file checks. Independent reviewer did not run Windows or load vendor code.
- Archive digest, 34-file manifest and Windows x64 descriptor mappings recorded. Third-party binary linkage and license notices remain unresolved. No installed production backend.
- Owner authorized **P0.1-F1.5 read-only public-source/release-build provenance and notices research**, detailed in docs/specs/P0.1-F1.5-BINARY-PROVENANCE.md. No native download, Godot/DLL execution, F2 or ADR-0002 approval authorized.


## 2026-10-08 — P0.1-F1.5 source/release-build provenance integrated
- PR #18 F1.5 corrected research and source/log evidence, reviewed head 3d675398e9ae86fa5e66ec5edece07b8b3bdb3bf, merged 42df9f0fdc333b932483c7af91a3b7ccf20fef6d.
- PR #19 original independent provenance review and required link-log corrections, merged aa7cfa1d9405a4dffbd93ae58b7c892f6643d988.
- PR #20 passing corrected source/log provenance review, merged d6d4f05935b9165d336357ae787d1a641d08b455.
- Historical Windows x64 release run 32419292967 editor/release jobs include exact link input objects and resolved godot-cpp SHA 9c8aeff0f58ad030f3d1030e8262de1322cd0ccd. Accepted as build-log evidence, not independently attested retained DLL code.
- Owner authorized F1.6 document-only notice/provenance resolution per docs/specs/P0.1-F1.6-NOTICE-RESOLUTION.md. The ZIP contains the project MIT license but no separate third-party notices in the accepted F1 manifest; potential LZ4, meshoptimizer, FastNoiseLite and godot-cpp notice obligations require further reconciliation. No license clearance, F2 authorization, addon adoption, or backend selection.


## 2026-10-08 — F1.6 notice draft accepted and F2 execution-design gate prepared
- PR #22 corrected source-exact 5-component third-party notice draft and PowerShell pinned-text/local-link verifier, reviewed SHA cfa0b7cf6b4a59f40cf355245c4e44dc92299a5d, **merged** 2e9adf2cc93c26a7faa6c538c7f99de13c569d65.
- PR #23 original independent F1.6 review (two FastNoiseLite transcription deviations and blank-line formatting), **merged** 7fb653ca892c5b5340a9f5d8c647a0681afd9cb2.
- PR #24 passing SHA-specific independent F1.6 re-review with independent five-notice exact text comparisons, **merged** 6a3722edab09ea26f7bf477ec185180c020adb55.
- Accepted F1.6 *documentation only*, notices explicitly **DRAFT — NOT SHIPPED — NOT LEGAL CLEARANCE**. Linker input evidence is not complete native DLL provenance; actual redistribution notices/terms remain under owner review.
- Owner instructed integration followed by moving forward to a **restricted F2 test specification**. This authorized PREPARATION only, not third-party DLL execution, native archive download, addon staging, upstream contact, production redistribution, ADR-0002 approval or backend selection.
- F2 G0/G1/G2 isolation, exact artifact/engine pin, functional fixtures and independent-review gates are planned in docs/specs/P0.1-F2-ISOLATED-RUNTIME-PROOF-PLAN.md. Any G1 native execution needs a *new express owner authorization*.


## 2026-10-08 — P0.1-F2 G1 pre-execution environment block integrated; owner provisioning next
- Owner previously authorized **bounded G1 isolated internal/native testing** in issue #26, subject to an offline, unprivileged, controlled Windows Sandbox or throwaway VM. That decision does not authorize direct host native execution or production integration.
- PR #27 F2 preparation and **honest BLOCKED_ENVIRONMENT** report (reviewed HEAD 9d7cb325c4b60d84465d568fb67c5dcc45ef9246), **merged** 499bf40ddc52365aa52665544aa84bee2905bb7a. Fixture JSON and source-only validator corrected (0,0,0)=+2.75/11264 ticks, (0,4,0)=0/0, offline guest package staging; developer-reported 21 assertions over 7 samples and previous 64 ZIP synthetic assertions/34 cases. No Godot, native DLL or vendor ZIP executed/downloaded in F2.
- PR #28 initial independent review of proper blocked stop and preparation findings, **merged** 58e7dda2a721b62099b5e80a2a1348bf573896a6.
- PR #29 passing corrected F2 preparation review (independent source-only calculation for seven samples), **merged** c9db1abd1cbd71d9688e0312872c52fbd373cf51. GitHub checks were static only. A–G not run and no owner GUI test: F2 is NOT complete, still BLOCKED_ENVIRONMENT.
- A Windows guest-provisioning runbook plus inert .wsb.example configuration now guide **owner-side** enabling/diagnosis, disconnected network, read-only staging, guest standard-user verification and resource supervision. Merely enabling or starting Sandbox does not satisfy all security gates. No automatic elevated host changes, binary acquisition, addon install or native execution were undertaken by this documentation work.

## 2026-10-17 — P0.1 functional SDF terrain, brushes and localized chunks integrated

- **PR #78** visually accepted corrected SDF terrain, review head `44d920c9bcbdf9d602512a48f83e1c8fa4f3643a`, authorized merge `ff6eae5407321261a59d47ab0151230ded0993bb`. Green shaded terrain, cave cut, orbit/zoom. Review and owner GUI evidence; Godot tests developer reported.
- **PR #80** bounded ordered carve/fill, viewport picker and C/R/X controls; reviewed head `f2a16d7fe9dc6e564e91bc6c4b4dee3bfb8ec774`, owner visual PASS, authorized merge `455fe9e7eecce0fd365b4c7da5eefa6f26fbf18f`. Developer reported **186** assertions; hosted CI static.
- **PR #82** localized 16-chunk remeshing; reviewed head `be5ac506e4ac4a10f8fd683a72a766cac7134b07`, owner visual PASS, authorized merge `817fc72cd85d5de66932d2aa722d1b077d55bf92`. Developer reported **375** assertions; 7-run local medians 1/2/4 affected chunks ~43.8/87.7/193.8 ms vs full ~525–537 ms; no rendering-frame guarantee. Baseline seam tests over 24 internal chunk joins.
- **P1.0 PLAN Issue #83** approved as planning only. Owner subsequently authorized **P1.0A Issue #84** for Codex implementation in `C:\Dev\sandbox-sim-dev`, branch `feat/p1-0a-multiregion-spatial-ownership` at `817fc72cd85d5de66932d2aa722d1b077d55bf92`. At this checkpoint no P1.0A integration or independent GUI acceptance is claimed.
- This entry records past integration, **not** acceptance of entire Phase 0, final Voxel Tools/custom backend selection, P1 streaming, cross-region editing, multiplayer or persistence. F2-G1 protected-operation holds remain separate. See [CURRENT_STATUS](CURRENT_STATUS.md) and [dated checkpoint](../checkpoints/2026-10-17-P1-0A-KICKOFF.md).

## 2026-10-17 — Dynamic streaming and lighting merges, P1.0C planned

- [PR #88](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/88) dynamic region streaming merge `13d08b828553df4a3b2bb9d3eb783b4cc3f45beb`. Source reviewed with stage failure/retry caveats; developer reported 7,943 Godot assertions. Owner observed load/unload but lighting ineffective; lighting deferred.
- [PR #90](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/90) lighting visual fix reviewed head `9a5cb4f36c2066c8aabb031cf10c1c5ca41489b2`, owner accepted for prototype visual testing and authorized merge **`2f86c42503cfa3a334215b1ff5b9bf9658263440`**. Close terrain shading improved; cave somewhat darker, existing stippling not fixed. Developer reported 7,947 assertions; CI static only. [Issue #89](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/issues/89) closed completed.
- Next [Issue #91](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/issues/91) P1.0C global ordered cross-region edits **planning only**; branch prepared at `2f86c42503cfa3a334215b1ff5b9bf9658263440`. No coding or merge authorized; F2-G1 protected holds unchanged.

## 2026-10-20 — P1.0C owner-authorized PR #92 integration

- [PR #92](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/92) **MERGED**, actual `main` merge SHA `9452cefe5788bbbd3a38fedb55773d10ebafb0d2`. First parent `2f86c42503cfa3a334215b1ff5b9bf9658263440`; second parent `7e484c2912de04448726d0a63fbaed39d4fd7b3c`; tree `889cf6df4c06dff4578b9d1797cd1a8cef95e0b5`. GitHub remote readback confirmed.
- Independently reviewed feature HEAD `531bae3d5d5770b67e4b7fa4c5c44a8c13249284`, source commit `f632f7cc06066b690ad7574fe7b92bb306851893`. [Independent review #5578386601](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/92#pullrequestreview-5578386601) PASS with GUI-performance caveats; later PR92 commits documentation-only.
- Codex-reported pinned Godot 4.7.2 full suite **10,366 assertions / 0 failures**; reviewer did not independently execute the suite. Hosted GitHub CI static only. Owner GUI PASS for sustained editing/movement, seams/corners, X/C/R, unload/reentry and resolved stream error.
- The merged feature uses global transient 256-command ordered SDF edits, replay across region loads and revision-safe bounded CPU meshing. No persistent save, production LOD/collision, backend selection, cross-platform bitwise guarantee or complete P1 acceptance implied.
- All 13 unique historical PR #87 checkpoint files were preserved in PR #92 and are therefore in `main`. PR #87 was independently observed **closed without merge** at 2026-10-20T10:12:11Z; do not attribute its closure to this merge or overwrite the reconciled documentation.
- Owner approved P1.1 R2 plan, included in #92; proposed P1.1A is a separately gated experimental LOD0/1 fixture, not approval of native Voxel Tools or P1.1B/C. See [post-merge checkpoint](../checkpoints/2026-10-20-PR92-P1-0C-MERGE.md).
- All five F2-G1 holds unchanged.

## 2026-10-20 — P1.1A experimental LOD 0/1 fixture

- Owner separately authorized the P1.1A implementation after verified PR #92 and PR #95 integration; branch `feat/p1-1a-lod01-transition-fixture` starts from main `f42f9dbdd54809df202a81b4aa59ed0d1f377a2e`.
- Added an isolated GDScript transition-cell fixture, matched LOD0/LOD1 references, deterministic topology/ledger tests, CPU-only exploratory benchmarks, and the [P1.1A specification](../specs/P1-1A-LOD01-TRANSITION-FIXTURE.md). The production scene, SDF v1, ledger semantics and P1.0C mesher are unchanged.
- Full validation evidence and exact feature SHA are in the [P1.1A implementation checkpoint](../checkpoints/2026-10-20-P1-1A-IMPLEMENTATION.md). Performance and geometric acceptance remain pending owner-approved targets; headless data is not visual/GPU evidence. Feature PR remains draft/unmerged.
- No P1.1B/C, native Voxel Tools, ADR-0002 adoption or F2-G1 operation. All five protected-state holds remain.
