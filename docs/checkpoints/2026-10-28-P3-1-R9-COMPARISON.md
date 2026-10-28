# P3.1 R9 comparative checkpoint

Date: 2026-10-28

Four isolated R9 candidates were each compiled/imported, run once on the frozen zero-edit gate, and followed by the complete common Godot 4.7.2 validation. All common validations passed 21 suites/21,464 assertions/0 failures. Each candidate stopped at its first mandatory zero gate: A exceeded the 10,000 unique-sample ceiling; B and C each reported 110 internal open edges; D reported 1,121 internal opens and 355 nonmanifold edges. Candidate-specific downstream geometry, seam, picking, physics and performance gates therefore remain unmeasured. No winner is recommended.

Four isolated candidate draft PRs #170–#173 and a separate comparison draft PR are published against the R9 preregistration branch. See [complete comparison](reports/P3-1-R9-COMPARISON/RESULTS.md). PRs #162/#165/#166/#168 and all five F2-G1 holds remain unchanged. No production source or schema was changed and no PR was merged.
