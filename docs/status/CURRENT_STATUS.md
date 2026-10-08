# Canonical project status — 2026-10-08 (P0.1-F1 accepted; F1.5 authorized)

Verify current Git refs before treating this snapshot as live. Repository: private publiomcko-cloud/procedural-sandbox-simulation.
Authority: docs/PROJECT_CHARTER.md, accepted ADR-0001, docs/workflow/PROJECT_MEMORY_PROTOCOL.md. **ADR-0002 remains PROPOSED/DEFERRED.**

## Integrated and accepted
- P0.0 Godot 4.7.2 bootstrap, deterministic fixture tests (52 developer-reported assertions), scene/camera checks (18), and owner-confirmed visible F5 cube; implementation PR #2 merged as b8bd49b325b9a33e320442211736cf8b85c23b12. Reviewer inspected source without independent Windows execution.
- P0.1 backend comparative research PR #7 merged as b27b4e90ca19d7e83f34003de488d063f00399eb; independent research review #8 merged as a1171450e4178399f3130790368dc093be176c65. No backend selected.
- P0.1-F0 v1.7x source/artifact compatibility inventory PR #10 (reviewed e8af422c4c29fc86e1e3ba63fed766ffc69e9c95) merged as 3c2c50f3b19f162711aee22dd3421a687064ba5c; initial failed review #11 and passing review #12 preserved as eef5d53fe9d14a97f324631e133441729ea728bb and c39edf72e1ff8d660eb4b96ac305771f7f64daa8.
- P0.1-F1 static artifact inspection and corrected safety suite PR #14: reviewed head d86755e4623fa018db7c7096c74ac4316e961d00; **merged** as a30329d6cac071bfa1b281aea3e6b297a4314fae. Original finding review PR #15 merged as 7161efb39cf8f47091c9ba4562f8c9f9666a1628. Passing review PR #16 merged as 166de84a411cef9c7727653c6b5cdb3143374fce. Owner approved all merges 2026-10-08.
- Accepted F1 developer evidence: official GodotVoxelExtension.zip v1.7x measured at 54,457,774 bytes with independently developer-computed SHA-256 600737572a5e25541ba6f503e842a3717ba19afafa5474510a6ceff995a1d2d8 matching GitHub metadata; 34 entries, 134,335,779 declared expanded bytes, 29 descriptor mapping references including Windows debug/release DLLs; corrected PowerShell synthetic suite 64 assertions/34 cases/0 failures developer-reported. Static CI checks passed. ChatGPT source-reviewed but did not re-execute PowerShell or inspect raw binaries on Windows. F1 artifacts and SHA verification stored at docs/artifacts/; no vendor DLLs or ZIP were committed.

## Current authorization
Owner authorized **P0.1-F1.5 source/build-provenance and license-notice investigation only** after F1 acceptance and integration. Controlling ticket: docs/specs/P0.1-F1.5-BINARY-PROVENANCE.md.
Read pinned source/build scripts, public release/CI metadata, dependency licenses, and build provenance; write evidence-backed research and handoff in a new draft PR. No native artifact download, loading, compilation, runtime, installation, addon adoption, distribution certification or direct contact with maintainers.

## Open issues / not authorized
- Exact Windows v1.7x DLL third-party static linkage remains UNKNOWN. F1 ZIP has project MIT LICENSE.md but no separately bundled third-party notices. Source-tree SQLite/LZ4/meshoptimizer/FastNoiseLite/FastNoise2 presence does not prove binary linkage. Do not assert license compliance or violation without build evidence.
- No tested compatibility with official Godot 4.7.2 GL Compatibility, renderer/export targets, vendor async mesh/collider revision fencing, wide-coordinate domain mapping or performance benchmarks. First-LOD edit constraints documented but not tested in project.
- **F2 remains NOT AUTHORIZED**: loading vendor DLL, running Godot extension, installing plugin into game, or any runtime experiment needs an explicit subsequent owner decision after independent review and evidence.
- ADR-0002 backend selection not approved. F3/F4, P0.2/P0.3/P0.4/P0.5, V1 and V2 remain incomplete.
- Prior F1 acceptance does not imply safe production distribution or legal clearance.

## Next step
Assign Codex F1.5 on a clean feature worktree from updated origin/main. The developer produces pinned-source dependency/notice evidence matrix, source build/packaging provenance, uncertainty/maintainer-question list, documentation-only handoff and DRAFT PR. An independent SHA-specific evaluation follows. Owner separately approves merges and any F2 gate. Exact preceding merge ledger in docs/status/CHANGELOG.md.
