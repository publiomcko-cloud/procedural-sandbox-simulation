# 2026-11-08 — P4.0B integration receipt

## Terminal status

`P4_0B_INTEGRATED / DOMAIN_SIMULATION_NOT_STARTED`

Integration identity:

- issue: #263;
- PR: #264;
- qualified runtime/source: `d741d1fa0711034a46ac4d57450310a365114f8b`;
- final PR head: `ed38295c786d0b5e059d157c4d55a0e2c24d6a64`;
- merge commit on `main`: `25a2dd8687cf513aa414a0469dc1f5de659863e3`;
- Godot: `4.7.2.stable.official.ed1daf0bf`.

## Pre-merge gates

The final PR head passed:

- Starter checks: SUCCESS;
- P4.0B simulation tier framework: SUCCESS.

The qualified runtime/source passed the complete self-hosted Windows/X64 Godot 4.7.2 envelope:

- P4.0B focused: 67/67;
- P4.0A focused: 74/74;
- M4.0 focused: 31/31;
- declarative mods: 79/79;
- entity commands: 67/67;
- Issue #108 D8: 34/34;
- placement: 53/53;
- smoke: 52/52;
- terrain SDF: 46/46;
- LOD0/1: 6474/6474;
- bootstrap: 18/18;
- startup: PASS.

The procedural-object suite preserved the accepted historical envelope exactly: 671/1, one camera-revisit failure, nine same-revision fingerprint conflicts and zero `SCRIPT ERROR`.

## Integrated capability

The integrated P4 foundation now contains:

- deterministic bounded fixed-tick scheduling;
- scalar deferred catch-up;
- pause/manual step;
- stable simulation scope IDs;
- explicit `active / aggregate / dormant` tiers;
- independent tier/state revisions;
- bounded data-only generic state;
- deterministic aggregate cadence;
- direct identity-routed due decisions;
- deterministic tier snapshot/restore;
- atomic scheduler+tier runtime restore;
- scheduler/tier performance telemetry.

## Visual acceptance

No separate owner visual acceptance is required for P4.0B itself because this slice introduces no new rendered effect, user interaction, material presentation or visible simulation behavior.

A visual/interactive acceptance gate becomes mandatory when a later P4 slice introduces user-observable simulation behavior, such as automatic tier-driven visible changes or the first material/environment domain. A final P4 exit still requires end-to-end visual/interactive acceptance.

## Next frontier

P4.0B does not select the next domain slice.

The remaining near-term P4 choices are:

1. bounded automatic tier-assignment/routing policy; or
2. first mod-first material/environment state domain.

Neither was included in PR #264.
