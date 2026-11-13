class_name DM18CanonicalRegionCache
extends RefCounted

## DM18 experimental, derived 16-chunk canonical MESH RESOURCE cache.
## Not an edit ledger, physics authority, object stream or simulation scope.
## Records can be replayed ONLY through TerrainDemo._publish_region with fresh
## world state and a new stage token, after exact revision/identity checks.
## ArrayMesh references retain GPU resources as well as engine-managed memory:
## this byte budget is an ESTIMATE, not a precise RAM/VRAM accounting.
const MAX_ENTRIES := 192
const MAX_ESTIMATED_BYTES := 134_217_728 # 128 MiB
const MAX_RECORD_BYTES := 16_777_216 # 16 MiB; huge regions bypass cache

var _records: Dictionary = {}
var _lru: Array[String] = []
var _estimated_bytes := 0

var stores := 0
var hits := 0
var misses := 0
var rejected := 0
var evictions := 0
var cached_meshes := 0


static func identity(
	world_seed: int, generator_version: int,
	brush_scope_id: int, brush_revision: int,
	effect_revision: int, cave: bool, backend: String
) -> Dictionary:
	return {
		"seed": world_seed,
		"generator_version": generator_version,
		"brush_scope_id": brush_scope_id,
		"brush_revision": brush_revision,
		"effect_revision": effect_revision,
		"cave": cave,
		"backend": backend,
	}


static func same_identity(a: Dictionary, b: Dictionary) -> bool:
	if a.is_empty() or b.is_empty():
		return false
	for key in ["seed", "generator_version", "brush_scope_id",
			"brush_revision", "effect_revision", "cave", "backend"]:
		if not a.has(key) or not b.has(key) or a[key] != b[key]:
			return false
	return true


func remember(region_id: String, region_key: Vector2i,
	identity_token: Dictionary, meshes: Dictionary,
	lods: Dictionary, fallback: Dictionary,
	vertex_counts: Dictionary, triangle_counts: Dictionary
) -> bool:
	if region_id.is_empty() or identity_token.is_empty() or meshes.size() != 16 	or lods.size() != 16 or vertex_counts.size() != 16 	or triangle_counts.size() != 16:
		return false
	var byte_estimate := 0
	for coord_value in meshes.keys():
		var coordinate: Vector2i = coord_value
		var mesh: Mesh = meshes[coordinate]
		if mesh == null or mesh.get_surface_count() < 1 		or not lods.has(coordinate) or int(lods[coordinate]) != 0 		or not vertex_counts.has(coordinate) or not triangle_counts.has(coordinate):
			return false
		# At least position+normal+GPU overhead, deliberately conservative.
		byte_estimate += maxi(1, int(vertex_counts[coordinate])) * 48 + 2048
		if byte_estimate > MAX_RECORD_BYTES:
			return false
	erase(region_id)
	_records[region_id] = {
		"region_key": region_key,
		"identity": identity_token.duplicate(true),
		"meshes": meshes.duplicate(),
		"lods": lods.duplicate(),
		"fallback": fallback.duplicate(),
		"vertex_counts": vertex_counts.duplicate(),
		"triangle_counts": triangle_counts.duplicate(),
		"estimated_bytes": byte_estimate,
	}
	_lru.append(region_id)
	_estimated_bytes += byte_estimate
	stores += 1
	cached_meshes += meshes.size()
	_enforce_budget()
	return _records.has(region_id)


func lookup(region_id: String, expected_identity: Dictionary) -> Dictionary:
	if not _records.has(region_id):
		misses += 1
		return {}
	var record: Dictionary = _records[region_id]
	if not same_identity(record.get("identity", {}), expected_identity):
		rejected += 1
		erase(region_id)
		return {}
	for mesh_value in (record["meshes"] as Dictionary).values():
		if not is_instance_valid(mesh_value) or (mesh_value as Mesh).get_surface_count() < 1:
			rejected += 1
			erase(region_id)
			return {}
	hits += 1
	_lru.erase(region_id)
	_lru.append(region_id)
	return {
		"region_key": record["region_key"],
		"meshes": (record["meshes"] as Dictionary).duplicate(),
		"lods": (record["lods"] as Dictionary).duplicate(),
		"fallback": (record["fallback"] as Dictionary).duplicate(),
		"vertex_counts": (record["vertex_counts"] as Dictionary).duplicate(),
		"triangle_counts": (record["triangle_counts"] as Dictionary).duplicate(),
	}


func has_region(region_id: String) -> bool:
	return _records.has(region_id)


func is_reusable(region_id: String, expected_identity: Dictionary) -> bool:
	return _records.has(region_id) 		and same_identity((_records[region_id] as Dictionary).get("identity", {}), expected_identity)


func erase(region_id: String) -> void:
	if not _records.has(region_id):
		return
	var record: Dictionary = _records[region_id]
	_estimated_bytes = maxi(0, _estimated_bytes - int(record["estimated_bytes"]))
	_records.erase(region_id)
	_lru.erase(region_id)


func clear() -> void:
	_records.clear()
	_lru.clear()
	_estimated_bytes = 0


func stats() -> Dictionary:
	return {
		"entries": _records.size(),
		"estimated_bytes": _estimated_bytes,
		"stores": stores, "hits": hits, "misses": misses,
		"rejected": rejected, "evictions": evictions,
		"cached_meshes_total": cached_meshes,
	}


func _enforce_budget() -> void:
	while _records.size() > MAX_ENTRIES or _estimated_bytes > MAX_ESTIMATED_BYTES:
		if _lru.is_empty():
			return
		evictions += 1
		erase(_lru[0])
