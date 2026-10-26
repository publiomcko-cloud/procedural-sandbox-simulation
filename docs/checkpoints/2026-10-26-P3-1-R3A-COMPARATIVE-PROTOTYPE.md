# P3.1 R3A — Ledger, Mesh Cache, and Density Snapshot Prototype

Date: 2026-10-26  
Repository: `publiomcko-cloud/procedural-sandbox-simulation`  
Production baseline and prototype code parent: `92b442d7f5b605c7bc9c48fac2aceea9d71813aa` (PR #129 source).  
Prototype code commit: `ffb5ccc4e59c03913b179f2b2db05cddd90ab1cd`.  
Last verified `origin/main` at preflight: `5997a76d345f45bf86edfe83f690336391e8be27`.  
Draft evidence PR: [#137](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/137), based on `feat/p3-1-scalable-terrain-storage`; open, unmerged.  
R3 architecture: [PR #136](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/136), draft.  
Reference benchmark: [Issue #131](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/issues/131) / [PR #134](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/134), draft.

## Event and disposition

Owner-authorized isolated R3A comparison is implemented under `game/tests/prototypes/` with byte-pinned Issue #131 input fixtures. Production source, world schemas, user saves, PR #129/#134, native components and Issue #108 were not changed or run. The schema-2 ordered terrain ledger remains the only modification authority. A and B artifacts are rebuildable derived outputs; C is a rebuildable sampled representation.

Final campaign `campaign-06` passed 9/9 rows with 23/23 frozen-input hash checks, zero harness failures, zero stderr and exit code 0 on pinned Godot 4.7.2. Its only `P31_R3A_PASS` establishes harness completion, not product/performance acceptance. Three mesh repeats are insufficient for independent-run p95/p99 conclusions. Process samples recorded engine RSS-style working set/private values; no GPU, VRAM, actual display frame, publication or GUI measurement was performed.

Full `scripts/validate.ps1` had two failures in the pre-existing procedural-object regression on its first run. Without source/test changes, a fresh-profile focused run passed that suite 638/638, and a fresh-profile full rerun passed all **21 groups / 21,464 assertions / 0 failures**, exit 0. Both the failed and successful complete logs are retained. The successful run recorded the existing unavailable junction fixture and three nonfatal camera colinearity warnings. This means the current candidate has a passing full rerun and a preserved intermittent baseline-suite result; reviewers should assess that flakiness rather than treating the initial failure as nonexistent.

## Experimental findings

* **A — exact replay pruning + LOD1:** zero mismatches in tested full/indexed/fast probes and selected mesh vertices. Distributed 8,192 LOD1 sample p50 improved from 103.365 to 83.386 ms, but concentrated 8,192 regressed from 6,502.572 to 21,008.214 ms. The candidate still scans every operation and adds predicate cost. Reject this implementation.
* **B — persistent derived CPU mesh cache:** integrity, restart hit, corruption rejection/rebuild, and edit invalidation paths ran. Warm cache was useful on the selected concentrated cases, but distributed 8,192 warm LOD1 read cost 174.762 ms versus 103.365 ms canonical builder; the whole-ledger key invalidates unrelated chunks on every append. It caches CPU arrays only, not `ArrayMesh` publication/GPU data. Consider only a future explicitly authorized chunk-local experiment with complete dependency keys, limits and ledger fallback.
* **C — 0.5-unit Float64 density lattice:** building the selected 2,277-sample lattice costs ~0.25 sec at 256 ops and ~9.7–9.8 sec at 8,192 ops. One appended operation updates the existing lattice in ~2.5–85.9 ms, matches a full rebuild at all stored nodes and persists/reloads with zero lattice mismatch. However every edit row had two off-grid probe mismatches; LOD normal differences ranged ~16°–157°, and the canonical cave control found 9/9 centerline points open while the snapshot found 0/9. Reject as a continuous-SDF replacement. Grid exactness is not continuous-field equivalence.

See [complete report and raw evidence](../reports/P3-1-R3A/REPORT.md), [prototype specification](../specs/P3-1-R3A-COMPARATIVE-PROTOTYPE.md), and evidence SHA-256 index. No acceptance threshold or backend decision was invented.

## Limits and next gate

These headless measurements do not establish smooth gameplay, rendering or presentation latency. Results are from one host/process and one final campaign, using fixed reference traces, not multi-process scored measurements. No world-scale cache/disk quota, many-chunk snapshot memory bound, corruption campaign under OS termination, or cross-platform determinism was established. The density snapshot remains approximate between samples. Recommendation: no production adoption; exact replay candidate A is rejected, C is rejected for exact SDF use, B may receive separate owner authorization for a scoped chunk-local design/prototype. Independent source/evidence review and separate owner decision are required. All five F2-G1 holds remain unchanged.
