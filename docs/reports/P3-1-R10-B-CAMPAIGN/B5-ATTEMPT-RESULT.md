# R10-B5 attempt result — nested local field refinement failed geometry gates

Attempt `B5-NESTED-20261030-310C53F`, source HEAD `15955fb3742390fc4bc2f7409fdc82e3a5021eac`, implementation parent `310c53f0a250cc16449f52ec8d10497ac5c1af35`. The one geometry invocation exited 0, had no script errors/warnings, and recorded terminal `FAILED_TARGET`; it was not repeated.

## Sample and field result

The original 0.25-step A6 volume remained intact (`ecf86bce57e82cd0949d4576e7b7ebe4d1ef8d0633ac7f6d540fd56df6573be2`, payload `2ff3685296a8d035967a8c723bc42cb8320a9500dc699538a731490d089203d0`, revision 2). Candidate D built a separate 0.125-step field over the same world extent, with 16×16×16 cells / 4,913 samples; its volume integrity/reload gate passed (`d50aacd52376eb5f65b81d903d9bcdb3530f1f036c29e044040edbe7ac20f57e`, payload `9b023bc4edbc0086cf4070a43168a488632c33f3d5f356ad587f5741ac9f8a72`, revision 2). The 729 shared coarse/fine lattice samples matched exactly as float32 values.

This nested-node agreement did not imply matching polygonized geometry. The R10-A6 fine-field mesh SHA was `da5084731aab486b2fd04e2d8c4e9ff385334bf7fc7754a6df5d7b98141d3c94`; extraction took 1,949,905 µs. It had 2,560 triangles, 27 internal open edges, 147 ROI boundary-open edges, zero nonmanifold edges, zero emitted degenerates, zero winding errors, 48 missing required adjacencies and 16 rejections at the unchanged `cross_squared > 1e-12` cutoff. `geometry_realization_complete=false`.

| Outer face | Coarse segments | Fine segments | Unmatched | Exact match |
|---|---:|---:|---:|---|
| X− | 20 | 38 | 58 | No |
| X+ | 20 | 42 | 62 | No |
| Y− | 16 | 32 | 48 | No |
| Y+ | 0 | 0 | 0 | Yes (both empty) |
| Z− | 17 | 35 | 52 | No |
| Z+ | 0 | 0 | 0 | Yes (both empty) |

The contour keys use the preregistered 1e-6 endpoint quantization for comparison only. Four faces failed; two equal empty sets are vacuous matches. The all-six-face gate therefore failed. The fixed ray gate was 0 disagreements in 25 ROI rays and all 6 controls passed. Mixed LOD was skipped because the equal-LOD topology gate failed. The original volume and ledger were not modified. No continuous-SDF equivalence, product tolerance, or performance acceptance is claimed.

## Process evidence

Evidence directory: `C:\Users\PUBLI\AppData\Local\Temp\P3_1_R10B_20261030_e2d6c8b0\B5-NESTED-20261030-310C53F\B5-NESTED-20261030-310C53F_geometry`.

Godot 4.7.2 process PID 2868 (launcher PID 34056), run ID `1e315bc402be48b59ccefcfe0e53e3ce`, exit 0, elapsed 7,569.7 ms, stop-loss not triggered, minimum free commit 20,739,330,048 bytes. The corresponding check-only and graph-contract gates both passed on HEAD `15955fb` before this single scenario.

| Raw item | SHA-256 |
|---|---|
| Attempt JSON | `75e454557b44a896d1dbc06bfe26ea7e845259858e2a54cc59d64fd1b2bbbd23` |
| stdout | `a14398b5905e6481bb592408ce032b676a7365bd3368c16dc3eae4aa663d00af` |
| stderr (empty) | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| Process record | `939082030e2401f86dd2e9cb8cd6b988358e5dfc5398a53ab949c26596a48e57` |
| Launch intent | `3cd4849c99ade9f72debbc912127e4ca32d8f347a2967cb8578419a0d74692e9` |
| Process-created record | `49f6db4272cf8fb1a45c830be8e67ec1881e7ddb4a08ac5c04b902660d4c5988` |
| Resource monitor | `d184774c5ca70bfbbf789907357a0e23a990f340901f884e9ac772ac793ccb2c` |

B5 rejects this uniform local refinement as a conforming candidate: exact nested samples alone did not preserve the extracted contours or meet topology. It does not prove that every adaptive or transition-cell strategy is impossible.
