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
	await _test_dynamic_region_streaming_and_focused_edits()
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
			print("SEAM_POSITION_MISMATCH: %s nearest=%s distance=%.6f" % [left_key, nearest_key, nearest_distance])
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
	_check(scene.get("active_regions").size() == 1 and scene.get("chunk_nodes").size() == 16, "focused center region becomes visible after its staged mesh slices finish")
	await _wait_for_requested_window(scene)
	var chunk_nodes: Dictionary = scene.get("chunk_nodes")
	var region_states: Dictionary = scene.get("world_states")
	var initial_diagnostics: Dictionary = scene.get("last_mesh_diagnostics").duplicate(true)
	var active_regions: Dictionary = scene.get("active_regions")
	_check(active_regions.size() == 9 and chunk_nodes.size() == 144, "camera focus requests and publishes a complete 3x3 region window")
	_check(scene.get("last_mesh_diagnostics")["active_region_count"] == 9, "startup diagnostics report nine active regions")
	_check(scene.get("last_mesh_diagnostics")["peak_mesh_slices_per_frame"] == 1, "streaming builds no more than one vertical mesh slice in any process frame")
	_check(scene.get("last_mesh_diagnostics")["queued_chunk_count"] == 0, "initial requested-region queue drains completely")
	_check(initial_diagnostics["peak_mesh_slice_queue_depth"] == 1440, "initial nine-region request remains bounded to 1440 incremental slice jobs")
	_check(initial_diagnostics["remeshed_chunk_count"] == 144 and initial_diagnostics["triangle_count"] == 87077, "initial streamed window preserves the exact 144-chunk baseline geometry")
	_check(scene.get_node("CanvasLayer/Status").text.contains("WASD/arrows") and scene.get_node("CanvasLayer/Status").text.contains("dynamic SDF regions"), "HUD documents dynamic camera focus controls")
	_check(region_states.size() == 9, "initial domain states correspond only to requested or active regions")
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
	_check(active_regions.size() > active_before_move and active_regions.size() <= 25, "positive traversal loads new regions while respecting the resident cap")
	_check(chunk_nodes.size() <= 25 * ChunkGrid.CHUNK_COUNT_X * ChunkGrid.CHUNK_COUNT_Z, "positive traversal keeps active chunk nodes bounded")
	_check(scene.get("last_mesh_diagnostics")["queued_chunk_count"] <= 25 * ChunkGrid.CHUNK_COUNT_X * ChunkGrid.CHUNK_COUNT_Z, "streaming job queue remains bounded by resident capacity")
	var positive_seams := _active_chunk_data(scene, [Vector2i.ZERO, Vector2i(1, 0)])
	for z in range(ChunkGrid.CHUNK_COUNT_Z):
		_check_seam(positive_seams, Vector2i(3, z), Vector2i(4, z), true)
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
	var base_sample: float = negative_state.sample_density(Vector3(8.0, 4.0, 6.0))
	_check(negative_state.apply_sphere(BrushState.Mode.FILL, Vector3(8.0, 4.0, 6.0), 1.25), "test applies one bounded transient operation to the focused region state")
	var edited_sample: float = negative_state.sample_density(Vector3(8.0, 4.0, 6.0))
	_check(edited_sample > base_sample, "focused-region edit is retained in canonical domain data")
	for _step in range(12):
		await _send_key(KEY_D)
	_check(not scene.get("active_regions").has("-1,0") and scene.get("edited_region_states").has("-1,0"), "unload removes render nodes but keeps bounded transient edit data")
	for _step in range(12):
		await _send_key(KEY_A)
	await _wait_for_requested_window(scene)
	var reloaded_state: RefCounted = scene.get("active_regions")["-1,0"]["world_state"]
	_check(reloaded_state == negative_state, "re-entering a region reuses its in-memory edited state")
	_check(reloaded_state.sample_density(Vector3(8.0, 4.0, 6.0)) > base_sample, "region reload preserves the accepted transient edit")
	_check(scene.get("active_regions").size() <= 25 and scene.get("chunk_nodes").size() <= 400, "repeated region crossings stay within region and chunk caps")
	_check(scene.get("loading_regions").size() <= 9 and scene.get("last_mesh_diagnostics")["peak_mesh_slices_per_frame"] == 1, "ordinary load queue and per-frame work remain bounded after repeated crossings")
	var diagnostics: Dictionary = scene.get("last_mesh_diagnostics")
	_check(diagnostics["peak_active_region_count"] <= 25 and diagnostics["peak_queue_depth"] <= 400 and diagnostics["peak_mesh_slice_queue_depth"] <= 4000, "observed resident and worst-case rebuild queues stay within fixed caps")
	for id_value in scene.get("loading_regions"):
		var staged: Dictionary = scene.get("loading_regions")[id_value]
		var staged_key: Vector2i = staged["region_key"]
		_check(maxi(absi(staged_key.x - scene.get("focus_region_key").x), absi(staged_key.y - scene.get("focus_region_key").y)) <= 1, "obsolete load work cannot remain queued outside the requested window")
	print("TERRAIN_STREAM_INITIAL_METRICS: active=%d chunks=%d triangles=%d queue_peak=%d slice_queue_peak=%d elapsed_ms=%.3f mesh_work_total_ms=%.3f peak_mesh_slice_ms=%.3f peak_process_work_ms=%.3f" % [
		initial_diagnostics["active_region_count"], initial_diagnostics["active_chunk_count"], initial_diagnostics["triangle_count"],
		initial_diagnostics["peak_queue_depth"], initial_diagnostics["peak_mesh_slice_queue_depth"], initial_diagnostics["elapsed_ms"], initial_diagnostics["total_mesh_work_ms"],
		initial_diagnostics["peak_mesh_slice_ms"], initial_diagnostics["peak_process_work_ms"],
	])
	print("TERRAIN_STREAM_METRICS: active=%d peak_active=%d chunk_nodes=%d queued=%d peak_queued=%d peak_mesh_slice_ms=%.3f peak_process_work_ms=%.3f loads=%d unloads=%d" % [
		diagnostics["active_region_count"], diagnostics["peak_active_region_count"], diagnostics["active_chunk_count"],
		diagnostics["queued_chunk_count"], diagnostics["peak_queue_depth"], diagnostics["peak_mesh_slice_ms"],
		diagnostics["peak_process_work_ms"], diagnostics["streamed_region_loads"], diagnostics["streamed_region_unloads"],
	])
	scene.queue_free()
	await process_frame


func _send_key(keycode: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	root.push_input(event)
	await process_frame


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
	_check(scene.get("active_regions").has(id), "focused region becomes visible after bounded slice work")


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
		return false
	for index in range(actual_normals.size()):
		if actual_normals[index].distance_to(expected_normals[index]) > 0.0001:
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
	var outside_density: float = Field.sample_density(SEED, Vector2i.ZERO, Vector3(world_x, outside_y, world_z))
	for y_step in range(1, 100):
		var candidate_y := 8.0 - float(y_step) * 0.1
		var density: float = Field.sample_density(SEED, Vector2i.ZERO, Vector3(world_x, candidate_y, world_z))
		if outside_density < 0.0 and density >= 0.0:
			var low := candidate_y
			var high := outside_y
			for _iteration in range(16):
				var middle := (low + high) * 0.5
				if Field.sample_density(SEED, Vector2i.ZERO, Vector3(world_x, middle, world_z)) >= 0.0:
					low = middle
				else:
					high = middle
			return (low + high) * 0.5
		outside_y = candidate_y
		outside_density = density
	return NAN


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
