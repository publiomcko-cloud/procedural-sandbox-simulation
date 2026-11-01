# P3.1 R12-CXR R3 attempt 05 pretarget freeze

Date: 2026-10-31 America/Sao_Paulo; process timestamps are UTC.

## Identity and prior attempt

- Repository origin: https://github.com/publiomcko-cloud/procedural-sandbox-simulation.git
- Last verified main: 5997a76d345f45bf86edfe83f690336391e8be27
- Branch: exp/p3-1-r12-cxr-per-cavity-continuation
- Exact code source: 4734e6cb0c80cde086ea86e7d8afcda983e3a24b; direct parent 43afc868c9d86678834b3469feef6fd5b8b83180.
- PR #214 remains OPEN/DRAFT/UNMERGED. PRs #212 and #213 remain OPEN/DRAFT/UNMERGED.
- Attempt 04 on source 2964bd55 is preserved as PARTIAL and will not be rerun. It started the R3 subset-search but crashed on a Dictionary-to-Array type mismatch before any field-support candidate attempt or candidate triangle was generated. Its independent result checkpoint and raw evidence remain in the index.

## Bounded source correction

The R3 selector now treats each base adjacency row as a Dictionary, reads and sorts its keys before expansion, and returns a deterministic fail-closed result for malformed non-Dictionary rows. The contract suite adds four assertions for a multi-triangle subset expansion, candidate/node evidence, stability under reordered seeds/adjacency insertion, and malformed-row rejection. Only the contract test and test-only field-support realizer changed. No frozen geometry inputs, budgets, topology/cutoff criteria, production paths, or acceptance thresholds changed.

## Exact-source pretarget evidence

Execution used a fresh detached checkout at 4734e6cb and the pinned Godot 4.7.2 executable with isolated APPDATA/LOCALAPPDATA/TEMP/TMP profile.

1. Editor import: exit 0, no parser/script errors.
2. CXR contract suite: exit 0, marker R12CXR_CONTRACT_TESTS_PASS, 153 assertions, zero failures, empty stderr.
3. Campaign check-only: exit 0, marker R12CXR_CAMPAIGN_CHECK_ONLY_PASS, attempt R3_CHECK_20261031_09, exact source/campaign/realizer/fixture pins, target R9.2.SEAM.XPLUS_EQUAL.v1.
4. Attempt-05 dispatcher control: exit 0; controlled child returned expected exit 23 and exact stdout/stderr; duplicate reservation and overwrite were denied; process termination confirmed; resource sample captured.
5. PowerShell parser results: dispatcher and launcher wrapper both have zero parse errors. New dispatcher SHA-256 b935c0dc34364ca85e2147968341bded9cf254404b6295319713263799243af0; wrapper SHA-256 aa882be39cf393bc0f0d8345c488efb2410fc0fe59f3343e31137124a5d0468d.

A first external assertion-count guard expected 152; the actual successful suite reported 153. That wrapper guard stopped before check-only. The successful test output/record is preserved and correctly classified in cxr-contracts-gate-classification.json; the test suite was not rerun. Campaign check-only then passed independently. No R3 geometry scenario has run on this source.

Raw logs, process records, inputs, source pins, the dispatcher, wrapper, summary and evidence hash inventory are under pretarget evidence. See pretarget-summary-v2.json and evidence-sha256-index.txt.

## Next step

At this checkpoint, R3_TARGET_20261031_05 for R9.2.SEAM.XPLUS_EQUAL.v1 is NOT_STARTED. The exact source checkout, fixtures, engine, isolated user profile, and a new durable dispatcher reservation path are frozen. The attempt-05 launcher must revalidate all pins and stop-loss conditions immediately before launch. If the target starts, it must not be rerun. Do not proceed to controls, ROI rays, later geometry gates, E2E, or scripts/validate.ps1 unless the equal-LOD gate passes.

This remains test-only research; no production adoption, schema work, Issue #108, merge, or release is authorized. Preserve all five F2-G1 holds.