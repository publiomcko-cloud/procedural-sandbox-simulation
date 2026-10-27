# R6-V raw attempt index

The complete original files below are retained from C:\Users\PUBLI\AppData\Local\Temp\p31-r6v-causal-48f51ad9fd9e461d962eb52788179b68. Failed attempts are preserved and excluded from final measurements.

| Attempt | Exit | Disposition |
|---|---:|---|
| Initial class/parser check | 1 | Diagnostic script parse errors: out-of-scope identifiers variant, cross_sections, chunk_seams, macro_seams and stats, plus inferred next-cell type; fixed only in test-only diagnostic. Raw check.stderr.log retained. |
| First focused diagnostic | 1 | Invalid sub-minimum brush radii were rejected; diagnostic continued into mesh normals and emitted nonfinite-normal warnings. Not measurement evidence. |
| R2 focused diagnostic | 0 | 117 assertions passed, but only 8 chunks were built, causing incomplete cross-section coverage/fallback. Retained, excluded. |
| R3 focused diagnostic | 0 | Final 16-chunk run, 213 assertions, 12 scenario/policy records, no stderr. This is the focused R6-V result. |
| Full project validation | 0 | Godot 4.7.2 scripts/validate.ps1, 21,464 assertions, zero failures. |

Later clean check records are check-r2 through check-r6. The final check-r6 reports clean=true. After a trailing-whitespace-only source normalization, a final standalone check-only also exited 0 with empty stderr; see final-source-check.*. Import and every attempt log, duration, exit code, process id and timeout marker are kept in focused-attempts/; the final isolated full validation log/environment are in the parent evidence folder.
