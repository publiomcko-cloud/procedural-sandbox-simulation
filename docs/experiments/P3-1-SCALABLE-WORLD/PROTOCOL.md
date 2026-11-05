# Scalable world load + fidelity qualification

Status: experimental qualification on `exp/p3-1-shared-surface-e2e-success`.

## Objective

Qualify the existing materialized-SDF candidate against the two remaining scalability risks:

1. edit history growth must not make normal world/chunk load replay the complete journal;
2. checkpoint/compaction must preserve the current gameplay surface and shared regional boundary.

The source of truth remains the ordered append-only edit journal. Gameplay recovery uses materialized SDF tiles plus only the uncheckpointed tail. Historical journal segments remain available for audit/rebuild but are excluded from the hot gameplay load path.

## Structural acceptance gates

- every accepted edit has a monotonically increasing sequence;
- checkpoint tail is bounded by the configured checkpoint interval;
- after a final checkpoint, hot restore reads only `head.json`;
- normal chunk acquisition reads spatial pointers/blobs lazily and reads **zero journal segments**;
- lifetime/archived operation counts survive process-style restore;
- LOD0 gameplay-lattice SDF samples after compaction equal an uncompacted complete-ledger oracle exactly;
- chunk vertex geometry and triangle counts equal the complete-ledger oracle after repeated compaction;
- the shared X-region boundary signature equals the complete-ledger oracle and keeps zero bad incidence / zero T-junctions;
- the same test is parameterized by `--edits=N`, so load magnitude can be increased without changing code or gates.

No universal wall-clock threshold is claimed from GitHub-hosted hardware. Timings are emitted as evidence so target-hardware gameplay budgets can be applied separately.

## Important fidelity boundary

Materialized tiles preserve the canonical current gameplay lattice (0.5 m) exactly. Off-lattice historical SDF is reconstructed by trilinear interpolation for gradient/normal queries. Therefore this candidate guarantees current rendered surface geometry at the production lattice; it does not claim bit-identical continuous-field history at arbitrary sub-lattice coordinates.

## Default CI load

The hosted default is 4,096 deterministic edits with a checkpoint every 128 edits. This is a structural regression gate, not a declaration that 4,096 edits is the world limit.

For local stress testing, use the same script with larger `--edits` values such as 100000 or 1000000, subject to machine time/disk limits.

## Terminal marker

`SCALABLE_WORLD_QUALIFICATION_PASS: assertions=<n> failures=0`
