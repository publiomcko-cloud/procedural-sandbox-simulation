class_name ProceduralRockMeshAdapter
extends RefCounted

## Converts the data-only stacked_spheres_v1 recipe output into one bounded low-poly mesh.
const LONGITUDE_SEGMENTS := 10
const LATITUDE_SEGMENTS := 6
const MAX_LOBES := 32


static func build_mesh(lobes: Array) -> Dictionary:
	if lobes.is_empty() or lobes.size() > MAX_LOBES:
		return _failure("invalid_lobe_count")
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for lobe_value in lobes:
		if not lobe_value is Dictionary or not lobe_value.get("center_mm") is Vector3i:
			return _failure("invalid_lobe_record")
		var center_mm: Vector3i = lobe_value["center_mm"]
		var radius_mm: int = int(lobe_value.get("radius_mm", 0))
		if radius_mm < 50 or radius_mm > 5000:
			return _failure("invalid_lobe_radius")
		var center := Vector3(center_mm) / 1000.0
		var radius := float(radius_mm) / 1000.0
		for latitude in range(LATITUDE_SEGMENTS):
			var theta0 := PI * float(latitude) / float(LATITUDE_SEGMENTS)
			var theta1 := PI * float(latitude + 1) / float(LATITUDE_SEGMENTS)
			for longitude in range(LONGITUDE_SEGMENTS):
				var phi0 := TAU * float(longitude) / float(LONGITUDE_SEGMENTS)
				var phi1 := TAU * float(longitude + 1) / float(LONGITUDE_SEGMENTS)
				var a := _sphere_direction(theta0, phi0)
				var b := _sphere_direction(theta1, phi0)
				var c := _sphere_direction(theta0, phi1)
				var d := _sphere_direction(theta1, phi1)
				if latitude == 0:
					_add_triangle(surface, center, radius, c, d, b)
				elif latitude == LATITUDE_SEGMENTS - 1:
					_add_triangle(surface, center, radius, a, c, b)
				else:
					_add_triangle(surface, center, radius, a, c, b)
					_add_triangle(surface, center, radius, c, d, b)
	var mesh := surface.commit()
	if mesh == null or mesh.get_surface_count() != 1:
		return _failure("mesh_commit_failed")
	return {"ok": true, "mesh": mesh, "vertex_count": _triangle_vertex_count(lobes.size())}


static func _sphere_direction(theta: float, phi: float) -> Vector3:
	var sin_theta := sin(theta)
	return Vector3(sin_theta * cos(phi), cos(theta), sin_theta * sin(phi))


static func _add_triangle(surface: SurfaceTool, center: Vector3, radius: float, first: Vector3, second: Vector3, third: Vector3) -> void:
	for direction in [first, second, third]:
		surface.set_normal(direction.normalized())
		surface.add_vertex(center + direction * radius)


static func _triangle_vertex_count(lobe_count: int) -> int:
	return lobe_count * LONGITUDE_SEGMENTS * (LATITUDE_SEGMENTS - 1) * 6


static func _failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
