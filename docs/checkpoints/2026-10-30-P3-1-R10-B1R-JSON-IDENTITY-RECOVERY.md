# P3.1 R10-B1R JSON identity recovery

Date: 2026-10-30
Draft PR: #208
Source before correction: `ba8882daf422a761822c6da9df22f4a0d638ea72`

## Attempt classification

The exact-source preflight gates passed on `ba8882d`. A candidate domain was
generated twice with identical physical SHA-256
`7118fa5059ce4b5561b28473f9ef7c6ee8a04c2f9e15b97e1b6d6fb1cd68e346`, and
its identity was pinned before the geometry invocation in
`B1R_DOMAIN_PIN_RECEIPT.json` (SHA-256
`fbdc06d6a48896c7dac90ba77e8c9ab68ed4aa389cbfdc83ff6e04d9c9a4cf5c`).

The single attempted `geometry-b1r` process was created (PID 1480, parent
33984) and exited 3 after 2,062 ms, before any candidate search. It emitted
`R10B_BLOCKED` with
`b1r_domain_integrity_or_identity_failed` /
`candidate_domain_identity_not_bound_to_current_run`; there was no
`R10B_ATTEMPT_COMPLETE` marker and no solver terminal result. Thus no valid
direct-geometry result exists and the B1R geometry slot remains unconsumed
under the preregistered attempt accounting.

The expected and parsed identity records matched in all frozen strings and
floating values. The serialized JSON parser represented integer-valued fields
such as revision `2` and ROI cell indices `8` as floating Variants
`2.0` and `8.0`; the harness used strict Dictionary equality, so an otherwise
identical physical domain was rejected before solver invocation. Both artifact
SHA-256 checks had passed. This was a harness JSON-type compatibility defect,
not a geometry feasibility result.

## Bounded source correction

The correction adds recursive identity comparison that:

- requires identical dictionary keys and array lengths/order;
- compares strings, booleans and other values by type and value;
- accepts an integer-expected field from JSON only when its numeric value is
  finite, exactly integral, within the exactly representable binary64 integer
  range, and equal to the expected integer;
- compares expected floats only to finite numerically equal values.

The same comparator is used at both the campaign's current-run binding boundary
and the direct solver's independent domain-loader boundary. The physical
candidate-domain hash remains mandatory and is checked before JSON parsing.
The domain-audit self-test now loads a JSON round trip, exercises successful
integer normalization, rejects a fractional revision identity, and retains
the existing tampered-owner rejection.

This correction does not change candidate generation, pruning, root positions,
boundary, cutoff, solver limits, geometry, or acceptance thresholds. A new
source SHA requires all exact-source preflight gates and a newly generated,
newly pinned domain artifact before the one B1R geometry attempt.

No retry of the failed process was made. No triangulation search, production
validation, mixed-LOD check or full E2E was run. All five F2-G1 holds remain.
