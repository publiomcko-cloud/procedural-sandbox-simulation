extends SceneTree

const Spatial := preload("res://scripts/terrain/terrain_spatial_ownership.gd")
const ChunkGrid := preload("res://scripts/terrain/terrain_chunk_grid.gd")
const Mesher := preload("res://scripts/terrain/marching_tetrahedra.gd")
const Field := preload("res://scripts/terrain/sdf_world.gd")
const Picker := preload("res://scripts/terrain/terrain_brush_picker.gd")
const BrushState := preload("res://scripts/terrain/sdf_brush_edit_state.gd")

const SEED := 424242
const MIN_WORLD_CELL := Vector2i(-Spatial.CELLS_PER_REGION_X, -Spatial.CELLS_PER_REGION_Z)
const WORLD_CELL_COUNT := Vector2i(Spatial.CELLS_PER_REGION_X * 3, Spatial.CELLS_PER_REGION_Z * 3)

var assertions := 0
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_region_transforms_and_negative_ownership()
	_test_cell_and_chunk_ownership()
	_test_region_and_corner_continuity()
	_test_global_cut_plane()
	_test_three_by_three_mesh_union_and_seams()
	_test_cross_region_edit_mesh_equivalence()
	_test_near_boundary_normal_dependencies()
	await _test_dynamic_region_streaming_and_focused_edits()
	await _test_edit_while_neighbor_is_loading()
	if failures == 0:
		print("TERRAIN_MULTI_REGION_PASS: assertions=%d failures=0" % assertions)
	else:
		push_error("TERRAIN_MULTI_REGION_FAIL: assertions=%d failures=%d" % [assertions, failures])
	quit(0 if failures == 0 else 1)


func _test_region_transforms_and_negative_ownership() -> void:
	_check(Spatial.preview_region_keys().size() == 9, "static preview is exactly nine region keys")
	var cases := [
		{"world": Vector3(-16.0, 2.0, -12.0), "region": Vector2i(-1, -1), "local": Vector3(0.0, 2.0, 0.0)},
		{"world": Vector3(-0.01, 3.0, -0.01), "region": Vector2i(-1, -1), "local": Vector3(15.99, 3.0, 11.99)},
		{"world": Vector3(0.0, 1.0, 0.0), "region": Vector2i(0, 0), "local": Vector3(0.0, 1.0, 0.0)},
		{"world": Vector3(16.0, 4.0, 12.0), "region": Vector2i(1, 1), "local": Vector3(0.0, 4.0, 0.0)},
		{"world": Vector3(31.999, -1.0, 23.999), "region": Vector2i(1, 1), "local": Vector3(15.999, -1.0, 11.999)},
		{"world": Vector3(-32.0, 0.0, -24.0), "region": Vector2i(-2, -2), "local": Vector3(0.0, 0.0, 0.0)},
	]
	for test_case in cases:
		var mapped: Dictionary = Spatial.world_to_region_local(test_case["world"])
		_check(mapped["valid"], "finite world coordinates map to a region")
		_check(mapped["region_key"] == test_case["region"], "world coordinate uses floor-based half-open region ownership")
		_check(mapped["local_position"].is_equal_approx(test_case["local"]), "mapped local coordinate is within its owning region")
		_check(Spatial.region_local_to_world(mapped["region_key"], mapped["local_position"]).is_equal_approx(test_case["world"]), "region transform round-trips exactly within float tolerance")
	var invalid: Dictionary = Spatial.world_to_region_local(Vector3(NAN, 0.0, 0.0))
	_check(not invalid["valid"], "non-finite world coordinate is rejected")
	_check(Spatial.region_key_for_cell(-33, -25) == Vector2i(-2, -2), "negative nonmultiple cell indices use mathematical floor")
	_check(Spatial.region_key_for_cell(-32, -24) == Vector2i(-1, -1), "negative exact border cell belongs to its half-open region")
	_check(Spatial.region_key_for_cell(-1, -1) == Vector2i(-1, -1), "negative last cell remains in the preceding region")
	_check(Spatial.region_key_for_cell(0, 0) == Vector2i.ZERO, "zero cell belongs to center region")
	_check(Spatial.region_key_for_cell(32, 24) == Vector2i(1, 1), "positive border cell belongs to the following region")


func _test_cell_and_chunk_ownership() -> void:
	var ownership: Dictionary = {}
	var enumerated := 0
	for region_key in Spatial.preview_region_keys():
		for chunk_coordinate in ChunkGrid.all_coordinates():
			var bounds: Vector4i = ChunkGrid.cell_bounds(chunk_coordinate)
			for local_z in range(bounds.z, bounds.w):
				for local_x in range(bounds.x, bounds.y):
					var world_cell := Vector2i(region_key.x * Spatial.CELLS_PER_REGION_X + local_x, region_key.y * Spatial.CELLS_PER_REGION_Z + local_z)
					var key := "%d,%d" % [world_cell.x, world_cell.y]
					if ownership.has(key):
						_check(false, "no world lattice cell has two region/chunk owners")
						ownership[key] += 1
					else:
						ownership[key] = 1
					enumerated += 1
					_check(Spatial.owns_world_cell(region_key, chunk_coordinate, world_cell), "enumerated cell maps back to its owning region and chunk")
	_check(enumerated == WORLD_CELL_COUNT.x * WORLD_CELL_COUNT.y, "3x3 region chunks cover exactly the canonical world-cell extent")
	_check(ownership.size() == enumerated, "no chunk cell is duplicated or omitted")
	var all_once := true
	for count in ownership.values():
		all_once = all_once and count == 1
	_check(all_once, "every world-space cell has exactly one render owner")
	_check(Spatial.chunk_for_region_cell(Vector2i(-1, 0)) == Vector2i(-1, -1), "out-of-region local cell has no valid chunk owner")


func _test_region_and_corner_continuity() -> void:
	var boundaries := [
		{"world": Vector3(0.0, 0.0, 6.0), "a": Vector2i(-1, 0), "b": Vector2i(0, 0)},
		{"world": Vector3(16.0, 3.0, 5.5), "a": Vector2i(0, 0), "b": Vector2i(1, 0)},
		{"world": Vector3(8.0, 1.3, 0.0), "a": Vector2i(0, -1), "b": Vector2i(0, 0)},
		{"world": Vector3(8.0, 3.2, 12.0), "a": Vector2i(0, 0), "b": Vector2i(0, 1)},
		{"world": Vector3(-16.0, 1.2, -6.0), "a": Vector2i(-2, -1), "b": Vector2i(-1, -1)},
		{"world": Vector3(-8.0, 2.5, -12.0), "a": Vector2i(-1, -2), "b": Vector2i(-1, -1)},
	]
	for boundary in boundaries:
		for y in [0.25, 1.25, 3.5, 7.0]:
			var world_point: Vector3 = boundary["world"]
			world_point.y = y
			var a_key: Vector2i = boundary["a"]
			var b_key: Vector2i = boundary["b"]
			var a_local := Vector3(world_point.x - float(a_key.x) * Spatial.REGION_SIZE_X, y, world_point.z - float(a_key.y) * Spatial.REGION_SIZE_Z)
			var b_local := Vector3(world_point.x - float(b_key.x) * Spatial.REGION_SIZE_X, y, world_point.z - float(b_key.y) * Spatial.REGION_SIZE_Z)
			var da: float = Field.sample_density(SEED, a_key, a_local)
			var db: float = Field.sample_density(SEED, b_key, b_local)
			_check(absf(da - db) < 0.00001, "versioned SDF is continuous across signed region boundary coordinates")
	var corner_world_points := [Vector3(0.0, 1.1, 0.0), Vector3(16.0, 2.8, 12.0), Vector3(-16.0, 1.4, -12.0)]
	for world_point in corner_world_points:
		var x_side := [floori(world_point.x / Spatial.REGION_SIZE_X) - 1, floori(world_point.x / Spatial.REGION_SIZE_X)]
		var z_side := [floori(world_point.z / Spatial.REGION_SIZE_Z) - 1, floori(world_point.z / Spatial.REGION_SIZE_Z)]
		var reference := NAN
		for rz in z_side:
			for rx in x_side:
				var key := Vector2i(rx, rz)
				var local := Vector3(world_point.x - float(rx) * Spatial.REGION_SIZE_X, world_point.y, world_point.z - float(rz) * Spatial.REGION_SIZE_Z)
				var density: float = Field.sample_density(SEED, key, local)
				if is_nan(reference):
					reference = density
				else:
					_check(absf(density - reference) < 0.00001, "four region samples agree at signed region corner")


func _test_global_cut_plane() -> void:
	var world_points := [Vector3(8.0, 3.0, 5.5), Vector3(8.0, 3.0, 6.0), Vector3(8.0, 3.0, 12.0), Vector3(8.0, 3.0, 18.0)]
	for world_point in world_points:
		var mapped: Dictionary = Spatial.world_to_region_local(world_point)
		var local: Vector3 = mapped["local_position"]
		var region: Vector2i = mapped["region_key"]
		var cut: float = Field.sample_density(SEED, region, local, true)
		var center_local := Vector3(world_point.x, world_point.y, world_point.z)
		var reference: float = Field.sample_density(SEED, Vector2i.ZERO, center_local, true)
		_check(absf(cut - reference) < 0.00001, "visual cave section uses the same global Z plane for every region")
	_check(Field.sample_density(SEED, Vector2i(0, 1), Vector3(8.0, 3.0, 0.0), true) <= -5.999, "global section cuts at world Z=12 inside a positive Z region")
	var negative_region_sample := Field.sample_density(SEED, Vector2i(0, -1), Vector3(8.0, -1.0, 11.9), true)
	var equivalent_world_sample := Field.sample_density(SEED, Vector2i.ZERO, Vector3(8.0, -1.0, -0.1), true)
	_check(is_equal_approx(negative_region_sample, equivalent_world_sample), "negative Z region uses the same global section plane as equivalent world coordinates")


func _test_three_by_three_mesh_union_and_seams() -> void:
	var full: Dictionary = Mesher.build_world_reference_mesh(SEED, MIN_WORLD_CELL, WORLD_CELL_COUNT)
	_check(full["valid"], "monolithic world-space reference mesh builds for the 3x3 extent")
	var full_signatures := _mesh_signatures(full["mesh"], Vector3.ZERO)
	var chunk_signatures: Array[String] = []
	var chunk_triangles := 0
	var normal_samples := 0
	var outward_samples := 0
	var winding_samples := 0
	var correctly_wound_samples := 0
	var chunk_data: Dictionary = {}
	for region_key in Spatial.preview_region_keys():
		var region_world_origin: Vector3 = Spatial.region_origin_world(region_key)
		for chunk_coordinate in ChunkGrid.all_coordinates():
			var result: Dictionary = Mesher.build_chunk_mesh(SEED, region_key, chunk_coordinate)
			var offset := region_world_origin + ChunkGrid.origin_for(chunk_coordinate)
			var region_local_chunk_origin: Vector3 = ChunkGrid.origin_for(chunk_coordinate)
			chunk_data[_global_chunk_coordinate(region_key, chunk_coordinate)] = {"mesh": result["mesh"], "offset": offset}
			chunk_signatures.append_array(_mesh_signatures(result["mesh"], offset))
			chunk_triangles += result["triangle_count"]
			var mesh: ArrayMesh = result["mesh"]
			if mesh.get_surface_count() > 0:
				var arrays: Array = mesh.surface_get_arrays(0)
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
				var stride := maxi(3, int(vertices.size() / 256 / 3) * 3)
				for vertex_index in range(0, vertices.size(), stride):
					var local_point: Vector3 = vertices[vertex_index]
					var normal: Vector3 = normals[vertex_index].normalized()
					var region_local_point := local_point + region_local_chunk_origin
					var density_out: float = Field.sample_density(SEED, region_key, region_local_point + normal * 0.12)
					var density_in: float = Field.sample_density(SEED, region_key, region_local_point - normal * 0.12)
					if density_out < density_in:
						outward_samples += 1
					normal_samples += 1
				var triangle_start: int = 0
				if triangle_start + 2 < vertices.size():
					var face_normal := (vertices[triangle_start + 1] - vertices[triangle_start]).cross(vertices[triangle_start + 2] - vertices[triangle_start])
					var mean_normal: Vector3 = (normals[triangle_start] + normals[triangle_start + 1] + normals[triangle_start + 2]).normalized()
					if face_normal.dot(mean_normal) > 0.0:
						correctly_wound_samples += 1
					winding_samples += 1
	_check(full["triangle_count"] == chunk_triangles, "3x3 chunk union has the same triangle count as monolithic world mesh")
	var sorted_chunk_signatures := _sorted_signatures(chunk_signatures)
	if full_signatures != sorted_chunk_signatures:
		var full_counts := _signature_counts(full_signatures)
		var chunk_counts := _signature_counts(sorted_chunk_signatures)
		var full_only: Array[String] = []
		var chunk_only: Array[String] = []
		for signature in full_counts:
			if int(full_counts[signature]) != int(chunk_counts.get(signature, 0)) and full_only.size() < 3:
				full_only.append("%s x%d/%d" % [signature, full_counts[signature], chunk_counts.get(signature, 0)])
		for signature in chunk_counts:
			if int(chunk_counts[signature]) != int(full_counts.get(signature, 0)) and chunk_only.size() < 3:
				chunk_only.append("%s x%d/%d" % [signature, chunk_counts[signature], full_counts.get(signature, 0)])
		print("MULTIREGION_SIGNATURE_DIFF: full_only=%s chunk_only=%s" % [full_only, chunk_only])
	_check(full_signatures == sorted_chunk_signatures, "3x3 chunk union matches monolithic world triangles within float32 quantization")
	_check(chunk_data.size() == 144, "3x3 region mesh map contains all 144 stable chunk slots")
	_check(normal_samples > 0 and outward_samples >= int(normal_samples * 0.9), "sampled normals point from solid toward empty across the full region grid")
	_check(winding_samples > 0 and correctly_wound_samples == winding_samples, "sampled chunk triangles preserve outward winding")
	var seam_count := 0
	for z in range(12):
		for x in range(11):
			_check_seam(chunk_data, Vector2i(x, z), Vector2i(x + 1, z), true)
			seam_count += 1
	for z in range(11):
		for x in range(12):
			_check_seam(chunk_data, Vector2i(x, z), Vector2i(x, z + 1), false)
			seam_count += 1
	_check(seam_count == 264, "all intra-chunk and cross-region seams in the 3x3 mesh are verified")
	print("MULTIREGION_EQUIVALENCE: regions=9 chunks=144 full_triangles=%d chunk_triangles=%d reference_samples=%d" % [full["triangle_count"], chunk_triangles, full["sample_count"]])


func _test_cross_region_edit_mesh_equivalence() -> void:
	var edits := BrushState.new(SEED, Field.GENERATOR_VERSION)
	_check(edits.add_sphere(BrushState.Mode.CARVE, Vector3(16.0, 4.0, 6.0), 1.25), "mesh comparison accepts a canonical edit centered on the shared region seam")
	_check(edits.add_sphere(BrushState.Mode.FILL, Vector3(16.25, 4.0, 6.0), 1.0), "mesh comparison preserves interleaved fill ordering on the same seam")
	var full := Mesher.build_world_reference_mesh(SEED, Vector2i.ZERO, Vector2i(64, 24), false, edits)
	var full_positions := _mesh_signatures(full["mesh"], Vector3.ZERO)
	var full_oriented := _oriented_mesh_signatures(full["mesh"], Vector3.ZERO)
	var full_outward := _edited_normals_outward(full["mesh"], Vector3.ZERO, Vector2i.ZERO, false, edits)
	var streamed_positions: Array[String] = []
	var streamed_oriented: Array[String] = []
	var streamed_outward := Vector2i.ZERO
	var edited_chunks: Dictionary = {}
	var streamed_triangles := 0
	for region_key in [Vector2i.ZERO, Vector2i(1, 0)]:
		var region_origin: Vector3 = Spatial.region_origin_world(region_key)
		for coordinate in ChunkGrid.all_coordinates():
			var chunk := Mesher.build_chunk_mesh(SEED, region_key, coordinate, false, edits)
			var offset := region_origin + ChunkGrid.origin_for(coordinate)
			streamed_positions.append_array(_mesh_signatures(chunk["mesh"], offset))
			streamed_oriented.append_array(_oriented_mesh_signatures(chunk["mesh"], offset))
			var outward: Vector2i = _edited_normals_outward(chunk["mesh"], offset, region_key, false, edits)
			streamed_outward += outward
			edited_chunks[_global_chunk_coordinate(region_key, coordinate)] = {"mesh": chunk["mesh"], "offset": offset}
			streamed_triangles += chunk["triangle_count"]
	_check(full["valid"] and full["triangle_count"] == streamed_triangles, "edited 2-region chunk union preserves monolithic triangle count")
	_check(full_positions == _sorted_signatures(streamed_positions), "edited global SDF chunk union matches monolithic triangle position multisets")
	_check(full_oriented == _sorted_signatures(streamed_oriented), "edited global SDF preserves triangle winding across the region seam")
	_check(full_outward.y > 0 and full_outward.x >= int(ceil(float(full_outward.y) * 0.9)), "edited monolithic SDF normals point toward empty space")
	_check(streamed_outward.y > 0 and streamed_outward.x >= int(ceil(float(streamed_outward.y) * 0.9)), "edited chunk SDF normals point toward empty space")
	for z in range(ChunkGrid.CHUNK_COUNT_Z):
		_check_edit_seam_if_present(edited_chunks, Vector2i(7, z + 4), Vector2i(8, z + 4), true)
	var left: float = edits.sample_density(SEED, Vector2i.ZERO, Vector3(16.0, 4.0, 6.0))
	var right: float = edits.sample_density(SEED, Vector2i(1, 0), Vector3(0.0, 4.0, 6.0))
	_check(is_equal_approx(left, right), "interleaved global commands produce identical shared seam samples")
	var cut_full := Mesher.build_world_reference_mesh(SEED, Vector2i.ZERO, Vector2i(64, 24), true, edits)
	var cut_positions := _mesh_signatures(cut_full["mesh"], Vector3.ZERO)
	var cut_oriented := _oriented_mesh_signatures(cut_full["mesh"], Vector3.ZERO)
	var cut_outward := _edited_normals_outward(cut_full["mesh"], Vector3.ZERO, Vector2i.ZERO, true, edits)
	var cut_chunk_positions: Array[String] = []
	var cut_chunk_oriented: Array[String] = []
	var cut_chunk_outward := Vector2i.ZERO
	var cut_chunks: Dictionary = {}
	for region_key in [Vector2i.ZERO, Vector2i(1, 0)]:
		var region_origin: Vector3 = Spatial.region_origin_world(region_key)
		for coordinate in ChunkGrid.all_coordinates():
			var cut_chunk := Mesher.build_chunk_mesh(SEED, region_key, coordinate, true, edits)
			var offset := region_origin + ChunkGrid.origin_for(coordinate)
			cut_chunk_positions.append_array(_mesh_signatures(cut_chunk["mesh"], offset))
			cut_chunk_oriented.append_array(_oriented_mesh_signatures(cut_chunk["mesh"], offset))
			cut_chunk_outward += _edited_normals_outward(cut_chunk["mesh"], offset, region_key, true, edits)
			cut_chunks[_global_chunk_coordinate(region_key, coordinate)] = {"mesh": cut_chunk["mesh"], "offset": offset}
	_check(cut_positions == _sorted_signatures(cut_chunk_positions) and cut_oriented == _sorted_signatures(cut_chunk_oriented), "global cut-plane mode preserves edited triangle positions and winding across region chunks")
	_check(cut_outward.y > 0 and cut_outward.x >= int(ceil(float(cut_outward.y) * 0.9)), "global cut-plane monolithic normals point toward empty space")
	_check(cut_chunk_outward.y > 0 and cut_chunk_outward.x >= int(ceil(float(cut_chunk_outward.y) * 0.9)), "global cut-plane chunk normals point toward empty space")
	_check_cut_seam_samples(edits)
	print("GLOBAL_EDIT_EQUIVALENCE: regions=2 operations=%d full_triangles=%d chunk_triangles=%d" % [edits.get_edit_count(), full["triangle_count"], streamed_triangles])


func _test_near_boundary_normal_dependencies() -> void:
	var seam_z := 5.0
	var seam_y := _surface_height(16.0, seam_z)
	_check(is_finite(seam_y), "deterministic near-boundary brush point uses the actual generated terrain surface height")
	if not is_finite(seam_y):
		return
	var baseline_left := _region_boundary_normal_map(Vector2i.ZERO, true)
	var baseline_right := _region_boundary_normal_map(Vector2i(1, 0), false)
	_check(not baseline_left.is_empty() and _normal_maps_match(baseline_left, baseline_right), "unmodified shared region seam has matching vertex normals")
	var edits := BrushState.new(SEED, Field.GENERATOR_VERSION)
	var center := Vector3(15.0, seam_y, seam_z)
	_check(center.x + 0.9 < Spatial.REGION_SIZE_X, "positive X test brush remains wholly inside canonical support region")
	_check(edits.add_sphere(BrushState.Mode.CARVE, center, 0.9), "positive near-boundary brush is admitted for actual terrain geometry")
	var operation: Dictionary = edits.get_operations_snapshot()[0]
	_check(operation["support_regions"] == [Vector2i.ZERO] and operation["dependency_regions"] == [Vector2i(1, 0)], "positive boundary neighbor is a rebuild dependency only, not canonical support")
	var edited_left := _region_boundary_normal_map(Vector2i.ZERO, true, edits)
	var edited_right := _region_boundary_normal_map(Vector2i(1, 0), false, edits)
	_check(not edited_left.is_empty() and _normal_maps_match(edited_left, edited_right), "rebuilt adjacent regions publish identical normals at shared seam vertices")
	_check(_normal_map_differs(baseline_left, edited_right), "the dependency-side seam normal changes after sampling the one-sided brush")
	_check(not _normal_maps_match(edited_left, _region_boundary_normal_map(Vector2i(1, 0), false)), "keeping the dependency-side mesh stale would create a shared-normal mismatch")
	var negative_surface_y := _surface_height(-16.0, -5.0)
	_check(is_finite(negative_surface_y), "negative-coordinate test point resolves to deterministic terrain surface")
	if is_finite(negative_surface_y):
		var negative_edits := BrushState.new(SEED, Field.GENERATOR_VERSION)
		var negative_center := Vector3(-16.91, negative_surface_y, -5.0)
		_check(negative_center.x + 0.9 < -16.0, "negative test brush stays inside its canonical region across X")
		_check(negative_edits.add_sphere(BrushState.Mode.FILL, negative_center, 0.9), "negative near-boundary surface brush is admitted")
		var negative_operation: Dictionary = negative_edits.get_operations_snapshot()[0]
		_check(negative_operation["support_regions"] == [Vector2i(-2, -1)] and negative_operation["dependency_regions"].has(Vector2i(-1, -1)), "negative sample dependency is assigned by mathematical floor")


func _region_boundary_normal_map(region_key: Vector2i, is_left: bool, edits: RefCounted = null) -> Dictionary:
	var result: Dictionary = {}
	var origin := Spatial.region_origin_world(region_key)
	var boundary_x := origin.x + Spatial.REGION_SIZE_X if is_left else origin.x
	for z in range(ChunkGrid.CHUNK_COUNT_Z):
		var coordinate := Vector2i(ChunkGrid.CHUNK_COUNT_X - 1 if is_left else 0, z)
		var built := Mesher.build_chunk_mesh(SEED, region_key, coordinate, false, edits)
		var offset := origin + ChunkGrid.origin_for(coordinate)
		var boundary_map := _boundary_map(built["mesh"], offset, true, boundary_x)
		for key in boundary_map:
			if not result.has(key):
				result[key] = []
			(result[key] as Array).append(boundary_map[key])
	return result


func _normal_map_differs(a: Dictionary, b: Dictionary) -> bool:
	for key in a:
		if not b.has(key):
			continue
		for normal_value in a[key]:
			var normal: Vector3 = normal_value
			for other_value in b[key]:
				if normal.dot(Vector3(other_value)) < 0.999:
					return true
	return false


func _oriented_mesh_signatures(mesh: ArrayMesh, origin: Vector3) -> Array[String]:
	var result: Array[String] = []
	if mesh.get_surface_count() == 0:
		return result
	var arrays: Array = mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	for index in range(0, vertices.size(), 3):
		var parts: Array[String] = []
		for offset in range(3):
			var point: Vector3 = vertices[index + offset] + origin
			parts.append("%.4f,%.4f,%.4f" % [point.x, point.y, point.z])
		result.append("%s|%s|%s" % [parts[0], parts[1], parts[2]])
	return _sorted_signatures(result)


func _mesh_normal_map(mesh: ArrayMesh, origin: Vector3) -> Dictionary:
	var result: Dictionary = {}
	if mesh.get_surface_count() == 0:
		return result
	var arrays: Array = mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	for index in range(vertices.size()):
		var key := _point_key(vertices[index] + origin)
		if not result.has(key):
			result[key] = []
		(result[key] as Array).append(normals[index].normalized())
	return result


func _merge_normal_map(target: Dictionary, source: Dictionary) -> void:
	for key in source:
		if not target.has(key):
			target[key] = []
		(target[key] as Array).append_array(source[key])


func _normal_maps_match(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for key in a:
		if not b.has(key) or (a[key] as Array).size() != (b[key] as Array).size():
			return false
		var unmatched: Array = (b[key] as Array).duplicate()
		for normal_value in a[key]:
			var normal: Vector3 = normal_value
			var match_index := -1
			for index in range(unmatched.size()):
				if normal.dot(unmatched[index]) > 0.999:
					match_index = index
					break
			if match_index < 0:
				var best_dot := -1.0
				for other in unmatched:
					best_dot = maxf(best_dot, normal.dot(other))
				print("NORMAL_MAP_MISMATCH: point=%s best_dot=%.6f ref_count=%d candidate_count=%d" % [key, best_dot, (a[key] as Array).size(), (b[key] as Array).size()])
				return false
			unmatched.remove_at(match_index)
	return true


func _edited_normals_outward(mesh: ArrayMesh, offset: Vector3, fallback_region: Vector2i, cut: bool, edits: RefCounted) -> Vector2i:
	if mesh.get_surface_count() == 0:
		return Vector2i.ZERO
	var arrays: Array = mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var stride := maxi(1, int(vertices.size() / 512))
	var outward_count := 0
	var sample_count := 0
	for index in range(0, vertices.size(), stride):
		var point: Vector3 = vertices[index] + offset
		var normal := normals[index].normalized()
		var mapped: Dictionary = Spatial.world_to_region_local(point)
		var key: Vector2i = mapped["region_key"] if mapped.get("valid", false) else fallback_region
		var local: Vector3 = mapped["local_position"] if mapped.get("valid", false) else point
		var outside_density: float = edits.sample_density(SEED, key, local + normal * 0.12, cut)
		var inside_density: float = edits.sample_density(SEED, key, local - normal * 0.12, cut)
		if outside_density < inside_density:
			outward_count += 1
		sample_count += 1
	return Vector2i(outward_count, sample_count)


func _check_edit_seam_if_present(chunk_data: Dictionary, left_coord: Vector2i, right_coord: Vector2i, x_axis: bool) -> void:
	var left: Dictionary = chunk_data[left_coord]
	var right: Dictionary = chunk_data[right_coord]
	var boundary: float = right["offset"].x if x_axis else right["offset"].z
	var left_map := _boundary_map(left["mesh"], left["offset"], x_axis, boundary)
	var right_map := _boundary_map(right["mesh"], right["offset"], x_axis, boundary)
	if left_map.is_empty() and right_map.is_empty():
		_check(true, "edited adjacent chunks have matching empty seam intervals")
		return
	_check(not left_map.is_empty() and not right_map.is_empty() and _boundary_matches(left_map, right_map), "edited global region seam positions and normals agree")


func _check_cut_seam_samples(edits: RefCounted) -> void:
	var checked := 0
	for yi in range(ChunkGrid.CELL_COUNT_Y + 1):
		for zi in range(ChunkGrid.CELL_COUNT_Z + 1):
			var y := ChunkGrid.MIN_BOUND.y + float(yi) * ChunkGrid.SAMPLE_STEP
			var z := float(zi) * ChunkGrid.SAMPLE_STEP
			var left: float = edits.sample_density(SEED, Vector2i.ZERO, Vector3(16.0, y, z), true)
			var right: float = edits.sample_density(SEED, Vector2i(1, 0), Vector3(0.0, y, z), true)
			if not is_equal_approx(left, right):
				_check(false, "cut and edit samples remain continuous at a region seam")
				return
			checked += 1
	_check(checked == (ChunkGrid.CELL_COUNT_Y + 1) * (ChunkGrid.CELL_COUNT_Z + 1), "cut and edited SDF samples remain continuous across every shared seam lattice point")


func _check_seam(chunk_data: Dictionary, left_coord: Vector2i, right_coord: Vector2i, x_axis: bool) -> void:
	var left: Dictionary = chunk_data[left_coord]
	var right: Dictionary = chunk_data[right_coord]
	var left_mesh: ArrayMesh = left["mesh"]
	var right_mesh: ArrayMesh = right["mesh"]
	var left_offset: Vector3 = left["offset"]
	var right_offset: Vector3 = right["offset"]
	var boundary := right_offset.x if x_axis else right_offset.z
	var left_map := _boundary_map(left_mesh, left_offset, x_axis, boundary)
	var right_map := _boundary_map(right_mesh, right_offset, x_axis, boundary)
	_check(not left_map.is_empty() and not right_map.is_empty(), "adjacent rendered chunks have a surface along shared boundary")
	var matches := _boundary_matches(left_map, right_map)
	if not matches:
		print("MULTIREGION_SEAM_DIFF: left=%s right=%s x_axis=%s left_vertices=%d right_vertices=%d" % [left_coord, right_coord, x_axis, left_map.size(), right_map.size()])
	_check(matches, "adjacent region/chunk boundary positions and outward normals agree")


func _boundary_map(mesh: ArrayMesh, offset: Vector3, x_axis: bool, boundary: float) -> Dictionary:
	var result: Dictionary = {}
	if mesh.get_surface_count() == 0:
		return result
	var arrays: Array = mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	for index in range(vertices.size()):
		var point: Vector3 = vertices[index] + offset
		if absf((point.x if x_axis else point.z) - boundary) > 0.00001:
			continue
		result[_point_key(point)] = normals[index]
	return result


func _boundary_matches(left: Dictionary, right: Dictionary) -> bool:
	for left_key in left:
		var nearest_key := ""
		var nearest_distance := INF
		for right_key in right:
			var distance := _key_point(left_key).distance_to(_key_point(right_key))
			if distance < nearest_distance:
				nearest_distance = distance
				nearest_key = right_key
		if nearest_distance > 0.0002:
			print("SEAM_POSITION_MISMATCH: left=%s right=%s nearest=%s distance=%.6f" % [left_key, right.keys(), nearest_key, nearest_distance])
			return false
		var normal_dot := Vector3(left[left_key]).dot(Vector3(right[nearest_key]))
		if normal_dot <= 0.999:
			print("SEAM_NORMAL_MISMATCH: %s dot=%.6f left=%s right=%s" % [left_key, normal_dot, left[left_key], right[nearest_key]])
			return false
	for right_key in right:
		var found := false
		for left_key in left:
			if _key_point(left_key).distance_to(_key_point(right_key)) <= 0.0002:
				found = true
				break
		if not found:
			print("SEAM_RIGHT_ONLY: %s" % right_key)
			return false
	return true


func _test_dynamic_region_streaming_and_focused_edits() -> void:
	var packed := load("res://scenes/terrain_demo.tscn") as PackedScene
	_check(packed != null, "multiregion demonstration scene loads")
	if packed == null:
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	await _wait_for_region(scene, Vector2i.ZERO)
	_check(scene.get("active_regions").size() == 1 and scene.get("chunk_nodes").size() == 16, "focused center region becomes visible after its CPU mesh jobs finish")
	await _wait_for_requested_window(scene)
	var chunk_nodes: Dictionary = scene.get("chunk_nodes")
	var region_states: Dictionary = scene.get("world_states")
	var initial_diagnostics: Dictionary = scene.get("last_mesh_diagnostics").duplicate(true)
	var active_regions: Dictionary = scene.get("active_regions")
	_check(active_regions.size() == 9 and chunk_nodes.size() == 144, "camera focus requests and publishes a complete 3x3 region window")
	_check(scene.get("last_mesh_diagnostics")["active_region_count"] == 9, "startup diagnostics report nine active regions")
	_check(scene.get("last_mesh_diagnostics")["peak_mesh_uploads_per_frame"] <= 2, "streaming publishes no more than two finished chunk meshes per process frame")
	_check(scene.get("last_mesh_diagnostics")["queued_chunk_count"] == 0, "initial requested-region queue drains completely")
	_check(initial_diagnostics["peak_mesh_job_queue_depth"] == 144, "initial nine-region request remains bounded to one CPU job per chunk")
	_check(initial_diagnostics["remeshed_chunk_count"] == 144 and initial_diagnostics["triangle_count"] == 87077, "initial streamed window preserves the exact 144-chunk baseline geometry")
	_check(scene.get_node("CanvasLayer/Status").text.contains("WASD/arrows") and scene.get_node("CanvasLayer/Status").text.contains("P1.0C global SDF edits"), "HUD documents controls and global edit ledger")
	_check(region_states.size() == 9, "initial domain states correspond only to requested or active regions")
	var ledger: RefCounted = scene.get("edit_ledger")
	var left_boundary_id: String = ChunkGrid.stable_id(Vector2i.ZERO, Vector2i(3, 2))
	var right_boundary_id: String = ChunkGrid.stable_id(Vector2i(1, 0), Vector2i(0, 2))
	var left_boundary_node: MeshInstance3D = scene.get("chunk_nodes")[left_boundary_id]
	var right_boundary_node: MeshInstance3D = scene.get("chunk_nodes")[right_boundary_id]
	var left_before: ArrayMesh = left_boundary_node.mesh
	var right_before: ArrayMesh = right_boundary_node.mesh
	var retry_total_before: int = scene.get("last_mesh_diagnostics").get("mesh_stage_retry_total", 0)
	scene.set("debug_fail_next_mesh_stage", true)
	scene.set("selected_brush_mode", BrushState.Mode.CARVE)
	var near_seam_surface_y := _surface_height(15.0, 6.0)
	_check(is_finite(near_seam_surface_y), "dynamic neighbor test resolves the real terrain surface near positive X seam")
	var near_seam_center := Vector3(15.0, near_seam_surface_y, 6.0)
	var one_sided_accepted: bool = ledger.add_sphere(BrushState.Mode.CARVE, near_seam_center, 0.9)
	_check(one_sided_accepted, "one-sided near-seam operation is admitted once with an explicit bounded test radius")
	if one_sided_accepted:
		scene.call("_schedule_edit_transaction", ledger.get_operations_snapshot()[-1])
	var near_seam_operation: Dictionary = ledger.get_operations_snapshot()[0]
	_check(near_seam_operation["support_regions"] == [Vector2i.ZERO] and near_seam_operation["dependency_regions"].has(Vector2i(1, 0)), "one-sided geometric support explicitly fans out to the normal-dependent neighbor")
	await process_frame
	_check(left_boundary_node.mesh == left_before and right_boundary_node.mesh == right_before, "injected stage failure leaves both visible sides on the old mesh set")
	_check(scene.get("last_mesh_diagnostics").get("mesh_stage_retry_total", 0) > retry_total_before, "injected cross-region mesh failure triggers a bounded transaction retry")
	await _wait_for_edit_transaction(scene)
	_check(left_boundary_node.mesh != left_before and right_boundary_node.mesh != right_before, "successful transaction publishes both sides of the seam together")
	_check(ledger.get_edit_count() == 1 and ledger.get_last_sequence() == 0, "one accepted cross-region gesture occupies one global log slot")
	var edit_metrics: Dictionary = scene.get("last_mesh_diagnostics").duplicate(true)
	scene.call("_move_focus", Vector3(64.0, 0.0, 0.0))
	await _wait_for_requested_window(scene)
	_check(not scene.get("active_regions").has("1,0") and ledger.get_edit_count() == 1, "dependency-only neighbor unloads while canonical brush remains in the global ledger")
	scene.call("_move_focus", Vector3(-48.0, 0.0, 0.0))
	await _wait_for_requested_window(scene)
	_check(scene.get("active_regions").has("1,0"), "dependency-only neighbor reloads when it re-enters the requested region window")
	if scene.get("active_regions").has("1,0"):
		var reloaded_neighbor: Dictionary = scene.get("active_regions")["1,0"]
		var dependent_chunk_coordinate := Vector2i(0, 2)
		var reloaded_chunk: MeshInstance3D = reloaded_neighbor["chunk_nodes"][ChunkGrid.stable_id(Vector2i(1, 0), dependent_chunk_coordinate)]
		var expected_neighbor := Mesher.build_chunk_mesh(SEED, Vector2i(1, 0), dependent_chunk_coordinate, false, ledger)
		_check(_meshes_equal(reloaded_chunk.mesh, expected_neighbor["mesh"]), "dependency-only neighbor reconstructs byte-equivalent geometry and normals after reload")
		var reentry_seams := _active_chunk_data(scene, [Vector2i.ZERO, Vector2i(1, 0)])
		for seam_chunk_z in range(ChunkGrid.CHUNK_COUNT_Z):
			_check_seam(reentry_seams, Vector2i(3, seam_chunk_z), Vector2i(4, seam_chunk_z), true)
	scene.call("_move_focus", Vector3(-16.0, 0.0, 0.0))
	await _wait_for_requested_window(scene)
	_check(scene.get("focus_region_key") == Vector2i.ZERO, "dependency reload test restores the original focus before existing traversal checks")
	print("GLOBAL_EDIT_BENCH: elapsed_ms=%.3f dirty_regions=%d dirty_chunks=%d dirty_jobs=%d frame_p50/p95/p99_ms=%.3f/%.3f/%.3f resident_peak=%d ledger=%d/%d" % [
		edit_metrics.get("elapsed_ms", 0.0), edit_metrics.get("last_rebuild_region_count", 0),
		edit_metrics.get("last_rebuild_chunk_count", 0), edit_metrics.get("last_dirty_mesh_job_count", 0),
		edit_metrics.get("frame_time_p50_ms", 0.0), edit_metrics.get("frame_time_p95_ms", 0.0),
		edit_metrics.get("frame_time_p99_ms", 0.0), edit_metrics.get("peak_active_region_count", 0),
		ledger.get_edit_count(), BrushState.MAX_EDITS,
	])
	print("GLOBAL_EDIT_STAGE_BENCH: queue_wait_p50/p95/total_ms=%.3f/%.3f/%.3f stages=%s" % [
		edit_metrics.get("mesh_queue_wait_p50_ms", 0.0), edit_metrics.get("mesh_queue_wait_p95_ms", 0.0),
		edit_metrics.get("mesh_queue_wait_total_ms", 0.0), JSON.stringify(edit_metrics.get("stage_timings_ms", {})),
	])
	var camera: Camera3D = scene.get_node("Camera3D")
	var view_light := camera.get_node_or_null("ViewAlignedLight") as SpotLight3D
	_check(view_light != null, "camera has an auxiliary aligned spotlight")
	if view_light != null:
		_check(view_light.light_energy >= 12.0 and view_light.light_energy <= 16.0 and not view_light.shadow_enabled, "auxiliary light adds a bounded close-range fill without replacing directional shading")
	var active_before_move := active_regions.size()
	await _send_key(KEY_D)
	await _send_key(KEY_D)
	await _wait_for_requested_window(scene)
	_check(scene.get("focus_region_key") == Vector2i(1, 0), "viewport movement crosses the positive region boundary with stable floor ownership")
	_check(active_regions.size() >= active_before_move and active_regions.size() <= 25, "positive traversal preserves resident coverage while respecting the region cap")
	_check(chunk_nodes.size() <= 25 * ChunkGrid.CHUNK_COUNT_X * ChunkGrid.CHUNK_COUNT_Z, "positive traversal keeps active chunk nodes bounded")
	_check(scene.get("last_mesh_diagnostics")["queued_chunk_count"] <= 25 * ChunkGrid.CHUNK_COUNT_X * ChunkGrid.CHUNK_COUNT_Z, "streaming job queue remains bounded by resident capacity")
	var positive_seams := _active_chunk_data(scene, [Vector2i.ZERO, Vector2i(1, 0)])
	for z in range(ChunkGrid.CHUNK_COUNT_Z):
		_check_seam(positive_seams, Vector2i(3, z), Vector2i(4, z), true)
	var operation_count_before_viewport: int = ledger.get_edit_count()
	var positive_viewport_hit := await _push_viewport_brush(scene, BrushState.Mode.FILL)
	_check(positive_viewport_hit, "real viewport click accepts a brush centered on the positive region seam")
	if positive_viewport_hit:
		await _wait_for_edit_transaction(scene)
		var positive_operation: Dictionary = ledger.get_operations_snapshot()[-1]
		var positive_affected: Array[Vector2i] = positive_operation["support_regions"]
		_check(ledger.get_edit_count() == operation_count_before_viewport + 1, "one viewport gesture appends exactly one global command")
		_check(positive_affected.has(Vector2i.ZERO) and positive_affected.has(Vector2i(1, 0)), "positive seam viewport command affects both neighboring region keys")
		var cancel_test_hit := await _push_viewport_brush(scene, BrushState.Mode.CARVE)
		_check(cancel_test_hit, "second viewport edit starts before cave-section cancellation")
		if cancel_test_hit:
			var before_cancel_count: int = ledger.get_edit_count()
			var cave_toggle := InputEventKey.new()
			cave_toggle.keycode = KEY_C
			cave_toggle.pressed = true
			root.push_input(cave_toggle)
			await _wait_for_global_rebuild(scene)
			_check(ledger.get_edit_count() == before_cancel_count, "C cancels staged publication but retains every accepted global operation")
			_check(scene.get("_edit_transaction").is_empty() and scene.get("cave_section_enabled"), "C resolves a pending edit by rebuilding the coherent visible set")
			var cave_restore := InputEventKey.new()
			cave_restore.keycode = KEY_C
			cave_restore.pressed = true
			root.push_input(cave_restore)
			await _wait_for_global_rebuild(scene)
	var positive_state: RefCounted = scene.get("world_states")["1,0"]
	_check(positive_state.region_key == Vector2i(1, 0), "loaded region retains its canonical signed region key")
	for _step in range(5):
		await _send_key(KEY_A)
	await _wait_for_requested_window(scene)
	_check(scene.get("focus_region_key") == Vector2i(-1, 0), "viewport traversal crosses into negative coordinates without truncation toward zero")
	_check(scene.get("active_regions").has("-1,0") and scene.get("active_regions").has("0,0"), "negative focus loads the correct neighboring region pair")
	var negative_seams := _active_chunk_data(scene, [Vector2i(-1, 0), Vector2i.ZERO])
	for z in range(ChunkGrid.CHUNK_COUNT_Z):
		_check_seam(negative_seams, Vector2i(-1, z), Vector2i(0, z), true)
	var negative_entry: Dictionary = scene.get("active_regions")["-1,0"]
	var negative_state: RefCounted = negative_entry["world_state"]
	var expected_mesh: Dictionary = Mesher.build_chunk_mesh(SEED, Vector2i(-1, 0), Vector2i.ZERO)
	var observed_node: MeshInstance3D = negative_entry["chunk_nodes"][ChunkGrid.stable_id(Vector2i(-1, 0), Vector2i.ZERO)]
	_check(_meshes_equal(observed_node.mesh, expected_mesh["mesh"]), "negative-region streamed mesh matches canonical deterministic chunk generation")
	var base_sample: float = negative_state.sample_density(Vector3(15.75, 4.0, 6.0))
	scene.set("selected_brush_mode", BrushState.Mode.FILL)
	scene.set("orbit_target", Vector3(-0.5, 3.0, 6.0))
	scene.set("orbit_offset", Vector3(0.0, 10.0, 18.0))
	scene.call("_update_camera")
	scene.call("_update_focus_key")
	scene.call("_reconcile_region_window", true)
	await _wait_for_requested_window(scene)
	var negative_viewport_hit := await _push_viewport_brush(scene, BrushState.Mode.FILL)
	_check(negative_viewport_hit, "real viewport click accepts a brush centered on the negative zero seam")
	if negative_viewport_hit:
		await _wait_for_edit_transaction(scene)
		var negative_operation: Dictionary = ledger.get_operations_snapshot()[-1]
		var negative_affected: Array[Vector2i] = negative_operation["support_regions"]
		_check(negative_affected.has(Vector2i(-1, 0)) and negative_affected.has(Vector2i.ZERO), "negative seam viewport command uses floor-owned keys on both sides")
	var global_count_before_unload: int = ledger.get_edit_count()
	var edited_sample: float = negative_state.sample_density(Vector3(15.75, 4.0, 6.0))
	_check(edited_sample > base_sample, "cross-region edit affects its negative-side owner")
	var positive_neighbor_state: RefCounted = scene.get("active_regions")["0,0"]["world_state"]
	_check(is_equal_approx(
		negative_state.sample_density(Vector3(16.0, 4.0, 6.0)),
		positive_neighbor_state.sample_density(Vector3(0.0, 4.0, 6.0))
	), "global operation produces an identical density on both sides of the shared x=0 sample")
	for _step in range(12):
		await _send_key(KEY_D)
	_check(not scene.get("active_regions").has("-1,0") and scene.get("edit_ledger").get_edit_count() == global_count_before_unload, "unload removes render nodes while all bounded global commands remain")
	for _step in range(12):
		await _send_key(KEY_A)
	await _wait_for_requested_window(scene)
	var reloaded_state: RefCounted = scene.get("active_regions")["-1,0"]["world_state"]
	_check(reloaded_state.brush_edits.get_instance_id() == ledger.get_instance_id(), "re-entered region reuses the canonical global edit ledger")
	_check(reloaded_state.sample_density(Vector3(15.75, 4.0, 6.0)) > base_sample, "region reload replays the accepted cross-region transient edit")
	var sequence_before_reset: int = ledger.get_last_sequence()
	var count_before_reset: int = ledger.get_edit_count()
	await _send_key(KEY_X)
	await _wait_for_global_rebuild(scene)
	_check(ledger.get_edit_count() == count_before_reset - 1, "X removes only global commands whose support intersects the focused negative region")
	_check(ledger.get_last_sequence() == sequence_before_reset, "focused reset does not reuse the removed command sequence")
	_check(is_equal_approx(reloaded_state.sample_density(Vector3(15.75, 4.0, 6.0)), base_sample), "focused reset remeshes the negative side and removes its cross-region effect")
	var unloaded_center := Vector3(-48.0, 4.0, 6.0)
	var unloaded_baseline: float = Field.sample_density(SEED, Vector2i(-3, 0), Vector3(0.0, 4.0, 6.0))
	_check(ledger.add_sphere(BrushState.Mode.CARVE, unloaded_center, 1.25), "canonical operation is accepted while both intersected regions are unloaded")
	_check(not scene.get("active_regions").has("-3,0") and not scene.get("active_regions").has("-4,0"), "unloaded-region operation does not require retaining region meshes")
	var load_retry_before: int = scene.get("last_mesh_diagnostics").get("mesh_stage_retry_total", 0)
	scene.set("debug_fail_next_load_stage", true)
	for _step in range(8):
		await _send_key(KEY_A)
	await _wait_for_requested_window(scene)
	_check(not scene.get("debug_fail_next_load_stage"), "injected first-load failure was consumed by a disposable streamed region")
	_check(scene.get("last_mesh_diagnostics").get("mesh_stage_retry_total", 0) > load_retry_before, "failed initial load is explicitly retried within a fixed bound")
	var replayed_entry: Dictionary = scene.get("active_regions")["-3,0"]
	var replayed_state: RefCounted = replayed_entry["world_state"]
	_check(replayed_state.sample_density(Vector3(0.0, 4.0, 6.0)) < unloaded_baseline, "later region load replays the earlier global operation")
	var replayed_chunk_id: String = ChunkGrid.stable_id(Vector2i(-3, 0), Vector2i(0, 2))
	var replayed_mesh: Dictionary = Mesher.build_chunk_mesh(SEED, Vector2i(-3, 0), Vector2i(0, 2), false, ledger)
	_check(_meshes_equal(replayed_entry["chunk_nodes"][replayed_chunk_id].mesh, replayed_mesh["mesh"]), "reloaded mesh bytes derive from the canonical command ledger")
	_check(scene.get("active_regions").size() <= 25 and scene.get("chunk_nodes").size() <= 400, "repeated region crossings stay within region and chunk caps")
	_check(scene.get("loading_regions").size() <= 9 and scene.get("last_mesh_diagnostics")["peak_mesh_uploads_per_frame"] <= 2, "ordinary load queue and per-frame uploads remain bounded after repeated crossings")
	var diagnostics: Dictionary = scene.get("last_mesh_diagnostics")
	_check(diagnostics["peak_active_region_count"] <= 25 and diagnostics["peak_queue_depth"] <= 400 and diagnostics["peak_mesh_job_queue_depth"] <= 400, "observed resident and worst-case rebuild queues stay within fixed caps")
	for id_value in scene.get("loading_regions"):
		var staged: Dictionary = scene.get("loading_regions")[id_value]
		var staged_key: Vector2i = staged["region_key"]
		_check(maxi(absi(staged_key.x - scene.get("focus_region_key").x), absi(staged_key.y - scene.get("focus_region_key").y)) <= 1, "obsolete load work cannot remain queued outside the requested window")
	print("TERRAIN_STREAM_INITIAL_METRICS: active=%d chunks=%d triangles=%d queue_peak=%d mesh_job_queue_peak=%d elapsed_ms=%.3f mesh_work_total_ms=%.3f peak_mesh_ms=%.3f peak_process_work_ms=%.3f" % [
		initial_diagnostics["active_region_count"], initial_diagnostics["active_chunk_count"], initial_diagnostics["triangle_count"],
		initial_diagnostics["peak_queue_depth"], initial_diagnostics["peak_mesh_job_queue_depth"], initial_diagnostics["elapsed_ms"], initial_diagnostics["total_mesh_work_ms"],
		initial_diagnostics["peak_mesh_upload_ms"], initial_diagnostics["peak_process_work_ms"],
	])
	print("TERRAIN_STREAM_STAGE_METRICS: queue_wait_p50/p95/total_ms=%.3f/%.3f/%.3f stages=%s" % [
		initial_diagnostics.get("mesh_queue_wait_p50_ms", 0.0), initial_diagnostics.get("mesh_queue_wait_p95_ms", 0.0),
		initial_diagnostics.get("mesh_queue_wait_total_ms", 0.0), JSON.stringify(initial_diagnostics.get("stage_timings_ms", {})),
	])
	print("TERRAIN_STREAM_METRICS: active=%d peak_active=%d chunk_nodes=%d queued=%d peak_queued=%d peak_mesh_upload_ms=%.3f peak_process_work_ms=%.3f loads=%d unloads=%d" % [
		diagnostics["active_region_count"], diagnostics["peak_active_region_count"], diagnostics["active_chunk_count"],
		diagnostics["queued_chunk_count"], diagnostics["peak_queue_depth"], diagnostics["peak_mesh_upload_ms"],
		diagnostics["peak_process_work_ms"], diagnostics["streamed_region_loads"], diagnostics["streamed_region_unloads"],
	])
	var lod_region: Vector2i = scene.get("focus_region_key")
	var lod_coordinate := Vector2i.ZERO
	var lod_id: String = ChunkGrid.stable_id(lod_region, lod_coordinate)
	var lod_node: MeshInstance3D = scene.get("chunk_nodes")[lod_id]
	var lod_mesh_before: Mesh = lod_node.mesh
	var lod_center: Vector3 = Spatial.region_origin_world(lod_region) + ChunkGrid.origin_for(lod_coordinate) + ChunkGrid.size_for(lod_coordinate) * 0.5
	var lod_camera: Camera3D = scene.get("camera")
	lod_camera.global_position = lod_center + Vector3(60.0, 0.0, 0.0)
	scene.set("lod_enabled", true)
	var lod_coordinates: Array[Vector2i] = [lod_coordinate]
	scene.call("_begin_region_stage", lod_region, "partial", lod_coordinates)
	_check(int(scene.get("loading_regions")["%d,%d" % [lod_region.x, lod_region.y]]["lod_by_coordinate"][lod_coordinate]) == 1, "camera-distance selection stages one LOD1 chunk in the active scene")
	await _wait_for_chunk_lod(scene, lod_region, lod_coordinate, 1)
	_check(int(lod_node.get_meta("lod_level", -1)) == 1 and lod_node.mesh != lod_mesh_before, "completed LOD1 ArrayMesh is published on the playable chunk node")
	scene.set("lod_enabled", false)
	scene.call("_update_lod_selection")
	await _wait_for_chunk_lod(scene, lod_region, lod_coordinate, 0)
	_check(int(lod_node.get_meta("lod_level", -1)) == 0, "LOD0 fallback rebuilds the changed playable chunk")
	scene.queue_free()
	await process_frame


func _test_edit_while_neighbor_is_loading() -> void:
	var packed := load("res://scenes/terrain_demo.tscn") as PackedScene
	if packed == null:
		_check(false, "loading-neighbor edit scene loads")
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	await _wait_for_region(scene, Vector2i.ZERO)
	var neighbor_id := "1,0"
	_check(scene.get("loading_regions").has(neighbor_id), "positive seam neighbor remains incrementally loading while focus is already visible")
	var accepted: bool = scene.call("_accept_brush_at_world", Vector3(16.0, 4.0, 6.0))
	_check(accepted, "global brush is accepted while one intersected neighbor is still loading")
	if accepted:
		_check(scene.get("loading_regions").has(neighbor_id) and scene.get("loading_regions")[neighbor_id]["purpose"] == "edit_transaction", "stale load stage is replaced by a revision-pinned full edit stage")
		await _wait_for_edit_transaction(scene)
		await _wait_for_requested_window(scene)
		var entry: Dictionary = scene.get("active_regions")[neighbor_id]
		var state: RefCounted = entry["world_state"]
		_check(state.brush_edits.get_instance_id() == scene.get("edit_ledger").get_instance_id(), "loaded neighbor samples the canonical global ledger")
		var chunk_id: String = ChunkGrid.stable_id(Vector2i(1, 0), Vector2i(0, 2))
		var expected := Mesher.build_chunk_mesh(SEED, Vector2i(1, 0), Vector2i(0, 2), false, state.brush_edits)
		_check(_meshes_equal(entry["chunk_nodes"][chunk_id].mesh, expected["mesh"]), "neighbor published after loading matches the accepted global command")
	scene.queue_free()
	await process_frame


func _send_key(keycode: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	root.push_input(event)
	await process_frame


func _push_viewport_brush(scene: Node, mode: int) -> bool:
	if not scene.get("_edit_transaction").is_empty() or scene.get("global_rebuild_pending"):
		return false
	scene.set("selected_brush_mode", mode)
	scene.set("orbit_offset", Vector3(0.0, 10.0, 18.0))
	scene.call("_update_camera")
	await process_frame
	var before_count: int = scene.get("edit_ledger").get_edit_count()
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.shift_pressed = mode == BrushState.Mode.FILL
	click.position = root.get_visible_rect().size * 0.5
	root.push_input(click, true)
	await process_frame
	return scene.get("edit_ledger").get_edit_count() == before_count + 1


func _wait_for_requested_window(scene: Node) -> void:
	for _frame in range(4000):
		var focus: Vector2i = scene.get("focus_region_key")
		var active: Dictionary = scene.get("active_regions")
		var complete := true
		for z in range(focus.y - 1, focus.y + 2):
			for x in range(focus.x - 1, focus.x + 2):
				if not active.has("%d,%d" % [x, z]):
					complete = false
		if complete:
			return
		await process_frame
	_check(false, "all nine camera-requested regions finish incremental loading within the bounded test wait")


func _wait_for_region(scene: Node, region_key: Vector2i) -> void:
	var id := "%d,%d" % [region_key.x, region_key.y]
	for _frame in range(4000):
		if scene.get("active_regions").has(id):
			return
		await process_frame
	_check(scene.get("active_regions").has(id), "focused region becomes visible after bounded mesh jobs")


func _wait_for_global_rebuild(scene: Node) -> void:
	for _frame in range(4000):
		if not scene.get("global_rebuild_pending"):
			return
		await process_frame
	_check(not scene.get("global_rebuild_pending"), "C/R rebuild completes incrementally after pending edit cancellation")


func _wait_for_edit_transaction(scene: Node) -> void:
	for _frame in range(2000):
		if scene.get("_edit_transaction").is_empty():
			return
		await process_frame
	_check(scene.get("_edit_transaction").is_empty(), "cross-region edit transaction completes or explicitly resolves after unload")


func _wait_for_chunk_lod(scene: Node, region_key: Vector2i, coordinate: Vector2i, expected_lod: int) -> void:
	var chunk_id: String = ChunkGrid.stable_id(region_key, coordinate)
	var region_id := "%d,%d" % [region_key.x, region_key.y]
	for _frame in range(2400):
		await process_frame
		var active: Dictionary = scene.get("active_regions")
		if active.has(region_id) and active[region_id]["chunk_nodes"].has(chunk_id) \
			and not scene.get("loading_regions").has(region_id) \
			and int(active[region_id]["chunk_nodes"][chunk_id].get_meta("lod_level", -1)) == expected_lod:
			return
	_check(false, "playable LOD stage reaches expected level %d before bounded test timeout" % expected_lod)


func _active_chunk_data(scene: Node, region_keys: Array[Vector2i]) -> Dictionary:
	var result: Dictionary = {}
	var active: Dictionary = scene.get("active_regions")
	for region_key in region_keys:
		var entry: Dictionary = active["%d,%d" % [region_key.x, region_key.y]]
		for coordinate in ChunkGrid.all_coordinates():
			var global_coordinate := Vector2i(region_key.x * ChunkGrid.CHUNK_COUNT_X + coordinate.x, region_key.y * ChunkGrid.CHUNK_COUNT_Z + coordinate.y)
			var chunk_id: String = ChunkGrid.stable_id(region_key, coordinate)
			result[global_coordinate] = {
				"mesh": entry["chunk_nodes"][chunk_id].mesh,
				"offset": Spatial.region_origin_world(region_key) + ChunkGrid.origin_for(coordinate),
			}
	return result


func _meshes_equal(actual: ArrayMesh, expected: ArrayMesh) -> bool:
	if actual.get_surface_count() != expected.get_surface_count():
		print("MESH_MISMATCH: actual_surfaces=%d expected_surfaces=%d" % [actual.get_surface_count(), expected.get_surface_count()])
		return false
	if actual.get_surface_count() == 0:
		return true
	var actual_arrays: Array = actual.surface_get_arrays(0)
	var expected_arrays: Array = expected.surface_get_arrays(0)
	var actual_vertices: PackedVector3Array = actual_arrays[Mesh.ARRAY_VERTEX]
	var expected_vertices: PackedVector3Array = expected_arrays[Mesh.ARRAY_VERTEX]
	var actual_normals: PackedVector3Array = actual_arrays[Mesh.ARRAY_NORMAL]
	var expected_normals: PackedVector3Array = expected_arrays[Mesh.ARRAY_NORMAL]
	if actual_vertices != expected_vertices or actual_normals.size() != expected_normals.size():
		if actual_vertices.size() != expected_vertices.size():
			print("MESH_MISMATCH: actual_vertices=%d expected_vertices=%d actual_normals=%d expected_normals=%d" % [actual_vertices.size(), expected_vertices.size(), actual_normals.size(), expected_normals.size()])
		elif not actual_vertices.is_empty():
			for index in range(actual_vertices.size()):
				if actual_vertices[index] != expected_vertices[index]:
					print("MESH_MISMATCH: first_vertex_index=%d actual=%s expected=%s" % [index, actual_vertices[index], expected_vertices[index]])
					break
		return false
	for index in range(actual_normals.size()):
		if actual_normals[index].distance_to(expected_normals[index]) > 0.001:
			print("MESH_NORMAL_MISMATCH: index=%d distance=%.6f actual=%s expected=%s" % [index, actual_normals[index].distance_to(expected_normals[index]), actual_normals[index], expected_normals[index]])
			return false
	return true


func _find_surface_click(scene: Node, target_region: Vector2i, require_unsafe_center: bool) -> Vector2:
	var camera: Camera3D = scene.get_node("Camera3D")
	var viewport_size := root.get_visible_rect().size
	var world_state: RefCounted = scene.get("world_state")
	var sample_field := func(point: Vector3) -> float:
		return world_state.sample_density(point)
	var x_values := range(target_region.x * 16 + 1, target_region.x * 16 + 16, 3)
	var z_values := range(target_region.y * 12 + 1, target_region.y * 12 + 12, 3)
	for x in x_values:
		for z in z_values:
			var y := _surface_height(float(x), float(z))
			if is_nan(y):
				continue
			var projected := camera.unproject_position(Vector3(float(x), y, float(z)))
			if projected.x < 0.0 or projected.y < 0.0 or projected.x >= viewport_size.x or projected.y >= viewport_size.y:
				continue
			var ray_origin := camera.project_ray_origin(projected)
			var ray_direction := camera.project_ray_normal(projected)
			var pick: Dictionary = Picker.pick_surface(ray_origin, ray_direction, sample_field)
			if not pick.get("hit", false):
				continue
			var mapped: Dictionary = Spatial.world_to_region_local(pick["position"])
			if mapped["region_key"] != target_region:
				continue
			if target_region == Vector2i.ZERO and bool(scene.call("_is_center_edit_safe", mapped["local_position"])) != require_unsafe_center:
				return projected
			if target_region != Vector2i.ZERO:
				return projected
	return Vector2(-1.0, -1.0)


func _find_unsafe_center_edge_click(scene: Node) -> Vector2:
	var camera: Camera3D = scene.get_node("Camera3D")
	var viewport_size := root.get_visible_rect().size
	var world_state: RefCounted = scene.get("world_state")
	var sample_field := func(point: Vector3) -> float:
		return world_state.sample_density(point)
	for x in [15.0, 15.25, 15.5, 15.75]:
		for z in [3.0, 6.0, 9.0]:
			var y := _surface_height(x, z)
			if is_nan(y):
				continue
			var projected := camera.unproject_position(Vector3(x, y, z))
			if projected.x < 0.0 or projected.y < 0.0 or projected.x >= viewport_size.x or projected.y >= viewport_size.y:
				continue
			var pick: Dictionary = Picker.pick_surface(camera.project_ray_origin(projected), camera.project_ray_normal(projected), sample_field)
			if pick.get("hit", false):
				var mapped: Dictionary = Spatial.world_to_region_local(pick["position"])
				if mapped["region_key"] == Vector2i.ZERO and not bool(scene.call("_is_center_edit_safe", mapped["local_position"])):
					return projected
	return Vector2(-1.0, -1.0)


func _surface_height(world_x: float, world_z: float) -> float:
	var outside_y := 8.0
	var outside_density: float = _sample_world_field(Vector3(world_x, outside_y, world_z))
	for y_step in range(1, 100):
		var candidate_y := 8.0 - float(y_step) * 0.1
		var density: float = _sample_world_field(Vector3(world_x, candidate_y, world_z))
		if outside_density < 0.0 and density >= 0.0:
			var low := candidate_y
			var high := outside_y
			for _iteration in range(16):
				var middle := (low + high) * 0.5
				if _sample_world_field(Vector3(world_x, middle, world_z)) >= 0.0:
					low = middle
				else:
					high = middle
			return (low + high) * 0.5
		outside_y = candidate_y
		outside_density = density
	return NAN


func _sample_world_field(world_position: Vector3) -> float:
	var mapped: Dictionary = Spatial.world_to_region_local(world_position)
	return Field.sample_density(SEED, mapped["region_key"], mapped["local_position"])


func _dispatch_left_click(position: Vector2) -> void:
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = position
	root.push_input(click, true)


func _snapshot_meshes(scene: Node) -> Dictionary:
	var snapshot: Dictionary = {}
	var chunk_nodes: Dictionary = scene.get("chunk_nodes")
	for chunk_id in chunk_nodes:
		snapshot[chunk_id] = chunk_nodes[chunk_id].mesh
	return snapshot


func _snapshots_equal(left: Dictionary, right: Dictionary) -> bool:
	if left.size() != right.size():
		return false
	for key in left:
		if left[key] != right.get(key):
			return false
	return true


func _global_chunk_coordinate(region_key: Vector2i, chunk_coordinate: Vector2i) -> Vector2i:
	return Vector2i((region_key.x + 1) * ChunkGrid.CHUNK_COUNT_X + chunk_coordinate.x, (region_key.y + 1) * ChunkGrid.CHUNK_COUNT_Z + chunk_coordinate.y)


func _mesh_signatures(mesh: ArrayMesh, offset: Vector3) -> Array[String]:
	var signatures: Array[String] = []
	if mesh.get_surface_count() == 0:
		return signatures
	var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for index in range(0, vertices.size(), 3):
		var triangle: Array[String] = []
		for vertex_index in range(3):
			triangle.append(_point_key(vertices[index + vertex_index] + offset))
		triangle.sort()
		signatures.append("%s|%s|%s" % [triangle[0], triangle[1], triangle[2]])
	signatures.sort()
	return signatures


func _point_key(point: Vector3) -> String:
	return "%.3f,%.3f,%.3f" % [point.x, point.y, point.z]


func _key_point(key: String) -> Vector3:
	var values := key.split(",")
	return Vector3(values[0].to_float(), values[1].to_float(), values[2].to_float())


func _sorted_signatures(values: Array[String]) -> Array[String]:
	var result := values.duplicate()
	result.sort()
	return result


func _signature_counts(values: Array[String]) -> Dictionary:
	var result: Dictionary = {}
	for value in values:
		result[value] = int(result.get(value, 0)) + 1
	return result


func _check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error("ASSERTION FAILED: " + label)
