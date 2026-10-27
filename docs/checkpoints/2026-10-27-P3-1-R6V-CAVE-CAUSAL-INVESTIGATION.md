# P3.1 R6-V cave-shape causal investigation — 2026-10-27

## Scope and identity

Owner-authorized isolated diagnostic for Issue #145. No production integration, schema changes, merge or Issue #108 implementation. The experiment is based on R5-V HEAD 234e73d0e39504559c4df6869ae302c74e58d8a; that commit directly follows R4 051249642611a7fa9cd2006be450bad0e184e4ee. Production reference remains 92b442d7f5b605c7bc9c48fac2aceea9d71813aa. The report and raw logs are in docs/reports/P3-1-R6V/.

## Findings

Compared coarse-boundary/center-residual, canonical refined-cell boundary/center-residual, coarse-boundary center-plus-face residual, and their combination across a zero-edit cave, one wall carve, and ordered center fill/wall carve. Each snapshot was materialized over sixteen chunks.

Coarse interpolation preserves measured scalar continuity but expands the canonical 1.75-unit vertical cave opening to 4.875 units and creates radial surface-displacement p95 0.03361 units. Canonical samples on selected refined-cell boundaries restore the measured opening and reduce displacement p95 to 0.002109, but create up to 0.153837 density gap at interfaces with unrefined neighbors. The combined policy still has 0.040883 gap. Curvature selection raises the zero-edit refined-cell count about 6.1% and median build time about 28.1% without changing the observed coarse-boundary cave section. These results localize the main deformation to boundary interpolation/anchoring and show that the tested local boundary substitution is nonconforming.

The diagnostic did not implement a collider or a complete extracted-mesh contour/T-junction test. Those items remain unmeasured; no no-crack, collider, or geometry-acceptance claim is made.

## Validation and disposition

Final focused diagnostic: exit 0, 213 assertions, zero failures, 3 field snapshots x 4 policies, 16 chunks; no stderr. Full Godot 4.7.2 validation: exit 0, 21,464 assertions, zero failures, 507,647 ms; three existing colinear-camera warnings and no parser/script/runtime errors. Full evidence is in the report folder. Focused preliminary parse/setup/8-chunk failures are preserved and excluded from final results.

P3_1_R6V_BLOCKED_WITH_EVIDENCE because the required collision-proxy and complete mesh-topology observations were unavailable. This does not block source review of the bounded diagnostic, but the geometry question is not fully closed. No approximate representation is approved. All five F2-G1 holds remain.
