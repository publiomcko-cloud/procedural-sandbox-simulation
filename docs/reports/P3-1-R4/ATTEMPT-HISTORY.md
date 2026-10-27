# P3.1 R4 campaign attempt history

## Attempt 1 — diagnostic, excluded from final measurements

- Source HEAD: `8b76e778b0f282a37aa11a229b795c423f581467`.
- Frozen manifest SHA-256: `c6fd895685304795101968ed1104385d31c3f4b1cf303fb26582b16a22666c31`.
- Original evidence root: `C:\Users\PUBLI\AppData\Local\Temp\p31-r4-campaign-312def8287844d5c90e563bca4fd4e9f`.
- The runner attempted rows in manifest order and stopped globally at row 11. It recorded 6 PASS rows, 4 FUNCTIONAL_FAIL rows, 1 INVALID_EVIDENCE row, and 79 NOT_RUN_GLOBAL_STOP rows.
- The four concentrated R3B failures exposed `r4_chunk_subledger.gd::as_snapshot()` returning aliased `Packed*Array` members. Appending to the projection mutated the previously captured snapshot used as C's base. C then applied the same final operation again. The fix returns independent packed-array values and retains explicit pre-append capture. A new focused regression checks snapshot isolation and exact C-vs-full voxel materialization.
- The nonperiodic R3C N0256 fixture uses pinned varying radii. The harness's former fixed-580-mm-only check rejected it before geometry evaluation. The corrected path preserves 580 mm for R3B inputs while validating and replaying each frozen R3C radius exactly within canonical ledger bounds.
- The old runner required PASS-only cave/picker/voxel diagnostics before distinguishing FAIL. It marked the valid frozen-input functional failure as INVALID_EVIDENCE, then globally stopped. The revised runner validates common source/run/input identity for both statuses, requires geometry diagnostics only for PASS, and treats substantive functional failures as per-scenario stop conditions while retaining true input-integrity failures as invalid evidence.
- No raw attempt was deleted or replaced. The original TEMP root is retained. Its files will be copied unchanged into this report's evidence package before final publication; its samples remain diagnostic and cannot be pooled with the final campaign.

## Final campaign

Pending at the time this checkpoint was written. A final campaign must use a committed source identity, the same frozen 90-row manifest and preregistered stop-loss, fresh evidence paths, one launch per row, no retry after a scenario has started, and must retain all PASS, functional failure, timeout, and NOT_RUN dispositions.
