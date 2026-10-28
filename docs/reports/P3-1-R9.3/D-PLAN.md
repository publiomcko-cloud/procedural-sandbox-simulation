# R9.3-D preregistration — bounded volume/extractor separation

Baseline evidence head: ac9357766736751b40b6afab69e48538063b5c59; measured candidate source: 6f0a4b41349e228a546646f758d6992c2aca6f9e. Frozen R9.2 manifest SHA-256: 1610c535f98a11e26ca1890c0d99addf4316fbcaa7ec9cdb7dfaa71cf5bb3972. Candidate is test-only.

## Hypothesis order
1. Separate storage/materialization integrity from extractor defects by extracting the exact reloaded float32 bytes with an independently authored reference extractor and comparing to Candidate D on identical samples.
2. Independently verify the reference extractor on analytic plane, sphere and saddle volumes, including deterministic output, expected sign convention, and bounded topology diagnostics. If reference validation fails, report extractor comparison NOT_COMPARABLE; do not call either output correct.
3. Only if the reference is verified, isolate topology/fidelity divergence per frozen zero/CARVE/FILL-CARVE/local rebuild and neighbor/seam fixtures. Keep D's storage lifecycle and corruption-on-disk check separate.

## Frozen limits before execution
Reuse only R9.2 rows/ROIs; no volume dimensions above the frozen manifest. One warmup plus five samples per row, at most two independent campaign processes. Per scenario 60 s; aggregate 600 s; max 10,000 volume nodes, 20,000 triangles, 512 MiB external process-tree peak. Stop immediately at limit. D's file remains disposable and unique per run; preserve expected/corrupt hashes and actual disk reread. Do not treat materialization or corruption rejection as geometry acceptance.