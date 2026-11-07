# 2026-11-07 — Issue #108 closure and M4.0 pre-P4 architecture handoff

## Event

The owner declared Issue #108 complete after D.8 and instructed that the mod-first architecture recommendations and Issue #108 performance lessons be recorded before proceeding to M4.0.

Issue #108 is closed on GitHub as `completed`.

Final functional integration:

- PR #254 — D.8 precision-safe LOD1 terrain-object effects;
- merge commit `5a69a2ec9e96411fd256abc97ae9a6c32d4658a9`;
- Issue #108 closure comment records owner GUI acceptance.

## Accepted architectural decisions

Two new decisions are recorded:

1. [ADR-0007 — Generalize the mod-first content core before P4](../decisions/ADR-0007-MOD-FIRST-CONTENT-CORE-BEFORE-P4.md).
2. [ADR-0008 — Main-thread budget, derived-work isolation and performance observability](../decisions/ADR-0008-MAIN-THREAD-BUDGET-AND-PERFORMANCE-OBSERVABILITY.md).

The owner authorizes M4.0 as the next development slice after this documentary handoff.

P4 implementation remains downstream of M4.0.

## Current mod-first boundary

Accepted as already working:

- common first-party/external package discovery;
- data-only manifests;
- dependency/version validation;
- deterministic content registration and pinning;
- procedural-rock definitions;
- static population rules;
- terrain-interaction rules;
- deterministic procedural object generation;
- persistent sparse object/entity state;
- player/editor/mod entity command origin contract;
- Issue #108 terrain-effect derivation from mod-defined object interaction rules.

Not yet generalized:

- registry internals still directly know the three current content families;
- primary definition pins do not yet have a uniform canonical content SHA-256 contract;
- base terrain/caves/material systems are still engine-owned/hard-coded;
- P4/P5 simulation content contracts do not yet exist;
- data-only mods cannot introduce arbitrary executable algorithms or components.

## M4.0 intent

M4.0 is a behavior-preserving architectural gate:

- generalize content registration through engine-owned type handlers;
- preserve the existing declarative loader;
- preserve first-party/external parity;
- add a uniform canonical content fingerprint/pin surface;
- keep existing object/population/terrain-effect semantics and identity stable;
- prove a synthetic new content type can be added through a handler without modifying loader discovery;
- do not begin environmental simulation yet.

## Performance handoff

The accepted retrospective is:

[Issue #108 performance retrospective and forward development rules](../reports/2026-11-07-ISSUE108-PERFORMANCE-RETROSPECTIVE.md).

The binding forward rule is ADR-0008: future streamed/simulated systems must be bounded, revision-gated, decomposed into pure worker preparation and bounded main-thread commits where applicable, directly indexed rather than globally scanned, and instrumented at stage level.

## Authority boundary

This checkpoint authorizes the M4.0 implementation slice.

It does not authorize:

- P4 implementation before M4.0 qualification;
- scripted mod execution;
- terrain backend replacement;
- physics/collision/networking;
- changes to protected F2-G1 work.
