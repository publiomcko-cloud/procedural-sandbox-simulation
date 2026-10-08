# P0.1-F2 isolated runtime harness (guest-side preparation)

**State: PREPARED, NOT EXECUTED.** This folder contains only a declarative analytic fixture and the ordered run protocol. It contains no vendor archive, DLL, Godot binary, imported addon, or production-project changes. It does not claim F2 runtime compatibility.

## Fixture

`fixtures/analytic_sdf_v1.json` versions the F0 analytic plane/spherical-hill/tunnel field, domain-positive-solid convention, 16 m logical regions, 0.5 m initial sample pitch, one-sample seam halo, canonical tick rules, material IDs and sign probes. The sphere centered at `(0,-1,0)` with radius 5 reaches `y=4`, so it protrudes above the plane. These values define inputs; they do not define pass tolerances. Before each probe, log tolerances and acceptance criteria so that results cannot be tuned after observation.

The field uses `density = min(max(-y, 5 - length(p - (0,-1,0))), -(1.25 - distance_to_segment(p, (-8,-4,0), (8,-4,0))))`. At `(0,0,0)`, density is `+2.75` (solid, 11264 canonical ticks), not zero. `(0,4,0)` is an exact-zero spherical surface sample. The tunnel is a subtractive cylinder segment inside the solid and crosses the x=0 region boundary. Vendor SDF sign, units, quantization, unloaded-query behavior and material mapping must be measured independently.

Run the deterministic source-only fixture check with `pwsh -NoProfile -File tests/f2_runtime/validate_fixture.ps1`. This evaluates the declared analytic field and canonical ticks from JSON; it does not execute Godot or vendor code and is not a runtime test.

## Isolation prerequisites (hard gate)

Run only in a disposable Windows Sandbox or throwaway Windows VM provisioned separately by the owner. Acquire and verify the approved inputs on the host **before launching the guest**, then transfer them through a narrowly scoped, read-only input mount/copy. The host may download and hash the exact ZIP as data; it must not extract the ZIP, load any DLL, or run vendor code. Start the guest with networking disabled. Use an unprivileged guest account; do not mount secrets, profiles, cloud sessions, SSH keys, or writable host project directories. Keep project, Godot user data, caches and logs in a unique guest-local run root. Use a supervising controller for per-probe five-minute limits and a 30-minute total budget; record actual memory/disk/CPU controls and do not claim a limit that was not enforced. If any prerequisite cannot be demonstrated, stop with `BLOCKED_ENVIRONMENT`.

Do not install Windows features, weaken host protections, run vendor code on the host, invoke vendor installers/build scripts, access the network from the guest, or add dependencies. Do not extract into a repository worktree. Use the accepted `scripts/inspect-zip.ps1` preflight/extractor only after confirming its canonical guest-local destination and exact archive identity. Do not commit the ZIP or DLLs.

## Run record

Create an evidence directory in the guest keyed by a fresh run UUID. Record operator/authorization issue, local time and UTC, guest type/settings, network state, user privilege, enforced limits, source and destination canonical paths, and SHA-256 for every executable, archive, fixture, and mapped DLL before launch. Preserve stdout/stderr, exit codes, timeout and process-tree cleanup evidence. Export only reviewed logs/screenshots through an explicitly controlled channel.

### Host preparation, before guest launch

1. Obtain only the owner-approved official Godot Windows x86_64 distribution and exact ZIP URL `https://github.com/Zylann/godot_voxel/releases/download/v1.7x/GodotVoxelExtension.zip`. The ZIP acquisition is a host-side data transfer only; do not extract it, open/dispatch it, execute its contents, or load any DLL on the host.
2. Verify the official Godot file version `4.7.2.stable.official.ed1daf0bf`, Windows x86_64 identity and SHA-256. Verify the ZIP is exactly 54,457,774 bytes with SHA-256 `600737572a5e25541ba6f503e842a3717ba19afafa5474510a6ceff995a1d2d8`. Record commands, paths, timestamp and hashes. Stop on any mismatch.
3. Configure a narrowly scoped read-only transfer for only these verified inputs. For Windows Sandbox, explicitly set networking to **Disable** in a custom `.wsb` configuration; do not accept the network-enabled default. Do not map secrets or writable project paths. The transfer mechanism is not authorization to run vendor code on the host.

### Offline guest, before any native load

1. Launch the disposable guest with networking disabled and the owner-approved resource, privilege, timeout, evidence and cleanup controls. Verify and record its effective settings before staging inputs.
2. Copy the read-only inputs to a unique guest-local run root. Recompute and verify Godot identity/version/hash and the ZIP exact size/SHA-256 inside the guest. Stop on any mismatch.
3. In the guest, run the F1 synthetic adversarial ZIP suite and the pinned archive preflight using a safe guest-local destination. Only then extract within the guest-local throwaway project. Never extract to the host or repository. Remove the input mount after the guest copy and hashes are verified, when the sandbox mechanism permits.
4. Hash descriptor-mapped editor and template-release DLLs in the guest. Record hashes and actual commands. Execute A–F in order, stopping at the first mandatory failure. Preserve failed logs; do not patch vendor code or reinterpret unsupported behavior as pass.

Guest networking must remain disabled throughout. Never enable it to fetch or update an input; if host-side acquisition and controlled read-only transfer are unavailable, stop with `BLOCKED_ENVIRONMENT`. Export only deliberately reviewed, sanitized evidence through a separately controlled channel.

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

The 2026-10-08 G1 attempt stopped before Probe A. The host had no discoverable `WindowsSandbox.exe`, no Hyper-V VM management cmdlet/module, and no installed VirtualBox or VMware control executable; querying Windows optional-feature state failed with an elevation-required error. No isolated guest could be controlled or verified. Therefore no archive download, Godot identity check, extraction, or native execution was attempted. During the subsequent source-only preparation correction, `validate_fixture.ps1` checked the analytic fixture; the existing synthetic ZIP safety suite also ran using generated archives only (see the F2 runtime report and handoff). Neither check involved Godot or vendor code.
