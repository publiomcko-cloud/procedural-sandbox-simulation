# Independent F2 G1 Supervision Design Re-review — 2026-10-09

Developer PR: https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/45 (draft, open, unmerged)
Issue: https://github.com/publiomcko-cloud/procedural-sandbox-simulation/issues/44
Prior reviewer finding PR #46: https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/46 (immutable corrections-required review)
**Exact reviewed HEAD: 5a5ba68350d316a2626c3c1a3598d45d1498804c**
Verified parent: 876d48aff2a450c132778060dd828babf15e0a96
Developer branch: docs/f2-g1-supervision-issue44
PR base SHA: dfcd264bcee1910bb83a990a56613e78adb9d3b1 (draft PR #42)
Main and merge-base SHA: 0b3e69cec1bd0eeb6da5ff19b50f410acf33129b

**VERDICT: PASS_DESIGN. All PR #46 findings R1–R3 RESOLVED at this immutable SHA.**
**Runtime status: G1 BLOCKED_ENVIRONMENT; F2 A–G NOT_RUN.**
A design acceptance does not approve native staging, guest resource qualification, Godot launch, an OS feature change, nor merging any PR. Readiness for a particular guest requires fresh owner approval and observed enforcement; none has occurred here.

## Provenance, exact scope and validation

Independently fetched PR #45 metadata and HEAD commit, previous reviewed parent, GitHub compare and exact complete source Markdown documents. The new HEAD is one direct commit after 876d48a..., with 5 linear commits ahead of PR #42's fixed base, no divergence. Only these two documents change on the corrective commit:
- docs/specs/P0.1-F2-G1-SUPERVISION-FEASIBILITY.md (25 additions / 9 deletions)
- docs/handoffs/P0.1_F2_G1_SUPERVISION_HANDOFF.md (20 additions / 7 deletions)

Across the entire PR #45 the same two files are new; no code, native binaries, scripts, .wsb settings, workflows, input maps, or implementations were modified. Both exact-head Starter checks, runs 37913752113 and 37913746221, finished SUCCESS. The jobs perform checkout and static expected-file validation, **not** source/PowerShell tests or VM resource enforcement. Developer reports documentation consistency and git diff --check passed; reviewer did not execute developer-local checks. No native/guest runtime was conducted or requested.

## R1 — Distinct owner screenshots and source lineage: RESOLVED

The spec now distinguishes an earlier guest run associated with source HEAD cc2feb14a56061a6bc749468bf04eeb179bd5049, which showed child exit code **unavailable**, token/network/mapping PASS and misleading outer DiagnosticGateFailed, from the later screenshot showing child exit code **0**, diagnostic INCOMPLETE / ReadinessGatesRemainUnknown, a verified nonadministrator diagnostic account, no active adapters/default routes, read-only mapped input, and Remote Display Adapter inventory. The later report is consistent with the corrected Issue #43 source at dfcd264bcee1910bb83a990a56613e78adb9d3b1, but screenshots alone **do not cryptographically prove guest scripts, config or exact SHA**. Both spec and handoff explicitly prevent claiming that earlier screenshot proved the corrected logic or any Godot-native process identity.

## R2 — Host watchdog loss and guest-scoped cessation: RESOLVED IN DESIGN

The architecture now requires, **before any VM starts**, immutable hypervisor VM ID + run ID + reviewed config identity, pre-armed and query-back-verified 30-minute deadline, a host primary watchdog **and separately failing** expiry/lease reaper capable of stopping only the named disposable VM. Loss of the primary controller, handle or heartbeat, missing secondary component, inability to arm the deadline, missing immutable identity, failed or unconfirmed VM stop, and missed deadline all explicitly fail closed and prohibit a claim of enforced session limits.

The inert qualification plan covers wrong-identity rejection, no accidental stop of a concurrently running decoy VM, primary process termination/handle loss, secondary expiry on deadline and confirmed cessation, and restart lease qualification only on an independently disposable hypervisor (not on the owner's development host). Scoped least-privilege permissions, no wildcard VM selection, no forced broad host termination and no elevation are retained. These are **requirements for a future implementation, not observed mechanisms**: no watchdog or VM currently exists in accepted evidence, so CPU/disk/session limits remain UNKNOWN and native G1 remains blocked.

## R3 — Native editor versus export and actual GL driver: RESOLVED

The corrected renderer plan targets the exact official native Godot editor 4.7.2.stable.official.ed1daf0bf, not an exported Godot game. Future evidence must record actual RenderingServer.get_current_rendering_method() equal to gl_compatibility, actual RenderingServer.get_current_rendering_driver_name(), underlying API, device/vendor/version, expected executable identity, nonadministrator process token and visible renderer output in a fully qualified guest. Driver names opengl3, opengl3_es and opengl3_angle have distinct evidence requirements. ANGLE/D3D11 requires proof of actual backing device; a method/driver name or a command-line request is insufficient proof of backend support. The specification correctly distinguishes Godot 4.7 native editor Compatibility minimum OpenGL 3.3 from Windows **exported project** Compatibility minimum OpenGL 3.3 or Direct3D 11. It does not assume export backend support certifies the editor.

Official crosschecks: https://docs.godotengine.org/en/4.7/about/system_requirements.html and https://docs.godotengine.org/en/4.7/classes/class_renderingserver.html (methods and opengl3_angle documented).

## Preserved isolation contract and remaining risk

The accepted document accurately identifies that the documented Windows Sandbox .wsb controls provide no CPU ceiling, disk quota or whole-session deadline; MemoryInMB, monitoring and read-only host map are not substitutes. Windows Job Objects constrain associated processes, not the whole Windows guest. A pre-provisioned offline disposable Windows VM is only the **preferred candidate**, not a qualified or available environment. Proposed 2-vCPU/20%, memory and fixed VHDX figures are preliminary, unmeasured, and not owner-approved. VM and process tree enforcement, closed network egress, approved safe evidence export/disposal, actual future Godot process token, and OpenGL/ANGLE backend support all remain UNKNOWN. Owner screenshot provides narrowly scoped diagnostic-only observation; no native A–G execution, no Godot, Voxel Tools, native ZIP or DLL was executed.

Independent technical references:
- Microsoft Windows Sandbox configuration: https://learn.microsoft.com/en-us/windows/security/application-security/application-isolation/windows-sandbox/windows-sandbox-configure-using-wsb-file
- Microsoft Job Objects: https://learn.microsoft.com/en-us/windows/win32/procthread/job-objects
- Godot editor/export distinction and RenderingServer: links above.

## Subsequent stage — gated and separate

This is **PASS_DESIGN / READY_FOR_SEPARATELY_REVIEWED_CONTROL_IMPLEMENTATION**, not READY_FOR_STAGING and not evidence a VM can be started now. First determine whether an existing, fully isolated disposable VM can be supplied without feature installation, unapproved privileges, or weakening isolation. If so, propose a new scoped source-only design/implementation of the least-privilege watchdog, Job Object supervisor and inert fault fixtures; independently source review it and obtain specific owner approval **before** any inert guest execution. An actual resource bound requires demonstrated enforcement and effective identity verification, not CI mocks. If no suitable VM exists, retain BLOCKED_ENVIRONMENT. Keep PRs #32, #42, #45 and historic reviewer PR #46 draft and unmerged. Do not merge or run Godot/native probes based on this design verdict.

**FINAL: PASS_DESIGN / R1-R3 RESOLVED / G1 BLOCKED_ENVIRONMENT / NATIVE F2 A–G NOT_RUN.**
