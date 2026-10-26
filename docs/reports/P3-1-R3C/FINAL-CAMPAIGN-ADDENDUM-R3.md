# P3.1 R3C — Final campaign addendum R3

**Frozen before any accepted final-campaign measurement.** This addendum supersedes the R2 adaptive-addendum source pin solely because the first attempted final process exposed a pre-scenario harness defect. It makes no change to workload bytes, scenario selection, expected outputs, or any numeric gate from the original preregistration and R2 adaptive addendum.

## Source and preserved preflight failure

The executable benchmark, cache, digest utility, test, and campaign runner source for the next final campaign is pinned to code commit `8f7d59d5aab724438f065a3ba6d38986a16b3183`. The full campaign HEAD is the commit containing this addendum; every process record must report that exact HEAD.

The first attempted process at prior HEAD `2e7cfb9a665b5b8d8abcb71b133733e5c52b6513` is retained at `C:\Users\PUBLI\AppData\Local\Temp\p31-r3c-final-2e7cfb9a665b5b8d`. It failed before `scenario_started` or any benchmark sample with `r3c_frozen_fixture_digest_mismatch`. The cause was that the R3B checksum sidecar format contains both the digest and exact filename, while the harness compared the entire line to a digest-only value. The harness now validates exactly the format frozen by each fixture family: R3B requires `<lowercase SHA-256><two spaces><exact command basename>`; R3C requires exactly the lowercase SHA-256. The sidecar utility has positive and negative tests. The prior attempt is not an R3B/R3C measurement and is not replaced or deleted.

The runner now queries CIM for a child engine immediately after `Start-Process` returns, before its first polling interval, then continues the existing polling and image-hash checks. This only closes a short-process observation window; it does not accept missing attribution. Any run lacking verified process identity still blocks the campaign and remains retained.

## Final-campaign boundary

Use unchanged R3B inputs and all eight R3C nonperiodic inputs, five independent processes per workload, serially. Preserve all previously frozen acceptance gates. Confirm the fixture file/manifest hashes before launch. Each started scenario has one launch only; any process that begins and fails is retained, with no automatic retry. The selected D256 adaptive probe remains as specified in `ADAPTIVE-ADMISSION-ADDENDUM-R2.md`; all other scenario and cache measurements retain the original unconditional path.

No source edits, threshold changes, or workload changes are authorized after this preregistration commit. A further source correction requires a new exact source identity and a replacement addendum before another final-campaign process.
