# P1.0A static multi-region ownership

P1.0A changes the P0.1 demonstration from one oversized mesh domain to a fixed
3×3 preview of logical regions centered on region `(0,0)`. It is a static render
set for this run; it does not load or unload regions.

## Coordinate contract

The version-1 SDF remains stateless and keeps its existing world-position phase:

```text
world_x = region_key.x * 16 + region_local_x
world_z = region_key.y * 12 + region_local_z
```

Each region owns X/Z cells in the half-open domain `[0,16) × [0,12)` at a 0.5
unit sample step: 32×24 cells. Its upper lattice samples at X=16 and Z=12 are
available to interpolate boundary cells, but those samples do not create another
cell or rendered skirt. Mathematical floor selects region ownership, including
negative coordinates: world X=-0.01 belongs to region X=-1 with local X=15.99.

Each region divides its cells into 4×4 chunks of 8×6 cells. Chunk IDs include
signed region and chunk coordinates. Mesh vertices remain region-local and each
chunk node receives the exact integer-derived world origin of its region plus
its local chunk origin. The SDF is evaluated at the same world coordinates on
each side of region and chunk boundaries.

The fixed preview contains region keys `(-1..1, -1..1)`, or 9 regions and 144
chunk render nodes. Seed, generator version, region keys and ordered edits remain
in `TerrainWorldState`, separate from those nodes. The center region is the only
editable region in this increment. A picked surface point is mapped to its
half-open region before accepting an edit; neighbor-region hits and center brush
spheres that reach a region or mesh boundary are rejected without mutation.
Cross-region edits, persistence, streaming and networking are deferred.

The C visualization uses one world-space plane at Z=6, so it does not restart at
each region. It affects rendered density only and does not change canonical SDF
samples or the ordered center edit list. Cave placement continues along global X
according to the original version-1 formula.

Automated checks enumerate ownership across all 6,912 cells in the 3×3 grid,
compare the 144-chunk union with a monolithic world-space reference, check all
264 adjacent chunk boundaries (including region seams) for position and normal
continuity, test signed region/corner sample continuity, and exercise center-only
viewport edits. The headless checks do not substitute for the owner's visual
inspection of the 3×3 view.
