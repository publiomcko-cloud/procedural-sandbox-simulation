# P0.1-F2 isolated runtime harness (guest-side preparation)

**State: PREPARED, NOT EXECUTED.** This folder contains only a declarative analytic fixture and the ordered run protocol. It contains no vendor archive, DLL, Godot binary, imported addon, or production-project changes. It does not claim F2 runtime compatibility.

## Fixture

`fixtures/analytic_sdf_v1.json` versions the F0 analytic plane/sphere/tunnel field, domain-positive-solid convention, 16 m logical regions, 0.5 m initial sample pitch, one-sample seam halo, canonical tick rules, material IDs and sign probes. These values define inputs; they do not define pass tolerances. Before each probe, log tolerances and acceptance criteria so that results cannot be tuned after observation.

The field uses `density = min(max(-y, 5 - length(p - (0,-1,0))), -(1.25 - distance_to_segment(p, (-8,-4,0), (8,-4,0))))`. The tunnel is a subtractive cylinder segment inside the solid and crosses the x=0 region boundary. Vendor SDF sign, units, quantization, unloaded-query behavior and material mapping must be measured independently.

## Isolation prerequisites (hard gate)

Run only in a disposable Windows Sandbox or throwaway Windows VM provisioned separately by the owner. Start with networking disabled. Use an unprivileged guest account; do not mount secrets, profiles, cloud sessions, SSH keys, or writable host project directories. Stage only verified, read-only Godot and archive inputs. Keep project, Godot user data, caches and logs in a unique guest-local run root. Use a supervising controller for per-probe five-minute limits and a 30-minute total budget; record actual memory/disk/CPU controls and do not claim a limit that was not enforced. If any prerequisite cannot be demonstrated, stop with `BLOCKED_ENVIRONMENT`.

Do not install Windows features, weaken host protections, run vendor code on the host, invoke vendor installers/build scripts, access the network from the guest, or add dependencies. Do not extract into a repository worktree. Use the accepted `scripts/inspect-zip.ps1` preflight/extractor only after confirming its canonical guest-local destination and exact archive identity. Do not commit the ZIP or DLLs.

## Run record

Create an evidence directory in the guest keyed by a fresh run UUID. Record operator/authorization issue, local time and UTC, guest type/settings, network state, user privilege, enforced limits, source and destination canonical paths, and SHA-256 for every executable, archive, fixture, and mapped DLL before launch. Preserve stdout/stderr, exit codes, timeout and process-tree cleanup evidence. Export only reviewed logs/screenshots through an explicitly controlled channel.

Before any native load:

1. Verify the exact official Godot file version `4.7.2.stable.official.ed1daf0bf`, Windows x86_64 identity and SHA-256, and select **GL Compatibility**. Stop if the version/build/renderer is wrong.
2. Download only `https://github.com/Zylann/godot_voxel/releases/download/v1.7x/GodotVoxelExtension.zip` if the approved guest input is unavailable. Require exactly 54,457,774 bytes and SHA-256 `600737572a5e25541ba6f503e842a3717ba19afafa5474510a6ceff995a1d2d8`; rerun the full F1 synthetic suite and archive preflight in the guest before extraction. Do not proceed on any hash, size, archive, path, or descriptor mismatch.
3. Copy only the required project assets and descriptor-mapped Windows DLLs into the guest-local throwaway project. Hash the editor and template-release DLLs and record all actual commands. Never place vendor files in this repository.
4. Execute A–F in order. Stop at the first mandatory failure. Preserve failed logs; do not patch vendor code or reinterpret unsupported behavior as pass.

## Ordered probe worksheet

| Probe | Minimum observation | Mandatory stop/disposition |
|---|---|---|
| A | Official build/renderer, extension descriptor mapping, class registration, clean start/exit and import diagnostics. | Stop on engine/renderer/descriptor/import mismatch or unresolved native dependency. |
| B | Evaluate analytic fixture and compare plane, sphere, enclosed cave/tunnel and region-boundary samples; establish vendor sign, units, quantization and unavailable-query semantics. | Stop on incorrect/missing geometry semantics; record actual tolerances before run. |
| C | GL Compatibility smooth mesh, cave interior, normals/winding/seams, stable local material mapping, missing ID and >4 blend behavior. | Stop if renderer requires an unapproved path or mesh/material claims cannot be observed. |
| D | Bounded subtract/add/sculpt/material edits, including a two-region border stroke and first-LOD out-of-range rejection/defer case. | Stop if unsupported extent is masked, or canonical edits/samples cannot be reconciled. |
| E | Collision before/after edit; rapid edits, pending work during unload/reload; determine public completion/cancellation and prepublication revision-fence visibility. | If public API cannot prevent stale mesh/collision publication, report `UNSUPPORTED` / project-contract blocker. Eventual convergence is not revision-safe publication. |
| F | Reordered region requests, semantic hashes, signed-wide-i64 to chunk-local mapping limits, clean close/reopen and rebuildable-cache behavior. | Stop on request-order-dependent semantics or unsupported coordinate precision. Do not claim crash recovery or durable journal behavior. |
| G | Owner-run isolated GUI verification of surface/cave, seams, LOD and collision alignment with screenshots and exact build/run record. | Owner records PASS/FAIL. Headless evidence cannot substitute. |

For each executed probe, write command, start/end time, exit code, log path/hash, fixture hash, observations, PASS/FAIL/UNSUPPORTED/INCONCLUSIVE, deviations, and cleanup/rollback state. Do not report unobserved behavior.

## Current host attempt

The 2026-10-08 attempt stopped before Probe A. The host had no discoverable `WindowsSandbox.exe`, no Hyper-V VM management cmdlet/module, and no installed VirtualBox or VMware control executable; querying Windows optional-feature state failed with an elevation-required error. No isolated guest could be controlled or verified. Therefore no archive download, Godot identity check, extraction, or native execution was attempted. The only executed test was the existing synthetic ZIP safety suite (see the F2 runtime report and handoff).
