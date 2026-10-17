extends SceneTree

const TerrainField := preload("res://scripts/terrain/sdf_world.gd")
const TerrainMesher := preload("res://scripts/terrain/marching_tetrahedra.gd")
const BrushEditState := preload("res://scripts/terrain/sdf_brush_edit_state.gd")
const BrushPicker := preload("res://scripts/terrain/terrain_brush_picker.gd")
const ChunkGrid := preload("res://scripts/terrain/terrain_chunk_grid.gd")

var assertion_count := 0
var failure_count := 0


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	_test_brush_field_contract()
	_test_edit_bounds_and_reset()
	_test_global_ledger_contract()
	_test_picker_contract()
	await _test_viewport_interaction()
	if failure_count == 0:
		print("TERRAIN_BRUSH_PASS: assertions=%d failures=0" % assertion_count)
	else:
		push_error("TERRAIN_BRUSH_FAIL: assertions=%d failures=%d" % [assertion_count, failure_count])
	quit(0 if failure_count == 0 else 1)


func _test_brush_field_contract() -> void:
	var region := Vector2i.ZERO
	var cave_center: Vector2 = TerrainField.cave_center(424242, region, 8.0)
	var open_point := Vector3(8.0, cave_center.y, cave_center.x)
	var baseline: float = TerrainField.sample_density(424242, region, open_point)
	var carve := BrushEditState.new()
	var fill := BrushEditState.new()
	_check(baseline < 0.0, "test carve point starts in empty field")
	_check(carve.add_sphere(BrushEditState.Mode.CARVE, open_point, 1.25), "carve operation is accepted")
	_check(fill.add_sphere(BrushEditState.Mode.FILL, open_point, 1.25), "fill operation is accepted")
	_check(carve.sample_density(424242, region, open_point) < baseline, "carve decreases density at brush center")
	_check(fill.sample_density(424242, region, open_point) > baseline, "fill increases density at brush center")
	var remote_point := Vector3(-40.0, -35.0, -40.0)
	_check(
		is_equal_approx(carve.sample_density(424242, region, remote_point), TerrainField.sample_density(424242, region, remote_point)),
		"brush leaves a distant sample unchanged"
	)
	var repeated := BrushEditState.new()
	repeated.add_sphere(BrushEditState.Mode.CARVE, open_point, 1.25)
	_check(
		is_equal_approx(repeated.sample_density(424242, region, open_point), carve.sample_density(424242, region, open_point)),
		"fixed seed and ordered edits produce repeatable samples"
	)
	var carve_then_fill := BrushEditState.new()
	carve_then_fill.add_sphere(BrushEditState.Mode.CARVE, open_point, 1.25)
	carve_then_fill.add_sphere(BrushEditState.Mode.FILL, open_point, 1.25)
	var fill_then_carve := BrushEditState.new()
	fill_then_carve.add_sphere(BrushEditState.Mode.FILL, open_point, 1.25)
	fill_then_carve.add_sphere(BrushEditState.Mode.CARVE, open_point, 1.25)
	_check(
		not is_equal_approx(
			carve_then_fill.sample_density(424242, region, open_point),
			fill_then_carve.sample_density(424242, region, open_point)
		),
		"brush operations replay in insertion order"
	)
	var canonical_before_section: float = carve.sample_density(424242, region, Vector3(8.0, 4.0, 8.0))
	var section_value: float = carve.sample_density(424242, region, Vector3(8.0, 4.0, 8.0), true)
	_check(canonical_before_section != section_value, "cave section changes only the visualization sample")
	_check(carve.get_edit_count() == 1, "visual cave section does not add or change brush edits")
	var snapshot: Array[Dictionary] = carve.get_operations_snapshot()
	snapshot[0]["radius"] = 99.0
	_check(carve.get_operations_snapshot()[0]["radius"] == 1.25, "edit snapshots do not expose mutable canonical state")
	var sculpt_mesh: Dictionary = TerrainMesher.build_mesh(424242, region, false, fill)
	var base_mesh: Dictionary = TerrainMesher.build_mesh(424242, region)
	var sculpt_vertices: PackedVector3Array = sculpt_mesh["mesh"].surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var base_vertices: PackedVector3Array = base_mesh["mesh"].surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	_check(sculpt_vertices != base_vertices, "applying a sphere edit changes rebuilt mesh vertices")
	_check(sculpt_mesh["triangle_count"] > 0 and sculpt_mesh["sample_count"] == base_mesh["sample_count"], "edited mesh remains bounded and nonempty")


func _test_edit_bounds_and_reset() -> void:
	var edits := BrushEditState.new()
	var center := Vector3(8.0, 4.5, 6.0)
	_check(not edits.add_sphere(BrushEditState.Mode.CARVE, center, BrushEditState.MIN_RADIUS - 0.01), "too-small radius is rejected")
	_check(not edits.add_sphere(BrushEditState.Mode.CARVE, center, BrushEditState.MAX_RADIUS + 0.01), "too-large radius is rejected")
	_check(not edits.add_sphere(99, center, 1.0), "unknown brush mode is rejected")
	_check(not edits.add_sphere(BrushEditState.Mode.CARVE, Vector3(INF, 0.0, 0.0), 1.0), "non-finite brush center is rejected")
	for _index in range(BrushEditState.MAX_EDITS):
		_check(edits.add_sphere(BrushEditState.Mode.CARVE, center, 1.0), "bounded edit slot is accepted")
	var count_before_rejection := edits.get_edit_count()
	_check(not edits.add_sphere(BrushEditState.Mode.FILL, center, 1.0), "edit count limit rejects the next operation")
	_check(edits.get_edit_count() == count_before_rejection, "rejected operation does not alter edit state")
	var sample_before_reset: float = edits.sample_density(424242, Vector2i.ZERO, center)
	var base_sample: float = TerrainField.sample_density(424242, Vector2i.ZERO, center)
	_check(not is_equal_approx(sample_before_reset, base_sample), "accepted edits affect the field before reset")
	edits.clear()
	_check(edits.get_edit_count() == 0, "reset clears the transient ordered edit list")
	_check(
		is_equal_approx(edits.sample_density(424242, Vector2i.ZERO, center), base_sample),
		"reset restores the original base density"
	)


func _test_picker_contract() -> void:
	var samples := [0]
	var all_empty := func(_point: Vector3) -> float:
		samples[0] += 1
		return -1.0
	var no_hit: Dictionary = BrushPicker.pick_surface(Vector3.ZERO, Vector3.DOWN, all_empty)
	_check(not no_hit["hit"], "ray with no field crossing reports no hit")
	_check(samples[0] == BrushPicker.MAX_STEPS + 1, "no-hit ray terminates at the fixed work limit")
	var non_finite := func(_point: Vector3) -> float:
		return NAN
	_check(not BrushPicker.pick_surface(Vector3.ZERO, Vector3.DOWN, non_finite)["hit"], "non-finite field sample fails closed")
	var sample_field := func(point: Vector3) -> float:
		return TerrainField.sample_density(424242, Vector2i.ZERO, point)
	var vertical_hit: Dictionary = BrushPicker.pick_surface(Vector3(8.0, 10.0, 6.0), Vector3.DOWN, sample_field)
	_check(vertical_hit["hit"], "fixed ray march finds the known terrain surface")
	if vertical_hit["hit"]:
		_check(TerrainMesher.contains_mesh_point(vertical_hit["position"]), "picked point belongs to the finite visible mesh bounds")
		_check(absf(TerrainField.sample_density(424242, Vector2i.ZERO, vertical_hit["position"])) < 0.02, "picked point is refined close to the field surface")


func _test_global_ledger_contract() -> void:
	var corner := BrushEditState.new(424242, TerrainField.GENERATOR_VERSION)
	_check(corner.add_sphere(BrushEditState.Mode.CARVE, Vector3(16.0, 4.0, 12.0), 1.25), "exact positive region corner accepts one canonical global command")
	var corner_op: Dictionary = corner.get_operations_snapshot()[0]
	var corner_regions: Array[Vector2i] = corner_op["affected_regions"]
	_check(corner_regions.size() == 4, "sphere support at an exact corner fans out to exactly four regions")
	_check(corner_regions.has(Vector2i(0, 0)) and corner_regions.has(Vector2i(1, 0)) and corner_regions.has(Vector2i(0, 1)) and corner_regions.has(Vector2i(1, 1)), "corner fanout includes the four half-open owners")
	_check(corner_op["operation_id"] == "sdf-v1-seed424242-seq0", "stable command ID derives only from seed, generator version and global sequence")
	_check(corner_op["sequence"] == 0 and corner_op["revision"] == 1, "first command has global sequence zero and revision one")
	var negative := BrushEditState.new(424242, TerrainField.GENERATOR_VERSION)
	_check(negative.add_sphere(BrushEditState.Mode.FILL, Vector3(0.0, 4.0, 0.0), 1.25), "exact zero corner accepts a negative-coordinate crossing command")
	var negative_regions: Array[Vector2i] = negative.get_operations_snapshot()[0]["affected_regions"]
	_check(negative_regions.size() == 4 and negative_regions.has(Vector2i(-1, -1)) and negative_regions.has(Vector2i(-1, 0)) and negative_regions.has(Vector2i(0, -1)) and negative_regions.has(Vector2i(0, 0)), "zero-corner fanout uses mathematical floor for all four signed keys")
	var boundary_left := negative.sample_density(424242, Vector2i(-1, -1), Vector3(16.0, 4.0, 12.0))
	var boundary_right := negative.sample_density(424242, Vector2i.ZERO, Vector3(0.0, 4.0, 0.0))
	_check(is_equal_approx(boundary_left, boundary_right), "global replay produces the same density at an exact shared border sample")
	var one_sided_support := BrushEditState.new(424242, TerrainField.GENERATOR_VERSION)
	_check(one_sided_support.add_sphere(BrushEditState.Mode.CARVE, Vector3(-2.0, -2.0, 6.0), 0.45), "small sphere can have support in only one region")
	_check(one_sided_support.get_operations_snapshot()[0]["affected_regions"] == [Vector2i(-1, 0)], "spatial fanout records only the region whose bounds intersect the sphere")
	_check(is_equal_approx(
		one_sided_support.sample_density(424242, Vector2i(-1, 0), Vector3(16.0, -2.0, 6.0)),
		one_sided_support.sample_density(424242, Vector2i.ZERO, Vector3(0.0, -2.0, 6.0))
	), "shared border samples agree even when the canonical sphere intersects only one region")
	var cloned := BrushEditState.new(424242, TerrainField.GENERATOR_VERSION)
	cloned.add_sphere(BrushEditState.Mode.FILL, Vector3(0.0, 4.0, 0.0), 1.25)
	_check(cloned.get_operations_snapshot()[0]["operation_id"] == negative.get_operations_snapshot()[0]["operation_id"], "same versioned command stream produces a deterministic operation ID")
	var bounded := BrushEditState.new(424242, TerrainField.GENERATOR_VERSION)
	for _index in range(BrushEditState.MAX_EDITS):
		_check(bounded.add_sphere(BrushEditState.Mode.CARVE, Vector3(8.0, 4.0, 6.0), 1.0), "bounded global ledger admits an operation")
	var before_reject := bounded.get_operations_snapshot()
	var revision_before_reject: int = bounded.revision
	var sequence_before_reject: int = bounded.get_last_sequence()
	_check(not bounded.add_sphere(BrushEditState.Mode.FILL, Vector3(8.0, 4.0, 6.0), 1.0), "global ledger rejects operation beyond fixed cap")
	_check(bounded.get_operations_snapshot() == before_reject and bounded.revision == revision_before_reject and bounded.get_last_sequence() == sequence_before_reject, "overflow rejection leaves log, revision, sequence and index unchanged")
	var before_reset_sequence: int = corner.get_last_sequence()
	var reset_result: Dictionary = corner.clear_for_region(Vector2i(0, 0))
	_check(reset_result["removed_count"] == 1 and reset_result["affected_regions"].size() == 4, "focused reset removes a cross-region command and returns all dependent regions")
	_check(corner.get_edit_count() == 0 and corner.get_region_edit_count(Vector2i(1, 1)) == 0, "focused reset clears the command from every spatial index bucket")
	_check(corner.add_sphere(BrushEditState.Mode.CARVE, Vector3(8.0, 4.0, 6.0), 1.0), "global ledger accepts a new command after focused reset")
	_check(corner.get_operations_snapshot()[0]["sequence"] == before_reset_sequence + 1, "focused reset never reuses a prior global sequence")


func _test_viewport_interaction() -> void:
	var packed := load("res://scenes/terrain_demo.tscn") as PackedScene
	_check(packed != null, "terrain scene loads for viewport edit test")
	if packed == null:
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	await _wait_for_region(scene, Vector2i.ZERO)
	var camera: Camera3D = scene.get_node("Camera3D")
	var world_state: RefCounted = scene.get("world_state")
	var edits: RefCounted = world_state.brush_edits
	var start_meshes := _snapshot_chunk_meshes(scene)
	var start_chunk_nodes := _snapshot_chunk_nodes(scene)
	_check(start_meshes.size() == ChunkGrid.CHUNK_COUNT_X * ChunkGrid.CHUNK_COUNT_Z, "scene publishes a region only after all its chunk jobs finish")
	_check(scene.get("last_mesh_diagnostics")["active_chunk_count"] == start_meshes.size(), "initial diagnostics report active chunk count")
	var viewport_size := root.get_visible_rect().size
	var click_position := viewport_size * 0.5
	var carve_click := InputEventMouseButton.new()
	carve_click.button_index = MOUSE_BUTTON_LEFT
	carve_click.pressed = true
	carve_click.position = click_position
	root.push_input(carve_click, true)
	await _wait_for_edit_transaction(scene)
	_check(edits.get_edit_count() == 1, "viewport-dispatched left click ray-picks and applies a carve edit")
	_check(scene.get("selected_brush_mode") == BrushEditState.Mode.CARVE, "left click selects carve mode")
	var carve_diagnostics: Dictionary = scene.get("last_mesh_diagnostics")
	var carved_meshes := _snapshot_chunk_meshes(scene)
	var dirty_ids: Array[String] = carve_diagnostics["remeshed_chunk_ids"]
	_check(carve_diagnostics["remeshed_chunk_count"] > 0, "accepted carve rebuilds affected chunk meshes")
	_check(carve_diagnostics["remeshed_chunk_count"] < start_meshes.size(), "accepted carve avoids a full-grid rebuild")
	_check(carve_diagnostics["elapsed_ms"] >= 0.0, "edit diagnostics include measured elapsed time")
	_check(carve_diagnostics["triangle_count"] > 0, "edit diagnostics include total triangle count")
	var replaced_dirty_meshes := 0
	var unchanged_clean_meshes := 0
	var preserved_chunk_nodes := 0
	var carve_geometry_changed := false
	for chunk_id in start_meshes:
		if start_chunk_nodes[chunk_id] == scene.get("chunk_nodes")[chunk_id]:
			preserved_chunk_nodes += 1
		var before_mesh: ArrayMesh = start_meshes[chunk_id]
		var after_mesh: ArrayMesh = carved_meshes[chunk_id]
		if dirty_ids.has(chunk_id):
			if before_mesh != after_mesh:
				replaced_dirty_meshes += 1
				if before_mesh.get_surface_count() > 0 and after_mesh.get_surface_count() > 0:
					var before_vertices: PackedVector3Array = before_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
					var after_vertices: PackedVector3Array = after_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
					carve_geometry_changed = carve_geometry_changed or before_vertices != after_vertices
		else:
			if before_mesh == after_mesh:
				unchanged_clean_meshes += 1
	_check(replaced_dirty_meshes == dirty_ids.size(), "every reported dirty chunk replaces its mesh")
	_check(unchanged_clean_meshes == start_meshes.size() - dirty_ids.size(), "unaffected chunk mesh objects remain unchanged")
	_check(preserved_chunk_nodes == start_chunk_nodes.size(), "localized rebuild preserves every chunk scene node instance")
	_check(carve_geometry_changed, "viewport carve changes generated chunk geometry")

	var fill_click := InputEventMouseButton.new()
	fill_click.button_index = MOUSE_BUTTON_LEFT
	fill_click.pressed = true
	fill_click.shift_pressed = true
	fill_click.position = click_position + Vector2(4.0, 0.0)
	root.push_input(fill_click, true)
	await _wait_for_edit_transaction(scene)
	_check(edits.get_edit_count() == 2, "viewport-dispatched Shift+left click applies fill")
	_check(scene.get("selected_brush_mode") == BrushEditState.Mode.FILL, "Shift+left click selects fill mode")
	var mode_label: String = scene.get_node("CanvasLayer/Status").text
	_check(mode_label.contains("Selected: FILL") and mode_label.contains("Global edits: 2/32"), "HUD reports selected mode and global edit count")

	var operations_before_section: Array[Dictionary] = edits.get_operations_snapshot()
	var section_event := InputEventKey.new()
	section_event.keycode = KEY_C
	section_event.pressed = true
	root.push_input(section_event)
	await _wait_for_global_rebuild(scene)
	_check(scene.get("cave_section_enabled"), "viewport C shortcut enables the visualization section")
	_check(edits.get_operations_snapshot() == operations_before_section, "C does not mutate canonical brush edits")
	var section_mesh: ArrayMesh = scene.get_node("TerrainChunks/Terrain").mesh
	_check(scene.get("last_mesh_diagnostics")["remeshed_chunk_count"] >= start_meshes.size(), "C rebuilds active chunks for the global visualization cut")

	var regenerate := InputEventKey.new()
	regenerate.keycode = KEY_R
	regenerate.pressed = true
	root.push_input(regenerate)
	await _wait_for_global_rebuild(scene)
	_check(edits.get_edit_count() == 2, "R regeneration retains accepted edits")
	_check(edits.get_operations_snapshot() == operations_before_section, "R preserves the ordered brush data")
	_check(scene.get_node("TerrainChunks/Terrain").mesh != section_mesh, "R rebuilds the finite mesh")
	_check(scene.get("last_mesh_diagnostics")["remeshed_chunk_count"] >= start_meshes.size(), "R regenerates active chunks")

	var initial_camera_position := camera.position
	var right_down := InputEventMouseButton.new()
	right_down.button_index = MOUSE_BUTTON_RIGHT
	right_down.pressed = true
	right_down.position = Vector2(30.0, 30.0)
	root.push_input(right_down, true)
	await process_frame
	var drag := InputEventMouseMotion.new()
	drag.position = Vector2(50.0, 40.0)
	drag.relative = Vector2(20.0, 10.0)
	drag.button_mask = MOUSE_BUTTON_MASK_RIGHT
	root.push_input(drag, true)
	await process_frame
	_check(not camera.position.is_equal_approx(initial_camera_position), "right-drag remains routed through viewport around the HUD")
	var right_up := InputEventMouseButton.new()
	right_up.button_index = MOUSE_BUTTON_RIGHT
	right_up.pressed = false
	right_up.position = Vector2(50.0, 40.0)
	root.push_input(right_up, true)
	await process_frame
	var distance_before_zoom: float = camera.position.distance_to(Vector3(8.0, 3.1, 6.0))
	var zoom_event := InputEventMouseButton.new()
	zoom_event.button_index = MOUSE_BUTTON_WHEEL_UP
	zoom_event.pressed = true
	zoom_event.position = click_position
	root.push_input(zoom_event, true)
	await process_frame
	_check(camera.position.distance_to(Vector3(8.0, 3.1, 6.0)) < distance_before_zoom, "wheel zoom remains functional through the viewport")

	var reset := InputEventKey.new()
	reset.keycode = KEY_X
	reset.pressed = true
	root.push_input(reset)
	await _wait_for_global_rebuild(scene)
	_check(edits.get_edit_count() == 0, "viewport X shortcut clears transient edits")
	_check(scene.get("cave_section_enabled"), "reset preserves cave-section visualization mode")
	_check(scene.get_node("TerrainChunks/Terrain").mesh != null, "reset rebuilds the base terrain")
	_check(scene.get("last_mesh_diagnostics")["remeshed_chunk_count"] >= start_meshes.size(), "X reset regenerates the visible region set")
	scene.queue_free()
	await process_frame


func _snapshot_chunk_meshes(scene: Node) -> Dictionary:
	var snapshot: Dictionary = {}
	var chunk_nodes: Dictionary = scene.get("chunk_nodes")
	for chunk_id in chunk_nodes:
		var chunk_node: MeshInstance3D = chunk_nodes[chunk_id]
		snapshot[chunk_id] = chunk_node.mesh
	return snapshot


func _snapshot_chunk_nodes(scene: Node) -> Dictionary:
	var snapshot: Dictionary = {}
	var chunk_nodes: Dictionary = scene.get("chunk_nodes")
	for chunk_id in chunk_nodes:
		snapshot[chunk_id] = chunk_nodes[chunk_id]
	return snapshot


func _wait_for_region(scene: Node, region_key: Vector2i) -> void:
	var id := "%d,%d" % [region_key.x, region_key.y]
	for _frame in range(600):
		if scene.get("active_regions").has(id):
			return
		await process_frame
	_check(scene.get("active_regions").has(id), "focused region completes incremental loading")


func _wait_for_region_stage(scene: Node, region_key: Vector2i) -> void:
	var id := "%d,%d" % [region_key.x, region_key.y]
	for _frame in range(600):
		if not scene.get("loading_regions").has(id):
			return
		await process_frame
	_check(not scene.get("loading_regions").has(id), "focused region staged mesh work completes")


func _wait_for_edit_transaction(scene: Node) -> void:
	for _frame in range(2000):
		if scene.get("_edit_transaction").is_empty():
			return
		await process_frame
	_check(scene.get("_edit_transaction").is_empty(), "global edit mesh transaction completes incrementally")


func _wait_for_global_rebuild(scene: Node) -> void:
	for _frame in range(2000):
		if not scene.get("global_rebuild_pending"):
			return
		await process_frame
	_check(not scene.get("global_rebuild_pending"), "global mesh rebuild completes incrementally")


func _check(condition: bool, label: String) -> void:
	assertion_count += 1
	if not condition:
		failure_count += 1
		push_error("ASSERTION FAILED: " + label)
