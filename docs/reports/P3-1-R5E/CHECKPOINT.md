# P3.1 R5-E Checkpoint — 2026-10-27

Research remains isolated on `bench/p3-1-r5e-exact-cache`, based on R4 final `051249642611a7fa9cd2006be450bad0e184e4ee`. The focused harness now explicitly preloads `sdf_world.gd` for its cave probe. The expanded 8,192-operation run completed with 8,998 assertions, 16 exact-density failures, and worse query and mesh timings than canonical replay. The full repository validator completed separately with exit 0. This does not supersede the R5-E exactness failure. Do not integrate this prototype into production. Raw evidence is retained under `evidence/`.
