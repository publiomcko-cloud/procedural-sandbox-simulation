# Contract preflight attempt 01 — retained failure

Command: Godot 4.7.2 console, headless, `--path C:\r92-contract\game --script res://tests/prototypes/p3_1_r9_2_contract_tests.gd`.

Observed output from the process capture:

```text
Godot Engine v4.7.2.stable.official.ed1daf0bf - https://godotengine.org
SCRIPT ERROR: Parse Error: Invalid argument for "find()" function: argument 1 should be "int" but is "PackedByteArray".
   at: GDScript::reload (res://tests/prototypes/p3_1_r9_2_diagnostic_base.gd:290)
SCRIPT ERROR: Compile Error: Failed to compile depended scripts.
   at: GDScript::reload (res://tests/prototypes/p3_1_r9_2_contract_tests.gd:0)
ERROR: Failed to load script "res://tests/prototypes/p3_1_r9_2_contract_tests.gd" with error "Compilation failed".
   at: load (modules/gdscript/gdscript_resource_format.cpp:46)
SCRIPT ERROR: Invalid call. Nonexistent function 'load_manifest' in base 'GDScript'.
   at: _run (res://tests/prototypes/p3_1_r9_2_contract_tests.gd:11)
```

The dependent script compile failure caused the SceneTree test process to remain alive after the script error. It was stopped with Ctrl+C; process exit was 1. This was a recoverable R9.2 harness defect, not a candidate scenario execution. The exact byte substring lookup was replaced with bounded bytewise matching. No production file or manifest expectation changed. The first attempt's output was returned directly by the process tool; this file is a transcript record, not a byte-for-byte stdout/stderr artifact.
