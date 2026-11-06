extends RefCounted

## Worker-only immutable input and CPU result. This object never owns a scene or Mesh resource.
const Mesher := preload("res://scripts/terrain/marching_tetrahedra.gd")
const LodMesher := preload("res://scripts/terrain/lod01_chunk_mesher.gd")
const Field := preload("res://scripts/terrain/sdf_world.gd")
const BrushState := preload("res://scripts/terrain/sdf_brush_edit_state.gd")
const Spatial := preload("res://scripts/terrain/terrain_spatial_ownership.gd")

var seed: int
var region_key: Vector2i
var coordinate: Vector2i
var cave_section_enabled: bool
var brush_snapshot: Variant
var lod_level := 0
var result: Dictionary = {}
var queued_usec: int
var worker_started_usec := 0
var worker_finished_usec := 0
var worker_thread_id := 0


func _init(
	seed_value: int,
	region_value: Vector2i,
	coordinate_value: Vector2i,
	cave_value: bool,
	brush_snapshot_value: Variant,
	queued_value: int,
	lod_value: int = 0
) -> void:
	seed = seed_value
	region_key = region_value
	coordinate = coordinate_value
	cave_section_enabled = cave_value
	brush_snapshot = brush_snapshot_value
	queued_usec = queued_value
	lod_level = clampi(lod_value, 0, 1)


func run() -> void:
	worker_started_usec = Time.get_ticks_usec()
	worker_thread_id = OS.get_thread_caller_id()
	if brush_snapshot is Dictionary and not bool(brush_snapshot.get("valid", true)):
		result = {
			"valid": false,
			"reason": String(brush_snapshot.get("storage_error", "invalid_brush_snapshot")),
			"region_key": region_key,
			"coordinate": coordinate,
			"ledger_revision": int(brush_snapshot.get("revision", -1)),
		}
		worker_finished_usec = Time.get_ticks_usec()
		return
	var immutable_snapshot: Dictionary = brush_snapshot if brush_snapshot is Dictionary else {}
	var has_terrain_effects := not (
		immutable_snapshot.get("terrain_object_effect_frames", []) as Array
	).is_empty()
	if lod_level == 1 and not has_terrain_effects:
		var snapshot: Dictionary = immutable_snapshot
		result = LodMesher.build_chunk_cpu_data(
			seed, region_key, coordinate, snapshot, Callable(self, "_sample_lod_density")
		)
		if not result.get("valid", false):
			var fallback_reason := String(result.get("reason", "lod1_build_failed"))
			result = Mesher.build_chunk_cpu_data(
				seed, region_key, coordinate, cave_section_enabled, brush_snapshot
			)
			result["lod_level"] = 0
			result["lod_fallback"] = true
			result["lod_fallback_reason"] = fallback_reason
	else:
		result = Mesher.build_chunk_cpu_data(
			seed, region_key, coordinate, cave_section_enabled, brush_snapshot
		)
		if lod_level == 1 and has_terrain_effects:
			result["lod_level"] = 0
			result["lod_fallback"] = true
			result["lod_fallback_reason"] = "terrain_effect_precision_frame_requires_lod0"
	worker_finished_usec = Time.get_ticks_usec()


func _sample_lod_density(world_position: Vector3) -> float:
	if not world_position.is_finite():
		return NAN
	var mapped_region := Spatial.region_key_for_world_position(world_position)
	var mapped_local := Spatial.region_local_for_world_position(world_position, mapped_region)
	var snapshot: Dictionary = brush_snapshot if brush_snapshot is Dictionary else {}
	if snapshot.is_empty():
		return Field.sample_density(seed, mapped_region, mapped_local, cave_section_enabled)
	return BrushState.sample_density_snapshot(
		seed, mapped_region, mapped_local, cave_section_enabled, snapshot
	)
