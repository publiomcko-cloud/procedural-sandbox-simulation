# P0.1 localized terrain chunk coordinates

This document records the original single-region P0.1 chunk contract. The fixed
mesh domain described here was superseded by P1.0A; current region ownership,
canonical bounds and multi-region behavior are defined in
[`P1_0A_MULTIREGION_OWNERSHIP.md`](P1_0A_MULTIREGION_OWNERSHIP.md).

The shared data model remains useful: `TerrainWorldState` owns the seed,
generator version, region key and ordered brush operations, while scene nodes
own rendered chunk meshes. No networking or persistence is part of these
increments.

Brush centers and radii use region-local world coordinates. Accepted edits are
ordered data with monotonic sequence numbers. Chunk mesh vertices are local to
their chunk nodes, and stable chunk identities derive from region keys and
integer chunk coordinates rather than scene-node names. This keeps canonical
world state independent from rendering objects and suitable for future
replicated operations.
