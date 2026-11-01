# R6 target-attempt accounting addendum

Date: 2026-11-01 20:50 UTC  
Issue: #218  
Source under audit: `836a2cd8e681dfb35f0bbaa5f1f55b1bfcc59b0f` (parent `69648002dc961301cbf789107453a718a206ca64`)

This addendum preserves each raw attempt artifact. It corrects the ledger interpretation only; no raw JSON was edited.

| ID | Source SHA | Raw outcome | Procedure accounting |
|---|---|---|---|
| R6-01 | `63a4c44f1dc18eaffdd42c1b54f969973ae88012` | Pre-geometry tooling failure: `zero_vertex_inventory_disagrees_with_frozen_constructor` at `(0,0,4)`, tetrahedron 0. The R6-A corrected inventory was incorrectly compared with the raw frozen constructor inventory. Search/E/F and target geometry did not start. | **Not consumed**; D0/pre-geometry correction. Transcript: [attempt 01](evidence/attempts/r6-target-attempt-01-pregeometry-failure.txt). |
| R6-02 | `d9f5a6b02729ddc779d81dda5d772b9df520ed83` | D search returned `PARTIAL/WALL_TIME_CAP`: 16 examined, 67 generated, queue 40, 30,127 ms. | **Consumed.** The raw JSON says `target_attempt_consumed=false`; this was an accounting field defect. The bounded scientific D search had started and reached its wall cap. Corrected here without changing the raw file. [Raw result](evidence/attempts/r6-target-attempt-02.json). |
| R6-03 | `13c47e94452d658018975d7aa5074e6dec4abc08` | `PARTIAL/WALL_TIME_CAP`: 119 examined, 407 generated, queue 178, 30,362 ms. | **Consumed.** [Raw result](evidence/attempts/r6-target-attempt-03.json). |
| R6-04 | `69648002dc961301cbf789107453a718a206ca64` | `PARTIAL/WALL_TIME_CAP`: 556 examined, 1,254 generated, queue 288, 30,003 ms. | **Consumed.** [Raw result](evidence/attempts/r6-target-attempt-04.json). |
| R6-05 | `836a2cd8e681dfb35f0bbaa5f1f55b1bfcc59b0f` | `EXHAUSTED/FINITE_CAUSAL_SEARCH_EXHAUSTED`: 844 examined, 1,254 generated, queue 0, 28,811 ms. | **Consumed.** Search ended by finite candidate exhaustion; no state/time/queue cap was hit. [Raw result](evidence/attempts/r6-target-attempt-05.json). |

**Count: 4 of 5 valid target attempts consumed; one remains unused.** R6-05 exhausted the enumerated causally adjacent cavity candidates within the procedure limits. This supports only bounded-search exhaustion for this pinned fixture and search policy. It does not prove global geometric infeasibility. R6-E/F and all downstream gates did not start because no boundary-feasible cavity was produced.