# P3.1 R12-C Stage 0 and C1 preregistration — 2026-10-30

## Authorization and scope

Owner-authorized R12-C test-only topology-to-geometry campaign. This checkpoint records the isolated worktree and Stage 0/C1 preregistration; it does not claim execution or geometry acceptance.

- Repository origin: https://github.com/publiomcko-cloud/procedural-sandbox-simulation.git
- Worktree: C:\r12c-20261030
- Branch: exp/p3-1-r12-c-topology-geometry-realization
- Base/head at branch creation: eede76dbc8cb967a646679dd137eac0cdb9538aa, direct parent 6e412ab186faecda1717aa4aa938e1d7e7296cbc
- R10-BX measured source: 42012b476adb1369a5b281dfe8dac2a38b700751
- R10-B1R source ancestor: 6f28273d0113f93678034b9e482140e73e765721
- PRs #207, #208, #209 remain separate and unmodified; no production integration or merge.

Existing workspace, stashes, .gd.uid files, user saves, and all five F2-G1 holds are preserved.

## Scientific starting point

R10-BX's bounded graph preprocessing exceeded its 180-second pre-search limit and was INCONCLUSIVE. No SAT/UNSAT result exists. R12-C will not resume root-mandatory SAT search.

The campaign reuses the frozen Candidate D field and R9.2 equal-LOD case. The Stage 0/C1 procedure, cutoffs, resource policy, and separate future hypothesis preregistration are in [PREREGISTRATION.md](../reports/P3-1-R12-C-CAMPAIGN/PREREGISTRATION.md).

## Current result

No Godot execution has occurred at this checkpoint. Stage 0 fixture builder and process runner are being prepared on the isolated branch. First runtime gates remain cold import, script check-only, then Stage 0 fixture generation. C1 is not executable until Stage 0 passes and its fixture is pinned.

All geometry results, if produced, remain experimental and headless/UNSCORED. No product tolerance or production architecture is adopted. The five F2-G1 holds remain unchanged.
