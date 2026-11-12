extends RefCounted

## DM4: unedited visual halo, built with EXACTLY the same Q8.8 0.5-m
## Surface Nets backend, chunk ownership and halo as the definitive B4.
## This worker is still non-authoritative: no scene resources, world state,
## object-effect scopes, brush edits or simulation state are accessed.
const B4 := preload("res://scripts/experiments/discrete_surface_nets_backend.gd")
const Grid := preload("res://scripts/terrain/terrain_chunk_grid.gd")
const SAMPLE_STEP := Grid.SAMPLE_STEP

var seed: int
var region: Vector2i
var lod: int
var result: Dictionary = {}
var started_usec := 0
var finished_usec := 0


func _init(world_seed: int, region_key: Vector2i, level: int = 0) -> void:
	seed = world_seed
	region = region_key
	lod = level


func run() -> void:
	started_usec = Time.get_ticks_usec()
	result = build_data(seed, region, lod)
	finished_usec = Time.get_ticks_usec()


## Result triangles are local to the region, not to their individual chunks.
## The 16 chunk outputs are concatenated without altering ANY vertex, normal,
## edge ownership or lattice sample: a pristine canonical region's geometry
## is exactly the same, including its +/- one-cell Surface Nets halo.
static func build_data(world_seed: int, key: Vector2i, level: int = 0) -> Dictionary:
	if level != 0:
		return {"valid": false, "reason": "dm4_high_only_no_low_fallback"}
	var started := Time.get_ticks_usec()
	var backend := B4.new()
	if not backend.generate(world_seed, key, SAMPLE_STEP):
		return {"valid": false, "reason": "dm4_b4_lattice_failed"}
	var positions := PackedVector3Array()
	var normals := PackedVector3Array()
	var chunk_triangle_counts: Dictionary = {}
	var skipped_total := 0
	for coordinate in Grid.all_coordinates():
		var chunk_data: Dictionary = backend.build_chunk(coordinate)
		if not bool(chunk_data.get("valid", false)):
			skipped_total += int(chunk_data.get("skipped_faces", 0))
			return {
				"valid": false,
				"reason": "dm4_b4_chunk_surface_invalid",
				"chunk": coordinate,
				"skipped_faces": skipped_total,
			}
		var origin: Vector3 = Grid.origin_for(coordinate)
		var chunk_positions: PackedVector3Array = chunk_data["positions"]
		var chunk_normals: PackedVector3Array = chunk_data["normals"]
		if chunk_positions.size() != chunk_normals.size():
			return {"valid": false, "reason": "dm4_b4_chunk_normals_mismatch"}
		for vertex in chunk_positions:
			positions.append(vertex + origin)
		normals.append_array(chunk_normals)
		chunk_triangle_counts[coordinate] = int(chunk_data["triangle_count"])
	return {
		"valid": positions.size() == normals.size(),
		"lod": 0,
		"backend": "b4_surface_nets",
		"geometry_mode": "same_as_pristine_definitive",
		"step": SAMPLE_STEP,
		"positions": positions,
		"normals": normals,
		"triangle_count": positions.size() / 3,
		"sample_sites": backend.last_generation_sample_count,
		"chunk_triangle_counts": chunk_triangle_counts,
		"skipped_faces": skipped_total,
		"worker_usec": Time.get_ticks_usec() - started,
	}
