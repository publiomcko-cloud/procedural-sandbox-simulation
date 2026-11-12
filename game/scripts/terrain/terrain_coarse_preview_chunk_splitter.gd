class_name TerrainCoarsePreviewChunkSplitter
extends RefCounted

## Derived visualization only. Split the same 96 preview triangles into
## independent chunk patches via planar clipping; do not re-sample the world.
const Grid := preload("res://scripts/terrain/terrain_chunk_grid.gd")


static func split(cpu_data: Dictionary) -> Dictionary:
	var output: Dictionary = {}
	if not cpu_data.get("valid", false):
		return output
	var points: PackedVector3Array = cpu_data.get("positions", PackedVector3Array())
	var normals: PackedVector3Array = cpu_data.get("normals", PackedVector3Array())
	if points.size() != normals.size() or points.size() % 3 != 0:
		return output
	for coordinate in Grid.all_coordinates():
		var origin := Grid.origin_for(coordinate)
		var size := Grid.size_for(coordinate)
		var min_x := origin.x
		var max_x := origin.x + size.x
		var min_z := origin.z
		var max_z := origin.z + size.z
		var clipped_positions := PackedVector3Array()
		var clipped_normals := PackedVector3Array()
		for i in range(0, points.size(), 3):
			var a := points[i]
			var b := points[i + 1]
			var c := points[i + 2]
			if maxf(a.x, maxf(b.x, c.x)) <= min_x \
			or minf(a.x, minf(b.x, c.x)) >= max_x \
			or maxf(a.z, maxf(b.z, c.z)) <= min_z \
			or minf(a.z, minf(b.z, c.z)) >= max_z:
				continue
			var polygon: Array[Vector3] = [a, b, c]
			polygon = _clip(polygon, 0, min_x, true)
			polygon = _clip(polygon, 0, max_x, false)
			polygon = _clip(polygon, 2, min_z, true)
			polygon = _clip(polygon, 2, max_z, false)
			if polygon.size() < 3:
				continue
			for k in range(1, polygon.size() - 1):
				var p0 := polygon[0]
				var p1 := polygon[k]
				var p2 := polygon[k + 1]
				if (p1 - p0).cross(p2 - p0).length_squared() <= 0.000000000001:
					continue
				for point in [p0, p1, p2]:
					clipped_positions.append(point)
					clipped_normals.append(normals[i])
		output[coordinate] = {
			"valid": true,
			"positions": clipped_positions,
			"normals": clipped_normals,
			"vertex_count": clipped_positions.size(),
			"triangle_count": clipped_positions.size() / 3,
		}
	return output


static func _clip(polygon: Array[Vector3], axis: int, boundary: float, minimum: bool) -> Array[Vector3]:
	var out: Array[Vector3] = []
	if polygon.is_empty():
		return out
	var previous: Vector3 = polygon[-1]
	var previous_inside := previous[axis] >= boundary if minimum else previous[axis] <= boundary
	for current in polygon:
		var inside := current[axis] >= boundary if minimum else current[axis] <= boundary
		if inside != previous_inside:
			var delta := current[axis] - previous[axis]
			if absf(delta) > 0.000000000001:
				var portion := clampf((boundary - previous[axis]) / delta, 0.0, 1.0)
				out.append(previous.lerp(current, portion))
		if inside:
			out.append(current)
		previous = current
		previous_inside = inside
	return out
