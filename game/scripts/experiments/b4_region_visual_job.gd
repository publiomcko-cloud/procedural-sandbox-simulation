extends RefCounted

## DM4: real B4 Q8.8 Surface Nets mesh, exactly 0.5m across every
## visual region. Uses the same pristine sample field and grid as canonical
## DM2 B4. No scene nodes, effects, edits or mutable authority on workers.
const B4 := preload("res://scripts/experiments/discrete_surface_nets_backend.gd")
const Grid := preload("res://scripts/terrain/terrain_chunk_grid.gd")
const STEP := 0.5

var seed: int
var region: Vector2i
var lod: int
var result: Dictionary = {}
var started_usec := 0
var finished_usec := 0
var fast_pristine := false
var worker_thread_id := 0


func _init(world_seed: int, region_key: Vector2i, level: int = 0, enable_fast: bool = false) -> void:
	seed = world_seed
	region = region_key
	# Compatibility metadata only. All jobs have uniform B4 HIGH density.
	lod = 0
	fast_pristine = enable_fast


func run() -> void:
	worker_thread_id = OS.get_thread_caller_id()
	started_usec = Time.get_ticks_usec()
	result = build_data(seed, region, lod, fast_pristine)
	finished_usec = Time.get_ticks_usec()


## Combine 16 B4 chunk meshes into one region-relative mesh. The sample
## halo and edge ownership remain exactly those of the existing B4 oracle.
## A high region never changes grid resolution on distance transitions.
static func build_data(world_seed: int, key: Vector2i, _level: int = 0, fast: bool = false) -> Dictionary:
	var started := Time.get_ticks_usec()
	var mesher := B4.new()
	var generation_started_usec := Time.get_ticks_usec()
	var generate_ok := mesher.generate_pristine_fast(world_seed, key, STEP) if fast \
		else mesher.generate(world_seed, key, STEP)
	if not generate_ok:
		return {"valid": false, "reason": "b4_generate_failed"}
	var generation_usec := Time.get_ticks_usec() - generation_started_usec
	var meshing_started_usec := Time.get_ticks_usec()
	var positions := PackedVector3Array()
	var normals := PackedVector3Array()
	var total_quads := 0
	var chunk_build_usec := 0
	var chunk_combine_usec := 0
	for coordinate in Grid.all_coordinates():
		var chunk_started := Time.get_ticks_usec()
		var part: Dictionary = mesher.build_chunk_pristine_fast(coordinate) if fast \
			else mesher.build_chunk(coordinate)
		chunk_build_usec += Time.get_ticks_usec() - chunk_started
		if not bool(part.get("valid", false)):
			return {
				"valid": false,
				"reason": "b4_chunk_incomplete",
				"coordinate": coordinate,
				"skipped_faces": part.get("skipped_faces", -1),
			}
		var combine_started := Time.get_ticks_usec()
		var origin: Vector3 = Grid.origin_for(coordinate)
		var source_positions: PackedVector3Array = part["positions"]
		var source_normals: PackedVector3Array = part["normals"]
		if source_positions.size() != source_normals.size():
			return {"valid": false, "reason": "b4_chunk_array_mismatch"}
		for index in range(source_positions.size()):
			positions.append(source_positions[index] + origin)
		normals.append_array(source_normals)
		total_quads += int(part["quad_count"])
		chunk_combine_usec += Time.get_ticks_usec() - combine_started
	return {
		"valid": true,
		"lod": 0,
		"backend": "b4",
		"sample_step": STEP,
		"positions": positions,
		"normals": normals,
		"triangle_count": positions.size() / 3,
		"sample_sites": mesher.last_generation_sample_count,
		"surface_quads": total_quads,
		"worker_usec": Time.get_ticks_usec() - started,
		"fast_pristine": fast,
		"precompute_usec": mesher.last_pristine_precompute_usec,
		"lattice_usec": mesher.last_pristine_lattice_usec,
		"cell_rebuild_usec": mesher.last_pristine_rebuild_usec,
		"uniform_cells_skipped": mesher.last_pristine_uniform_cells,
		"chunk_build_usec": chunk_build_usec,
		"chunk_combine_usec": chunk_combine_usec,
		"field_generate_usec": generation_usec,
		"surface_mesh_usec": Time.get_ticks_usec() - meshing_started_usec,
	}
