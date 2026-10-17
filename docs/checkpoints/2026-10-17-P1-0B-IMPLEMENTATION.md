# Immutable documentary checkpoint — P1.0B implementation handoff

**Checkpoint ID:** `CHK-2026-10-17-P1-0B-IMPLEMENTATION`

**Event:** P1.0B dynamic region streaming and camera-aligned visibility correction implemented and locally validated; independent source review and owner GUI retest are the next gates.

**Publication state at creation:** implementation is on `feat/p1-0b-dynamic-region-streaming`, based on `7f87c1e9c0cc1e85dd5c5fb612ebf2cd40aeffb0`. Draft PR creation is authorized and pending final publication. No merge or release is authorized.

## Implementation and validation evidence

- The camera focus uses the existing floor-based spatial ownership map. A 3×3 request window loads dynamically, completed regions remain resident through radius two, and the active render cap is 25 regions / 400 chunk meshes.
- Region generation is progressive: at most one two-cell-high mesh slice is built per process frame; the complete 16-chunk region publishes together. Existing C/R/X full rebuilds stage the visible target set before replacement. Existing seed, generator, negative-coordinate mapping, global Z=6 section and chunk seam rules are retained.
- A subtle camera-child spotlight was added. The existing lit terrain material, ambient contribution and directional light remain in use.
- Godot 4.7.2 stable official `ed1daf0bf` full local validation passed: import; smoke 52/52; SDF 40/40; brush 89/89; chunk 179/179; multiregion/streaming 7,565/7,565; bootstrap 18/18; main-scene startup. Total: 7,943 assertions, zero failures. `git diff --check` passed.
- The streaming suite observed 9 regions / 144 chunks / 87,077 triangles after initial fill. Maximum resident count during traversal was 12; 21 loads and 9 unloads were observed. The initial headless window completed in 9,964 ms, with 5,231 ms total measured mesh work, 20.551 ms peak slice time and 20.676 ms peak controller work.

## Limits and next gates

The one-slice-per-frame bound is a work-count bound, not a frame-time guarantee. The measured indivisible synchronous slice exceeded 16.7 ms on this machine. Full initial population took about ten seconds headlessly, and can take longer in a frame-paced GUI. The scene has not received an owner GUI or pixel retest; lighting assertions check configuration, not rendered appearance. Edits remain transient, are capped at 16 edited region states, and cannot cross region boundaries. Persistence, networking, LOD, P1.0C and release remain out of scope.

The next authorized actions are to commit and publish one draft PR, conduct independent source review of its exact final SHA, and have the owner perform the visual retest. Preserve the operational holds: `CURRENT_PROTECTED_STATE_UNKNOWN`, `V3_NOT_ATTESTED`, `ACL_REVIEW_REQUIRED`, `G1_BLOCKED_ENVIRONMENT`, `F2_G1_RELEASE_HOLD`.
