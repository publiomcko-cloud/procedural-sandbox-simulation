extends SceneTree

const Mesher := preload("res://scripts/terrain/marching_tetrahedra.gd")
const Grid := preload("res://scripts/terrain/terrain_chunk_grid.gd")
const WorldState := preload("res://scripts/terrain/terrain_world_state.gd")
const BrushState := preload("res://scripts/terrain/sdf_brush_edit_state.gd")

var assertions := 0
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_partition_and_ids()
	_test_full_mesh_equivalence()
	_test_shared_boundaries()
	_test_dirty_selection()
	_test_world_state_ordering()
	_run_comparable_benchmarks()
	if failures == 0:
		print("TERRAIN_CHUNK_PASS: assertions=%d failures=0" % assertions)
	else:
		push_error("TERRAIN_CHUNK_FAIL: assertions=%d failures=%d" % [assertions, failures])
	quit(0 if failures == 0 else 1)


func _test_partition_and_ids() -> void:
	var coordinates := Grid.all_coordinates()
	_check(coordinates.size() == 16, "fixed region contains sixteen mesh chunks")
	var ids: Array[String] = []
	var covered_cells := 0
	for coordinate in coordinates:
		var bounds: Vector4i = Grid.cell_bounds(coordinate)
		covered_cells += (bounds.y - bounds.x) * (bounds.w - bounds.z)
		var id: String = Grid.stable_id(Vector2i(3, -2), coordinate)
		_check(not ids.has(id), "stable chunk IDs are unique")
		ids.append(id)
		_check(id == Grid.stable_id(Vector2i(3, -2), coordinate), "stable chunk ID is deterministic")
		_check(Grid.is_valid_coordinate(coordinate), "enumerated coordinate is valid")
		var origin: Vector3 = Grid.origin_for(coordinate)
		var size: Vector3 = Grid.size_for(coordinate)
		_check(size.x > 0.0 and size.z > 0.0, "chunk has bounded horizontal extent")
		_check(origin.x >= Grid.MIN_BOUND.x and origin.z >= Grid.MIN_BOUND.z, "chunk origin is within region")
	_check(covered_cells == Grid.CELL_COUNT_X * Grid.CELL_COUNT_Z, "half-open chunk cell ranges cover every horizontal cell exactly once")
	_check(not Grid.is_valid_coordinate(Vector2i(-1, 0)), "negative chunk coordinate is rejected")
	_check(not Grid.is_valid_coordinate(Vector2i(4, 0)), "out-of-range chunk coordinate is rejected")


func _test_full_mesh_equivalence() -> void:
	var full: Dictionary = Mesher.build_mesh(424242, Vector2i.ZERO)
	var full_signatures := _mesh_signatures(full["mesh"], Vector3.ZERO)
	var chunk_signatures: Array[String] = []
	var chunk_triangles := 0
	var chunk_samples := 0
	for coordinate in Grid.all_coordinates():
		var result: Dictionary = Mesher.build_chunk_mesh(424242, Vector2i.ZERO, coordinate)
		_check(result["valid"], "valid chunk coordinate builds successfully")
		var origin: Vector3 = Grid.origin_for(coordinate)
		chunk_signatures.append_array(_mesh_signatures(result["mesh"], origin))
		chunk_triangles += result["triangle_count"]
		chunk_samples += result["sample_count"]
	_check(full["triangle_count"] == chunk_triangles, "chunk union preserves full-mesh triangle count")
	_check(full_signatures == _sorted_signatures(chunk_signatures), "chunk union preserves exact quantized triangles")
	_check(chunk_samples < full["sample_count"] * 1.5, "chunk meshes sample a bounded shared-plane halo without full-region duplication")
	var invalid: Dictionary = Mesher.build_chunk_mesh(424242, Vector2i.ZERO, Vector2i(4, 0))
	_check(not invalid["valid"] and invalid["triangle_count"] == 0, "invalid chunk build fails closed with an empty mesh")
	print("CHUNK_EQUIVALENCE: full_triangles=%d chunk_triangles=%d full_samples=%d chunk_samples=%d" % [full["triangle_count"], chunk_triangles, full["sample_count"], chunk_samples])


func _test_shared_boundaries() -> void:
	var chunk_data: Dictionary = {}
	for coordinate in Grid.all_coordinates():
		chunk_data[coordinate] = Mesher.build_chunk_mesh(424242, Vector2i.ZERO, coordinate)["mesh"]
	var seam_pairs := 0
	for z in range(Grid.CHUNK_COUNT_Z):
		for x in range(Grid.CHUNK_COUNT_X - 1):
			_check_seam(chunk_data, Vector2i(x, z), Vector2i(x + 1, z), true)
			seam_pairs += 1
	for z in range(Grid.CHUNK_COUNT_Z - 1):
		for x in range(Grid.CHUNK_COUNT_X):
			_check_seam(chunk_data, Vector2i(x, z), Vector2i(x, z + 1), false)
			seam_pairs += 1
	_check(seam_pairs == 24, "all horizontal and vertical adjacent chunk seams are checked")


func _check_seam(chunk_data: Dictionary, left_coord: Vector2i, right_coord: Vector2i, x_axis: bool) -> void:
	var left_mesh: ArrayMesh = chunk_data[left_coord]
	var right_mesh: ArrayMesh = chunk_data[right_coord]
	var left_origin: Vector3 = Grid.origin_for(left_coord)
	var right_origin: Vector3 = Grid.origin_for(right_coord)
	var boundary_x := Grid.origin_for(right_coord).x if x_axis else 0.0
	var boundary_z := Grid.origin_for(right_coord).z if not x_axis else 0.0
	var left_map := _boundary_vertex_normals(left_mesh, left_origin, x_axis, boundary_x, boundary_z)
	var right_map := _boundary_vertex_normals(right_mesh, right_origin, x_axis, boundary_x, boundary_z)
	_check(left_map.size() > 0 and right_map.size() > 0, "adjacent chunks expose surface samples at shared boundary")
	_check(_boundary_sets_match(left_map, right_map), "adjacent chunks have matching boundary surface vertices within float32 tolerance")


func _boundary_vertex_normals(mesh: ArrayMesh, origin: Vector3, x_axis: bool, boundary_x: float, boundary_z: float) -> Dictionary:
	var result: Dictionary = {}
	if mesh.get_surface_count() == 0:
		return result
	var arrays: Array = mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	for index in range(vertices.size()):
		var point: Vector3 = vertices[index] + origin
		var on_boundary := absf(point.x - boundary_x) < 0.00001 if x_axis else absf(point.z - boundary_z) < 0.00001
		if not on_boundary:
			continue
		var key := _point_key(point)
		result[key] = normals[index]
	return result


func _boundary_sets_match(left: Dictionary, right: Dictionary) -> bool:
	for left_key in left:
		var left_point := _key_point(left_key)
		var nearest_key := ""
		var nearest_distance := INF
		for right_key in right:
			var distance := left_point.distance_to(_key_point(right_key))
			if distance < nearest_distance:
				nearest_distance = distance
				nearest_key = right_key
		if nearest_distance > 0.0001:
			print("SEAM_VERTEX_GAP: left=%s nearest=%s distance=%.8f" % [left_key, nearest_key, nearest_distance])
			return false
		var left_normal: Vector3 = left[left_key]
		var right_normal: Vector3 = right[nearest_key]
		if left_normal.dot(right_normal) <= 0.999:
			print("SEAM_NORMAL_GAP: left=%s right=%s dot=%.8f" % [left_key, nearest_key, left_normal.dot(right_normal)])
			return false
	for right_key in right:
		var right_point := _key_point(right_key)
		var found := false
		for left_key in left:
			if right_point.distance_to(_key_point(left_key)) <= 0.0001:
				found = true
				break
		if not found:
			return false
	return true


func _key_point(key: String) -> Vector3:
	var components := key.split(",")
	return Vector3(components[0].to_float(), components[1].to_float(), components[2].to_float())


func _test_dirty_selection() -> void:
	var inside := Grid.affected_chunks_for_sphere(Vector3(0.0, 0.0, 0.0), 0.45)
	var border := Grid.affected_chunks_for_sphere(Vector3(8.0, 0.0, 0.0), 0.45)
	var corner := Grid.affected_chunks_for_sphere(Vector3(8.0, 0.0, 6.0), 0.45)
	_check(inside.size() == 1, "interior edit dirties one chunk")
	_check(border.size() == 2, "exact chunk-border edit dirties both neighbors")
	_check(corner.size() == 4, "exact chunk-corner edit dirties all four neighbors")
	_check(inside == Grid.affected_chunks_for_sphere(Vector3(0.0, 0.0, 0.0), 0.45), "dirty chunk selection is deterministic")
	_check(Grid.affected_chunks_for_sphere(Vector3(0.0, 20.0, 0.0), 1.0).is_empty(), "edit outside the vertical mesh domain dirties no chunk")
	_check(Grid.affected_chunks_for_sphere(Vector3.ZERO, NAN).is_empty(), "non-finite radius dirties no chunk")


func _test_world_state_ordering() -> void:
	var state := WorldState.new(424242, Vector2i(2, 5))
	_check(state.generator_version > 0, "world state records generator version")
	_check(state.chunk_id(Vector2i(1, 2)) == "region:2,5/chunk:1,2", "chunk identity is stable across scene node lifetime")
	_check(state.apply_sphere(BrushState.Mode.CARVE, Vector3(8.0, 4.0, 6.0), 0.75), "world state accepts a bounded operation")
	_check(state.brush_edits.revision == 1, "accepted operation advances canonical revision")
	_check(state.brush_edits.get_operations_snapshot()[0]["sequence"] == 0, "first operation receives sequence zero")
	_check(state.apply_sphere(BrushState.Mode.FILL, Vector3(8.0, 4.0, 6.0), 0.75), "second ordered operation is accepted")
	_check(state.brush_edits.get_operations_snapshot()[1]["sequence"] == 1, "second operation receives the next sequence")
	state.clear_edits()
	_check(state.brush_edits.revision == 3 and state.brush_edits.get_edit_count() == 0, "clearing edits advances revision and empties the operation list")
	_check(state.apply_sphere(BrushState.Mode.CARVE, Vector3(8.0, 4.0, 6.0), 0.75), "operation can be added after reset")
	_check(state.brush_edits.get_operations_snapshot()[0]["sequence"] == 2, "operation sequence remains monotonic after reset")
	state.clear_edits()
	var empty_revision: int = state.brush_edits.revision
	state.clear_edits()
	_check(state.brush_edits.revision == empty_revision, "clearing an already empty state is a no-op")


func _run_comparable_benchmarks() -> void:
	var patterns := {
		"interior": Vector3(1.0, 0.0, 0.0),
		"border": Vector3(8.0, 0.0, 0.0),
		"corner": Vector3(8.0, 0.0, 6.0),
	}
	# One warm-up per implementation; alternate measurement order to reduce order bias.
	for pattern_name in patterns:
		var center: Vector3 = patterns[pattern_name]
		var state := WorldState.new()
		_check(state.apply_sphere(BrushState.Mode.CARVE, center, 0.75), "benchmark case applies the same canonical edit before both measurements")
		var dirty: Array[Vector2i] = Grid.affected_chunks_for_sphere(center, 0.75)
		Mesher.build_mesh(state.world_seed, state.region_key, false, state.brush_edits)
		Mesher.build_chunk_mesh(state.world_seed, state.region_key, dirty[0], false, state.brush_edits)
		var full_times: Array[float] = []
		var local_times: Array[float] = []
		for repetition in range(7):
			if repetition % 2 == 0:
				full_times.append(_time_full(state))
				local_times.append(_time_local(state, dirty))
			else:
				local_times.append(_time_local(state, dirty))
				full_times.append(_time_full(state))
		var full_stats := _median_spread(full_times)
		var local_stats := _median_spread(local_times)
		print("TERRAIN_CHUNK_BENCH: pattern=%s affected_chunks=%d repetitions=7 full_median_ms=%.3f full_spread_ms=%.3f local_median_ms=%.3f local_spread_ms=%.3f" % [
			pattern_name, dirty.size(), full_stats.x, full_stats.y, local_stats.x, local_stats.y,
		])
		_check(dirty.size() > 0 and dirty.size() < Grid.CHUNK_COUNT_X * Grid.CHUNK_COUNT_Z, "benchmark local case rebuilds a strict subset of chunks")
		_check(full_stats.x > 0.0 and local_stats.x > 0.0, "benchmark records comparable positive elapsed times")


func _time_full(state: RefCounted) -> float:
	var started := Time.get_ticks_usec()
	var result: Dictionary = Mesher.build_mesh(state.world_seed, state.region_key, false, state.brush_edits)
	return float(Time.get_ticks_usec() - started) / 1000.0 if result["valid"] else 0.0


func _time_local(state: RefCounted, dirty: Array[Vector2i]) -> float:
	var started := Time.get_ticks_usec()
	for coordinate in dirty:
		Mesher.build_chunk_mesh(state.world_seed, state.region_key, coordinate, false, state.brush_edits)
	return float(Time.get_ticks_usec() - started) / 1000.0


func _median_spread(values: Array[float]) -> Vector2:
	var sorted := values.duplicate()
	sorted.sort()
	return Vector2(sorted[sorted.size() / 2], sorted[-1] - sorted[0])


func _mesh_signatures(mesh: ArrayMesh, origin: Vector3) -> Array[String]:
	var result: Array[String] = []
	if mesh.get_surface_count() == 0:
		return result
	var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for index in range(0, vertices.size(), 3):
		var triangle: Array[String] = []
		for offset in range(3):
			triangle.append(_point_key(vertices[index + offset] + origin))
		triangle.sort()
		result.append("%s|%s|%s" % [triangle[0], triangle[1], triangle[2]])
	return _sorted_signatures(result)


func _point_key(point: Vector3) -> String:
	# ArrayMesh stores vertex attributes at float32 precision. Four decimals
	# compare geometry across local-origin subtraction without hiding visible gaps.
	return "%.4f,%.4f,%.4f" % [point.x, point.y, point.z]


func _sorted_signatures(values: Array[String]) -> Array[String]:
	var result := values.duplicate()
	result.sort()
	return result


func _sorted_keys(values: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for key in values:
		result.append(key)
	result.sort()
	return result


func _check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error("ASSERTION FAILED: " + label)
