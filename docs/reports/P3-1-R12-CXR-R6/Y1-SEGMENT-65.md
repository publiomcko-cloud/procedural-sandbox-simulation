# R6-Y1 segment 65: partial support-domain result

## Disposition

Segment 65 of attempt `R6-Y1-COMPLETE-SUPPORT-20261102-01` closed at the synthesis time limit. Its status is `R6_Y1_SUPPORT_DOMAIN_PARTIAL_LIMIT` (`PARTIAL_LIMIT_SYNTHESIS_TIME`). This is **not UNSAT**, does not prove support-domain exhaustion, and does not show global structural incompatibility.

Source: `84a952e1935b284157f3aa1587ff317a1bc49a07`; parent: `b5d924bb3dbb47264c20ea5da47a56d2f522b8d1`. The source is published on the functional draft [PR #219](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/219). This evidence/report update is on the documentation draft [PR #222](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/222). Neither PR is merged.

Attempt accounting: six previous valid target attempts and one R6-Y1 target attempt (seven cumulative). The frozen seven-face cavity signature is `3745afdcb772193a3edf18f0abb48510aca58bd5893604c3cf9d60495e97878d`.

## Checkpoint and frontier

- Retained/raw unique supports: 126 / 126.
- Enumerator: `DETERMINISTIC_SOURCE_PAIR_REGION_STREAM`; finite candidate enumeration is incomplete.
- Last cursor: domain 1, facet 1, region 690, tetrahedron 1, candidate 0; 7,350 completed critical candidates and 40 completed support rows.
- Segment result: 356 unresolved continuous regions and 655 numeric frontiers.
- `resume-check` cumulative state: 8,693 frontiers and 2,073,712,582 tested binary32 triples. It reports 469 previously resolved region outcomes: 46 with no strict cavity intersection, 385 with analytic upper bound at/below cutoff, and 38 representable support witnesses. The current segment separately retains 356 unresolved regions.
- No candidate graph/solver or downstream gate ran from this partial segment. Equal-LOD, controls, ROI rays, volume, mixed LOD, deterministic repeat, full E2E and `scripts/validate.ps1` are not claimed as passed.

Frozen invariants remain unchanged: Candidate-D and topology authority, roots/arcs, field/volume, ROI, controls and holds, strict cutoff `cross^2 > 1e-12`, and epsilons `1e-7`.

## Raw artifacts and integrity

- [Result JSON](evidence/y1/segment-65/result-segment-65.json), 2,329,516 bytes; SHA-256 `9886ce6cb0b8ff41b426e22ecb8fe4a4d45ef20dbe87af596e7d77c2aaa87253`.
- [Append-only support-domain stream](evidence/y1/segment-65/result-segment-65.json.support-domain.jsonl), 11,838,600 bytes, 8,742 physical lines; SHA-256 `381b844c91f82ba0472a890a08a050b2994c723fbf69fb3c6e3dcb9323055398`.
- [SHA256SUMS.txt](evidence/y1/segment-65/SHA256SUMS.txt) pins both raw artifacts and this report.
- The resume check passed (exit 0), verified these result/stream hashes, and resumed the same attempt. Two earlier resume-check invocations failed only because the Godot project root/script path was wrong; the corrected `--path game` invocation passed.
- The original synthesis terminal PID and exit code were not retained. No Godot process remained after segment close. This process observation is not a scientific completion claim.

## Reproduce resume-check

From the repository root after retrieving these files:

```powershell
$bin='C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe'
$repo=(git rev-parse --show-toplevel)
$p=Join-Path $repo 'docs/reports/P3-1-R12-CXR-R6/evidence/y1/segment-65/result-segment-65.json'
$stream=$p+'.support-domain.jsonl'
$env:R12CXR_R6_MODE='y1-resume-check'
$env:R12CXR_R6_Y1_RESUME_INPUT=$p
$env:R12CXR_R6_Y1_RESUME_SHA256=(Get-FileHash -Algorithm SHA256 -LiteralPath $p).Hash.ToLowerInvariant()
$env:R12CXR_R6_Y1_RESUME_STREAM_SHA256=(Get-FileHash -Algorithm SHA256 -LiteralPath $stream).Hash.ToLowerInvariant()
$env:R12CXR_R6_ATTEMPT_ID='R6-Y1-COMPLETE-SUPPORT-20261102-01'
$env:R12CXR_SOURCE_SHA='84a952e1935b284157f3aa1587ff317a1bc49a07'
& $bin --headless --path game --script res://tests/prototypes/p3_1_r12_cxr_r6_campaign.gd
```

Evidence grade: implementation-agent runtime/evidence record for this bounded continuation, suitable for independent source and artifact review. No independent review or owner GUI acceptance is implied.
