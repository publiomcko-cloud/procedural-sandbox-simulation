extends RefCounted
class_name EnvironmentHydrologyDomain

## P5.0E orchestration for generated river/ocean bindings, reservoir exchange
## and atomic cross-region finite-water flow.

const EnvironmentStoreScript := preload("res://scripts/simulation/environment_state_store.gd")
const SurfaceCacheScript := preload("res://scripts/simulation/environment_surface_cache.gd")
const BatchJobScript := preload("res://scripts/simulation/environment_hydrology_batch_job.gd")

const OCEAN_START_GLOBAL_CELL_Z := 60
const OCEAN_LEVEL_MM := 4_000
const RIVER_LEVEL_OFFSET_MM := 250
const RIVER_MAX_TERRAIN_MM := 6_000
const RIVER_PERIOD_CELLS := 64
const RIVER_HALF_PERIOD_CELLS := 32
const RIVER_MEANDER_DIVISOR := 4

var _runoff_domain: RefCounted
var _profile_id := ""
var _world_seed := 0
var _generator_version := -1
var _initialized := false

var _batches_total := 0
var _committed_batches_total := 0
var _deferred_scopes_total := 0
var _stale_rejections_total := 0
var _cross_region_transfer_ul_total := 0
var _reservoir_inflow_ul_total := 0
var _reservoir_outflow_ul_total := 0
var _binding_inflow_ul_total := 0
var _boundary_transfer_count_total := 0
var _river_bindings_total := 0
var _ocean_bindings_total := 0


func initialize(
	runoff_domain: RefCounted,
	profile_id: String,
	world_seed: int,
	generator_version: int
) -> Dictionary:
	if _initialized:
		return _failure("environment_hydrology_already_initialized")
	if runoff_domain == null:
		return _failure("environment_hydrology_runoff_domain_unavailable")
	if profile_id.is_empty() or profile_id != profile_id.strip_edges():
		return _failure("environment_hydrology_profile_invalid")
	if generator_version < 0:
		return _failure("environment_hydrology_generator_version_invalid")
	_runoff_domain = runoff_domain
	_profile_id = profile_id
	_world_seed = world_seed
	_generator_version = generator_version
	_reset_metrics()
	_initialized = true
	return {
		"ok": true,
		"reason": "ok",
		"world_seed": _world_seed,
		"generator_version": _generator_version,
		"profile_id": _profile_id,
	}


func is_initialized() -> bool:
	return _initialized


func process_due_batch(
	environment_store: RefCounted,
	surface_cache: RefCounted,
	scope_ids: Array[String],
	logical_tick: int,
	max_scope_count: int
) -> Dictionary:
	var built := build_batch_snapshot(
		environment_store,
		surface_cache,
		scope_ids,
		logical_tick,
		max_scope_count
	)
	if not built.get("ok", false):
		return built
	var processed_noops: Array[String] = built.get("noop_scope_ids", [])
	var deferred: Array[String] = built.get("deferred_scope_ids", [])
	var snapshot: Dictionary = built.get("work_snapshot", {})
	if snapshot.is_empty():
		return {
			"ok": true,
			"reason": "ok",
			"noop": true,
			"processed_scope_ids": processed_noops,
			"deferred_scope_ids": deferred,
			"committed_scope_count": 0,
		}

	var solved := solve_batch_snapshot(snapshot)
	if not solved.get("ok", false):
		return solved
	var committed := commit_batch_result(
		environment_store, surface_cache, solved
	)
	if not committed.get("ok", false):
		return committed
	if committed.get("deferred", false):
		return committed

	var processed: Array[String] = []
	processed.append_array(processed_noops)
	for value in solved.get("scope_results", []):
		var row: Dictionary = value
		processed.append(String(row["scope_id"]))
	processed.sort()

	_batches_total += 1
	_committed_batches_total += 1
	_deferred_scopes_total += deferred.size()
	_cross_region_transfer_ul_total += int(
		solved.get("cross_region_transfer_ul", 0)
	)
	_reservoir_inflow_ul_total += int(solved.get("reservoir_inflow_ul", 0))
	_reservoir_outflow_ul_total += int(solved.get("reservoir_outflow_ul", 0))
	_boundary_transfer_count_total += int(
		solved.get("boundary_transfer_count", 0)
	)
	var binding_total := 0
	for row_value in solved.get("scope_results", []):
		var row: Dictionary = row_value
		binding_total += int(row.get("binding_reservoir_inflow_ul", 0))
	_binding_inflow_ul_total += binding_total
	return {
		"ok": true,
		"reason": "ok",
		"noop": false,
		"processed_scope_ids": processed,
		"deferred_scope_ids": deferred,
		"committed_scope_count": int(committed.get("committed_scope_count", 0)),
		"cross_region_transfer_ul": int(
			solved.get("cross_region_transfer_ul", 0)
		),
		"reservoir_inflow_ul": int(solved.get("reservoir_inflow_ul", 0)),
		"reservoir_outflow_ul": int(solved.get("reservoir_outflow_ul", 0)),
		"binding_reservoir_inflow_ul": binding_total,
		"boundary_transfer_count": int(
			solved.get("boundary_transfer_count", 0)
		),
		"scope_results": solved.get("scope_results", []).duplicate(true),
	}


func build_batch_snapshot(
	environment_store: RefCounted,
	surface_cache: RefCounted,
	scope_ids: Array[String],
	logical_tick: int,
	max_scope_count: int
) -> Dictionary:
	if not _initialized:
		return _failure("environment_hydrology_not_initialized")
	if environment_store == null or not environment_store.is_initialized():
		return _failure("environment_hydrology_store_unavailable")
	if surface_cache == null or not surface_cache.is_initialized():
		return _failure("environment_hydrology_surface_cache_unavailable")
	if logical_tick < 0:
		return _failure("environment_hydrology_tick_invalid")
	if max_scope_count < 1:
		return _failure("environment_hydrology_scope_budget_invalid")

	var ids: Array[String] = []
	var seen: Dictionary = {}
	for value in scope_ids:
		var scope_id := String(value)
		if scope_id.is_empty() or seen.has(scope_id):
			continue
		seen[scope_id] = true
		ids.append(scope_id)
	ids.sort()
	if ids.size() > max_scope_count:
		ids.resize(max_scope_count)

	var entries: Array[Dictionary] = []
	var deferred: Array[String] = []
	var noops: Array[String] = []
	for scope_id in ids:
		var record: Dictionary = environment_store.get_scope(scope_id)
		if record.is_empty():
			return _failure("environment_hydrology_scope_missing")
		var last_tick := int(record["last_environment_tick"])
		if logical_tick < last_tick:
			return _failure("environment_hydrology_tick_not_monotonic")
		if logical_tick == last_tick:
			noops.append(scope_id)
			continue
		var surface_record: Dictionary = surface_cache.get_scope(scope_id)
		if surface_record.is_empty():
			deferred.append(scope_id)
			continue
		if (
			int(surface_record.get("world_seed", 0)) != _world_seed
			or int(surface_record.get("generator_version", -1))
				!= _generator_version
		):
			return _failure("environment_hydrology_surface_provenance_invalid")

		var built: Dictionary = _runoff_domain.build_work_snapshot(
			environment_store,
			surface_cache,
			scope_id,
			_profile_id,
			logical_tick
		)
		if not built.get("ok", false):
			return built
		if built.get("deferred", false):
			deferred.append(scope_id)
			continue
		if built.get("noop", false):
			noops.append(scope_id)
			continue

		var work: Dictionary = built["work_snapshot"]
		var pre_binding_total := _finite_total_from_arrays(
			work["surface_water_ul"],
			work["soil_water_ul"],
			work["reservoir_kind"]
		)
		var binding := _apply_generated_reservoir_bindings(
			work, surface_record
		)
		if not binding.get("ok", false):
			return binding
		var solved: Dictionary = _runoff_domain.solve_work_snapshot(work)
		if not solved.get("ok", false):
			return solved
		var update: Dictionary = solved["update"]
		entries.append({
			"scope_id": scope_id,
			"region_key": surface_record["region_key"],
			"logical_tick": logical_tick,
			"elapsed_ticks": int(solved["elapsed_ticks"]),
			"expected_state_revision": int(solved["expected_state_revision"]),
			"surface_water_ul": (
				update["surface_water_ul"] as PackedInt64Array
			).duplicate(),
			"soil_water_ul": (
				update["soil_water_ul"] as PackedInt64Array
			).duplicate(),
			"reservoir_kind": (
				update["reservoir_kind"] as PackedByteArray
			).duplicate(),
			"reservoir_level_mm": (
				update["reservoir_level_mm"] as PackedInt64Array
			).duplicate(),
			"surface_valid": (
				surface_record["surface_valid"] as PackedByteArray
			).duplicate(),
			"surface_height_mm": (
				surface_record["surface_height_mm"] as PackedInt64Array
			).duplicate(),
			"surface_cache_token": _surface_token(surface_record),
			"reservoir_inflow_ul_delta": int(
				binding.get("reservoir_inflow_ul", 0)
			),
			"reservoir_outflow_ul_delta": 0,
			"finite_initial_ul": int(solved.get("finite_initial_ul", 0)),
			"pre_binding_finite_initial_ul": pre_binding_total,
			"precipitation_ul": int(solved.get("precipitation_ul", 0)),
			"evaporation_ul": int(solved.get("evaporation_ul", 0)),
			"local_runoff_ul": int(solved.get("runoff_ul", 0)),
			"binding_reservoir_inflow_ul": int(
				binding.get("reservoir_inflow_ul", 0)
			),
		})

	return {
		"ok": true,
		"reason": "ok",
		"work_snapshot": {"entries": entries},
		"deferred_scope_ids": deferred,
		"noop_scope_ids": noops,
	}


func solve_batch_snapshot(work_snapshot: Dictionary) -> Dictionary:
	var job: RefCounted = BatchJobScript.new(work_snapshot)
	job.run()
	return job.result.duplicate(true)


func commit_batch_result(
	environment_store: RefCounted,
	surface_cache: RefCounted,
	solved: Dictionary
) -> Dictionary:
	if not solved.get("ok", false):
		return _failure("environment_hydrology_solve_invalid")
	var updates: Array = solved.get("updates", [])
	if updates.is_empty():
		return {
			"ok": true,
			"reason": "ok",
			"noop": true,
			"deferred": false,
			"committed_scope_count": 0,
		}

	var results_by_scope: Dictionary = {}
	for row_value in solved.get("scope_results", []):
		var row: Dictionary = row_value
		results_by_scope[String(row["scope_id"])] = row
	for update_value in updates:
		var update: Dictionary = update_value
		var scope_id := String(update["scope_id"])
		var current: Dictionary = environment_store.get_scope(scope_id)
		if (
			current.is_empty()
			or int(current["state_revision"])
				!= int(update["expected_state_revision"])
		):
			_stale_rejections_total += 1
			return {
				"ok": true,
				"reason": "environment_hydrology_state_stale",
				"noop": true,
				"deferred": true,
				"committed_scope_count": 0,
			}
		var current_surface: Dictionary = surface_cache.get_scope(scope_id)
		if (
			current_surface.is_empty()
			or not results_by_scope.has(scope_id)
			or _surface_token(current_surface)
				!= (results_by_scope[scope_id] as Dictionary)["surface_cache_token"]
		):
			_stale_rejections_total += 1
			return {
				"ok": true,
				"reason": "environment_hydrology_surface_cache_stale",
				"noop": true,
				"deferred": true,
				"committed_scope_count": 0,
			}

	var commit: Dictionary = environment_store.commit_batch(updates)
	if not commit.get("ok", false):
		return commit
	return {
		"ok": true,
		"reason": "ok",
		"noop": bool(commit.get("noop", false)),
		"deferred": false,
		"committed_scope_count": int(commit.get("committed_scope_count", 0)),
	}


func get_metrics() -> Dictionary:
	return {
		"initialized": _initialized,
		"profile_id": _profile_id,
		"world_seed": _world_seed,
		"generator_version": _generator_version,
		"batches_total": _batches_total,
		"committed_batches_total": _committed_batches_total,
		"deferred_scopes_total": _deferred_scopes_total,
		"stale_rejections_total": _stale_rejections_total,
		"cross_region_transfer_ul_total": _cross_region_transfer_ul_total,
		"reservoir_inflow_ul_total": _reservoir_inflow_ul_total,
		"reservoir_outflow_ul_total": _reservoir_outflow_ul_total,
		"binding_inflow_ul_total": _binding_inflow_ul_total,
		"boundary_transfer_count_total": _boundary_transfer_count_total,
		"river_bindings_total": _river_bindings_total,
		"ocean_bindings_total": _ocean_bindings_total,
	}


func generated_binding_for_cell(
	region_key: Vector2i,
	cell_index: int,
	surface_height_mm: int
) -> Dictionary:
	if cell_index < 0 or cell_index >= SurfaceCacheScript.DEFAULT_GRID_WIDTH * SurfaceCacheScript.DEFAULT_GRID_HEIGHT:
		return {}
	var x := cell_index % SurfaceCacheScript.DEFAULT_GRID_WIDTH
	var z := cell_index / SurfaceCacheScript.DEFAULT_GRID_WIDTH
	var global_x := region_key.x * SurfaceCacheScript.DEFAULT_GRID_WIDTH + x
	var global_z := region_key.y * SurfaceCacheScript.DEFAULT_GRID_HEIGHT + z

	if global_z >= OCEAN_START_GLOBAL_CELL_Z and surface_height_mm <= OCEAN_LEVEL_MM:
		return {
			"kind": EnvironmentStoreScript.RESERVOIR_OCEAN,
			"level_mm": OCEAN_LEVEL_MM,
		}
	var river_center := _river_center_global_x(global_z)
	if (
		global_x == river_center
		and surface_height_mm <= RIVER_MAX_TERRAIN_MM
	):
		return {
			"kind": EnvironmentStoreScript.RESERVOIR_RIVER,
			"level_mm": clampi(
				surface_height_mm + RIVER_LEVEL_OFFSET_MM,
				-EnvironmentStoreScript.MAX_ABS_RESERVOIR_LEVEL_MM,
				EnvironmentStoreScript.MAX_ABS_RESERVOIR_LEVEL_MM
			),
		}
	return {}


func _apply_generated_reservoir_bindings(
	work: Dictionary,
	surface_record: Dictionary
) -> Dictionary:
	var surface: PackedInt64Array = work["surface_water_ul"].duplicate()
	var soil: PackedInt64Array = work["soil_water_ul"].duplicate()
	var kinds: PackedByteArray = work["reservoir_kind"].duplicate()
	var levels: PackedInt64Array = work["reservoir_level_mm"].duplicate()
	var heights: PackedInt64Array = surface_record["surface_height_mm"]
	var valid: PackedByteArray = surface_record["surface_valid"]
	var region_key: Vector2i = surface_record["region_key"]
	var inflow := 0
	var river_bindings := 0
	var ocean_bindings := 0

	for cell in range(surface.size()):
		if int(kinds[cell]) != EnvironmentStoreScript.RESERVOIR_FINITE:
			continue
		if int(valid[cell]) == 0:
			continue
		var binding := generated_binding_for_cell(
			region_key, cell, int(heights[cell])
		)
		if binding.is_empty():
			continue
		inflow += int(surface[cell]) + int(soil[cell])
		surface[cell] = 0
		soil[cell] = 0
		kinds[cell] = int(binding["kind"])
		levels[cell] = int(binding["level_mm"])
		if int(binding["kind"]) == EnvironmentStoreScript.RESERVOIR_RIVER:
			river_bindings += 1
		else:
			ocean_bindings += 1

	work["surface_water_ul"] = surface
	work["soil_water_ul"] = soil
	work["reservoir_kind"] = kinds
	work["reservoir_level_mm"] = levels
	_river_bindings_total += river_bindings
	_ocean_bindings_total += ocean_bindings
	return {
		"ok": true,
		"reason": "ok",
		"reservoir_inflow_ul": inflow,
		"river_bindings": river_bindings,
		"ocean_bindings": ocean_bindings,
	}


func _river_center_global_x(global_z: int) -> int:
	var seed_base := posmod(_world_seed, 17) - 8
	var phase := posmod(global_z + posmod(_world_seed, RIVER_PERIOD_CELLS), RIVER_PERIOD_CELLS)
	var triangle := phase if phase < RIVER_HALF_PERIOD_CELLS else (RIVER_PERIOD_CELLS - 1 - phase)
	var meander := (triangle - (RIVER_HALF_PERIOD_CELLS / 2)) / RIVER_MEANDER_DIVISOR
	return seed_base + meander


func _finite_total_from_arrays(
	surface: PackedInt64Array,
	soil: PackedInt64Array,
	kinds: PackedByteArray
) -> int:
	var total := 0
	for cell in range(surface.size()):
		if int(kinds[cell]) == EnvironmentStoreScript.RESERVOIR_FINITE:
			total += int(surface[cell]) + int(soil[cell])
	return total


func _surface_token(record: Dictionary) -> Dictionary:
	return {
		"scope_id": String(record.get("scope_id", "")),
		"region_key": record.get("region_key", Vector2i.ZERO),
		"world_seed": int(record.get("world_seed", 0)),
		"generator_version": int(record.get("generator_version", -1)),
		"terrain_revision": int(record.get("terrain_revision", -1)),
		"terrain_cache_scope_id": int(record.get("terrain_cache_scope_id", 0)),
		"terrain_effect_revision": int(record.get("terrain_effect_revision", -1)),
	}


func _reset_metrics() -> void:
	_batches_total = 0
	_committed_batches_total = 0
	_deferred_scopes_total = 0
	_stale_rejections_total = 0
	_cross_region_transfer_ul_total = 0
	_reservoir_inflow_ul_total = 0
	_reservoir_outflow_ul_total = 0
	_binding_inflow_ul_total = 0
	_boundary_transfer_count_total = 0
	_river_bindings_total = 0
	_ocean_bindings_total = 0


func _failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
