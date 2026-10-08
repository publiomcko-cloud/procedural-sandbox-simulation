# Candidate-independent terrain adapter proposal

**Status:** Proposed conceptual contract for P0.1 review; not an implementation API.
**Authority:** subordinate to accepted ADR-0001 and `docs/architecture/CONTRACTS.md`. Does not select a backend or modify the accepted baseline.

## Design boundary

The simulation/domain layer owns world identity, generator manifest, deterministic base-field rules, edit command validation, revision numbers, canonical edit records, material-property definitions, and authoritative receipts. A terrain backend is a replaceable provider of field samples and derived products. Godot nodes, meshes, colliders, and backend caches are presentation/acceleration artifacts; they do not own world truth.

All operations below are conceptual. Concrete types, units, coordinate encoding, chunk dimensions, edit transaction guarantees, LOD policy, and schema versions require owner/evaluator review before implementation.

## Minimum domain interfaces

```text
TerrainAddress {
  world_id, region_key_i64_xyz, local_position, coordinate_schema
}

TerrainSample {
  density, material_blend[], source_revision, generator_version
}

RegionRequest {
  request_id, world_id, region_key, lod, bounds, priority,
  required_halo, expected_revision, backend_epoch
}

RegionData {
  immutable density/material field, region_revision,
  halo_revision_map, generator_manifest, edit_schema
}

EditCommand {
  command_id, actor_id, operation, stable_material_ids,
  canonical_parameters, affected_bounds, expected_revision_map,
  generator_manifest, command_schema_version
}

EditReceipt {
  command_id, outcome, committed_revision_map,
  invalidated_region_keys, durable_sequence, reason
}

BuildRequest {
  request_id, region_key, lod, source_revision,
  halo_revision_map, backend_epoch, outputs(mesh, collision)
}

BuildResult {
  request_id, region_key, lod, source_revision,
  halo_revision_map, backend_epoch, mesh_payload, collision_payload
}
```

### Query density and material

- `query_sample(address, consistency) -> sample | pending | unavailable | error` returns normalized domain density and zero or more stable material IDs/weights; it never exposes backend channel indices as stable identity.
- `query_batch(addresses, consistency)` may be added for performance, but must have identical semantic results.
- Density zero defines the isosurface. Proposed normalized convention is `density > 0` solid, consistent with the project architecture proposal; adapt signs at the provider boundary and confirm with owner before implementing. Material sample interpolation/weight normalization and missing-material behavior must be deterministic.
- Queries identify source revision and generator manifest so simulation consumers can detect stale samples.

### Request region data

- `request_region(request) -> request_id` is asynchronous and idempotent for the same request identity. Completion publishes immutable `RegionData` or an explicit failure.
- Region key uses stable wide signed integer coordinates; never derive identity from floating-point world coordinates or load order.
- Requested data includes a halo of at least one sample for central-difference normals; the eventual extraction stencil determines whether face-only or all 26 neighbors are dependencies.
- Unavailable data is explicit. An edit must not silently clip at unloaded boundaries.

### Apply revisions and edits

- `apply_edit(command) -> accepted | revision_conflict | invalid | unavailable | failed` is called only by the authoritative mutation coordinator.
- Validate permissions, operation parameters, material IDs, generator/schema compatibility, all affected region revisions, and region availability before commit.
- Successful multi-region commands append one canonical, ordered domain edit record and increment every affected region revision as one logical transaction. Backend cache changes are derived from that committed record and can be rebuilt.
- Minimum operations for the experiment: smooth add, subtract, sculpt/smooth, paint material. A proposed future transform-selection operation must preserve its clip/resample/relocation policy outside this minimum spike.
- Concurrent commands either serialize by domain transaction order or reject stale expected revisions. Never partial-commit silently.

### Invalidate neighbors and dependent products

- Commit returns the complete dependency invalidation set: changed regions plus neighbors read by the meshing/normal/collision stencil, and any cross-LOD transition owners.
- Neighbor invalidation carries each region's new revision. Default experiment assumes one-voxel halo and tests all 26 adjacent regions; narrow this only after proving the selected extraction/normal/collision stencil.
- Render, collision, navigation, hydrology and material-derived data have separate product flags/revisions. A backend may omit unsupported products only through an explicit capability result.

### Build and publish mesh/collision results

- Workers consume immutable snapshots and produce plain mesh/collision payloads with request ID, backend epoch, region revision, halo revisions, LOD and coordinate origin.
- Main-thread publication verifies world still loaded, epoch matches, every dependency revision still matches, and request remains current. Mismatched results are discarded; they must not overwrite newer geometry or collide with updated domain truth.
- Create or mutate Godot `Mesh`, physics resources and scene nodes only on a thread permitted by the pinned Godot API/configuration; prefer worker-built plain arrays plus main-thread resource integration.
- A publication receipt separately records mesh-visible revision and collision-active revision. This makes temporary visual/physics lag measurable and lets commands choose whether interaction waits for collision readiness.
- Shutdown/unload cancels or invalidates in-flight work and waits for persistence completion according to a documented policy.

### Serialize edits

- The domain serializer records world UUID, seed, generator ID/version/config hash, material registry manifest, edit schema, canonical commands, affected region keys and monotonic durable sequence/checkpoint marker.
- Backend-specific voxel blocks may be stored as a rebuild cache, but cannot replace the canonical edit log until recovery/migration guarantees are independently demonstrated and accepted.
- Deserialization validates versions and required IDs. Missing generator/material definitions fail explicitly or open a documented read-only recovery path; never discard data silently.
- P0.1 experiment must prove edit → save completion → unload/reload → close/reopen replay equality for fixed fixture cases. Crash injection and full crash-consistency proof belong to P0.2 unless owner expands scope.

## Determinism and concurrency invariants

1. `base_sample = f(world_seed, generator_version, region_key, coordinate, generator_parameters)` is independent of region request/traversal order and worker scheduling.
2. Mutable edit records are applied in canonical sequence order. Backend internal compression/meshing may vary if the authoritative field hash and serialized state remain equivalent.
3. Request keys include `backend_epoch` and source revisions; old results cannot publish after unload, replacement, edit, or backend restart.
4. Workers read immutable snapshots. They do not mutate domain truth or access the live scene tree.
5. Same supported platform/engine/configuration canonical sample and edit hashes must match exactly. Cross-platform bitwise equivalence is not claimed until measured and specified.

## Mod-facing boundary

Public mods receive versioned declarative material/property registration, density/material queries, and validated edit commands through a stable project facade. They do not receive `VoxelTool`, `VoxelBuffer`, `VoxelLodTerrain`, native pointers, `MeshInstance3D`, or persistence database handles. Script mods remain trusted executable code as ADR-0001 states. Adapter/backend version changes must not require content mods to branch on vendor IDs.

## Capability discovery and errors

Adapter reports supported resolutions/LODs, smooth operation set, collision product behavior, maximum query/edit range, async cancellation, persistence-cache support, and limitations. Unsupported request -> typed result with reason. Do not infer a feature from a visible node property or ignore it silently.

## Acceptance tests for a later implementation spike

- Stable sample/material results for fixed seed+version over reordered region requests.
- Positive/negative material edits across a two-or-more-region border; exact field equality after save/load.
- LOD transition seam inspection and automated gap/overlap checks; edit visible/collision revisions reconcile to committed revision.
- Two rapid conflicting edits: one serializes or reports revision conflict, with no torn region set.
- Edit while mesh build is in flight: old result is rejected, current revision eventually publishes.
- Unload/reload with background work in flight: no late publish into a new region/backend epoch.
- Public mod fixture queries and edits using only facade types and namespaced material IDs.
