# P3.1 R3C — Adaptive cache admission addendum

**Frozen for final campaign before any final R3C performance process.** This addendum supplements, and does not replace or relax, `PREREGISTRATION.md`. The source under test is the R3C experiment at `61ffe45de4126ba39e570954011d40767bd85371`; the final campaign commit will include this addendum and will be recorded separately. All production and R3B contracts remain unchanged.

## Selected workload and baseline evidence

The sole adaptive-admission workload is `P31.R3C.NONPERIODIC.DISTRIBUTED.N0256.v1`, with exact command-list SHA-256 `a61069eb72732db6ae2d12c80bc56f7d868cb9c4a2a0b3c9db0ee7a95df87cef`, manifest SHA-256 `0facbab3b76bdbee78741d02f57bc8c631c3610cfb8758fd42ac868855a0ee03`, seed `135031`, region `(-31,-64)`, and chunk `(2,2)`. Its first traversal builds the measured chunk once; this policy probe has **zero expected future revisits**. The separate cache correctness tests and normal benchmark observations do not count as future revisits for that probe.

Selection is supported by the preserved one-process exploratory baseline at source `d445d12261c42650d7d6a2b7909c002afd0b2b33`, `evidence/pre-optimization/nonperiodic-profile-attempt3/NONPERIODIC-DISTRIBUTED-256/runs/P31.R3C.NONPERIODIC.DISTRIBUTED.N0256.R01/output/result.jsonl`. It measured canonical LOD1 p50 `107124 us`, cache cold lookup `118536 us`, and cache builder `105254 us`. Across the eight baseline R3C workloads, this is the smallest absolute canonical LOD1 p50; the next smallest is distributed N0640 at `108259 us`. This single exploratory process selects the candidate only; it is not an acceptance result.

## Frozen policy and cost model

The policy input is a declared expected revisit count `R`, fixed by this scenario contract, not inferred from timing results:

- `R = 0`: build the canonical mesh and return it without identity encoding, cache lookup, serialization, lock acquisition, or disk publication.
- `R > 0`: preserve the existing unconditional derived-cache path. No other adaptive workload or policy variant is included.

For comparison, define `B` as the p50 canonical LOD1 CPU build time from the benchmark's paired baseline samples; `U` as the complete unconditional cold path from before cache construction through verified publication; `P` as the complete policy path from before cache construction through either verified publication or an explicit bypass; `D` as the measured fresh-process disk-hit latency; and `H = U - B`. The reported projected net benefit is `R * (B - D) - H`. With frozen `R = 0`, a positive cold cache overhead has no amortization benefit, so bypass is the deterministic result. The policy is a bounded prototype rule for this one declared workload, not an automatic production cost estimator.

Each of five independent processes uses two new, separate cache roots for the unconditional and policy arms, with order fixed as unconditional then policy. Both arms reconstruct the content identity from the same immutable snapshot and run the same canonical LOD1 builder. The timer begins before cache construction and ends after the result is returned; it includes cache-root initialization/inventory, identity construction, the builder, and the complete store transaction or bypass decision. `B` comes from the same process's paired canonical LOD1 samples. The policy result must be byte-identical to the canonical reference, report exactly one bypass, report zero stored disk bytes, and never count a bypass as a disk hit. The unconditional result must be byte-identical and show a verified cache publication. Preserve every per-process value and report the five-row distribution; the 25% overhead-reduction condition from the main preregistration is evaluated on the median paired cold overheads, without pooling scenarios. If either median overhead is nonpositive, report the percentage as not meaningful and do not claim the reduction gate passed.

No command bytes, expected results, workload selection, or numeric gates may change after this addendum is committed. Any implementation correction after preregistration requires a new independent source identity and a replacement preregistration before new final-campaign measurements.

## Cache concurrency and recovery boundary

All cache writers serialize quota inventory refresh, orphan temporary cleanup, same-key winner revalidation, eviction, unique temporary creation, and atomic final rename through an exclusive lock directory. The cache falls back to the canonical mesh if the lock cannot be acquired within the fixed 5-second bound. A process crash while holding the lock can leave a stale lock that disables further cache writes until the disposable cache root is discarded; stale-lock reclamation is deliberately not inferred from a PID. Temporary files are removed only after acquiring the lock. They are never read as entries. These are derived-cache recovery properties only; the ledger remains authoritative.
