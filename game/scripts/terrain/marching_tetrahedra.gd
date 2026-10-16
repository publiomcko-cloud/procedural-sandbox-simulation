class_name MarchingTetrahedra
extends RefCounted

## Bounded single-region isosurface extraction. All sampled values are pure SDF data.
const FIELD := preload("res://scripts/terrain/sdf_world.gd")
const MIN_BOUND := Vector3(-1.0, -2.0, -1.0)
const MAX_BOUND := Vector3(17.0, 8.0, 13.0)
const STEP := 0.5
const CORNERS := [
	Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(1, 1, 0), Vector3i(0, 1, 0),
	Vector3i(0, 0, 1), Vector3i(1, 0, 1), Vector3i(1, 1, 1), Vector3i(0, 1, 1),
]
const TETRAHEDRA := [
	[0, 5, 1, 6], [0, 1, 2, 6], [0, 2, 3, 6],
	[0, 3, 7, 6], [0, 7, 4, 6], [0, 4, 5, 6],
]


static func build_mesh(seed: int, region_key: Vector2i, show_cave_section: bool = false) -> Dictionary:
	var nx := int(round((MAX_BOUND.x - MIN_BOUND.x) / STEP)) + 1
	var ny := int(round((MAX_BOUND.y - MIN_BOUND.y) / STEP)) + 1
	var nz := int(round((MAX_BOUND.z - MIN_BOUND.z) / STEP)) + 1
	var values := PackedFloat32Array()
	values.resize(nx * ny * nz)
	for y in range(ny):
		for z in range(nz):
			for x in range(nx):
				var p := MIN_BOUND + Vector3(x, y, z) * STEP
				values[_index(x, y, z, nx, nz)] = FIELD.sample_density(seed, region_key, p, show_cave_section)

	var positions := PackedVector3Array()
	var normals := PackedVector3Array()
	for y in range(ny - 1):
		for z in range(nz - 1):
			for x in range(nx - 1):
				var cube_points: Array[Vector3] = []
				var cube_values: Array[float] = []
				for corner in CORNERS:
					var cx: int = x + corner.x
					var cy: int = y + corner.y
					var cz: int = z + corner.z
					cube_points.append(MIN_BOUND + Vector3(cx, cy, cz) * STEP)
					cube_values.append(values[_index(cx, cy, cz, nx, nz)])
				for tetra in TETRAHEDRA:
					_polygonize_tetra(tetra, cube_points, cube_values, positions, normals)
	var triangle_count := positions.size() / 3

	var mesh := ArrayMesh.new()
	if not positions.is_empty():
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = positions
		arrays[Mesh.ARRAY_NORMAL] = normals
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return {
		"mesh": mesh,
		"vertex_count": positions.size(),
		"triangle_count": triangle_count,
		"sample_count": values.size(),
	}


static func _polygonize_tetra(
	tetra: Array,
	cube_points: Array[Vector3],
	cube_values: Array[float],
	positions: PackedVector3Array,
	normals: PackedVector3Array
) -> int:
	var inside: Array[int] = []
	var outside: Array[int] = []
	for corner_index in tetra:
		if cube_values[corner_index] >= 0.0:
			inside.append(corner_index)
		else:
			outside.append(corner_index)
	if inside.is_empty() or outside.is_empty():
		return 0
	var inside_center := Vector3.ZERO
	var outside_center := Vector3.ZERO
	for index in inside:
		inside_center += cube_points[index]
	for index in outside:
		outside_center += cube_points[index]
	inside_center /= float(inside.size())
	outside_center /= float(outside.size())
	var toward_empty := outside_center - inside_center
	if inside.size() == 1:
		var a := _interpolate(inside[0], outside[0], cube_points, cube_values)
		var b := _interpolate(inside[0], outside[1], cube_points, cube_values)
		var c := _interpolate(inside[0], outside[2], cube_points, cube_values)
		_add_triangle(a, b, c, toward_empty, positions, normals)
		return 1
	if inside.size() == 3:
		var a := _interpolate(outside[0], inside[0], cube_points, cube_values)
		var b := _interpolate(outside[0], inside[1], cube_points, cube_values)
		var c := _interpolate(outside[0], inside[2], cube_points, cube_values)
		_add_triangle(a, b, c, toward_empty, positions, normals)
		return 1
	var a := _interpolate(inside[0], outside[0], cube_points, cube_values)
	var b := _interpolate(inside[0], outside[1], cube_points, cube_values)
	var c := _interpolate(inside[1], outside[0], cube_points, cube_values)
	var d := _interpolate(inside[1], outside[1], cube_points, cube_values)
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
	if normal.length_squared() <= 0.0000001:
		return
	if normal.dot(toward_empty) < 0.0:
		var swap := b
		b = c
		c = swap
		normal = -normal
	normal = normal.normalized()
	positions.append_array(PackedVector3Array([a, b, c]))
	normals.append_array(PackedVector3Array([normal, normal, normal]))


static func _index(x: int, y: int, z: int, size_x: int, size_z: int) -> int:
	return (y * size_z + z) * size_x + x
