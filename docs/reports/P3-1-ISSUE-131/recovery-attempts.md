# Integration-gate operational recovery record

Source under test remained the pinned PR #129 production commit `92b442d7f5b605c7bc9c48fac2aceea9d71813aa`. All attempts used disposable Godot profiles and output directories; no user world saves were opened.

1. `headless-benchmark`: an early opt-in harness run completed its 50 edit rows and one population traversal with exit 0. It was superseded because the population workload had only one repetition.
2. `headless-benchmark-final`: 50/50 edit rows and 20/20 population rows passed, then entity setup failed at registry discovery with `legacy_population_rules_missing`; process exit 1. This exposed a harness test setup problem, not a production failure.
3. `headless-benchmark-r3`: repeated the 50 edit and 20 population rows successfully, then entity setup failed with `package_root_unavailable`; exit 1. The sample package root was being resolved from unsupported `res://mods/examples` in the cold standalone environment.
4. Correction: use the project parent path for the checked-in examples directory (`ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir().path_join("mods/examples")`), matching the production stream's fallback. The source remained test-only.
5. `entity-benchmark-r4`: final corrected entity-only run passed 98 commands, restart and identity reconstruction. `--check-only` also passed.
6. `final-all-r5`: one fresh all-phase run with the corrected test setup passed 50 edit rows, 20 population rows and the entity scenario, exit 0, no failed rows. This is the authoritative integrated benchmark result.

The raw logs, exit codes and the failed-run process samples are retained under `results/raw/`. Attempts 2 and 3 are failures in harness setup and are not presented as passing integrated runs. The final run's environment omitted the optional `P31_SOURCE_SHA`; see `results/run-attribution.json` for the exact-source external binding and for the empty embedded-field disclosure.
