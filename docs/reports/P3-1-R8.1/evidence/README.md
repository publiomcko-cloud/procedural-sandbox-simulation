# R8.1 raw evidence

This directory preserves all five focused attempts (including the two harness bring-up failures), both full validation attempts, process records, raw stdout/stderr, and structured phase results. `SHA256SUMS.txt` inventories committed evidence files. Each `godot-profile` directory contains disposable generated profile/cache state and is intentionally excluded from version control; the process records retain the isolated paths used. No profile was copied into another attempt.

`validation-001` predates the final evidence fields in the diagnostic source. `validation-002` is the full `scripts/validate.ps1` run on the final measured source bytes and is authoritative for the complete regression result. Focused run-005 is authoritative for the final bounded geometry observations. `DIAGNOSTIC_COMPLETE` is a collection-complete marker, not a geometry pass.
