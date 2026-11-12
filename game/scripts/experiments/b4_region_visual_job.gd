extends RefCounted

## DM3 derived visualization. No snapshots, edits, entity state, scene nodes,
## meshes, physics or save access on the worker thread. Never authoritative.
const Field := preload("res://scripts/terrain/sdf_world.gd")
const Grid := preload("res://scripts/terrain/terrain_chunk_grid.gd")
const FINE_X_CELLS := 16
const FINE_Z_CELLS := 12
const LOW_X_CELLS := 8
const LOW_Z_CELLS := 6
const VERTICAL_STEP := 0.5
const BISECT_STEPS := 6

var seed: int
var region: Vector2i
var lod: int
var result: Dictionary = {}
var started_usec := 0
var finished_usec := 0


func _init(world_seed: int, region_key: Vector2i, level: int) -> void:
	seed = world_seed
	region = region_key
	lod = clampi(level, 0, 1)


func run() -> void:
	started_usec = Time.get_ticks_usec()
	result = build_data(seed, region, lod)
	finished_usec = Time.get_ticks_usec()


static func build_data(world_seed: int, key: Vector2i, level: int) -> Dictionary:
	var started := Time.get_ticks_usec()
	var x_cells := LOW_X_CELLS if level == 1 else FINE_X_CELLS
	var z_cells := LOW_Z_CELLS if level == 1 else FINE_Z_CELLS
	var heights := PackedFloat32Array()
	heights.resize((x_cells + 1) * (z_cells + 1))
	var samples := 0
	for z in range(z_cells + 1):
		for x in range(x_cells + 1):
			var px := float(x) * Field.REGION_SIZE_X / float(x_cells)
			var pz := float(z) * Field.REGION_SIZE_Z / float(z_cells)
			var h := _top_height(world_seed, key, px, pz)
			# Ocean-floor and sky-only cells may lack a top crossing in the
			# bounded Y extent; those triangles are omitted, not fabricated.
			heights[z * (x_cells + 1) + x] = h
			samples += 1
	var positions := PackedVector3Array()
	var normals := PackedVector3Array()
	for z in range(z_cells):
		for x in range(x_cells):
			var i := z * (x_cells + 1) + x
			var h00: float = heights[i]
			var h10: float = heights[i + 1]
			var h01: float = heights[i + x_cells + 1]
			var h11: float = heights[i + x_cells + 2]
			if not (is_finite(h00) and is_finite(h10)
					and is_finite(h01) and is_finite(h11)):
				continue
			var ax := float(x) * Field.REGION_SIZE_X / float(x_cells)
			var bx := float(x + 1) * Field.REGION_SIZE_X / float(x_cells)
			var az := float(z) * Field.REGION_SIZE_Z / float(z_cells)
			var bz := float(z + 1) * Field.REGION_SIZE_Z / float(z_cells)
			var a := Vector3(ax, h00, az)
			var b := Vector3(bx, h10, az)
			var c := Vector3(ax, h01, bz)
			var d := Vector3(bx, h11, bz)
			for triangle in [[a,c,b], [b,c,d]]:
				var face: Vector3 = (triangle[1] - triangle[0]).cross(
					triangle[2] - triangle[0]
				)
				if face.length_squared() <= 0.0000000001:
					continue
				var normal := face.normalized()
				for vertex in triangle:
					positions.append(vertex)
					normals.append(normal)
	return {
		"valid": true,
		"lod": level,
		"positions": positions,
		"normals": normals,
		"triangle_count": positions.size() / 3,
		"sample_sites": samples,
		"worker_usec": Time.get_ticks_usec() - started,
	}


static func _top_height(world_seed: int, region_key: Vector2i, x: float, z: float) -> float:
	var above := Grid.MAX_BOUND.y
	for n in range(1, int((Grid.MAX_BOUND.y - Grid.MIN_BOUND.y) / VERTICAL_STEP) + 1):
		var below := Grid.MAX_BOUND.y - float(n) * VERTICAL_STEP
		var density := Field.sample_density(
			world_seed, region_key, Vector3(x, below, z), false
		)
		if density >= 0.0:
			for _i in range(BISECT_STEPS):
				var midpoint := (above + below) * 0.5
				if Field.sample_density(
					world_seed, region_key, Vector3(x, midpoint, z), false
				) >= 0.0:
					below = midpoint
				else:
					above = midpoint
			return (above + below) * 0.5
		above = below
	return NAN
