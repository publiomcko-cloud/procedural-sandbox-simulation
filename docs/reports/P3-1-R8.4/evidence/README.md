# R8.4 raw evidence

This directory retains the complete R8.4 parser/import attempts, the single focused candidate process and the one full validation run. No failed evidence was overwritten.

| Path | Contents | Result |
| --- | --- | --- |
| `parse-001/` … `parse-004/` | Cold editor import and harness parse/check-only process records and logs. The first two harness checks expose source parse errors that were corrected before the candidate was allowed to start; final `parse-004` passes. | Final parse gate passed; superseded failures preserved. |
| `run-001/` | One frozen R8.4 diagnostic: input/source pins, complete root-oracle samples, frozen X+ reproduction, candidate progress, candidate topology/result, process metadata and raw stdout/stderr. | Exit 1 due the first mandatory X+ conforming gate; later geometry gates not run. |
| `validation-001/` | Complete raw full-validator output and execution/profile metadata. | Exit 0; 14,990 assertions / 0 failures in 20 assertion suites; three nonfatal camera-vector warnings. |
| `SHA256SUMS.txt` | SHA-256 for each file below this evidence root except this inventory itself. | Recompute before review. |

The candidate process record attributes the only geometry attempt to source commit `f6bfef10f6be0f903980123f7cbb9073bda98184` and Godot PID 53048. The process did not access production saves or alter protected project paths. Full-validator subprocess PIDs were not recorded individually; process-level attribution for those subprocesses is not claimed.

Inventory coverage: 48 files / 5304555 bytes before the checksum file. Generated with SHA-256 after evidence completion; the inventory does not hash itself.