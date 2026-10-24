# P2.0A — Irregular Procedural Rock Geometry Correction

Date: 2026-10-24

Repository: `publiomcko-cloud/procedural-sandbox-simulation`  
Workspace: `C:\Dev\sandbox-sim-dev`  
Branch: `feat/p2-0a-mod-first-procedural-objects`  
PR: [#106](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/106), open/draft/unmerged  
Correction commit: `29b0935336d084461b680b00eb0f4e020962098a`  
Direct parent: `5166c311ba8d6ac7e8c6eac3b9a097db1e1ef8c1`  
Main base: `0ea2ad834db5dc2de1110cf0388ea06604cc7715`

## Owner finding and correction

The owner confirmed the original GUI interaction and streaming behavior but rejected the visible rocks because the geometry looked like overlapping spheres. The prior adapter emitted a separate smooth UV sphere for each recipe lobe, exposing the recipe's intermediate construction as the final silhouette.

`ProceduralRockMeshAdapter` v2 now treats recipe lobe centers and radii as the bounding envelope for one irregular stone. It creates one twice-subdivided icosphere topology (320 triangles), maps it to the recipe envelope, and applies bounded directional and seed/index-derived radial variation. Triangles are emitted with flat outward face normals. Meshes remain one connected closed shell; the adapter rejects degenerate faces and invalid inputs. The recipe seed controls geometry variation, and the adapter version is recorded on each transient object node. Both first-party and external definitions still use the P0.3 loader/registry and this same adapter.

Placement records, world/object IDs, content pins, recipe and placement seeds, region ownership, terrain streaming, controls, terrain LOD, and schema-1 save behavior were not changed. The object layer remains transient and has no terrain-edit or save authority.

## Focused verification

Godot: `4.7.2.stable.official.ed1daf0bf`  
Executable: `C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe`  
Executable SHA-256: `c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643`

- Import plus focused procedural-object test: exit 0; `PROCEDURAL_OBJECT_PASS: assertions=135 failures=0`.
- Tests cover repeated same-seed mesh equality, different-seed silhouette variation, one 320-triangle surface per definition, finite geometry, flat-normal agreement, outward winding, nondegenerate triangles, connectedness, and exactly two incident faces per quantized edge.
- Full `scripts/validate.ps1`: exit 0; 16 assertion groups, 17,393 assertions, zero failures; final marker `VALIDATION_PASS: L0-L2`. No parser, script, runtime error, or warning diagnostics.
- Both validation runs used unique temporary `APPDATA` profiles. Full validation evidence is at `C:\Users\PUBLI\AppData\Local\Temp\p2_0a_rockshape_full_c305c910ef3c4a08b501cf498e894db4\`; focused evidence is at `C:\Users\PUBLI\AppData\Local\Temp\p2_0a_rockshape_focused_758acc06e2ce41c38f92fdc49820a4ab\`.

These checks establish deterministic topology and runtime construction. They do not establish artistic quality or replace owner visual review. GUI retest remains required.

## Documentation concurrency and status

PR #107 is a separate open draft that adds a current-status header and its own recent-merge row to the checkpoint index. This correction adds its index row next to the existing P2.0A entry and appends a new dated P2.0A update to `docs/status/CURRENT_STATUS.md`; it does not modify PR #107 or its branch. These edits are placed outside the portions changed by #107 to reduce textual merge overlap. Live GitHub refs must still be checked before either PR is integrated.

Status: PR #106 remains draft and unmerged. The earlier reported spherical appearance is corrected in source, but only the owner can accept the visual result. Independent exact-SHA source review and owner GUI retest are pending.

All five F2-G1 holds remain unchanged: `CURRENT_PROTECTED_STATE_UNKNOWN`, `V3_NOT_ATTESTED`, `ACL_REVIEW_REQUIRED`, `G1_BLOCKED_ENVIRONMENT`, `F2_G1_RELEASE_HOLD`.
