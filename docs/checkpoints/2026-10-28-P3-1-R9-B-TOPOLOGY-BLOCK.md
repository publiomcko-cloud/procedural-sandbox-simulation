# P3.1 R9 Candidate B topology-block checkpoint

Date: 2026-10-28

Candidate B's one-run frozen zero-edit gate completed within the node budget but failed exact topology: 110 internal open edges. It emitted 598 triangles and had no reported degenerates, nonmanifold edges, or winding inconsistencies. It stopped before edits and seam cases. Its current refinement is one-level Hermite/QEF refinement over parent-cell connectivity, not a balanced adaptive leaf mesh; refinement and quad telemetry labels are also inaccurate as documented in the report. No attempt was made to hide or rerun the geometry failure.

The common Godot 4.7.2 regression suite passed 21 suites/21,464 assertions/0 failures; this is not candidate geometry acceptance. See [R9-B results](../reports/P3-1-R9-B/RESULTS.md) and raw SHA-256-indexed evidence. All five F2-G1 holds remain unchanged.
