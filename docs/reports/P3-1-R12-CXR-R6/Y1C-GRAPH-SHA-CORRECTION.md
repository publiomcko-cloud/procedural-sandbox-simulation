# R6-Y1C candidate-graph SHA correction

This note records the canonical candidate-graph identity used by the completed R6-Y1C P1 certification.

- Correct candidate graph SHA-256: `8a560270de725d11a88cff210b66ddd7f98df6ba1018d49eb5f26fa961baf249`.
- Any prior R6-Y1C report or checkpoint containing a one-character-different candidate-graph SHA is superseded by the value above.
- This correction is documentary only. It does not change the 126-support graph contents, the frozen solver result, the P1 domain certificates, or the terminal interpretation.
- The finite 126-support graph is `UNSAT_COMPLETE` only for that captured graph. The completed P1 certification separately establishes that the required P1 option domain is exhausted for the current seven-face cavity under the frozen R6 constraints.

A separate functional correction on PR #219 makes serialized boundary `first_zero_candidate_obligation` endpoints derive from the authoritative `boundary_edge_map`; this prevents future evidence from repeating the endpoint-duplication presentation defect.

No merge, release, protected-state change, or R7 transition is authorized by this note.
