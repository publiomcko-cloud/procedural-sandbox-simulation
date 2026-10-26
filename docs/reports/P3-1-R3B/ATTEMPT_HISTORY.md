# R3B attempt history

All attempts remain retained; only `evidence/campaign-02-final/` is the final performance dataset.

| Attempt | Evidence | Disposition |
|---|---|---|
| Initial runner smoke | `evidence/pre-final-operations/parser-failure/` | Harness parser failed before a benchmark scenario completed. This was a host/harness preflight defect; no measurement accepted. |
| Early 256 smoke | `evidence/pre-final-operations/oracle-defect-smoke/` | Process exited successfully, but its baseline path used an operation-dictionary oracle rather than the canonical packed snapshot. Functional smoke is preserved but excluded from correctness and performance conclusions. |
| Early focused compile/check attempts | External TEMP directories `p31-r3b-diag-*`, `p31-r3b-focused-*`, and `p31-r3b-check-*` | Early type/compile diagnostics were corrected before the final focused and canonical validation. These temporary scratch records are not part of the final result set; relevant parser-failure and false-oracle examples above are retained in-repository. |
| Campaign 1 (`ca599e0ce5fe623eb2f683c4e8e975bca8c6958a`) | `evidence/campaign-01-invalid-builder-timing/` | 40/40 functional rows passed and had zero exactness mismatches, but the cache's builder-duration metric was captured incorrectly (`0`). Excluded from all performance conclusions. The instrumentation was corrected and covered by focused assertions before Campaign 2. |
| Focused builder-timing smoke | External TEMP `p31-r3b-builder-smoke-2a82bd50d6f84e939f039b261845c95d` | Two processes showed the expected `rebuilt` then `disk` layer and nonzero in-cache builder timing. Retained in TEMP; superseded for final analysis by the full final campaign. |
| Campaign 2 (`9ec3818e47b4f42027995b12e3d7a40a72cbf7ca`) | `evidence/campaign-02-final/` | Final 40-process dataset; 40/40 process and result checks PASS. The preregistered cold-cache and distributed-8192 non-regression gates still fail as documented in `REPORT.md`; no rerun was made to replace unfavorable results. |
| Final canonical validation (`9ec3818e47b4f42027995b12e3d7a40a72cbf7ca`) | `evidence/canonical-validation/final-head-9ec3818/` | 21 groups, 21,464 assertions, 0 failures, exit 0. Isolated user-data profile. |
