# P3.1 Storage implementation gates

Status: WORK STARTED / NO PRODUCTION CODE YET. Owner authorized implementing new scalable terrain save version with clean-start (no schema-1 import). Baseline `5997a76d345f45bf86edfe83f690336391e8be27`. Issue #127; design PR #128 stays independently draft. No merge approved.

## Mandatory behavior

- Distinct v2 save namespace from schema 1; do not auto-delete/overwrite legacy generations; unsupported legacy reports explicit choose-new-world action. Keep entity schema 3 independent and untouched.
- Immutable globally ordered CARVE/FILL authoritative operation IDs; durable segmented append/checkpoint with hash validation, crash/restart recoverability, idempotency and revision checks. Cross-region indices reference one operation rather than duplicating authority.
- At least >256 edits both sparse distributed and dense concentrated, preserving CARVE/FILL chronology and negative boundary consistency. Avoid naive sphere-support pruning: min/max SDF tails may matter outside geometric support. Exact sampling parity with v1 reference semantics for any admitted workload.
- No pretend unlimited capacity. Explicit quotas, bounded memory, index fanout, segment sizes and fail-closed disk errors. Snapshots or compact representations only where mathematically exact; otherwise keep ordered operations.
- Separate logical immutable historical operations from mesh caches. Resume from last verified durable generation, never expose uncommitted in-flight state as committed.
- Full Godot 4.7.2 validation + focused fault injection (append interrupted, segment corrupt, manifest lost, full disk, recovery), p50/p95/p99 scalability measurements, owner GUI clean new-world tests, and independent exact-SHA source review. No edit to real saves or workspaces; protect five F2-G1 holds and stashes/untracked UIDs.

This initial file is a work assignment / gate record, **not evidence that the storage code exists or tests passed**.
