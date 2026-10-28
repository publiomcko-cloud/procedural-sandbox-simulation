# P3.1 R9 Candidate D materialized-volume topology block

Date: 2026-10-28

Candidate D materialized and reloaded one frozen zero-edit float32 volume in its isolated Godot profile, then extracted a mesh with its declared MT extractor. The first topology gate failed: 1,121 internal open edges, 152 ROI-boundary opens and 355 nonmanifold edges. It stopped before edits, seams and picker/collider cases. The volume payload was 9,828 bytes; serialized file 9,935 bytes. Corruption handling was not actually exercised by reload; only a modified byte copy's digest difference was asserted. See [R9-D results](../reports/P3-1-R9-D/RESULTS.md) and preserved raw volume/log hashes.

Full common Godot 4.7.2 validation passed 21 suites/21,464 assertions/0 failures, but this does not accept Candidate D geometry. All five F2-G1 holds remain unchanged.
