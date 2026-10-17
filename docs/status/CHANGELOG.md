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

## 2026-10-17 — Two owner-authorized merges: documentary recovery and P1.0A

- [PR #85](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/85): docs-only HEAD `b9ea3473916f74f467659f17ba6282aa89cfb2b1`, merge `a7391fa7eafe55c9b38888249b3eaafbf03da9a9`, exact first parent `817fc72cd85d5de66932d2aa722d1b077d55bf92`. Adds recovery checkpoints, documented owner decisions and historic evidence. No new runtime tests or protected operations.
- [PR #86](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/86): source-reviewed functional HEAD `27b911e32ea396be6c66436542473093123e1b54`, merged **after #85** as `7f87c1e9c0cc1e85dd5c5fb612ebf2cd40aeffb0`. Nine fixed regions, 144 chunks, contiguous world-space SDF, center-only edits; independent [source review](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/86#pullrequestreview-5558985964), owner GUI [no apparent defects](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/86#issuecomment-6237430476), developer Godot reported 7,917 assertions. Hosted CI static only.
- Both merges explicitly owner-authorized and checked in GitHub. P1.0B/P1.0C remain unimplemented/not authorized, ADR-0002 remains proposed, and F2-G1 protected holds remain separate. New SHA-pinned post-merge checkpoints are [#85](../checkpoints/2026-10-17-PR85-MERGE.md) and [#86](../checkpoints/2026-10-17-PR86-MERGE.md), published first on a **draft docs-only PR**.
