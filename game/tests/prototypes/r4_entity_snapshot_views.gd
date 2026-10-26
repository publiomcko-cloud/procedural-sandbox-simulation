extends RefCounted

## Logical sharing model only. Terrain samples are stored once as immutable
## content-addressed bytes; entity state is revisioned and serialized separately.
## This does not claim thread-safe or production persistence semantics.
const MAX_BYTES := 1024 * 1024

var _terrain := {}
var _entities := {}
var last_reason := ""


func register_terrain(snapshot: RefCounted) -> String:
	last_reason = ""
	var densities: PackedFloat32Array = snapshot.densities
	var payload := var_to_bytes({"region": snapshot.region, "chunk": snapshot.chunk,
		"spacing": float(snapshot.spacing), "world_seed": int(snapshot.world_seed),
		"generator_version": int(snapshot.generator_version), "revision": int(snapshot.revision),
		"densities": densities})
	var content_hash := _sha256(payload)
	if not _terrain.has(content_hash):
		_terrain[content_hash] = {"payload": payload, "density_bytes": densities.size() * 4,
			"revision": int(snapshot.revision), "references": 0}
	elif _terrain[content_hash].payload != payload \
		or int(_terrain[content_hash].revision) != int(snapshot.revision):
		last_reason = "terrain_snapshot_identity_collision"
		return ""
	return content_hash


func attach_entity(entity_id: String, terrain_hash: String, initial_state: Dictionary) -> bool:
	last_reason = ""
	if entity_id.is_empty() or _entities.has(entity_id) or not _terrain.has(terrain_hash):
		last_reason = "entity_identity_or_terrain_missing"
		return false
	_entities[entity_id] = {"terrain_hash": terrain_hash, "revision": 0,
		"state": initial_state.duplicate(true)}
	_terrain[terrain_hash].references = int(_terrain[terrain_hash].references) + 1
	if not _within_quota():
		_entities.erase(entity_id)
		_terrain[terrain_hash].references = int(_terrain[terrain_hash].references) - 1
		last_reason = "entity_view_quota_exceeded"
		return false
	return true


func update_entity(entity_id: String, expected_entity_revision: int,
		expected_terrain_revision: int, component: String, value: Variant) -> bool:
	last_reason = ""
	if not _entities.has(entity_id):
		last_reason = "entity_not_found"
		return false
	var entity: Dictionary = _entities[entity_id]
	var terrain: Dictionary = _terrain[entity.terrain_hash]
	if int(entity.revision) != expected_entity_revision \
		or int(terrain.revision) != expected_terrain_revision:
		last_reason = "stale_entity_or_terrain_revision"
		return false
	if component.is_empty():
		last_reason = "entity_component_invalid"
		return false
	var next_state: Dictionary = entity.state.duplicate(true)
	next_state[component] = value
	var previous_state: Dictionary = entity.state
	entity.state = next_state
	entity.revision = expected_entity_revision + 1
	_entities[entity_id] = entity
	if not _within_quota():
		entity.state = previous_state
		entity.revision = expected_entity_revision
		_entities[entity_id] = entity
		last_reason = "entity_view_quota_exceeded"
		return false
	return true


func entity_snapshot(entity_id: String) -> Dictionary:
	return _entities.get(entity_id, {}).duplicate(true)


func stats() -> Dictionary:
	var terrain_bytes := 0
	var density_bytes := 0
	var entity_bytes := 0
	for entry in _terrain.values():
		terrain_bytes += (entry.payload as PackedByteArray).size()
		density_bytes += int(entry.density_bytes)
	for entry in _entities.values(): entity_bytes += var_to_bytes(entry.state).size()
	return {"unique_terrain_snapshots": _terrain.size(), "entity_views": _entities.size(),
		"terrain_serialized_bytes_once": terrain_bytes, "density_payload_bytes_once": density_bytes,
		"separate_entity_state_bytes": entity_bytes,
		"total_bytes": terrain_bytes + entity_bytes, "quota_bytes": MAX_BYTES}


func _within_quota() -> bool:
	return int(stats().total_bytes) <= MAX_BYTES


func _sha256(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()
