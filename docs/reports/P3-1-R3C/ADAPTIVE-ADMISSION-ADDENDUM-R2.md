# P3.1 R3C — Adaptive cache admission addendum R2

**Frozen for the final campaign at source `042ff7b5d4e5ce8bb54e8ac146518e700854d36b`.** This version supersedes the preceding adaptive addendum before any final performance process was run. It corrects only the provenance of the fresh-process disk-hit term. The original R3C preregistration and all R3B acceptance gates remain unchanged.

## Frozen selected workload

Only `P31.R3C.NONPERIODIC.DISTRIBUTED.N0256.v1` exercises the adaptive admission branch. Its command-list SHA-256 is `a61069eb72732db6ae2d12c80bc56f7d868cb9c4a2a0b3c9db0ee7a95df87cef`; manifest SHA-256 is `0facbab3b76bdbee78741d02f57bc8c631c3610cfb8758fd42ac868855a0ee03`; seed is `135031`; region is `(-31,-64)`; chunk is `(2,2)`. The policy probe builds that chunk once and has `R=0` expected future revisits. Diagnostic cache hits elsewhere in the harness do not count as expected revisits for this separate probe.

The preserved one-process baseline at source `d445d12261c42650d7d6a2b7909c002afd0b2b33`, `evidence/pre-optimization/nonperiodic-profile-attempt3/NONPERIODIC-DISTRIBUTED-256/runs/P31.R3C.NONPERIODIC.DISTRIBUTED.N0256.R01/output/result.jsonl`, measured canonical LOD1 p50 `107124 us`, first cache lookup `118536 us`, and builder `105254 us`. Of the eight baseline R3C workloads, D256 has the lowest absolute canonical LOD1 p50; distributed N0640 is next at `108259 us`. Those exploratory values select the workload; they are not final acceptance evidence.

## Policy and cost model

The scenario freezes the expected revisit count `R=0`. For `R=0`, the policy calls the canonical LOD1 builder and returns the result without cache identity encoding, cache lookup, serialization, lock acquisition, or disk publication. The existing path is preserved for `R>0`; the experiment adds no other adaptive variant.

For paired comparison, `B` is the same process's median canonical LOD1 build time, `U` is the unconditional cold path measured from before cache construction through verified publication, `P` is the policy path measured from before cache construction through bypass, and `H=U-B`. The reported expected net benefit is `R*(B-D)-H`. `D` is populated only from that independently launched process's `cache_first_lookup_us` when `cache_first_layer` is exactly `disk`; it is unavailable (`-1`) otherwise. The scenario runner shares a cache root only across the five serial process repetitions for that one scenario, so later repetitions can establish an actual fresh-process disk hit. `R=0` makes `D` immaterial to the admission decision.

Within each of five independent processes, two separate cold roots are used in fixed order: unconditional then bypass-policy. Each arm reconstructs the identity from the same immutable snapshot and invokes the same canonical LOD1 builder. Its end-to-end timer includes root creation and inventory, identity creation, meshing, and either complete checked cache publication or bypass. The unconditional and policy meshes must be byte-identical to the paired canonical mesh. The policy must report one bypass and zero disk bytes. All five paired rows are retained. Apply the main preregistered 25% cold-overhead-reduction condition to the median paired overheads for this single workload, without pooling scenarios; if either median overhead is nonpositive, the reduction is not meaningful and cannot be claimed as passed.

## Concurrency and failure boundary

Cache writers use an exclusive lock directory around inventory refresh, temporary cleanup, same-key winner revalidation, quota eviction, unique temporary creation, and atomic rename. Lock acquisition is bounded at five seconds; failure returns the canonical mesh uncached. A process crash while holding the lock may leave a stale lock and disable cache writes until the disposable root is discarded. No stale lock is reclaimed by guessing process identity. Temporary files are removed only while holding the lock and are never loaded as cache entries. These are derived-cache behaviors; the ledger remains the only authority.

No workload, scenario bytes, expected values, or numeric gates may be changed after this addendum is committed. A later implementation change requires a new source identity and preregistration before final measurements.
