# R6-D5 — boundary proof frontier exhaustion (PARTIAL)

**Terminal:** `R6_D5_PARTIAL_WITH_RESUMABLE_PROOF_FRONTIER`\
**Date:** 2026-11-04\
**Branch:** `exp/p3-1-r12-cxr-r6-realization-map-cavity`\
**Measured source:** `8d1ec27ad44ecba574865f1f39ae1eba05444bb5`\
**Parent:** `e6e33d8076d81eb4969bccf7c0330620cb93ddfb`

## Frozen candidate and result

D5 resumed the D4 frontier for the selected D2 candidate signature
`234ebf1520e00ee52ab93281d07b542ca4561f33e17f720f81baaed61ce0a1e6`.
It processed only required boundary obligations 2, 3, and 4, with 117 clipped
regions per obligation. The D4 result SHA-256 is
`6f70a61b7ed3fb7f602832ca29b7d1d922a98b8ea3cef98ec565880ffa2466cc`; the
reconstructed D4 region inventory SHA-256 is
`811a1de43ca389b3a2d0a6946654f6c55c0676ab8cddbc373ff5ee7d8456f319`.

| Boundary obligation | Regions | Proven empty | Partial | Legal option | Status |
| --- | ---: | ---: | ---: | ---: | --- |
| 2 | 117 | 19 | 98 | 0 | `OBLIGATION_PARTIAL` |
| 3 | 117 | 24 | 93 | 0 | `OBLIGATION_PARTIAL` |
| 4 | 117 | 19 | 98 | 0 | `OBLIGATION_PARTIAL` |
| **Total** | **351** | **62** | **289** | **0** | **PARTIAL** |

The latest region records retain 289 resumable region keys and 1,903 frontier
cells (852 for boundary 2, 251 for boundary 3, and 800 for boundary 4). They
contain 547 certificate leaves; 2,904 subdomain cells were processed. Across
those leaves, the rejection causes are 121 required-arc candidate-edge
crossings, 36 required-arc endpoint-inside cases, and 116 frozen-cutoff upper
bounds. Region-local empty results do not establish emptiness of an entire
obligation. In particular, no obligation is complete and no binary32 search was
reached for unresolved continuous subdomains.

The six pre-existing legal options regenerated unchanged at boundary indices
`[0, 1, 5, 6, 7, 8]`. No new legal option was found. The candidate was not
promoted, no graph was built, and the frozen solver was `NOT_RUN`. The D5
diagnostic/prequalification execution consumed no scientific target attempt.
No global infeasibility or candidate-wide impossibility is claimed.

## Frozen identities

- D4 authoritative result: SHA-256
  `6f70a61b7ed3fb7f602832ca29b7d1d922a98b8ea3cef98ec565880ffa2466cc`.
- D4 reconstructed 351-region inventory: SHA-256
  `811a1de43ca389b3a2d0a6946654f6c55c0676ab8cddbc373ff5ee7d8456f319`.
- D4 inventory runner result: SHA-256
  `e76cfefd280ab0583d0d737e4b19ae50a9e4ac61b12217bba243fa0dae84938a`.
- R6-D authoritative input: SHA-256
  `226bdbbc9fa61692548d0d38eb5eb0a1f2a96802c4a97049d5f30206f15272f3`.
- Frozen graph identity: SHA-256
  `8a560270de725d11a88cff210b66ddd7f98df6ba1018d49eb5f26fa961baf249`,
  126 supports; topology SHA-256
  `4ecbb2496fb34f1cf3c05a60192f76bdce7a52ec3148d02ba041510b804a8c95`;
  volume SHA-256
  `ecf86bce57e82cd0949d4576e7b7ebe4d1ef8d0633ac7f6d540fd56df6573be2`.
- Frozen gates remain cutoff `cross_squared > 1e-12`, residual epsilon
  `1e-7`, and barycentric epsilon `1e-7`.
- Godot: `4.7.2.stable.official.ed1daf0bf`; console binary SHA-256
  `c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643`.

## Method and resumability

The D5 helper reconstructs each clipped polygon and deterministic initial
triangle fan, then applies conservative interval rejection for required-arc
crossing/endpoint-inside and the frozen cutoff. Unresolved triangles are split
by deterministic longest-edge bisection. Each run processes at most 64 interval
nodes per region; bounded residue remains `REGION_PARTIAL`. The append-only
JSONL journal stores the candidate signature, obligation, deterministic region
key, source and clipped geometry identities, analytic/continuous/binary32
states, required-arc, field, barycentric, cutoff and legal-option results,
certificate leaves, proof hash, processed-node counts, cap and terminal reason.

The journal has 642 records: the initial 351 region records and 291 appended
revisions from the corrected-source resume. The final JSON has 351 latest
region records and marks resume idempotency true. A controlled contract fixture
verified that a split run followed by resume reproduces the direct run. Proof
leaves are checked by the project’s deterministic runner and contracts; no
independent external interval-proof verifier was run.

## Source corrections and validation

The first runner invocation on source
`e6e33d8076d81eb4969bccf7c0330620cb93ddfb` wrote evidence but did not terminate
and emitted `UNKNOWN_NOT_CAPTURED` in its marker. That failed process log and
its partial result are retained; they are not used as the final terminal
classification. The runner was corrected in source commit
`8d1ec27ad44ecba574865f1f39ae1eba05444bb5` to emit the exact terminal status and
exit after writing output. It also records accurate pointwise field and
barycentric gate values. The same frontier journal was resumed, not reset.

The captured process command was:

```text
C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe --headless --path game --script res://tests/prototypes/p3_1_r12_cxr_r6_campaign.gd
```

The launcher supplied `R12CXR_R6_MODE=r6d5-boundary-frontier`,
`R12CXR_R6_OUTPUT=C:\Users\PUBLI\AppData\Local\Temp\R6D5-boundary-frontier-8d1ec27-20261104.json`,
`R12CXR_R6D5_EXECUTION_SOURCE_SHA=8d1ec27ad44ecba574865f1f39ae1eba05444bb5`,
`R12CXR_R6D5_JOURNAL_PATH=C:\Users\PUBLI\AppData\Local\Temp\R6D5-region-journal-e6e33d8-20261104.jsonl`, and D4 input paths to the byte-pinned files in `evidence/r6-d4/` (authoritative result JSON and continuous-domain inventory). The runner verifies both D4 input hashes before processing. The original launcher environment transcript was not captured; these values are reconstructed from the final result, runner contract, and preserved file identities.

On the corrected source, Godot cold import passed; R6 contracts passed
158 assertions with 0 failures; campaign `check-only` passed; and the D5 run
exited successfully with the exact PARTIAL marker. Contract shutdown prints
renderer/ObjectDB leak warnings, but exit status was 0 and the `158/0` marker
was present. `git diff --check` is recorded at publication. These are
implementation-agent Godot runtime results (L4), not independent review or
owner GUI acceptance.

## Evidence and next step

Raw JSON results, the append-only journal, import/contract/check-only logs, both
runner logs, their exact byte counts, and SHA-256 values are in
[`evidence/r6-d5`](../evidence/r6-d5/). The first-run defect is preserved beside
the corrected run. Resume from the 289 final `resumable_region_keys` in the
corrected result and journal; keep all frozen identities and gates unchanged.
Continue deterministic region-level certification. Do not start binary32 search
without a certified continuous witness. If a legal option appears, add it
deterministically, regenerate the complete graph, and run the frozen solver.
Otherwise retain PARTIAL until the three obligations are proven empty or
complete.
