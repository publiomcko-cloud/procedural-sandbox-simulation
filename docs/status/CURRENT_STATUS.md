# Canonical project status — 2026-10-08 (P0.1 research integrated)
Verify actual GitHub refs before relying on this snapshot.
Repository: private publiomcko-cloud/procedural-sandbox-simulation.
Architecture and product charter: docs/PROJECT_CHARTER.md and ADR-0001-BASELINE.md.
Durable-review rules: docs/workflow/PROJECT_MEMORY_PROTOCOL.md.

## Integrated and accepted
P0.0 Godot 4.7.2 starter validation, deterministic 52-assertion pure-data fixture, 18-assertion scene/camera structural regression, and visible reference cube confirmed by owner after camera fix. Developer reported automated tests pass; ChatGPT independently reviewed source but did not execute Windows/Godot. Implementation PR #2 merge: b8bd49b325b9a33e320442211736cf8b85c23b12. P0.0 acceptance does NOT imply complete terrain or Phase 0.
P0.1 desk research PASS_RESEARCH_WITH_CONDITIONS and integrated:
- Research PR #7, reviewed HEAD c1c7a8a32a851e50e0e92a0e4c03e231b303e778, merge b27b4e90ca19d7e83f34003de488d063f00399eb.
- Review PR #8, review document docs/reviews/2026-10-08-P0-1-RESEARCH-c1c7a8a.md, merge a1171450e4178399f3130790368dc093be176c65.
- docs/research/P0.1-TERRAIN-BACKEND-COMPARISON.md, docs/architecture/TERRAIN_ADAPTER_PROPOSAL.md and docs/decisions/ADR-0002-TERRAIN-BACKEND-PROPOSED.md are integrated as research/proposals, NOT final design or vendor approval.
- See docs/status/CHANGELOG.md for exact prior PRs/merge SHAs and retained failure/correction reports.

## Current owner authorization boundary
On 2026-10-08 the owner authorized merging PR #7 and #8 and PREPARING a bounded P0.1 candidate compatibility experiment. Authorized now: F0 public-source and artifact-metadata inventory, conceptual API feasibility and reproducible isolated-test plan, independent review. NOT authorized: third-party binary/archive downloads, installation, GDExtension execution, custom engine substitution, native builds, adding dependencies, complete terrain adapter implementation, changing ADR-0001, approving ADR-0002 or backend production selection. See docs/specs/P0.1-COMPATIBILITY-GATE.md for full authorized F0 task.

## Current risks and gaps
- Voxel Tools 1.7 GDExtension exact 4.7.2 compatibility and Windows/export artifacts unverified; publisher says extension newer/less tested. FastNoise2 feature parity and domain-to-vendor async hooks must be audited.
- Canonical density sign, units, precision, buffer conversion and stable ID/coordinate limits require gate tests before binding implementation.
- Zero reliable terrain benchmark, no selected target performance budgets, no owner-approved binary; runtime feasibility undemonstrated.
- P0.2 edit transactions/crash recovery, P0.3 mod registry, P0.4 simulation tiers, P0.5 Phase 0 gate and all V1/V2 releases incomplete.
- No assurance of enforced remote branch rules or independent CI status checks.
- Developer-reported uncommitted .vscode/extensions.json from P0.1 research worktree was left untouched; do not accidentally stage or discard without review.

## Next task / state for fresh agents
Owner may assign Codex F0 evidence-only work on a fresh branch from updated origin/main. F0 should stop with SHA-specific draft PR, artifact/license inventory and proposed F1 approval request. ChatGPT independently reviews F0, owner explicitly decides if exactly identified native artifact may then be downloaded and tested. Do not treat this status update as permission to execute F1.
