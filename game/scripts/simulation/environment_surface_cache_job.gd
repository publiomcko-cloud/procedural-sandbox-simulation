extends RefCounted
class_name EnvironmentSurfaceCacheJob

## P5.0C worker-only immutable SDF surface derivation.
## No SceneTree, runtime or terrain authority is mutated from this object.

const Grid := preload("res://scripts/terrain/terrain_chunk_grid.gd")
const BaseTerrain := preload("res://scripts/terrain/sdf_world.gd")
const BrushState := preload("res://scripts/terrain/sdf_brush_edit_state.gd")
const SurfaceCache := preload("res://scripts/simulation/environment_surface_cache.gd")

const PROBE_STEP := 0.5
const BINARY_STEPS := 10
const NEIGHBOR_NORTH := 0
const NEIGHBOR_EAST := 1
const NEIGHBOR_SOUTH := 2
const NEIGHBOR_WEST := 3

# P5.0F-R2 optional, transient high-resolution shoreline samples.
# No change to the authoritative P5.0C surface-cache record schema.
const VISUAL_SUBDIVISIONS_PER_HYDRO_CELL := 2
const VISUAL_SAMPLES_X := SurfaceCache.DEFAULT_GRID_WIDTH * VISUAL_SUBDIVISIONS_PER_HYDRO_CELL + 1
const VISUAL_SAMPLES_Z := SurfaceCache.DEFAULT_GRID_HEIGHT * VISUAL_SUBDIVISIONS_PER_HYDRO_CELL + 1
# R3: sparse 0.5m true-SDF samples only in 1m coastal quadrants.
# Interior tiles reuse the R2 1m samples and do not incur extra SDF probes.
const VISUAL_FINE_GRID_WIDTH := (VISUAL_SAMPLES_X - 1) * 2 + 1
const MAX_REFINED_COAST_TILES := 96
const MAX_REFINED_SAMPLE_SITES := 512
const REFINEMENT_LEVEL_MARGIN_MM := 120

var scope_id: String
var seed: int
var generator_version: int
var region_key: Vector2i
var terrain_revision: int
var terrain_cache_scope_id: int
var terrain_effect_revision: int
var chunk_snapshots: Dictionary
var queued_usec: int

var worker_started_usec := 0
var worker_finished_usec := 0
var worker_thread_id := 0
var result: Dictionary = {}
var build_visual_shoreline := false
var visual_refine_levels_mm := PackedInt64Array()


func _init(
	scope_id_value: String,
	seed_value: int,
	generator_version_value: int,
	region_key_value: Vector2i,
	terrain_revision_value: int,
	terrain_cache_scope_id_value: int,
	terrain_effect_revision_value: int,
	chunk_snapshots_value: Dictionary,
	queued_usec_value: int
) -> void:
	scope_id = scope_id_value
	seed = seed_value
	generator_version = generator_version_value
	region_key = region_key_value
	terrain_revision = terrain_revision_value
	terrain_cache_scope_id = terrain_cache_scope_id_value
	terrain_effect_revision = terrain_effect_revision_value
	chunk_snapshots = chunk_snapshots_value.duplicate(true)
	queued_usec = queued_usec_value


func run() -> void:
	worker_started_usec = Time.get_ticks_usec()
	worker_thread_id = OS.get_thread_caller_id()
	result = _build()
	worker_finished_usec = Time.get_ticks_usec()


func _build() -> Dictionary:
	var width := SurfaceCache.DEFAULT_GRID_WIDTH
	var height := SurfaceCache.DEFAULT_GRID_HEIGHT
	var cell_count := width * height
	var surface_valid := PackedByteArray()
	var surface_height_mm := PackedInt64Array()
	var slope_milli := PackedInt32Array()
	var neighbor_mask := PackedByteArray()
	var neighbor_delta_mm := PackedInt64Array()
	var downhill_neighbor := PackedInt32Array()
	var downhill_drop_mm := PackedInt64Array()

	surface_valid.resize(cell_count)
	surface_height_mm.resize(cell_count)
	slope_milli.resize(cell_count)
	neighbor_mask.resize(cell_count)
	neighbor_delta_mm.resize(cell_count * SurfaceCache.NEIGHBOR_COUNT)
	downhill_neighbor.resize(cell_count)
	downhill_drop_mm.resize(cell_count)
	for index in range(cell_count):
		downhill_neighbor[index] = -1

	var clamped_top_count := 0
	var missing_surface_count := 0
	for z in range(height):
		for x in range(width):
			var index := z * width + x
			var local_x := (
				(float(x) + 0.5)
				* float(SurfaceCache.DEFAULT_CELL_SIZE_X_MM)
				/ 1000.0
			)
			var local_z := (
				(float(z) + 0.5)
				* float(SurfaceCache.DEFAULT_CELL_SIZE_Z_MM)
				/ 1000.0
			)
			var chunk_coordinate := _chunk_for_local(local_x, local_z)
			if not chunk_snapshots.has(chunk_coordinate):
				return _failure("surface_cache_chunk_snapshot_missing")
			var snapshot_value: Variant = chunk_snapshots[chunk_coordinate]
			if typeof(snapshot_value) != TYPE_DICTIONARY:
				return _failure("surface_cache_chunk_snapshot_invalid")
			var snapshot: Dictionary = snapshot_value
			if snapshot.has("valid") and not bool(snapshot.get("valid", true)):
				return _failure("surface_cache_chunk_snapshot_invalid")
			if int(snapshot.get("revision", -1)) != terrain_revision 				or int(snapshot.get("cache_scope_id", -1)) != terrain_cache_scope_id:
				return _failure("surface_cache_chunk_snapshot_revision_mismatch")
			var sampled := _sample_top_surface(local_x, local_z, snapshot)
			if not sampled.get("ok", false):
				return sampled
			if bool(sampled.get("valid", false)):
				surface_valid[index] = 1
				surface_height_mm[index] = int(sampled["height_mm"])
				if bool(sampled.get("clamped_top", false)):
					clamped_top_count += 1
			else:
				surface_valid[index] = 0
				surface_height_mm[index] = roundi(Grid.MIN_BOUND.y * 1000.0)
				missing_surface_count += 1

	_build_neighbors(
		surface_valid,
		surface_height_mm,
		slope_milli,
		neighbor_mask,
		neighbor_delta_mm,
		downhill_neighbor,
		downhill_drop_mm,
		width,
		height
	)

	var shoreline: Dictionary = {}
	if build_visual_shoreline:
		# Visualization is optional. Never fail a valid P5.0C hydrology cache
		# publication because higher-resolution presentation sampling failed.
		shoreline = _derive_shoreline_top_samples()
		if not shoreline.get("ok", false):
			shoreline = {
				"ok": false,
				"reason": String(shoreline.get("reason", "visual_shoreline_sample_failed")),
			}

	return {
		"valid": true,
		"reason": "ok",
		"visual_shoreline": shoreline,
		"record": {
			"scope_id": scope_id,
			"region_key": region_key,
			"world_seed": seed,
			"generator_version": generator_version,
			"terrain_revision": terrain_revision,
			"terrain_cache_scope_id": terrain_cache_scope_id,
			"terrain_effect_revision": terrain_effect_revision,
			"grid_width": width,
			"grid_height": height,
			"cell_size_x_mm": SurfaceCache.DEFAULT_CELL_SIZE_X_MM,
			"cell_size_z_mm": SurfaceCache.DEFAULT_CELL_SIZE_Z_MM,
			"surface_valid": surface_valid,
			"surface_height_mm": surface_height_mm,
			"slope_milli": slope_milli,
			"neighbor_mask": neighbor_mask,
			"neighbor_delta_mm": neighbor_delta_mm,
			"downhill_neighbor": downhill_neighbor,
			"downhill_drop_mm": downhill_drop_mm,
		},
		"diagnostics": {
			"cell_count": cell_count,
			"clamped_top_count": clamped_top_count,
			"missing_surface_count": missing_surface_count,
			"chunk_snapshot_count": chunk_snapshots.size(),
			"visual_shoreline_ok": (not build_visual_shoreline or bool(shoreline.get("ok", false))),
			"visual_shoreline_reason": String(shoreline.get("reason", "")),
			"visual_shoreline_sample_count": (
				int((shoreline.get("height_mm", PackedInt32Array()) as PackedInt32Array).size())
				if build_visual_shoreline else 0
			),
			"visual_shoreline_refined_sites": int(shoreline.get("refined_sample_count", 0)),
			"visual_shoreline_refined_tiles": int(shoreline.get("refined_tile_count", 0)),
		},
	}



## Derived-only terrain heights at a 1m grid (17x13), using exactly the
## immutable chunk snapshots already used by the P5.0C cache worker.
## Samples include saved brush edits and terrain-object effect frames.
func _derive_shoreline_top_samples() -> Dictionary:
	var samples := PackedInt32Array()
	var valid := PackedByteArray()
	samples.resize(VISUAL_SAMPLES_X * VISUAL_SAMPLES_Z)
	valid.resize(samples.size())
	var step_x := float(SurfaceCache.DEFAULT_CELL_SIZE_X_MM) / (
		1000.0 * float(VISUAL_SUBDIVISIONS_PER_HYDRO_CELL)
	)
	var step_z := float(SurfaceCache.DEFAULT_CELL_SIZE_Z_MM) / (
		1000.0 * float(VISUAL_SUBDIVISIONS_PER_HYDRO_CELL)
	)
	for z in range(VISUAL_SAMPLES_Z):
		for x in range(VISUAL_SAMPLES_X):
			var sample_x := float(x) * step_x
			var sample_z := float(z) * step_z
			var chunk := _chunk_for_local(sample_x, sample_z)
			if not chunk_snapshots.has(chunk):
				return {"ok": false, "reason": "visual_shoreline_snapshot_missing"}
			var source: Dictionary = chunk_snapshots[chunk]
			var sampled: Dictionary = _sample_top_surface(sample_x, sample_z, source)
			if not sampled.get("ok", false):
				return {"ok": false, "reason": String(sampled.get("reason", "visual_shoreline_sample_invalid"))}
			var index := z * VISUAL_SAMPLES_X + x
			samples[index] = int(sampled.get("height_mm", 0))
			valid[index] = 1 if bool(sampled.get("valid", false)) else 0
	# Immutable generator baseline: new brush excavations cannot create an
	# infinite-ocean visual source where base terrain was originally dry.
	# Read at the SAME sea-plane threshold as the R4 ocean clipping, without
	# mutating the current canonical terrain or hydrology authority.
	var base_sea_wet := PackedByteArray()
	if region_key.y >= 10 and generator_version == BaseTerrain.GENERATOR_VERSION:
		base_sea_wet.resize(samples.size())
		for z in range(VISUAL_SAMPLES_Z):
			for x in range(VISUAL_SAMPLES_X):
				var density := BaseTerrain.sample_density(
					seed, region_key, Vector3(float(x), 3.982, float(z))
				)
				base_sea_wet[z * VISUAL_SAMPLES_X + x] = 1 if density < 0.0 else 0
	var detail: Dictionary = _derive_adaptive_coast_samples(samples, valid)
	if not detail.get("ok", false):
		return detail
	return {
		"ok": true,
		"width": VISUAL_SAMPLES_X,
		"height": VISUAL_SAMPLES_Z,
		"height_mm": samples,
		"valid": valid,
		"base_sea_wet": base_sea_wet,
		"fine_height_mm": detail["fine_height_mm"],
		"fine_valid": detail["fine_valid"],
		"refined_tile_count": detail["refined_tile_count"],
		"refined_sample_count": detail["refined_sample_count"],
		"world_seed": seed,
		"generator_version": generator_version,
		"terrain_revision": terrain_revision,
		"terrain_cache_scope_id": terrain_cache_scope_id,
		"terrain_effect_revision": terrain_effect_revision,
		"region_key": region_key,
	}



## Work is bounded, deterministic and restricted to real waterline-adjacent
## 1m tiles. Site keys are stable packed 0.5m lattice indices (33x25).
## The optional failure never blocks authoritative SDF cache publication.
func _derive_adaptive_coast_samples(
	heights: PackedInt32Array, valid: PackedByteArray
) -> Dictionary:
	var refined_heights: Dictionary = {}
	var refined_valid: Dictionary = {}
	var refined_tiles := 0
	if visual_refine_levels_mm.is_empty():
		return {
			"ok": true, "fine_height_mm": refined_heights,
			"fine_valid": refined_valid,
			"refined_tile_count": 0, "refined_sample_count": 0,
		}
	for z in range(VISUAL_SAMPLES_Z - 1):
		for x in range(VISUAL_SAMPLES_X - 1):
			if refined_tiles >= MAX_REFINED_COAST_TILES:
				break
			var a := z * VISUAL_SAMPLES_X + x
			var b := a + 1
			var c := a + VISUAL_SAMPLES_X
			var d := c + 1
			if valid[a] == 0 or valid[b] == 0 or valid[c] == 0 or valid[d] == 0:
				continue
			var min_height: int = mini(mini(heights[a], heights[b]), mini(heights[c], heights[d]))
			var max_height: int = maxi(maxi(heights[a], heights[b]), maxi(heights[c], heights[d]))
			var near_waterline := false
			for level_mm in visual_refine_levels_mm:
				if min_height <= int(level_mm) + REFINEMENT_LEVEL_MARGIN_MM and max_height >= int(level_mm) - REFINEMENT_LEVEL_MARGIN_MM:
					near_waterline = true
					break
			if not near_waterline:
				continue
			refined_tiles += 1
			for fine_z in range(3):
				for fine_x in range(3):
					if fine_x % 2 == 0 and fine_z % 2 == 0:
						continue # Coarse grid already has this exact site.
					var gx := x * 2 + fine_x
					var gz := z * 2 + fine_z
					var id := gz * VISUAL_FINE_GRID_WIDTH + gx
					if refined_heights.has(id):
						continue
					if refined_heights.size() >= MAX_REFINED_SAMPLE_SITES:
						return {
							"ok": false, "reason": "shoreline_refinement_sample_budget_exceeded",
						}
					var local_x := float(gx) * 0.5
					var local_z := float(gz) * 0.5
					var chunk: Vector2i = _chunk_for_local(local_x, local_z)
					if not chunk_snapshots.has(chunk):
						return {"ok": false, "reason": "shoreline_refinement_snapshot_missing"}
					var source: Dictionary = chunk_snapshots[chunk]
					var sampled: Dictionary = _sample_top_surface(local_x, local_z, source)
					if not sampled.get("ok", false):
						return {"ok": false, "reason": "shoreline_refinement_sample_invalid"}
					refined_heights[id] = int(sampled.get("height_mm", 0))
					refined_valid[id] = 1 if bool(sampled.get("valid", false)) else 0
	return {
		"ok": true,
		"fine_height_mm": refined_heights,
		"fine_valid": refined_valid,
		"refined_tile_count": refined_tiles,
		"refined_sample_count": refined_heights.size(),
	}


func _sample_top_surface(
	local_x: float,
	local_z: float,
	snapshot: Dictionary
) -> Dictionary:
	var top_y := Grid.MAX_BOUND.y + BrushState.MESHING_QUERY_MARGIN
	var bottom_y := Grid.MIN_BOUND.y - BrushState.MESHING_QUERY_MARGIN
	var previous_y := top_y
	var previous_density := BrushState.sample_density_snapshot(
		seed,
		region_key,
		Vector3(local_x, previous_y, local_z),
		false,
		snapshot
	)
	if not is_finite(previous_density):
		return _failure("surface_cache_density_non_finite")
	if previous_density >= 0.0:
		return {
			"ok": true,
			"valid": true,
			"height_mm": roundi(top_y * 1000.0),
			"clamped_top": true,
		}

	var y := top_y - PROBE_STEP
	while y >= bottom_y - 0.000001:
		var density := BrushState.sample_density_snapshot(
			seed,
			region_key,
			Vector3(local_x, y, local_z),
			false,
			snapshot
		)
		if not is_finite(density):
			return _failure("surface_cache_density_non_finite")
		if previous_density <= 0.0 and density >= 0.0:
			var low_y := y
			var high_y := previous_y
			for _step in range(BINARY_STEPS):
				var mid_y := (low_y + high_y) * 0.5
				var mid_density := BrushState.sample_density_snapshot(
					seed,
					region_key,
					Vector3(local_x, mid_y, local_z),
					false,
					snapshot
				)
				if not is_finite(mid_density):
					return _failure("surface_cache_density_non_finite")
				if mid_density >= 0.0:
					low_y = mid_y
				else:
					high_y = mid_y
			return {
				"ok": true,
				"valid": true,
				"height_mm": roundi((low_y + high_y) * 500.0),
				"clamped_top": false,
			}
		previous_y = y
		previous_density = density
		y -= PROBE_STEP
	return {
		"ok": true,
		"valid": false,
		"height_mm": roundi(Grid.MIN_BOUND.y * 1000.0),
		"clamped_top": false,
	}


func _build_neighbors(
	surface_valid: PackedByteArray,
	surface_height_mm: PackedInt64Array,
	slope_milli: PackedInt32Array,
	neighbor_mask: PackedByteArray,
	neighbor_delta_mm: PackedInt64Array,
	downhill_neighbor: PackedInt32Array,
	downhill_drop_mm: PackedInt64Array,
	width: int,
	height: int
) -> void:
	var directions := [
		Vector2i(0, -1),
		Vector2i(1, 0),
		Vector2i(0, 1),
		Vector2i(-1, 0),
	]
	var run_mm := mini(
		SurfaceCache.DEFAULT_CELL_SIZE_X_MM,
		SurfaceCache.DEFAULT_CELL_SIZE_Z_MM
	)
	for z in range(height):
		for x in range(width):
			var index := z * width + x
			if int(surface_valid[index]) == 0:
				continue
			var current_height := int(surface_height_mm[index])
			var mask := 0
			var max_abs_delta := 0
			var best_drop := 0
			var best_neighbor := -1
			for direction_index in range(SurfaceCache.NEIGHBOR_COUNT):
				var neighbor_coordinate: Vector2i = Vector2i(x, z) + directions[direction_index]
				if neighbor_coordinate.x < 0 or neighbor_coordinate.x >= width 					or neighbor_coordinate.y < 0 or neighbor_coordinate.y >= height:
					continue
				var neighbor_index: int = neighbor_coordinate.y * width + neighbor_coordinate.x
				if int(surface_valid[neighbor_index]) == 0:
					continue
				mask |= 1 << direction_index
				var delta := current_height - int(surface_height_mm[neighbor_index])
				neighbor_delta_mm[index * SurfaceCache.NEIGHBOR_COUNT + direction_index] = delta
				max_abs_delta = maxi(max_abs_delta, absi(delta))
				if delta > best_drop:
					best_drop = delta
					best_neighbor = neighbor_index
			neighbor_mask[index] = mask
			slope_milli[index] = int(max_abs_delta * 1000 / maxi(1, run_mm))
			downhill_neighbor[index] = best_neighbor
			downhill_drop_mm[index] = best_drop


func _chunk_for_local(local_x: float, local_z: float) -> Vector2i:
	var chunk_width := float(Grid.CELLS_PER_CHUNK_X) * Grid.SAMPLE_STEP
	var chunk_depth := float(Grid.CELLS_PER_CHUNK_Z) * Grid.SAMPLE_STEP
	return Vector2i(
		clampi(floori(local_x / chunk_width), 0, Grid.CHUNK_COUNT_X - 1),
		clampi(floori(local_z / chunk_depth), 0, Grid.CHUNK_COUNT_Z - 1)
	)


func _failure(reason: String) -> Dictionary:
	return {"valid": false, "ok": false, "reason": reason}
