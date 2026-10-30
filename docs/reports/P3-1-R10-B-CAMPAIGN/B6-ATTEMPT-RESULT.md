# R10-B6 attempt result — bounded beam exhausted without a legal flip

Attempt `B6-BEAM-20261030-ABE1D54`; execution source HEAD `b1dd90ca7adb6ef941f3dc933008648fd1a91de6`; implementation commit `abe1d54dc8986fec2513b8ce261197867f4b8095`, parent `f622468dd750775c51394ae595fa5019114e7a1c`. The geometry process exited 0 with no script errors or warnings and emitted `FAILED_TARGET`; it was run once.

## Search result

The source root set, 34-root boundary, 110-triangle initial component, volume, canonical scalar samples, winding and fixed `cross_squared > 1e-12` cutoff were kept unchanged. The deterministic cutoff-directed beam examined all 182 internal edge candidates in the initial state. It generated no legal successor: 48 were rejected for projected orientation, 34 were fixed boundary edges, 31 failed strict projected-convexity, and 69 proposed an existing replacement diagonal. The queue was therefore genuinely exhausted for this bounded 2–2 flip graph after one state (one unique state, beam peak 1), in 33 ms / 349,412 µs reported solver time. Search limits were not hit. This is not a proof that no alternative triangulation or geometry exists; it is only exhaustion of the registered move set from this exact initial state.

## Geometry and controls

The result was unchanged from the A6 baseline: mesh SHA `1f21af7c3856ae72080e3e0c5ad44a3c608703470b5563212902bed08ad0f7d4`; 655 triangles; 10 internal open edges; 73 ROI-boundary open edges; 0 nonmanifold edges; 0 emitted degenerates; 0 winding errors; 21 required adjacencies missing; 7 fixed-cutoff required triangles rejected; minimum squared cross product `1.67075673894024e-16`; 3 sub-cutoff faces remained. The original revision-2 volume identity passed (`ecf86bce57e82cd0949d4576e7b7ebe4d1ef8d0633ac7f6d540fd56df6573be2`, payload `2ff3685296a8d035967a8c723bc42cb8320a9500dc699538a731490d089203d0`). The ROI ray oracle reported 0 disagreements / 25 rays and controls passed 6/6. Mixed LOD was skipped because equal LOD did not pass.

The attempt ended `FAILED_TARGET`. No deterministic repeat, mixed-LOD solver, full frozen E2E, or `scripts/validate.ps1` was run because no candidate satisfied equal-LOD topology. This search does not support a global exact-root infeasibility claim.

## Process and evidence

Evidence root: `C:\Users\PUBLI\AppData\Local\Temp\P3_1_R10B_20261030_e2d6c8b0\B6-BEAM-20261030-ABE1D54\B6-BEAM-20261030-ABE1D54_geometry`.

Godot process PID 12224, launcher PID 32828, run ID `f076f10fe01649a6bef7e2ffd232abf4`, exit 0, elapsed 4,777.9 ms. Resource/timeout aborts: none; minimum free commit: 21,434,511,360 bytes.

| Raw item | SHA-256 |
|---|---|
| Attempt JSON | `bcd84b6c3419fb58b3c3c3f1069556266a8e008e738d0bda912e438bccda250b` |
| stdout | `e5b02b7bae269035be3c1bfdc5d12c91817a384f51120241200add9f0c8c621d` |
| stderr (empty) | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| Process record | `007a177bd161fba2ac978054a2fb5286f999dfbe3669fc8db697afc2c88287b7` |
| Launch intent | `28fed16191bf9c729cf911b9a7d90cb7c30b877d8fa4791fe93ecb1ce12279af` |
| Process-created record | `fc46f79f87449513f104f46c34b4b37921b14b57a48ac25b5ef8dccefa510d21` |
| Resource monitor | `0ad3c67bb53477b1f6514d9fbfde2fa2eb28c752e1af11beeb9634365ff03e4c` |

The unchanged mesh digest and metrics confirm this registered beam found no changed realization. This result only rejects the bounded cutoff-guided flip search as a corrective candidate.
