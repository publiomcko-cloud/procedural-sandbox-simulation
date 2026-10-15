# F2 G1 — PR #50 PS5.1 entrypoint bridge (source-only candidate)

**Status:** `READY_FOR_INDEPENDENT_SOURCE_REVIEW` only after GitHub source SHA verification and appropriate Windows PS5.1 results; no protected installation, active-host read or runtime acceptance.

## Provenance and scope

- Repository: https://github.com/publiomcko-cloud/procedural-sandbox-simulation
- Exact source parent: `2c967661163fc157b638fa4f76da86c48aa57ff2` ([PR #50](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/50), draft and unmerged).
- Reused corrected production source from `e5a66a7558c027e54b1510e7197d6e3a331cff19` ([PR #58](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/58), draft and unmerged), tested and source-reviewed there.
- This is a **new, isolated child branch** `fix/f2-g1-pr50-ps51-entrypoint-bridge`; original PR #50/#58 branches are unchanged. The resulting commit SHA is read from the branch and must be independently pinned; no unstated code change is permitted.
- The minimal-path architectural design `05ee627d25e6bca4a1cb39d768ddae34c1135f34` remains conditional. Issue #48 limits apply.

## Production source changes (exactly two reused entrypoints)

1. `scripts/f2-acl/Invoke-F2IcaclsCapture.ps1`: replace StrictMode-unsafe pre-try `$args.Count` with `@($MyInvocation.UnboundArguments)` inside try; preserve zero-unbound-args fail-closed behavior and runtime import ordering.
2. `scripts/f2-acl/Invoke-F2IcaclsProtectedCoordinator.ps1`: reuse matching guarded argument validation and explicit CaptureId syntax check while retaining the exact installed-file location requirement and rejection before runtime module import.

Reused file bytes are the reviewed PR #58 production blob content. No parser, runtime, allocator, icacls builder, baseline collector, protocol, VM or guest change.

## Pin continuity

The PR #50 pin manifest remains the source of truth for unchanged modules and baseline collector. Exactly two entries change:

| Entry | PR #50 original | Reused PR #58 corrected |
|---|---|---|
| `LauncherScriptSha256` | `fb55240a16f0858980bb38851414b28ce5f403ba26697ff78f227ca22ff804b0` | `0b9214c3d6f6e96081b9d86aa8d62087c82527443f2c4b3e7ee09a1ca3dae818` |
| `CoordinatorScriptSha256` | `3badc19c8ac6ac450f9691258c6ecd2a3754cd665fd5989325c90b64290ae9e2` | `e965823752518edfcac7ed50bd49bf489f6d924fa404e41138266857ea41b624` |

Retained unchanged pins:
- Corroboration `06acb1d2eee45abcf1531a9b7113e342320b239bbc32aae1a10d114b55eaa13e`
- Runtime `e6751179d2a36abea65527c260fb0f1d1cc81bdccf867172befba4e9f5dffddc`
- Collector `bea7cc93710c83d48a8ef9e54af306401694f17f611e696caa856938ca71a19b`
- Protocol `42ba4dd5e31d1db64198bb1cee16d519f087a40364dfb4d2696b4a5bd844d728`
- Collector base commit `a62773f0553dff4a05055b18fa10834f7488ae55`

**Expected source-only updated F2_ICACLS_SOURCE_PINS.json SHA-256 (LF file bytes):** `37d0b94f148a66cc8f444c6db33930b6e07d84f7c56e7f729948bd25c7100926`; independently recompute on exact reviewed source. It is **not** a protected installed release manifest and cannot act as an external trust root.

## Synthetic-only validation plan and required acceptance

- `Test-F2AclEntrypointArguments.ps1`: reused PR #58 synthetic PowerShell 5.1 `-File` fixtures, 18 focused assertions; zero/extra launcher args; named/positional extra coordinator args; valid/invalid/missing CaptureId; coordinator path mismatch; source syntax/guard ordering. The test reads production source but executes only synthetic TEMP fixtures.
- `Test-F2AclCapture.Protocol.ps1`, `Test-F2AclIcacls.Corroboration.ps1`, `Test-F2AclIcacls.Runtime.ps1`: retained PR #50 synthetic suites. The source-only GitHub Windows workflow includes the new focused test and parser sweep.
- Negative outcomes, CI runner metadata, parser results, tracked hashes, process exits and `git diff --check` are independently reviewable. Never equate synthetic pass with real UAC/runtime.
- New source branch pin/commit and exact test results must be reviewed independently before any subsequent *separately authorized* protected package action.
- An eventual candidate external release manifest must be generated against the **final independently reviewed source SHA**, all seven exact physical hashes including this revised pin manifest, and an independently owner-approved protected trust-root mechanism. No current installed state can be inferred.

## Strict exclusions / residual gates

No actual host C:/G:/Hyper-V or protected evidence read/write; no UAC, installed launcher, coordinator, `icacls`, ACL change, VM/guest start, Godot, Voxel Tools, V3 updater, recovery, PR, merge or release. This work does not resolve the historical source absence of Phase 2B.2 provisioning or the capability/shared-group effective-rights questions.

Preserve `ACL_REVIEW_REQUIRED / G1_BLOCKED_ENVIRONMENT / F2_G1_RELEASE_HOLD / CURRENT_PROTECTED_STATE_UNKNOWN / V3_NOT_ATTESTED`. Post-third-UAC host attestation and owner execution permission are separate future gates.
