class_name DM17SharedRegionLattice
extends RefCounted

## Experimental derived-only Q8.8 pristine SDF lattice shared by all 16 B4
## chunk workers of one region. This is NOT terrain/brush/effect authority.
## Workers coalesce a region build; cache entries are immutable and bounded.
const Field := preload("res://scripts/terrain/sdf_world.gd")
const Grid := preload("res://scripts/terrain/terrain_chunk_grid.gd")
const SCALE := 256.0
const NX := Grid.CELL_COUNT_X + 3
const NY := Grid.CELL_COUNT_Y + 3
const NZ := Grid.CELL_COUNT_Z + 3
const MAX_REGIONS := 64

static var _mutex := Mutex.new()
static var _cache: Dictionary = {}
static var _order: Array[String] = []
static var _inflight: Dictionary = {}


static func acquire(world_seed: int, region_key: Vector2i) -> Dictionary:
	var key := "%d:%d:%d:%d" % [
		Field.GENERATOR_VERSION, world_seed, region_key.x, region_key.y
	]
	while true:
		_mutex.lock()
		if _cache.has(key):
			var result: Dictionary = _cache[key]
			_mutex.unlock()
			var copy := result.duplicate(false)
			copy["cache_hit"] = true
			return copy
		if _inflight.has(key):
			var existing: Dictionary = _inflight[key]
			var waiting: Semaphore = existing["semaphore"]
			existing["waiters"] = int(existing["waiters"]) + 1
			_inflight[key] = existing
			_mutex.unlock()
			waiting.wait()
			continue
		var semaphore := Semaphore.new()
		_inflight[key] = {"semaphore": semaphore, "waiters": 0}
		_mutex.unlock()

		var built := _build(world_seed, region_key)
		_mutex.lock()
		var pending: Dictionary = _inflight.get(key, {})
		var waiters := int(pending.get("waiters", 0))
		_cache[key] = built
		_order.append(key)
		while _order.size() > MAX_REGIONS:
			_cache.erase(_order.pop_front())
		_inflight.erase(key)
		_mutex.unlock()
		for _index in range(waiters):
			semaphore.post()
		var copy := built.duplicate(false)
		copy["cache_hit"] = false
		return copy
	return {"valid": false, "reason": "unreachable"}


static func clear() -> bool:
	_mutex.lock()
	if not _inflight.is_empty():
		_mutex.unlock()
		return false
	_cache.clear()
	_order.clear()
	_mutex.unlock()
	return true


static func _build(world_seed: int, region_key: Vector2i) -> Dictionary:
	# Preserve DM11's exact arithmetic and quantization order so the region
	# lattice and the independent per-chunk baseline have identical Q8.8 nodes.
	var surface_terms := PackedFloat64Array()
	var cave_y_terms := PackedFloat64Array()
	var cave_dz_terms := PackedFloat64Array()
	surface_terms.resize(NX * NZ)
	cave_y_terms.resize(NX * NZ)
	cave_dz_terms.resize(NX * NZ)
	var phase := float(posmod(world_seed, 100003)) * 0.000173
	for z in range(-1, Grid.CELL_COUNT_Z + 2):
		var world_z := float(region_key.y) * Field.REGION_SIZE_Z + float(z) * Grid.SAMPLE_STEP
		var z_term := 0.70 * cos(world_z * 0.31 - phase * 0.7)
		for x in range(-1, Grid.CELL_COUNT_X + 2):
			var world_x := float(region_key.x) * Field.REGION_SIZE_X + float(x) * Grid.SAMPLE_STEP
			var i := (z + 1) * NX + x + 1
			surface_terms[i] = 3.8 \
				+ 1.25 * sin(world_x * 0.22 + phase) \
				+ z_term \
				+ 0.28 * sin((world_x + world_z) * 0.11 + phase * 0.3)
			cave_y_terms[i] = 1.15 + 0.24 * sin(world_x * 0.25 + phase)
			var cave_z := 6.0 + 1.05 * sin(world_x * 0.17 + phase * 0.6)
			cave_dz_terms[i] = world_z - cave_z
	var nodes := PackedInt32Array()
	nodes.resize(NX * NY * NZ)
	for y in range(-1, Grid.CELL_COUNT_Y + 2):
		var local_y := Grid.MIN_BOUND.y + float(y) * Grid.SAMPLE_STEP
		var row_start := (y + 1) * NZ * NX
		for z in range(-1, Grid.CELL_COUNT_Z + 2):
			var row := row_start + (z + 1) * NX
			for x in range(-1, Grid.CELL_COUNT_X + 2):
				var i := (z + 1) * NX + x + 1
				var bounded_surface: float = minf(
					surface_terms[i] - local_y, local_y - Field.MIN_Y
				)
				var cave_distance := Vector2(
					local_y - cave_y_terms[i], cave_dz_terms[i]
				).length() - 0.92
				var density: float = minf(bounded_surface, cave_distance)
				nodes[row + x + 1] = roundi(density * SCALE)
	return {"valid": true, "nodes": nodes, "samples": nodes.size()}
