extends RefCounted

## E2: presentation-only approximation of the pristine generator's top surface.
## Worker produces CPU arrays; no scene nodes, edits, object effects or mesh
## resources are touched on a worker. Canonical terrain remains unchanged.
const Field := preload("res://scripts/terrain/sdf_world.gd")
const Grid := preload("res://scripts/terrain/terrain_chunk_grid.gd")
const ChunkSplitter := preload("res://scripts/terrain/terrain_coarse_preview_chunk_splitter.gd")
const X_CELLS := 8
const Z_CELLS := 6
const VERTICAL_STEP := 0.5
const BISECT_STEPS := 6

var seed: int
var region_key: Vector2i
var stage_token: int
var edit_revision: int
var effect_revision: int
var generator_version: int
var result: Dictionary = {}
var split_into_chunks := false
var worker_started_usec := 0
var worker_finished_usec := 0


func _init(
	world_seed: int, key: Vector2i, token: int,
	brush_revision: int, object_revision: int, version: int,
	per_chunk_preview: bool = false
) -> void:
	seed = world_seed
	region_key = key
	stage_token = token
	edit_revision = brush_revision
	effect_revision = object_revision
	generator_version = version
	split_into_chunks = per_chunk_preview


func run() -> void:
	worker_started_usec = Time.get_ticks_usec()
	result = build_cpu_data(seed, region_key)
	if split_into_chunks and result.get("valid", false):
		result["chunk_patches"] = ChunkSplitter.split(result)
	worker_finished_usec = Time.get_ticks_usec()


## Bounded regular top-surface approximation: 9x7 vertices, 96 triangles.
## Preview ignores tunnels and procedural-object SDF effects by design.
## Its identity is strictly separate from the definitive 16 chunk meshes.
static func build_cpu_data(world_seed: int, key: Vector2i) -> Dictionary:
	var start_usec := Time.get_ticks_usec()
	var heights: Array[float] = []
	for z in range(Z_CELLS + 1):
		for x in range(X_CELLS + 1):
			var px := float(x) * Field.REGION_SIZE_X / float(X_CELLS)
			var pz := float(z) * Field.REGION_SIZE_Z / float(Z_CELLS)
			var height := _upper_surface_height(world_seed, key, px, pz)
			if not is_finite(height):
				return {"valid": false, "reason": "coarse_surface_undefined"}
			heights.append(height)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	for z in range(Z_CELLS):
		for x in range(X_CELLS):
			var x0 := float(x) * Field.REGION_SIZE_X / float(X_CELLS)
			var x1 := float(x + 1) * Field.REGION_SIZE_X / float(X_CELLS)
			var z0 := float(z) * Field.REGION_SIZE_Z / float(Z_CELLS)
			var z1 := float(z + 1) * Field.REGION_SIZE_Z / float(Z_CELLS)
			var i := z * (X_CELLS + 1) + x
			var a := Vector3(x0, heights[i], z0)
			var b := Vector3(x1, heights[i + 1], z0)
			var c := Vector3(x0, heights[i + X_CELLS + 1], z1)
			var d := Vector3(x1, heights[i + X_CELLS + 2], z1)
			for tri in [[a, c, b], [b, c, d]]:
				var p0: Vector3 = tri[0]
				var p1: Vector3 = tri[1]
				var p2: Vector3 = tri[2]
				var normal: Vector3 = (p1 - p0).cross(p2 - p0).normalized()
				if not normal.is_finite() or normal.y <= 0.0:
					return {"valid": false, "reason": "coarse_invalid_winding"}
				for v in tri:
					vertices.append(v)
					normals.append(normal)
	return {
		"valid": true,
		"positions": vertices,
		"normals": normals,
		"vertex_count": vertices.size(),
		"triangle_count": vertices.size() / 3,
		"worker_usec": Time.get_ticks_usec() - start_usec,
	}


static func _upper_surface_height(world_seed: int, key: Vector2i, x: float, z: float) -> float:
	var above := Grid.MAX_BOUND.y
	# Walk downward from guaranteed air. Take the first positive-solid
	# crossing; this deliberately excludes cave openings beneath the top.
	for step in range(1, int((Grid.MAX_BOUND.y - Grid.MIN_BOUND.y) / VERTICAL_STEP) + 1):
		var below := Grid.MAX_BOUND.y - float(step) * VERTICAL_STEP
		var density := Field.sample_density(world_seed, key, Vector3(x, below, z), false)
		if density >= 0.0:
			for _iteration in range(BISECT_STEPS):
				var midpoint := (above + below) * 0.5
				if Field.sample_density(world_seed, key, Vector3(x, midpoint, z), false) >= 0.0:
					below = midpoint
				else:
					above = midpoint
			return (above + below) * 0.5
		above = below
	return NAN


## Called only on the main thread. Never call this from run().
static func mesh_from_cpu_data(cpu_data: Dictionary) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if not cpu_data.get("valid", false):
		return mesh
	var vertices: PackedVector3Array = cpu_data.get("positions", PackedVector3Array())
	var normals: PackedVector3Array = cpu_data.get("normals", PackedVector3Array())
	if vertices.is_empty() or vertices.size() != normals.size():
		return mesh
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
