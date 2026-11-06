class_name ProceduralRockMeshAdapter
extends RefCounted

## Renderer adapter for the shared deterministic geological shape core.
##
## All shape construction lives in ProceduralRockShapeDescriptor so terrain
## effects and visual geometry cannot drift into separate algorithms.
const ShapeDescriptor := preload("res://scripts/objects/procedural_rock_shape_descriptor.gd")

const GEOMETRY_VERSION := ShapeDescriptor.GEOMETRY_VERSION
const ALGORITHM := ShapeDescriptor.ALGORITHM
const MIN_TRIANGLES := ShapeDescriptor.MIN_TRIANGLES
const MAX_TRIANGLES := ShapeDescriptor.MAX_TRIANGLES
const MIN_AREA_SQUARED := ShapeDescriptor.MIN_AREA_SQUARED


static func build_mesh(recipe: Dictionary, seeds: Dictionary) -> Dictionary:
	var cpu_data := build_cpu_data(recipe, seeds)
	if not cpu_data.get("ok", false):
		return cpu_data
	return mesh_from_cpu_data(cpu_data)


## Pure geometry path suitable for WorkerThreadPool. No Resource,
## RenderingServer or SceneTree object is created here.
static func build_cpu_data(recipe: Dictionary, seeds: Dictionary) -> Dictionary:
	var geometry := ShapeDescriptor.build_geometry_data(recipe, seeds)
	if not geometry.get("ok", false):
		return geometry
	var vertices: Array[Vector3] = geometry["points"]
	var triangles: Array[Vector3i] = geometry["triangles"]
	var center: Vector3 = geometry["orientation_center"]
	if triangles.size() < MIN_TRIANGLES or triangles.size() > MAX_TRIANGLES:
		return _failure("triangle_budget_exceeded")

	var output_vertices := PackedVector3Array()
	var output_normals := PackedVector3Array()
	var signed_volume := 0.0
	var surface_area := 0.0
	for triangle in triangles:
		var a: Vector3 = vertices[triangle.x]
		var b: Vector3 = vertices[triangle.y]
		var c: Vector3 = vertices[triangle.z]
		var cross := (b - a).cross(c - a)
		if not cross.is_finite() or cross.length_squared() <= MIN_AREA_SQUARED:
			return _failure("degenerate_triangle")
		var face_center := (a + b + c) / 3.0
		if cross.dot(face_center - center) < 0.0:
			var temporary := b
			b = c
			c = temporary
			cross = (b - a).cross(c - a)
		var normal := cross.normalized()
		if not normal.is_finite() or normal.length_squared() < 0.99:
			return _failure("invalid_face_normal")
		output_vertices.append_array(PackedVector3Array([a, b, c]))
		output_normals.append_array(PackedVector3Array([normal, normal, normal]))
		signed_volume += a.dot(b.cross(c)) / 6.0
		surface_area += cross.length() * 0.5

	if not is_finite(signed_volume) or signed_volume <= 1.0e-8 		or not is_finite(surface_area) or surface_area <= 0.0:
		return _failure("invalid_shell_measure")
	var bounds := _measure_bounds(vertices)
	return {
		"ok": true,
		"positions": output_vertices,
		"normals": output_normals,
		"triangle_count": triangles.size(),
		"vertex_count": output_vertices.size(),
		"unique_vertex_count": vertices.size(),
		"surface_area_m2": surface_area,
		"volume_m3": signed_volume,
		"bounds_min": bounds["min"],
		"bounds_max": bounds["max"],
		"profile": recipe["profile"],
		"geometry_version": GEOMETRY_VERSION,
		"algorithm": ALGORITHM,
		"geometry_seeds": seeds.duplicate(true),
	}


## Main-thread resource commit for worker-produced geometry data.
static func mesh_from_cpu_data(cpu_data: Dictionary) -> Dictionary:
	if not cpu_data.get("ok", false):
		return cpu_data
	var positions: PackedVector3Array = cpu_data.get("positions", PackedVector3Array())
	var normals: PackedVector3Array = cpu_data.get("normals", PackedVector3Array())
	if positions.is_empty() or positions.size() != normals.size() or positions.size() % 3 != 0:
		return _failure("mesh_cpu_data_invalid")
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = positions
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if mesh.get_surface_count() != 1:
		return _failure("mesh_commit_failed")
	var result: Dictionary = cpu_data.duplicate(false)
	result["mesh"] = mesh
	result.erase("positions")
	result.erase("normals")
	return result


static func _measure_bounds(points: Array[Vector3]) -> Dictionary:
	var minimum := Vector3(INF, INF, INF)
	var maximum := Vector3(-INF, -INF, -INF)
	for point in points:
		minimum = minimum.min(point)
		maximum = maximum.max(point)
	return {"min": minimum, "max": maximum}


static func _failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
