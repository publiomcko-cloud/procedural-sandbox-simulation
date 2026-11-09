extends RefCounted
class_name EnvironmentRunoffJob

## P5.0D pure deterministic finite-water solve.
## Input is an immutable snapshot assembled on the main thread. The job owns no
## SceneTree state and performs no authoritative mutation.

const EnvironmentStoreScript := preload("res://scripts/simulation/environment_state_store.gd")

const RUNOFF_FRACTION_DENOMINATOR := 4
const MAX_ELAPSED_TICKS_PER_STEP := 10_000_000

var work_snapshot: Dictionary
var result: Dictionary = {}
var worker_started_usec := 0
var worker_finished_usec := 0
var worker_thread_id := 0


func _init(snapshot: Dictionary) -> void:
	work_snapshot = snapshot.duplicate(true)


func run() -> void:
	worker_started_usec = Time.get_ticks_usec()
	worker_thread_id = OS.get_thread_caller_id()
	result = _solve(work_snapshot)
	worker_finished_usec = Time.get_ticks_usec()
	result["worker_usec"] = worker_finished_usec - worker_started_usec
	result["worker_thread_id"] = worker_thread_id


func _solve(snapshot: Dictionary) -> Dictionary:
	var required := [
		"scope_id",
		"logical_tick",
		"expected_state_revision",
		"profile_id",
		"profile_sha256",
		"elapsed_ticks",
		"surface_water_ul",
		"soil_water_ul",
		"reservoir_kind",
		"reservoir_level_mm",
		"surface_valid",
		"downhill_neighbor",
		"downhill_drop_mm",
		"precipitation_ul_per_cell_per_tick",
		"infiltration_ul_per_cell_per_tick",
		"soil_capacity_ul_per_cell",
		"evaporation_ul_per_cell_per_tick",
		"surface_cache_token",
	]
	for field in required:
		if not snapshot.has(field):
			return _failure("environment_runoff_snapshot_fields_invalid")

	var elapsed_ticks := int(snapshot["elapsed_ticks"])
	if elapsed_ticks <= 0 or elapsed_ticks > MAX_ELAPSED_TICKS_PER_STEP:
		return _failure("environment_runoff_elapsed_tick_bound")

	var surface: PackedInt64Array = snapshot["surface_water_ul"].duplicate()
	var soil: PackedInt64Array = snapshot["soil_water_ul"].duplicate()
	var kinds: PackedByteArray = snapshot["reservoir_kind"].duplicate()
	var levels: PackedInt64Array = snapshot["reservoir_level_mm"].duplicate()
	var valid: PackedByteArray = snapshot["surface_valid"].duplicate()
	var downhill: PackedInt32Array = snapshot["downhill_neighbor"].duplicate()
	var drops: PackedInt64Array = snapshot["downhill_drop_mm"].duplicate()
	var count := surface.size()
	if (
		count <= 0
		or soil.size() != count
		or kinds.size() != count
		or levels.size() != count
		or valid.size() != count
		or downhill.size() != count
		or drops.size() != count
	):
		return _failure("environment_runoff_snapshot_shape_invalid")

	var precipitation_request := _saturating_product(
		int(snapshot["precipitation_ul_per_cell_per_tick"]), elapsed_ticks
	)
	var infiltration_request := _saturating_product(
		int(snapshot["infiltration_ul_per_cell_per_tick"]), elapsed_ticks
	)
	var evaporation_request := _saturating_product(
		int(snapshot["evaporation_ul_per_cell_per_tick"]), elapsed_ticks
	)
	var soil_capacity := int(snapshot["soil_capacity_ul_per_cell"])
	if soil_capacity < 0 or soil_capacity > EnvironmentStoreScript.MAX_WATER_UL_PER_CELL:
		return _failure("environment_runoff_soil_capacity_invalid")

	var finite_initial := _finite_total(surface, soil, kinds)
	var precipitation_total := 0
	var precipitation_overflow_total := 0
	var infiltration_total := 0
	var evaporation_total := 0

	# Climate forcing is composed into the same authoritative tick as runoff.
	for index in range(count):
		if int(kinds[index]) != EnvironmentStoreScript.RESERVOIR_FINITE:
			continue
		var current_surface := int(surface[index])
		var current_soil := int(soil[index])

		var precipitation_capacity := (
			EnvironmentStoreScript.MAX_WATER_UL_PER_CELL - current_surface
		)
		var precipitation_applied := mini(precipitation_request, precipitation_capacity)
		current_surface += precipitation_applied
		precipitation_total += precipitation_applied
		precipitation_overflow_total += precipitation_request - precipitation_applied

		var soil_room := maxi(0, soil_capacity - current_soil)
		var infiltration := mini(infiltration_request, mini(current_surface, soil_room))
		current_surface -= infiltration
		current_soil += infiltration
		infiltration_total += infiltration

		var evaporation_remaining := evaporation_request
		var surface_evaporation := mini(current_surface, evaporation_remaining)
		current_surface -= surface_evaporation
		evaporation_remaining -= surface_evaporation
		var soil_evaporation := mini(current_soil, evaporation_remaining)
		current_soil -= soil_evaporation
		evaporation_total += surface_evaporation + soil_evaporation

		surface[index] = current_surface
		soil[index] = current_soil

	# Runoff is simultaneous over the post-climate surface snapshot. A cell may
	# send only to its P5.0C deterministic local downhill neighbor. Cross-scope
	# and reservoir exchange remain outside P5.0D.
	var source_surface: PackedInt64Array = surface.duplicate()
	var outgoing := PackedInt64Array()
	var incoming := PackedInt64Array()
	outgoing.resize(count)
	incoming.resize(count)
	var runoff_total := 0
	var runoff_transfer_count := 0

	for index in range(count):
		if int(kinds[index]) != EnvironmentStoreScript.RESERVOIR_FINITE:
			continue
		if int(valid[index]) == 0:
			continue
		var destination := int(downhill[index])
		if destination < 0 or destination >= count or destination == index:
			continue
		if int(drops[index]) <= 0:
			continue
		if int(valid[destination]) == 0:
			continue
		if int(kinds[destination]) != EnvironmentStoreScript.RESERVOIR_FINITE:
			continue

		var available := int(source_surface[index])
		if available <= 0:
			continue
		var per_tick_request := _ceil_div(
			available, RUNOFF_FRACTION_DENOMINATOR
		)
		var requested := mini(
			available,
			_saturating_product(per_tick_request, elapsed_ticks)
		)
		if requested <= 0:
			continue
		var destination_room := maxi(
			0,
			EnvironmentStoreScript.MAX_WATER_UL_PER_CELL
				- int(source_surface[destination])
				- int(incoming[destination])
		)
		var amount := mini(requested, destination_room)
		if amount <= 0:
			continue
		outgoing[index] = amount
		incoming[destination] = int(incoming[destination]) + amount
		runoff_total += amount
		runoff_transfer_count += 1

	for index in range(count):
		var next_surface := (
			int(source_surface[index])
			- int(outgoing[index])
			+ int(incoming[index])
		)
		if next_surface < 0 or next_surface > EnvironmentStoreScript.MAX_WATER_UL_PER_CELL:
			return _failure("environment_runoff_water_bound_violation")
		surface[index] = next_surface

	var finite_final := _finite_total(surface, soil, kinds)
	var expected_final := finite_initial + precipitation_total - evaporation_total
	if finite_final != expected_final:
		return _failure("environment_runoff_conservation_violation")

	return {
		"ok": true,
		"reason": "ok",
		"scope_id": String(snapshot["scope_id"]),
		"logical_tick": int(snapshot["logical_tick"]),
		"expected_state_revision": int(snapshot["expected_state_revision"]),
		"profile_id": String(snapshot["profile_id"]),
		"profile_sha256": String(snapshot["profile_sha256"]),
		"surface_cache_token": (snapshot["surface_cache_token"] as Dictionary).duplicate(true),
		"update": {
			"scope_id": String(snapshot["scope_id"]),
			"expected_state_revision": int(snapshot["expected_state_revision"]),
			"last_environment_tick": int(snapshot["logical_tick"]),
			"surface_water_ul": surface,
			"soil_water_ul": soil,
			"reservoir_kind": kinds,
			"reservoir_level_mm": levels,
			"reservoir_inflow_ul_delta": 0,
			"reservoir_outflow_ul_delta": 0,
		},
		"elapsed_ticks": elapsed_ticks,
		"finite_initial_ul": finite_initial,
		"finite_final_ul": finite_final,
		"precipitation_ul": precipitation_total,
		"precipitation_overflow_ul": precipitation_overflow_total,
		"infiltration_ul": infiltration_total,
		"evaporation_ul": evaporation_total,
		"runoff_ul": runoff_total,
		"runoff_transfer_count": runoff_transfer_count,
	}


func _finite_total(
	surface: PackedInt64Array,
	soil: PackedInt64Array,
	kinds: PackedByteArray
) -> int:
	var total := 0
	for index in range(surface.size()):
		if int(kinds[index]) == EnvironmentStoreScript.RESERVOIR_FINITE:
			total += int(surface[index]) + int(soil[index])
	return total


func _ceil_div(value: int, divisor: int) -> int:
	if value <= 0:
		return 0
	return 1 + ((value - 1) / divisor)


func _saturating_product(value: int, multiplier: int) -> int:
	if value <= 0 or multiplier <= 0:
		return 0
	var limit := EnvironmentStoreScript.MAX_WATER_UL_PER_CELL
	if value > limit / multiplier:
		return limit
	return mini(limit, value * multiplier)


func _failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
