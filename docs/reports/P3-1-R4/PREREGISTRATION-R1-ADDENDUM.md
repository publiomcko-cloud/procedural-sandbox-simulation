# P3.1 R4 Preregistration Addendum R1

Date: 2026-10-26. This addendum freezes the remaining measurements before the
90-row campaign in `campaign-manifest.json`. It supplements, and does not
replace, `PREREGISTRATION.md`.

## Picker and collision evidence

Each workload process evaluates three deterministic vertical rays against the
canonical full ledger, exact chunk projection, B snapshot and C snapshot. The
ray starts in air inside the snapshot halo and uses the production v1 SDF
picker. Each arm records picker elapsed p50/p95/p99, density sample counts,
hit/miss agreement and hit-point displacement. This is a headless function
measurement, not InputEvent latency, collision, GPU, or presented-frame data.
The baseline has no terrain collision provider; collision queries are
`NOT_MEASURED`, not replaced with a synthetic collision claim.

## Entity snapshot sharing experiment

The bounded model registers one immutable content-addressed terrain snapshot
once and attaches multiple resident entity views that hold separate mutable
state dictionaries and entity revisions. It exercises two logical writers
using expected entity/terrain revisions, stale-write rejection, identity
stability and a test-only 1 MiB serialized-store ceiling. This is a sequential
logical concurrency model; it does not claim thread safety, production entity
storage, durability, physics or multiplayer behavior.

## Campaign artifact and summary semantics

The committed manifest enumerates 18 frozen workload scenarios across five
process repeats (90 rows), including exact command input, source-manifest and
inventory hashes, seed, generator, region/chunk, sequence range, architecture
arms and resolution schedule. A manifest row is one benchmark process; its
resolution list is serialized as an array even when it contains only 0.5.
Architecture-arm/resolution combinations are metric rows within that process,
not separate process launches. This clarifies the preregistration's composite
measurement identity. Each process has isolated profile, output,
storage and derived-cache directories. The runner reserves the row before
process creation, records process identity and raw streams, enforces one launch
per row, and right-censors a timeout without retrying it. A scenario's later
repeats stop after its first timeout or functional failure. Evidence-custody or
source-identity failures stop the entire campaign.

`metrics-per-run.csv` retains each process and arm. `scenario-summary.csv`
reports medians and ranges across completed process-level statistics; it does
not pool within-process query samples across processes. Missing and censored
rows remain separate. The decision criteria in the R4 preregistration remain
prototype-selection screens only; product budgets and geometry-error limits
remain `OWNER_TO_DEFINE`.
