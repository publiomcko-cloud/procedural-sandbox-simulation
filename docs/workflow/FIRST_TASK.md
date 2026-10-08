# First Codex developer assignment — P0.0

**Goal:** Establish and verify reproducible Godot 4.7.2 bootstrap, improve the starter headless test coverage and quality gates. No terrain backend installation yet.

**Read:** `AGENTS.md`, setup, architecture, contracts, P0 spec, workflow.

**Worktree:** `feat/phase0-prototype` created from accepted baseline. Avoid editing `main`.

**Tasks:**
1. Inspect actual project state; report engine version, baseline command outputs, and failures.
2. Correct any real bootstrap test/import defects; keep GUI scene minimal.
3. Extend script tests for fixed-seed deterministic pseudo-generation of a small pure-data region; document its algorithm/version and assert identical outputs irrespective of request order. Do not pass it off as the final terrain generator.
4. Add failure tests for invalid inputs and a clean test report.
5. Record exact commands and OS details; update quality documentation if implementation changes.

**Success:** `pwsh -File scripts/validate.ps1` succeeds on Windows with pinned Godot; no third-party dependency introduced; independent reviewer can reproduce; minimal scene visually launches. Provide commit SHA and structured handoff.

**Do not:** build full world, install Voxel Tools, claim Phase 0 completed, merge, or make unilateral architecture changes.
