# P3.1 R10-B1R domain-audit runner classification correction

Date: 2026-10-30
Experiment branch: `exp/p3-1-r10-b-constrained-realization`
Existing PR: #208, draft and unmerged
Source SHA whose domain audit was classified incorrectly:
`66b4c13522511a5c6d1fd2c083d659f63042d4d7`

## Preserved exact-source domain result

The domain-only Godot process on SHA `66b4c13` generated a candidate-domain
artifact and emitted `R10B_B1R_DOMAIN_COMPLETE` with status PASS. It performed
no direct triangulation search and emitted no geometry attempt result.

- Attempt: `b1r-domain-66b4`; PID 21084; process exit code 0.
- Evidence root:
  `C:\Users\PUBLI\AppData\Local\Temp\p3_1_r10b1r_66b4c13522511a5c6d1fd2c083d659f63042d4d7_cd1cd76cdaac42459aeb2cdcd3c9e066`
- Candidate-domain SHA-256:
  `5512ea1a7611e945c1d4f0bf23d947ba3cc22bba6f7ad6bccbce345425ac6254`
- Candidate triangles: 7,608; frozen roots: 73; boundary roots: 34.
- Positive solver-domain loader validation passed; estimated state:
  1,675,680 bytes.
- Negative tampered-owner test failed closed with
  `candidate_domain_half_open_owner_mismatch`.
- Source topology graph proof: valid, 369 roots, 502 polygons, 870 arcs, zero
  unresolved/nonmanifold arcs, topology SHA
  `4ecbb2496fb34f1cf3c05a60192f76bdce7a52ec3148d02ba041510b804a8c95`.

The runner nevertheless marked its process record
`DOMAIN_AUDIT_EVIDENCE_INVALID`. It required a separate
`R10B_GRAPH_CONTRACT_COMPLETE` marker, although the domain-only campaign
branch intentionally returns a single domain marker containing the complete
source-topology proof. A standalone graph-contract stage had also already
passed on this source SHA. This is an orchestration classification defect, not
a solver or geometry result. The artifact is preserved but will not be reused
after source changes because its source identity is SHA-bound.

## Bounded correction

The runner now validates the source-topology proof embedded in the domain
marker against the frozen root/polygon/arc counts, zero unresolved and
nonmanifold arcs, and exact frozen topology SHA. It also validates the
positive/negative domain-loader self-test and candidate count. It no longer
requires an unrelated duplicate graph marker in this stage. The standalone
graph-contract remains a separate required exact-SHA preflight stage.

## Status and next step

No direct triangulation solver ran and no valid B1R geometry terminal result
was emitted. Therefore B1R remains the one unconsumed final geometry slot.
Rerun import, parser, authority, ROI rays, graph contract and domain audit on
the new exact source. Generate and preregister a new candidate-domain digest
on that source before the single geometry attempt.

No production adoption, merge, release, Issue #108/#154 work or F2-G1 action
is authorized. All five F2-G1 holds remain.
