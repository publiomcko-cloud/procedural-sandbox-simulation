# P0.1 Localized terrain chunk coordinates

The demonstration region is a deterministic, finite SDF domain. `TerrainWorldState`
owns the seed, generator version, region key and ordered brush operations; scene
nodes own only the rendered chunk meshes. No networking or persistence is part of
this increment.

The X/Z domain has 36 by 28 cells at a 0.5-unit sample step. It is partitioned
into a fixed 4 by 4 grid. Cell ownership uses half-open ranges: a cell belongs to
exactly one chunk, while both adjacent chunks sample the shared lattice plane.
This keeps every cell emitted once and derives both sides of a seam from the same
world-space SDF coordinates.

Brush centers and radii use region-local world coordinates. An accepted operation
is stored as ordered data with a monotonic sequence number and increments the
world-state revision. A conservative one-sample-step halo selects every chunk
whose cells can depend on changed SDF samples. A brush rebuild replaces those
chunk meshes only; C and R rebuild all chunks while preserving edits, and X clears
the transient edit list before rebuilding.

Chunk mesh vertices are local to the chunk node. The node is positioned at the
chunk's X/Z region-local origin and Y=0. The stable identity is derived from the
region key and integer chunk coordinate, not a scene-node name. This leaves the
data model suitable for future replicated operations while keeping rendering
objects out of canonical world state.

The visible mesh is triangulated as a whole-region reference and as independent
chunks in tests. Their quantized triangle multisets and shared-boundary surface
vertices/normals are compared. Timings compare synchronous full-region generation
with synchronous generation of the affected chunks; they are measurements for
this fixed domain, not a performance guarantee.
