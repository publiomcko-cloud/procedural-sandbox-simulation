extends RefCounted

## Deterministic spawn-selection inputs for P5 owner GUI acceptance.
## This class only chooses a camera/focus target; it never creates water or edits
## authoritative environment state. All world coordinates are in meters.

const Field := preload("res://scripts/terrain/sdf_world.gd")
const SpatialGrid := preload("res://scripts/terrain/terrain_spatial_ownership.gd")
const Hydrology := preload("res://scripts/simulation/environment_hydrology_domain.gd")

const MAX_REGION_COORDINATE := 10_000
const MAX_WORLD_COORDINATE_M := 100_000.0
const PRESET_REGION_X_MIN := -6
const PRESET_REGION_X_MAX := 6
const PRESET_REGION_Z_MIN := 10
const PRESET_REGION_Z_MAX := 16
const GRID_WIDTH := 8
const GRID_HEIGHT := 6
const CELL_SIZE_M := 2.0
const TARGET_Y_M := 3.1
const MIN_OCEAN_MARGIN_M := 0.12


static func select_from_args(args: PackedStringArray, seed: int) -> Dictionary:
	var chosen := ""
	for argument in args:
		if argument.begins_with("--start-region=") or argument.begins_with("--start-position=") or argument.begins_with("--start-water="):
			if not chosen.is_empty():
				return _failure("multiple_start_location_options")
			chosen = argument
	if chosen.is_empty():
		return {"ok": true, "mode": "default", "target": Vector3(8.0, TARGET_Y_M, 6.0), "region": Vector2i.ZERO}
	if chosen.begins_with("--start-region="):
		var coordinates := _parse_pair(chosen.trim_prefix("--start-region="), true)
		if not coordinates.get("ok", false):
			return coordinates
		var region := Vector2i(int(coordinates["x"]), int(coordinates["z"]))
		return {
			"ok": true,
			"mode": "region",
			"region": region,
			"target": SpatialGrid.region_origin_world(region) + Vector3(
				SpatialGrid.REGION_SIZE_X * 0.5, TARGET_Y_M, SpatialGrid.REGION_SIZE_Z * 0.5
			),
		}
	if chosen.begins_with("--start-position="):
		var coordinates := _parse_pair(chosen.trim_prefix("--start-position="), false)
		if not coordinates.get("ok", false):
			return coordinates
		var target := Vector3(float(coordinates["x"]), TARGET_Y_M, float(coordinates["z"]))
		return {
			"ok": true,
			"mode": "position",
			"region": SpatialGrid.region_key_for_world_position(target),
			"target": target,
		}
	var preset := chosen.trim_prefix("--start-water=")
	if preset != "ocean":
		return _failure("unknown_start_water_preset")
	return _find_ocean_region(seed)


## Search a strictly bounded area within the generated ocean band. The target
## uses only the base SDF and will not override saved terrain edits. Actual
## reservoir bindings still require the configured hydrology runtime.
static func _find_ocean_region(seed: int) -> Dictionary:
	var best := {"ok": false, "reason": "no_ocean_candidate_in_search_window"}
	var best_count := -1
	var best_distance := 2147483647
	for rz in range(PRESET_REGION_Z_MIN, PRESET_REGION_Z_MAX + 1):
		for rx in range(PRESET_REGION_X_MIN, PRESET_REGION_X_MAX + 1):
			var region := Vector2i(rx, rz)
			var count := 0
			for cz in range(GRID_HEIGHT):
				for cx in range(GRID_WIDTH):
					var x := (float(cx) + 0.5) * CELL_SIZE_M
					var z := (float(cz) + 0.5) * CELL_SIZE_M
					# At the ocean plane, negative density means terrain below water.
					var density := Field.sample_density(
						seed, region,
						Vector3(x, float(Hydrology.OCEAN_LEVEL_MM) / 1000.0, z)
					)
					if density < -MIN_OCEAN_MARGIN_M:
						count += 1
			var distance := absi(rx) + absi(rz - PRESET_REGION_Z_MIN)
			if count > best_count or (count == best_count and distance < best_distance):
				best_count = count
				best_distance = distance
				best = {
					"ok": true,
					"mode": "ocean",
					"region": region,
					"target": SpatialGrid.region_origin_world(region) + Vector3(
						SpatialGrid.REGION_SIZE_X * 0.5,
						TARGET_Y_M,
						SpatialGrid.REGION_SIZE_Z * 0.5
					),
					"candidate_water_cells": count,
					"note": "base_sdf_only; actual persisted edits and hydrology bindings may differ",
				}
	if best_count < 1:
		return _failure("no_ocean_candidate_in_search_window")
	return best


static func _parse_pair(value: String, integer: bool) -> Dictionary:
	var components := value.split(",", true)
	if components.size() != 2:
		return _failure("start_coordinates_require_x_z")
	for text_value in components:
		if text_value.is_empty() or text_value.strip_edges() != text_value:
			return _failure("start_coordinates_invalid")
		if integer and not text_value.is_valid_int():
			return _failure("start_region_requires_integers")
		if not integer and not text_value.is_valid_float():
			return _failure("start_position_requires_numbers")
	var x := float(components[0])
	var z := float(components[1])
	var maximum := float(MAX_REGION_COORDINATE) if integer else MAX_WORLD_COORDINATE_M
	if not is_finite(x) or not is_finite(z) or absf(x) > maximum or absf(z) > maximum:
		return _failure("start_coordinates_out_of_bounds")
	return {"ok": true, "x": int(x) if integer else x, "z": int(z) if integer else z}


static func _failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
