class_name MarchingTetrahedra
extends RefCounted

## Bounded single-region isosurface extraction. All sampled values are pure SDF data.
const FIELD := preload("res://scripts/terrain/sdf_world.gd")
const BRUSH_STATE_SCRIPT := preload("res://scripts/terrain/sdf_brush_edit_state.gd")
const CHUNK_GRID := preload("res://scripts/terrain/terrain_chunk_grid.gd")
const SPATIAL := preload("res://scripts/terrain/terrain_spatial_ownership.gd")
const MIN_BOUND: Vector3 = CHUNK_GRID.MIN_BOUND
const MAX_BOUND: Vector3 = CHUNK_GRID.MAX_BOUND
const STEP: float = CHUNK_GRID.SAMPLE_STEP
const CORNERS := [
	Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(1, 1, 0), Vector3i(0, 1, 0),
	Vector3i(0, 0, 1), Vector3i(1, 0, 1), Vector3i(1, 1, 1), Vector3i(0, 1, 1),
]
const TETRAHEDRA := [
	[0, 5, 1, 6], [0, 1, 2, 6], [0, 2, 3, 6],
	[0, 3, 7, 6], [0, 7, 4, 6], [0, 4, 5, 6],
]


static func build_mesh(
	seed: int,
	region_key: Vector2i,
	show_cave_section: bool = false,
	brush_state: Variant = null
) -> Dictionary:
	return _build_mesh_cells(
		seed, region_key, CHUNK_GRID.MIN_BOUND, 0, CHUNK_GRID.CELL_COUNT_X, 0, CHUNK_GRID.CELL_COUNT_Z,
		show_cave_section, Vector3.ZERO, brush_state, Vector2i(-1, -1), 0, CHUNK_GRID.CELL_COUNT_Y
	)


static func build_chunk_mesh(
	seed: int,
	region_key: Vector2i,
	chunk_coordinate: Vector2i,
	show_cave_section: bool = false,
	brush_state: Variant = null
) -> Dictionary:
	if not CHUNK_GRID.is_valid_coordinate(chunk_coordinate):
		return {"mesh": ArrayMesh.new(), "vertex_count": 0, "triangle_count": 0, "sample_count": 0, "valid": false}
	var bounds: Vector4i = CHUNK_GRID.cell_bounds(chunk_coordinate)
	return _build_mesh_cells(
		seed, region_key, CHUNK_GRID.MIN_BOUND, bounds.x, bounds.y, bounds.z, bounds.w,
		show_cave_section, CHUNK_GRID.origin_for(chunk_coordinate), brush_state, chunk_coordinate,
		0, CHUNK_GRID.CELL_COUNT_Y
	)


static func build_chunk_cpu_data(
	seed: int,
	region_key: Vector2i,
	chunk_coordinate: Vector2i,
	show_cave_section: bool,
	brush_snapshot: Variant
) -> Dictionary:
	if not CHUNK_GRID.is_valid_coordinate(chunk_coordinate):
		return {"vertex_count": 0, "triangle_count": 0, "sample_count": 0, "valid": false}
	var bounds: Vector4i = CHUNK_GRID.cell_bounds(chunk_coordinate)
	return _build_mesh_cells(
		seed, region_key, CHUNK_GRID.MIN_BOUND, bounds.x, bounds.y, bounds.z, bounds.w,
		show_cave_section, CHUNK_GRID.origin_for(chunk_coordinate), brush_snapshot, chunk_coordinate,
		0, CHUNK_GRID.CELL_COUNT_Y, false
	)


static func build_world_reference_mesh(
	seed: int,
	min_world_cell: Vector2i,
	cell_count: Vector2i,
	show_cave_section: bool = false,
	brush_state: RefCounted = null
) -> Dictionary:
	if cell_count.x <= 0 or cell_count.y <= 0:
		return {"mesh": ArrayMesh.new(), "vertex_count": 0, "triangle_count": 0, "sample_count": 0, "valid": false}
	var world_min := Vector3(
		float(min_world_cell.x) * CHUNK_GRID.SAMPLE_STEP,
		CHUNK_GRID.MIN_BOUND.y,
		float(min_world_cell.y) * CHUNK_GRID.SAMPLE_STEP
	)
	return _build_mesh_cells(
		seed, Vector2i.ZERO, world_min, 0, cell_count.x, 0, cell_count.y,
		show_cave_section, Vector3.ZERO, brush_state, Vector2i(-1, -1), 0, CHUNK_GRID.CELL_COUNT_Y
	)


static func _build_mesh_cells(
	seed: int,
	region_key: Vector2i,
	grid_min: Vector3,
	cell_start_x: int,
	cell_end_x: int,
	cell_start_z: int,
	cell_end_z: int,
	show_cave_section: bool,
	mesh_origin: Vector3,
	brush_state: Variant,
	chunk_coordinate: Vector2i,
	cell_start_y: int,
	cell_end_y: int,
	make_mesh: bool = true
) -> Dictionary:
	var timings_usec := {
		"sdf_and_ledger": 0,
		"triangulation_and_face_normals": 0,
		"shared_gradient_normals": 0,
		"array_mesh_build": 0,
	}
	var nx := cell_end_x - cell_start_x + 1
	var ny := cell_end_y - cell_start_y + 1
	var nz := cell_end_z - cell_start_z + 1
	var values := PackedFloat32Array()
	values.resize(nx * ny * nz)
	var sample_started_usec := Time.get_ticks_usec()
	for y in range(ny):
		for z in range(nz):
			for x in range(nx):
				var p := grid_min + Vector3(cell_start_x + x, cell_start_y + y, cell_start_z + z) * STEP
				var density := _sample_density(seed, region_key, p, show_cave_section, brush_state)
				values[_index(x, y, z, nx, nz)] = density
	timings_usec["sdf_and_ledger"] = Time.get_ticks_usec() - sample_started_usec

	var positions := PackedVector3Array()
	var normals := PackedVector3Array()
	var shared_normal_cache: Dictionary = {}
	var sample_origin := grid_min + Vector3(cell_start_x, 0, cell_start_z) * STEP
	var world_region_origin: Vector3 = SPATIAL.region_origin_world(region_key)
	var world_sample_origin := world_region_origin + sample_origin
	var polygonize_started_usec := Time.get_ticks_usec()
	for y in range(ny - 1):
		for z in range(nz - 1):
			for x in range(nx - 1):
				var cube_points: Array[Vector3] = []
				var cube_values: Array[float] = []
				var has_solid_sample := false
				var has_empty_sample := false
				for corner in CORNERS:
					var cx: int = x + corner.x
					var cy: int = y + corner.y
					var cz: int = z + corner.z
					var sample_value: float = values[_index(cx, cy, cz, nx, nz)]
					cube_values.append(sample_value)
					has_solid_sample = has_solid_sample or sample_value >= 0.0
					has_empty_sample = has_empty_sample or sample_value < 0.0
				if not has_solid_sample or not has_empty_sample:
					continue
				for corner in CORNERS:
					cube_points.append(world_sample_origin + Vector3(x + corner.x, cell_start_y + y + corner.y, z + corner.z) * STEP)
				for tetra in TETRAHEDRA:
					_polygonize_tetra(tetra, cube_points, cube_values, positions, normals)
	var triangle_count := positions.size() / 3
	timings_usec["triangulation_and_face_normals"] = Time.get_ticks_usec() - polygonize_started_usec
	var has_chunk_coordinate := CHUNK_GRID.is_valid_coordinate(chunk_coordinate)
	var world_mesh_origin: Vector3 = world_region_origin + mesh_origin
	for vertex_index in range(positions.size()):
		var global_position: Vector3 = positions[vertex_index]
		var region_local_position: Vector3 = global_position - world_region_origin
		if has_chunk_coordinate and CHUNK_GRID.is_shared_boundary_vertex(region_local_position, chunk_coordinate):
			var shared_normal: Vector3 = shared_normal_cache.get(global_position, Vector3.ZERO)
			if not shared_normal_cache.has(global_position):
				var normal_started_usec := Time.get_ticks_usec()
				shared_normal = _sample_outward_normal(seed, region_key, region_local_position, show_cave_section, brush_state)
				timings_usec["shared_gradient_normals"] = int(timings_usec["shared_gradient_normals"]) + Time.get_ticks_usec() - normal_started_usec
				shared_normal_cache[global_position] = shared_normal
			if shared_normal.length_squared() > 0.000001:
				normals[vertex_index] = shared_normal
		positions[vertex_index] = global_position - world_mesh_origin

	var cpu_data := {
		"positions": positions,
		"normals": normals,
		"vertex_count": positions.size(),
		"triangle_count": triangle_count,
		"sample_count": values.size(),
		"timings_usec": timings_usec,
		"valid": true,
	}
	return mesh_from_cpu_data(cpu_data) if make_mesh else cpu_data


static func mesh_from_cpu_data(cpu_data: Dictionary) -> Dictionary:
	if not cpu_data.get("valid", false):
		return cpu_data
	var mesh := ArrayMesh.new()
	var positions: PackedVector3Array = cpu_data["positions"]
	if not positions.is_empty():
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = positions
		arrays[Mesh.ARRAY_NORMAL] = cpu_data["normals"]
		var upload_started_usec := Time.get_ticks_usec()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var timings: Dictionary = cpu_data.get("timings_usec", {})
		timings["array_mesh_build"] = Time.get_ticks_usec() - upload_started_usec
		cpu_data["timings_usec"] = timings
	cpu_data["mesh"] = mesh
	cpu_data.erase("positions")
	cpu_data.erase("normals")
	return cpu_data


static func contains_mesh_point(point: Vector3) -> bool:
	return point.x >= MIN_BOUND.x and point.x <= MAX_BOUND.x \
		and point.y >= MIN_BOUND.y and point.y <= MAX_BOUND.y \
		and point.z >= MIN_BOUND.z and point.z <= MAX_BOUND.z


static func _sample_density(
	seed: int,
	region_key: Vector2i,
	point: Vector3,
	show_cave_section: bool,
	brush_state: Variant
) -> float:
	if brush_state is Dictionary:
		return BRUSH_STATE_SCRIPT.sample_density_snapshot(seed, region_key, point, show_cave_section, brush_state)
	if brush_state is BRUSH_STATE_SCRIPT:
		return brush_state.sample_density(seed, region_key, point, show_cave_section)
	# Evaluate the immutable field from canonical world coordinates so a point
	# sampled through a neighboring region follows the same floating-point path.
	var world_point: Vector3 = SPATIAL.region_local_to_world(region_key, point)
	return FIELD.sample_density(seed, Vector2i.ZERO, world_point, show_cave_section)


static func _sample_outward_normal(
	seed: int,
	region_key: Vector2i,
	point: Vector3,
	show_cave_section: bool,
	brush_state: Variant
) -> Vector3:
	var half_step := STEP * 0.5
	var dx := _sample_density(seed, region_key, point + Vector3.RIGHT * half_step, show_cave_section, brush_state) \
		- _sample_density(seed, region_key, point - Vector3.RIGHT * half_step, show_cave_section, brush_state)
	var dy := _sample_density(seed, region_key, point + Vector3.UP * half_step, show_cave_section, brush_state) \
		- _sample_density(seed, region_key, point - Vector3.UP * half_step, show_cave_section, brush_state)
	var dz := _sample_density(seed, region_key, point + Vector3.BACK * half_step, show_cave_section, brush_state) \
		- _sample_density(seed, region_key, point - Vector3.BACK * half_step, show_cave_section, brush_state)
	var density_gradient := Vector3(dx, dy, dz)
	if density_gradient.length_squared() <= 0.000001:
		return Vector3.ZERO
	# Positive density is solid, so the outward normal points down the density gradient.
	return -density_gradient.normalized()


static func _polygonize_tetra(
	tetra: Array,
	cube_points: Array[Vector3],
	cube_values: Array[float],
	positions: PackedVector3Array,
	normals: PackedVector3Array
) -> int:
	var inside_count := 0
	var outside_count := 0
	var inside0 := -1
	var inside1 := -1
	var inside2 := -1
	var outside0 := -1
	var outside1 := -1
	var outside2 := -1
	for corner_index in tetra:
		if cube_values[corner_index] >= 0.0:
			match inside_count:
				0: inside0 = corner_index
				1: inside1 = corner_index
				2: inside2 = corner_index
			inside_count += 1
		else:
			match outside_count:
				0: outside0 = corner_index
				1: outside1 = corner_index
				2: outside2 = corner_index
			outside_count += 1
	if inside_count == 0 or outside_count == 0:
		return 0
	var inside_center := Vector3.ZERO
	var outside_center := Vector3.ZERO
	if inside_count > 0: inside_center += cube_points[inside0]
	if inside_count > 1: inside_center += cube_points[inside1]
	if inside_count > 2: inside_center += cube_points[inside2]
	if outside_count > 0: outside_center += cube_points[outside0]
	if outside_count > 1: outside_center += cube_points[outside1]
	if outside_count > 2: outside_center += cube_points[outside2]
	inside_center /= float(inside_count)
	outside_center /= float(outside_count)
	var toward_empty := outside_center - inside_center
	if inside_count == 1:
		var a := _interpolate(inside0, outside0, cube_points, cube_values)
		var b := _interpolate(inside0, outside1, cube_points, cube_values)
		var c := _interpolate(inside0, outside2, cube_points, cube_values)
		_add_triangle(a, b, c, toward_empty, positions, normals)
		return 1
	if inside_count == 3:
		var a := _interpolate(outside0, inside0, cube_points, cube_values)
		var b := _interpolate(outside0, inside1, cube_points, cube_values)
		var c := _interpolate(outside0, inside2, cube_points, cube_values)
		_add_triangle(a, b, c, toward_empty, positions, normals)
		return 1
	var a := _interpolate(inside0, outside0, cube_points, cube_values)
	var b := _interpolate(inside0, outside1, cube_points, cube_values)
	var c := _interpolate(inside1, outside0, cube_points, cube_values)
	var d := _interpolate(inside1, outside1, cube_points, cube_values)
	_add_triangle(a, b, d, toward_empty, positions, normals)
	_add_triangle(a, d, c, toward_empty, positions, normals)
	return 2


static func _interpolate(
	a_index: int,
	b_index: int,
	cube_points: Array[Vector3],
	cube_values: Array[float]
) -> Vector3:
	var a_value := cube_values[a_index]
	var b_value := cube_values[b_index]
	var denominator := a_value - b_value
	var weight := 0.5 if is_zero_approx(denominator) else clampf(a_value / denominator, 0.0, 1.0)
	return cube_points[a_index].lerp(cube_points[b_index], weight)


static func _add_triangle(
	a: Vector3,
	b: Vector3,
	c: Vector3,
	toward_empty: Vector3,
	positions: PackedVector3Array,
	normals: PackedVector3Array
) -> void:
	var normal := (b - a).cross(c - a)
	# Keep small but valid triangles near the zero set. A coarse absolute cutoff
	# can drop only one side of a shared face and open a visible chunk seam.
	if normal.length_squared() <= 0.000000000001:
		return
	if normal.dot(toward_empty) < 0.0:
		var swap := b
		b = c
		c = swap
		normal = -normal
	normal = normal.normalized()
	positions.append(a)
	positions.append(b)
	positions.append(c)
	normals.append(normal)
	normals.append(normal)
	normals.append(normal)


static func _index(x: int, y: int, z: int, size_x: int, size_z: int) -> int:
	return (y * size_z + z) * size_x + x
