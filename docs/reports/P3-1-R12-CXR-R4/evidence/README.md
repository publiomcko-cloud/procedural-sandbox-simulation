# R4 evidence layout

- `final-f48990e/` is the authoritative exact-source evidence for commit `f48990e25ffb1d377e02a9182240cabe35c815eb`; it includes isolated Godot profile run logs/process records, the D1/D2/D3 result, source and evidence SHA-256 inventories, and source-integrity metadata.
- The sibling `preflight/` and `d1_d2_d3/` folders preserve the earlier pre-commit exploratory run on `b2480bc71fe9c9616426d378feb00e3e33e785f2`. That run is superseded and is not counted as final validation.
- A pre-commit D1 attempt and a wrapper call that stopped before process creation are retained as diagnostics, not as target attempts. The pinned final run is in `final-f48990e/`.

No target attempt for `R9.2.SEAM.XPLUS_EQUAL.v1` was started in R4.
