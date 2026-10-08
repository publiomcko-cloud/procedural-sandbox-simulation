# ADR-0001: Project architecture baseline

**Status:** Accepted from owner decisions, 2026-10-08. Implementation details remain provisional.

**Decision:** Godot 4.7.2 stable for initial work; infinite/expandable chunked 3D world; smooth SDF voxel terrain with caves; terrain add/remove/sculpt/transform capability; hybrid procedural mesh objects; component/capability interaction; hybrid destruction; free placement with optional snapping; shared material-property system; deterministic base generation and versioned persistence; hybrid multi-resolution fixed-step simulation; data + trusted script mods; player and observer modes; V1 intermediate environmental simulation then V2 ecosystem simulation.

**Rationale:** Enables future editing and mods without coupling authored geometry to the simulation core.

**Constraints:** Transform-volume implementation may be deferred; all entities are addressable but need not be active physics objects. True infinite full-fidelity simulation is excluded.

**Change control:** New ADR required to change accepted choices; evidence and backward compatibility assessment required.
