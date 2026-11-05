class_name TerrainSdfTileMaterializationJob
extends RefCounted

## Worker-only immutable materialization input. It has no scene/store ownership.

const Field := preload("res://scripts/terrain/sdf_world.gd")
const Brush := preload("res://scripts/terrain/sdf_brush_edit_state.gd")
const Spatial := preload("res://scripts/terrain/terrain_spatial_ownership.gd")
const Grid := preload("res://scripts/terrain/terrain_chunk_grid.gd")

var seed: int
var region_key: Vector2i
var coordinate: Vector2i
var previous_values: PackedFloat64Array
var operations: Array[Dictionary]
var revision: int
var next_sequence: int
var result: Dictionary = {}
var worker_started_usec := 0
var worker_finished_usec := 0


func _init(
	seed_value: int,
	region_value: Vector2i,
	coordinate_value: Vector2i,
	previous_values_value: PackedFloat64Array,
	operations_value: Array[Dictionary],
	revision_value: int,
	next_sequence_value: int
) -> void:
	seed = seed_value
	region_key = region_value
	coordinate = coordinate_value
	previous_values = previous_values_value
	operations = operations_value
	revision = revision_value
	next_sequence = next_sequence_value


func run() -> void:
	worker_started_usec = Time.get_ticks_usec()
	result = _build()
	worker_finished_usec = Time.get_ticks_usec()
	result["worker_usec"] = worker_finished_usec - worker_started_usec


func _build() -> Dictionary:
	if not Grid.is_valid_coordinate(coordinate) or operations.is_empty():
		return {"valid": false, "reason": "invalid_materialization_job"}
	var region_origin := Spatial.region_origin_world(region_key)
	var local_origin := Grid.origin_for(coordinate)
	var world_origin := region_origin + Vector3(local_origin.x, Grid.MIN_BOUND.y, local_origin.z)
	var dims := Vector3i(
		Grid.CELLS_PER_CHUNK_X + 1,
		Grid.CELL_COUNT_Y + 1,
		Grid.CELLS_PER_CHUNK_Z + 1
	)
	var expected_count := dims.x * dims.y * dims.z
	if not previous_values.is_empty() and previous_values.size() != expected_count:
		return {"valid": false, "reason": "previous_tile_shape_mismatch"}
	var values := PackedFloat64Array()
	values.resize(expected_count)
	for y in range(dims.y):
		for z in range(dims.z):
			for x in range(dims.x):
				var value_index := (y * dims.z + z) * dims.x + x
				var world_point := world_origin + Vector3(x, y, z) * Grid.SAMPLE_STEP
				var density: float
				if previous_values.is_empty():
					var mapped: Dictionary = Spatial.world_to_region_local(world_point)
					if not mapped.get("valid", false):
						return {"valid": false, "reason": "sample_mapping_failed"}
					density = Field.sample_density(
						seed, mapped["region_key"], mapped["local_position"], false
					)
				else:
					density = float(previous_values[value_index])
				for operation in operations:
					var center: Vector3 = operation["center_world"]
					var threshold := world_point.distance_to(center) - float(operation["radius"])
					if int(operation["mode"]) == Brush.Mode.CARVE:
						density = minf(density, threshold)
					else:
						density = maxf(density, -threshold)
				if not is_finite(density):
					return {"valid": false, "reason": "sample_non_finite"}
				values[value_index] = density
	return {
		"valid": true,
		"tile": {
			"format": "materialized-sdf-tile",
			"format_version": 1,
			"tile_id": Grid.stable_id(region_key, coordinate),
			"region_key": region_key,
			"coordinate": coordinate,
			"origin_world": world_origin,
			"dims": dims,
			"step": Grid.SAMPLE_STEP,
			"base_revision": revision,
			"base_sequence": next_sequence - 1,
			"values": values,
		},
	}
