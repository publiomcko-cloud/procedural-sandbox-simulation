# P3.1 R9.6 — Shared Topology Contract and Execution Gate

Date: 2026-10-29

Issue: [#196](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/issues/196)

Disposition: **P3_1_R9_6_BLOCKED_WITH_EVIDENCE**

## Scope and provenance

This branch adds a test-only topology ledger and its focused GDScript checks. It does not modify Candidate A, Candidate D, production terrain, persistence, schemas, saves, Candidate C, or Candidate B. The R9.5 frozen manifest remains SHA-256 `1610c535f98a11e26ca1890c0d99addf4316fbcaa7ec9cdb7dfaa71cf5bb3972`; the triangle cutoff remains `cross_squared > 1e-12`.

| Item | Identity |
|---|---|
| R9.5 oracle parent | `895dbca3c6dd58bb9adacd63fb39c3ad524226ff` |
| R9.6 topology-contract commit | `f69e39e0ed4a67fe7f26b771cdec7ce70f53ddda` |
| Diagnostic import direct parent | `895dbca3c6dd58bb9adacd63fb39c3ad524226ff` |
| Diagnostic helper blob at import | `8f0f08b76f1d1a21089061c163858b43bd924918` |
| Diagnostic helper physical SHA-256 at import | `1a3a1caa4e4edfe7de78d697cbd2272c89368e489a125a57e91044fafb7228ff` |
| Current oracle HEAD | `9319c7d21cab4febda2a2f0f75f31cc7826eac8d` |
| Current HEAD parent | `bc99419f4894b26889b2c290f84a741454784ceb` |
| Current helper blob / physical SHA-256 | `a585941a19d5477e4b45f3c01d9730946489401a` / `b7cac8b0c11cc57b4272ae6e105ff676fffe2cfb8621484b60a62218f27d3d29` |
| Current topology-test blob / physical SHA-256 | `442c9aa2f17991eefd50d454bbe31f1023376a33` / `6ab30612056a6723280e83acacb486ed97b2980c5811562ca63e0430710f2270` |
| Godot 4.7.2 binary | `C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe`, SHA-256 `c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643` |

## Topology-first diagnostic artifact

`p3_1_r9_6_surface_topology.gd` stores stable root identities, points and owners; triangle-to-root connectivity; face arcs; per-edge required/emitted incidence; a deterministic topology hash; connected surface components; ROI-boundary ownership labels; and connected open-edge loop diagnostics. Geometry rejection is recorded separately from graph validity. A valid graph with rejected triangles explicitly reports `geometry_realization_complete=false`, so recording required connectivity cannot be mistaken for a mesh fix.

The test script includes positive closed-pair/component cases, deterministic insertion-order hashing, boundary ownership, duplicate-root and duplicate-triangle rejection, and a negative partial-realization case proving that a cutoff-rejected triangle stays in the required graph and exposes missing adjacency/open edges. It contains **38 assertion call sites by static count; none has executed**. It does not yet capture A/D tetrahedron root identities or produce replacement geometry. It is a shared diagnostic contract, not Attempt 1 for either candidate.

## Execution evidence and stop reason

Three exact-source editor-import attempts were made on the pinned helper commit `f69e39e0ed4a67fe7f26b771cdec7ce70f53ddda`. Each Godot process exited `-1073741819` after printing `ERROR: Parameter "mem" is null` and a native signal-11 backtrace. PIDs were 36184, 14664 and 50016. The first two inherited the host process environment; an evidence correction sidecar records that the second attempt's process JSON profile field was not actually applied. The third attempt did set isolated `APPDATA`, `LOCALAPPDATA`, `TEMP` and `TMP`. All complete stdout/stderr/process records are retained under `evidence/godot-import/`.

The separate `--script` test launch did not produce expected stdout, stderr or process JSON. PowerShell reported `OutOfMemoryException` and a runspace-shutdown stack overflow. Its PID and process-start status are UNKNOWN; a subsequent process snapshot showed no remaining Godot process. The test is not counted as passed or failed and was not retried.

At the failure snapshot Windows reported 66,944,192 KB total visible memory, 18,266,348 KB free physical memory, 77,184,192 KB total virtual memory, and only 89,908 KB free virtual-memory commit. `vmmemWSL` held about 26.19 GB private bytes / 6.98 GB working set. No owner process or VM was terminated to recover commit headroom. The only project-side residue is an empty ignored `.godot` directory in this new worktree; no project scene, benchmark, or user save was run. Because the import crashes before a successful parser gate, the R9.6 diagnostic tests and candidate geometry experiments remain unexecuted.

### Execution matrix

| Stage | Source | Result | Meaning |
|---|---|---|---|
| Godot version | pinned binary above | PASS, exit 0, `4.7.2.stable.official.ed1daf0bf` | identity only |
| Editor import attempt 1 | `f69e39e...`, PID 36184 | native crash, `-1073741819` | no import pass |
| Editor import attempt 2 | `f69e39e...`, PID 14664 | native crash, `-1073741819` | no import pass; inherited profile |
| Editor import attempt 3 | `f69e39e...`, PID 50016 | native crash, `-1073741819` | no import pass; isolated profile |
| Topology script | current source `9319c7d...` requested | process attribution UNKNOWN | no assertion result |
| Candidate A/D focused matrix | none | NOT RUN | no geometry attempt consumed |
| Full `scripts/validate.ps1` | none | NOT RUN | blocked before candidate execution |

## Prior causal evidence retained

R9.5 already established that the old nine ray hit/miss disagreements are an ROI-comparison defect: full-field roots outside or on the cropped Y endpoints were compared with an ROI mesh. The corrected 25-ray zero-edit ROI comparison was 0/25 disagreements for A, C and D. That bounded finding is not reopened here.

The X+ openings remain a geometry defect under the unchanged cutoff. A has 8 internal openings / 7 rejected microtriangles; D has 13 / 8. Existing-vertex loop caps cannot satisfy the cutoff. R9.6 did not reproduce or improve those meshes because runtime validation could not start.

## Research consulted (hypothesis input only)

- Baktash, Gillespie, Crane, “Subgrid Marching Tetrahedra,” ACM TOG / SIGGRAPH 2026, author research page: https://www.markjgillespie.com/Research/SubgridMarchingTets/index.html. Its explicit connectivity/root-count representation motivates retaining root connectivity before geometric realization; it is not imported, executed, or asserted equivalent to the current tetrahedral field.
- Schaefer, Ju, Warren, “Manifold Dual Contouring,” IEEE TVCG 13(3), 2007, DOI https://doi.org/10.1109/TVCG.2007.1012. It motivates considering topology-aware local surface representations, but its dual-contouring/octree method is not directly applied to A/D.
- Lengyel, “Transition Cells for Dynamic Multiresolution Marching Cubes,” Journal of Graphics, GPU, and Game Tools 15(2), 2011, DOI https://doi.org/10.1080/2151237X.2011.563682. It motivates a separately owned interface hypothesis only after local geometry tests pass; no transition patch was implemented.

No external code or binary was downloaded or executed.

## Disposition

The campaign is **BLOCKED_WITH_EVIDENCE** at the runtime resource gate. No Candidate A/D correction attempt has been implemented; A=0/3 and D=0/3. There are no before/after X+ geometry numbers, new SDF residuals, ray results, CPU measurements, or final validation totals for R9.6. The R9.5 baseline values above remain historical context only.

Next authorized execution requires sufficient host commit headroom or an owner-approved environment recovery. Do not terminate `vmmemWSL` or other owner processes automatically. After recovery, first run the current oracle import and 38-check topology script; only then pin an A1 topology-first attempt before its first candidate execution. Keep A2 refinement and A3 face-owned interface contingent on measured A1 results. Preserve all five F2-G1 holds.
