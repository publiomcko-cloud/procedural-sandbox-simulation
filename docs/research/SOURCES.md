# Source-backed tool choices (checked 2026-10-08)

- Godot version archive: https://godotengine.org/download/archive/ — 4.7.2 stable dated 2026-08-18; 4.8 dev series exists, not selected.
- Godot 4.7.2 download: https://godotengine.org/download/archive/4.7.2-stable/
- Official CLI reference: https://docs.godotengine.org/en/stable/tutorials/editor/command_line_tutorial.html — `--headless`, `--editor --import`, `--script`, `--path`.
- GDExtension configuration: https://docs.godotengine.org/en/stable/engine_details/engine_api/gdextension/gdextension_file.html
- Godot threading: https://docs.godotengine.org/en/stable/tutorials/performance/thread_safe_apis.html
- Godot runtime resource pack loading: https://docs.godotengine.org/en/stable/tutorials/export/exporting_pcks.html
- Voxel Tools documentation: https://voxel-tools.readthedocs.io/ — candidate for SDF/voxel terrain; compatibility and addon revision MUST be verified during P0.1 before use.
- Voxel Tools source: https://github.com/Zylann/godot_voxel — check licensing and Godot version/GDExtension build compatibility.
- OpenAI Codex overview: https://developers.openai.com/codex/ — authenticate and verify extension/model selections within installed UI.

## Research questions to resolve via recorded ADRs
- Voxel Tools edit/collision/LOD streaming behavior and official version matrix.
- Terrain provider adapter limits on chunk-border edits and asynchronous command completion.
- Save snapshots vs event logs under abrupt termination.
- Serializable mod schemas and version migration behavior.
- Long-running hydration and thermal stability under multiresolution updates.
- Native floating-point determinism across GPUs/OS variants.

No link in this file grants permission to install a dependency or run arbitrary third-party code.
