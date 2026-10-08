# Canonical project status — 2026-10-08 (P0.1-F1.6 integrated; F2 plan prepared)
Verify live Git refs before action. Repository: publiomcko-cloud/procedural-sandbox-simulation. Authority: docs/PROJECT_CHARTER.md, accepted ADR-0001, docs/workflow/PROJECT_MEMORY_PROTOCOL.md. **ADR-0002 remains PROPOSED/DEFERRED; no backend selected.**

## Verified integrated stages
- P0.0: accepted Godot 4.7.2 bootstrap, deterministic fixture and owner-observed cube; implementation PR #2 merged b8bd49b325b9a33e320442211736cf8b85c23b12. Developer-reported 52 pure-data and 18 scene/camera assertions; no independent reviewer Windows execution.
- P0.1 comparative source research: PR #7 merged b27b4e90ca19d7e83f34003de488d063f00399eb and independent review PR #8 a1171450e4178399f3130790368dc093be176c65. No adapter/backend adoption.
- P0.1-F0 source/artifact compatibility inventory: PR #10 merged 3c2c50f3b19f162711aee22dd3421a687064ba5c; first review #11 eef5d53fe9d14a97f324631e133441729ea728bb; passing review #12 c39edf72e1ff8d660eb4b96ac305771f7f64daa8.
- P0.1-F1 vetted ZIP inspection and static hash/manifest: PR #14 merged a30329d6cac071bfa1b281aea3e6b297a4314fae; original review #15 7161efb39cf8f47091c9ba4562f8c9f9666a1628; corrected passing review #16 166de84a411cef9c7727653c6b5cdb3143374fce.
- P0.1-F1.5 exact upstream public Windows build provenance: PR #18 merged 42df9f0fdc333b932483c7af91a3b7ccf20fef6d; first review #19 aa7cfa1d9405a4dffbd93ae58b7c892f6643d988; passing review #20 d6d4f05935b9165d336357ae787d1a641d08b455.
- P0.1-F1.6 source-exact THIRD-PARTY notice draft and checker: reviewed head cfa0b7cf6b4a59f40cf355245c4e44dc92299a5d, PR #22 merged 2e9adf2cc93c26a7faa6c538c7f99de13c569d65; first independent review PR #23 merged 7fb653ca892c5b5340a9f5d8c647a0681afd9cb2; passing independent review PR #24 merged 6a3722edab09ea26f7bf477ec185180c020adb55. All three merges expressly owner-authorized 2026-10-08.

## Accepted evidence and limits
- Official Voxel Tools v1.7x GodotVoxelExtension.zip: F1 developer computed exact SHA-256 600737572a5e25541ba6f503e842a3717ba19afafa5474510a6ceff995a1d2d8 and 54,457,774 bytes, matching publisher metadata; 34 archive entries, 29 descriptor mappings including Windows editor/release DLLs. Developer-reported synthetic ZIP safety suite 64 assertions in 34 cases, 0 failures. GitHub CI static; independent ChatGPT did not run Windows tests or vendor DLLs.
- F1.5 upstream run 32419292967 Windows jobs 96587536545 and 96587536763 succeeded; logged linker inputs include SQLite, LZ4, 16 meshoptimizer, 3 FastNoiseLite objects and godot-cpp archives. Historical resolved godot-cpp SHA is 9c8aeff0f58ad030f3d1030e8262de1322cd0ccd. This proves logged link inputs, **not** independently attested retained machine code or complete runtime dependencies.
- F1.6 draft under docs/legal/P0.1-F1.6-THIRD-PARTY-NOTICES-DRAFT.md exactly matches pinned LZ4, meshoptimizer, FastNoiseLite, godot-cpp and Voxel Tools license texts after newline normalization; independent source text comparison performed and passing review preserved. **DRAFT — NOT SHIPPED — NOT LEGAL CLEARANCE.** Original binary package contains main project LICENSE.md but no separately inventoried notices. Distribution/license completeness remains unresolved.

## Current authorization (planning only)
Owner authorized integrating PRs #22/#23/#24 and **preparing a restricted F2 runtime-test specification**, without any F2 execution authorization. Binding planning document: docs/specs/P0.1-F2-ISOLATED-RUNTIME-PROOF-PLAN.md.
Preparatory work is docs/source design only: official Godot 4.7.2 stable ed1daf0bf, Windows x64 and GL Compatibility renderer; isolated throwaway project and immutable v1.7x archive; procedural SDF/caves, edits, material/LOD/collisions, async stale publication, streaming/reopen and owner visual gates. **No Godot+vendor extension process has been run** and the vendor ZIP is not assumed retained after F1 temp cleanup.

## Hard open decisions — NOT authorized
- Native DLL loading/execution, installing addon even in sandbox, new third-party binary download, test harness execution with extension, F2 runtime, additional dependencies, owner GUI tests with vendor, F3/F4/P0.2 implementation, backend production selection, ADR-0002 acceptance and product redistribution each require separate owner decision under their own scope.
- Before any F2 execution: explicit owner approval of isolated execution environment, risk acceptance for local internal **nonredistributed** testing, exact Godot/package hashes, optional fresh archive download, process/network containment, stop/cleanup policy and test budget. License uncertainty does not silently disappear for internal testing.
- Exact retained DLL code, full runtime imports and redistribution notice sufficiency remain unknown; source-exact notice draft is not product/license certification; unsent upstream inquiry requires separate authority to send.
- Project's domain authority, wide spatial keys, deterministic generator/material IDs and revision guard are not replaced by third-party APIs; no performance evidence/benchmark and no engine/export compatibility proof has been produced.

## Next decision
Review integrated F2 planning specification and either explicitly authorize a bounded G1 isolated execution ticket or defer for provenance, isolation or legal-risk reasons. Any later F2 runtime developer PR gets independent SHA-specific review and owner visual outcome before merge. Exact merge log in docs/status/CHANGELOG.md.
