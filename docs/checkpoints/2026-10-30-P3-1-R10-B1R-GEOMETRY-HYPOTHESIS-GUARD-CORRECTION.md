# P3.1 R10-B1R geometry hypothesis guard correction

Date: 2026-10-30
Draft PR: #208
Source: `9d0217758c84ebd6031fbb1c533943894d1dac10`

## Preserved pre-solver attempt

The single candidate-domain audit passed on this SHA, including the serialized
JSON identity round-trip and tampered identity/owner negative checks. The
candidate domain itself was pinned before geometry:

- Domain SHA-256:
  `d51dab976c155dfbfcdb25a1914654d2cdc63cb3f71d8f9938eaace51ba23a2b`.
- Candidate triangles: 7,608; roots: 73; boundary roots: 34.
- Pin receipt:
  `B1R_DOMAIN_PIN_RECEIPT_R2.json`, SHA-256
  `898e80c3d88dfb0959e9178a5451d6b6d681be6485fe89099e674fd0727796d5`.

One geometry-stage process (PID 30884, parent 29940) exited 3 after 2,035 ms.
It emitted `R10B_BLOCKED` with `unimplemented_geometry_hypothesis` before
loading the pinned domain or calling the solver. The supplied ID was the exact
preregistered
`R10B1R_DIRECT_CONSTRAINED_TRIANGULATION_FEASIBILITY`, but only the domain
stage guard had previously been aligned; four other dispatch/qualification
guards still used the old shortened ID. There is no solver terminal result.
Under the campaign's explicit accounting this is a pre-geometry harness
failure, not a valid B1R result, so the sole geometry slot remains unconsumed.

Two attempted PowerShell evidence records from this stage are preserved but
invalid: their hashtable used bare `true` instead of `$true`, and
`ConvertTo-Json` wrote literal JSON `null`. Their SHA-256 is
`74234e98afe7498fb5daf1f36ac2d78acc339464f950703b8c019892f982b90b`.
The valid domain pin remains in the separate R2 receipt above; no geometry
attempt was made while that receipt-generation issue was corrected.

## Bounded correction

The campaign now defines one `B1R_HYPOTHESIS_ID` constant and uses the shared
`_is_b1r_hypothesis()` predicate for domain-only gating, supported-hypothesis
dispatch, solver execution, search-result selection, equal-LOD qualification
and mixed-LOD scope reporting. This prevents the domain and solver branches
from accepting different labels. No solver math, candidate pruning, root,
boundary, cutoff, geometry, or acceptance criteria changed.

The corrected source SHA must pass every exact-source gate, create a new
candidate-domain artifact, pass the JSON round-trip audit and receive a new
write-once pin receipt before another geometry-stage invocation.
