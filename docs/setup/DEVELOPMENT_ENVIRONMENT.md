# Environment definition and reproducibility

## Pinned inputs
- Godot: `4.7.2.stable` (standard build), reassess only through ADR.
- OS baseline: Windows 11 x64. Headless Linux CI is supplementary.
- Languages: GDScript first; native C++/GDExtension only after measured need and ABI compatibility review.
- Tooling: Git, VS Code, PowerShell 7. Python 3.11+ optional; Godot itself has no Python runtime dependency.
- Renderer and GPU/CPU/RAM: record per benchmark in `benchmarks/RESULT_TEMPLATE.md`.

## Directory ownership
- `game/`: runnable Godot project.
- `docs/`: design and operating specs; ADRs immutable after acceptance.
- `mods/`: sample external content specs, not yet runtime-loaded.
- `scripts/`: host validation.
- `benchmarks/`: repeatable profiles and target environment.

## Local configuration
Never commit tokens, credential files, private mod archives, editor user caches, exports or machine-local absolute paths. Use `GODOT_BIN` environment variable rather than writing tool locations into source.

## Validation levels
L0 static structure check; L1 Godot headless import; L2 Godot script smoke test; L3 playable GUI / collision test; L4 deterministic and performance benchmarks; L5 independent reviewer reproduction. Initial starter supports L0–L2 when a suitable Godot binary is installed.

## Before approving a dependency
Record license, pinned upstream URL/revision, engine version compatibility, threaded operations, save/edit/LOD limitations, benchmark results, and removal strategy. Never silently bundle unreviewed Voxel Tools binaries.
