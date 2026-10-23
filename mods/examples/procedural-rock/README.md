# Declarative Procedural Rock Example

This is a loadable data-only package for the P0.3 source-tree prototype. It registers `official.example.procedural_rock:basalt_stack` through the same manifest loader and content registry used by the bundled first-party package.

The package manifest pins the exact `firstparty.core_rocks` version `1.0.0`. The loader validates schema, engine version, namespace, dependency, content roots and definition data before registration. Package JSON is read as data; no package script is loaded or executed.

To exercise discovery, registration, lookup and deterministic recipe evaluation, run from the repository root:

```powershell
godot --headless --path .\game --script res://tests/declarative_mod_tests.gd
```

For a user installation, place declarative package directories under Godot's `user://mods` directory and pass that fixed root to `DeclarativeModLoader.discover_and_validate()`. The current prototype supports exact engine version `4.7.2` and schema version `1` only. It does not download, install, execute, or persist mod content.
