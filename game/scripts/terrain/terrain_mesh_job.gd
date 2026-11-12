extends RefCounted

## Worker-only immutable input and CPU result. This object never owns a scene or Mesh resource.
const Mesher := preload("res://scripts/terrain/marching_tetrahedra.gd")
const LodMesher := preload("res://scripts/terrain/lod01_chunk_mesher.gd")
const Field := preload("res://scripts/terrain/sdf_world.gd")
const BrushState := preload("res://scripts/terrain/sdf_brush_edit_state.gd")
const ExperimentalB4 := preload("res://scripts/experiments/discrete_surface_nets_backend.gd")

var seed: int
var region_key: Vector2i
var coordinate: Vector2i
var cave_section_enabled: bool
var brush_snapshot: Variant
var lod_level := 0
var experimental_b4 := false
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
	lod_value: int = 0,
	b4_value: bool = false
) -> void:
	seed = seed_value
	region_key = region_value
	coordinate = coordinate_value
	cave_section_enabled = cave_value
	brush_snapshot = brush_snapshot_value
	queued_usec = queued_value
	lod_level = clampi(lod_value, 0, 1)
	experimental_b4 = b4_value


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
	if experimental_b4:
		_run_experimental_b4(immutable_snapshot)
	elif lod_level == 1:
		result = LodMesher.build_chunk_cpu_data(
			seed, region_key, coordinate, immutable_snapshot, Callable(self, "_sample_lod_density")
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
	worker_finished_usec = Time.get_ticks_usec()



## No scene resources or world mutation. Validation/publication still owned by
## TerrainDemo, exactly as with the original SDF mesh job.
func _run_experimental_b4(snapshot: Dictionary) -> void:
	var backend := ExperimentalB4.new()
	var generate_started_usec := Time.get_ticks_usec()
	var generated := backend.generate_chunk(
		seed, region_key, coordinate, snapshot, cave_section_enabled
	)
	var generate_usec := Time.get_ticks_usec() - generate_started_usec
	if not generated:
		result = {
			"valid": false,
			"reason": "dm2_b4_snapshot_materialization_failed",
			"backend": "b4",
			"region_key": region_key,
			"coordinate": coordinate,
		}
		return
	var mesh_started_usec := Time.get_ticks_usec()
	result = backend.build_chunk(coordinate)
	var mesh_usec := Time.get_ticks_usec() - mesh_started_usec
	if not bool(result.get("valid", false)):
		result["reason"] = "dm2_b4_topology_or_mesh_failure"
		return
	result["backend"] = "b4"
	result["lod_level"] = 0
	result["lod_fallback"] = false
	result["timings_usec"] = {
		"sdf_and_ledger": generate_usec,
		"triangulation_and_face_normals": mesh_usec,
		"shared_gradient_normals": 0,
		"b4_materialize_usec": generate_usec,
		"b4_surface_nets_usec": mesh_usec,
	}


func _sample_lod_density(region_local_position: Vector3) -> float:
	if not region_local_position.is_finite():
		return NAN
	var snapshot: Dictionary = brush_snapshot if brush_snapshot is Dictionary else {}
	if snapshot.is_empty():
		return Field.sample_density(
			seed, region_key, region_local_position, cave_section_enabled
		)
	return BrushState.sample_density_snapshot(
		seed, region_key, region_local_position, cave_section_enabled, snapshot
	)
