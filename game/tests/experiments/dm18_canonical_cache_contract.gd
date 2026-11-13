extends SceneTree

## DM18 cache safety: all 16 chunks, exact refs, revision/seed/effects/cave,
## new stage ownership, bounded capacity and no warm-read mutation.
const Cache := preload("res://scripts/terrain/dm18_canonical_region_cache.gd")
const Grid := preload("res://scripts/terrain/terrain_chunk_grid.gd")
var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var cache := Cache.new()
	var id := Cache.identity(424242, 1, 314, 7, 11, false, "b4")
	var meshes := {}
	var lods := {}
	var fallback := {}
	var vertices := {}
	var triangles := {}
	var coordinates := Grid.all_coordinates()
	for coord in coordinates:
		meshes[coord] = ArrayMesh.new()
		lods[coord] = 0
		fallback[coord] = false
		vertices[coord] = 0
		triangles[coord] = 0
	_check(not cache.remember("bad", Vector2i.ZERO, id, {}, lods,
		fallback, vertices, triangles), "never store partial region")
	_check(cache.remember("0,0", Vector2i.ZERO, id, meshes, lods,
		fallback, vertices, triangles), "stores full 16 mesh region")
	var warm: Dictionary = cache.lookup("0,0", id)
	_check(warm.size() > 0 and warm["meshes"].size() == 16, "lookup all chunks")
	for coord in coordinates:
		_check(warm["meshes"][coord] == meshes[coord], "exact mesh references")
	_check(cache.is_reusable("0,0", id), "same identity reusable")
	(warm["meshes"] as Dictionary).erase(Vector2i.ZERO)
	_check((cache.lookup("0,0", id)["meshes"] as Dictionary).size() == 16,
		"lookup dictionary detached from cache")
	for field in ["seed", "generator_version", "brush_scope_id", "brush_revision",
			"effect_revision", "cave", "backend"]:
		var rejected_id := id.duplicate(true)
		if field == "cave":
			rejected_id[field] = true
		elif field == "backend":
			rejected_id[field] = "sdf"
		else:
			rejected_id[field] = int(rejected_id[field]) + 1
		_check(not cache.is_reusable("0,0", rejected_id),
			"reject stale " + field)
		_check(cache.lookup("0,0", rejected_id).is_empty(),
			"refuse stale lookup " + field)
		_check(cache.remember("0,0", Vector2i.ZERO, id, meshes, lods,
			fallback, vertices, triangles), "repopulate after invalidation " + field)
	# Budget is enforced by ESTIMATED bytes; the real engine RAM/VRAM is
	# measured in the integrated runner. No eviction may happen silently.
	for coord in coordinates:
		vertices[coord] = 5500
	for n in range(65):
		_check(cache.remember("r-" + str(n), Vector2i(n, 0), id, meshes,
			lods, fallback, vertices, triangles), "store bounded region")
	var stat: Dictionary = cache.stats()
	_check(int(stat["estimated_bytes"]) <= Cache.MAX_ESTIMATED_BYTES,
		"budget respected")
	_check(int(stat["entries"]) <= Cache.MAX_ENTRIES, "LRU entry cap respected")
	_check(int(stat["evictions"]) > 0, "eviction exercised")
	_check(cache.lookup("unknown", id).is_empty(), "miss is non-mutating")
	cache.clear()
	_check(int(cache.stats()["entries"]) == 0, "explicit reset")
	print("DM18_CANONICAL_CACHE_RESULT=" + JSON.stringify({
		"checks": checks, "failures": failures, "limit_bytes": Cache.MAX_ESTIMATED_BYTES,
		"before_clear": stat
	}))
	print("DM18_CANONICAL_CACHE_%s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("DM18_CANONICAL_CACHE_FAIL: " + message)
