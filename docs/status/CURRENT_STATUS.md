# Canonical project status — 2026-10-08 (F1.5 accepted; F1.6 authorized)
Check live GitHub references before action. Repository: private publiomcko-cloud/procedural-sandbox-simulation.
Authority: docs/PROJECT_CHARTER.md, docs/workflow/PROJECT_MEMORY_PROTOCOL.md, accepted ADR-0001. **ADR-0002 remains PROPOSED/DEFERRED.**

## Accepted and integrated
- P0.0: Godot 4.7.2 bootstrap and deterministic fixture; developer-reported 52+18 assertions and owner-confirmed reference cube visible; implementation PR #2 merge b8bd49b325b9a33e320442211736cf8b85c23b12. No independent Windows execution by reviewer.
- P0.1 terrain backend comparative research PR #7 merge b27b4e90ca19d7e83f34003de488d063f00399eb; independent review #8 merge a1171450e4178399f3130790368dc093be176c65. No production backend approved.
- P0.1-F0 release/source compatibility inventory PR #10 merge 3c2c50f3b19f162711aee22dd3421a687064ba5c, original review #11 merge eef5d53fe9d14a97f324631e133441729ea728bb, passing review #12 merge c39edf72e1ff8d660eb4b96ac305771f7f64daa8.
- P0.1-F1 safe static archive inspection PR #14 merge a30329d6cac071bfa1b281aea3e6b297a4314fae; original review #15 merge 7161efb39cf8f47091c9ba4562f8c9f9666a1628; passing review #16 merge 166de84a411cef9c7727653c6b5cdb3143374fce.
- P0.1-F1.5 public upstream release-build provenance PR #18 corrected head 3d675398e9ae86fa5e66ec5edece07b8b3bdb3bf merged 42df9f0fdc333b932483c7af91a3b7ccf20fef6d. Original review #19 merged aa7cfa1d9405a4dffbd93ae58b7c892f6643d988; passing SHA-specific review #20 merged d6d4f05935b9165d336357ae787d1a641d08b455. All three were owner-authorized.
- Accepted F1 evidence: Voxel Tools v1.7x GodotVoxelExtension.zip, publisher and developer-computed matching SHA-256 600737572a5e25541ba6f503e842a3717ba19afafa5474510a6ceff995a1d2d8, archive 54,457,774 bytes, 34 entries, 29 extension path/icon mappings including Windows editor and template-release DLLs. Corrected developer-reported ZIP synthetic tests 64 assertions, 34 named cases, 0 failures; evaluator did not execute Windows tests.
- Accepted F1.5 evidence: upstream release workflow run 32419292967, Windows jobs 96587536545 and 96587536763, godot-cpp historical resolved revision 9c8aeff0f58ad030f3d1030e8262de1322cd0ccd. Both success logs explicitly link SQLite, LZ4, 16 meshoptimizer objects, 3 FastNoiseLite objects and target-specific godot-cpp static libraries. These are verified **publisher logged linker inputs**, not evidence of exactly what machine code remains in each final DLL.

## Current owner authorization: P0.1-F1.6, docs/source only
The owner authorized integration of PRs #18/#19/#20 and moving to a bounded **third-party notice and provenance resolution** effort. Binding F1.6 specification: docs/specs/P0.1-F1.6-NOTICE-RESOLUTION.md.
Developer should assemble an accurate, explicitly UNShipped draft notice bundle from exact pinned original LZ4/meshoptimizer/FastNoiseLite/godot-cpp copyright/license texts; assess SQLite public domain and FastNoise2/Tracy source/link exclusions, distinguish legal obligations from build inputs, provide risk/decision memo. Use an isolated feature worktree from main and create a draft documentation-only PR for SHA-specific independent evaluation.

## Unresolved / NOT authorized
- Current binary ZIP includes a project MIT license but no separate third-party notice texts, based on F1 manifest. Distinct LZ4 BSD and meshoptimizer/FastNoiseLite/godot-cpp MIT notices are implicated by logged inputs. It is NOT established what exact object sections survived optimization or what all transitive runtime dependencies are. No legal compliance determination and no package redistribution authorization.
- No GDExtension has been loaded/executed/installed. No verified compatibility with official Godot 4.7.2 or GL Compatibility, no runtime/export evidence, async mesh/collider revision fencing, deterministic SDF fixture equivalence, benchmarks or terrain adapter.
- F2 runtime/DLL loading, official engine use with extension, plugin installation, contacting upstream maintainers, distribution, approving ADR-0002 or adopting production dependency each require separate owner authorization. No automatic merge. P0.2-P0.5 and V1/V2 unfinished.

## Next developer task
Implement **documentation-only F1.6** per the binding spec, preserving full exact license texts and provenance. Record unresolved legal/technical risks and realistic options for later F2 *nonredistributed sandbox* versus actual redistribution; produce handoff and DRAFT PR; stop for independent review. Never treat F1.6 notice drafts as legal clearance or permission to execute vendor code. For accepted merge history see docs/status/CHANGELOG.md.
