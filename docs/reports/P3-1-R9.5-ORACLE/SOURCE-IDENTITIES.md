# P3.1 R9.5 Oracle — Source identities

Repository origin:
https://github.com/publiomcko-cloud/procedural-sandbox-simulation.git

Oracle starts at R9.4 comparison 9bdfcd59241d76bd57b95b9e2bb5c1982834071b.
Exact oracle source HEAD is written in the run logs and checksum inventory
after this preregistration commit.

Preflight attempt `R95.ORACLE.A.c3a2a48` (source A pinned to the identities
above) exited before scenario execution because Godot 4.7.2 could not infer
the type of the test-only `mixed` local in the oracle harness. The complete
failure is preserved under
`C:\r95-evidence\oracle-A-c3a2a48\logs`. The harness local was made
explicitly `bool`; no candidate source, frozen input, or expected result was
changed. Any subsequent execution uses a new committed oracle identity.

The first A diagnostic at oracle commit `44efe3b0df998b83be5afff94e6db7f03ea6db40`
completed but is not valid ray-oracle evidence. It exposed an unsound adaptive
prune: child visitation used a quarter-parent-width test, although a possible
root may lie as far as half the parent width from the midpoint sample. This
missed two analytic roots on ray indices 0, 5, 6, 10 and 11. The initial ray
classification also compared only the global first root, even when that root
lay outside the cropped mesh ROI. The full attempt is preserved at
`C:\r95-evidence\oracle-A-44efe3b`; its candidate geometry counts are retained
as unqualified diagnostics, not conclusions. The next pinned oracle revision
uses a complete-interval 1-Lipschitz exclusion, compares the analytical root
set with the adaptive root set, records the legacy 256-step scan, and compares
mesh hits with every canonical root inside the same ROI.

| Candidate | Measured source commit | Direct parent | Original candidate file SHA-256 | R9.5 snapshot |
|---|---|---|---|---|
| A | f0c93415dd56886a1c05ff2e6a1340e420f22c59 | d5903242e41642a2633e18dc181c4389188c65b2 | 970fe99f192ea2a3fea3e682072ed3562e6f57c843561dd4440e46381a384d8a | game/tests/prototypes/r9_5_source_snapshots/candidate_a.gd |
| C control | af4d6027d9d57c9f2b8023aa27b31d2dd2dcedf2 | 5def207d7b1cff8d7f70476f1221c7b9c5771e27 | 7072f39b2c48dcb38048e2ee3d1687baa9377bcc99ca8250c2c0f84cff17d24 | game/tests/prototypes/r9_5_source_snapshots/candidate_c.gd |
| D | 6ea04229b5ff06090f346c8749c1f5a53994227c | 51744eebf17646ca52612936146adeb0f9db001b | a33b464ea569f54fb39b72d2198fa971796c0cb5370a64a9696362cd0313f2a6 | game/tests/prototypes/r9_5_source_snapshots/candidate_d.gd |

D's required test-only extractor dependency is copied byte-for-byte from the
R9.4-D measured worktree to
game/tests/prototypes/p3_1_r9_3d_reference_extractor.gd, physical SHA-256
d40eb386c534edadae2a8e5d51250bae8a64ef551d5ad5866671afef871f682b.

The frozen manifest is game/tests/prototypes/p3_1_r9_2_e2e_inputs.jsonl,
SHA-256 1610c535f98a11e26ca1890c0d99addf4316fbcaa7ec9cdb7dfaa71cf5bb3972.
The installed Godot 4.7.2 console binary SHA-256 is
c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643.

Snapshot physical hashes are computed from the committed R9.5 paths before
execution and included in the run evidence inventory. Git blob identities
are recorded after staging.
