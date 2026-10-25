extends SceneTree

const BrushPicker := preload("res://scripts/terrain/terrain_brush_picker.gd")
const SaveStore := preload("res://scripts/terrain/terrain_world_save_store.gd")
const Spatial := preload("res://scripts/terrain/terrain_spatial_ownership.gd")
const WorldState := preload("res://scripts/terrain/terrain_world_state.gd")
const ObjectStream := preload("res://scripts/objects/procedural_object_stream.gd")

var assertions := 0
var failures := 0
var fixture_root := ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	fixture_root = "user://p3_0d_placement_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(fixture_root))
	var previous_mouse_mode := Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var scene := await _create_isolated_scene()
	if scene == null:
		Input.mouse_mode = previous_mouse_mode
		_remove_fixture()
		quit(1)
		return
	var stream: Node = scene.get_node("ProceduralObjects")
	var viewport := scene.get_viewport()
	var camera: Camera3D = scene.get("camera")
	scene.set("orbit_target", Vector3(8.0, 8.0, 6.0))
	scene.set("orbit_offset", Vector3(12.0, 18.0, 14.0))
	scene.call("_update_camera")
	var visible_rect := viewport.get_visible_rect()
	var center := visible_rect.position + visible_rect.size * 0.5
	var pointer_offset := visible_rect.size.x * 0.04
	var left_screen := center + Vector2(-pointer_offset, 0.0)
	var right_screen := center + Vector2(pointer_offset, 0.0)
	var left_hit := _pick(scene, camera, left_screen)
	var right_hit := _pick(scene, camera, right_screen)
	_check(bool(left_hit.get("hit", false)) and bool(right_hit.get("hit", false)), "off-center viewport rays hit deterministic, irregular terrain surfaces")
	if not left_hit.get("hit", false) or not right_hit.get("hit", false):
		await _finish_scene(scene)
		Input.mouse_mode = previous_mouse_mode
		_remove_fixture()
		return
	var expected_left_mm := _to_mm(left_hit.position)
	var expected_right_mm := _to_mm(right_hit.position)
	_check(expected_left_mm != expected_right_mm, "distinct screen points produce distinct quantized world-space hits")
	var left_surface_density: float = scene.call("_sample_world_density", left_hit.position)
	var right_surface_density: float = scene.call("_sample_world_density", right_hit.position)
	_check(absf(left_surface_density) < 0.02 and absf(right_surface_density) < 0.02, "ray targets lie on sampled non-flat SDF terrain rather than a placement constant")
	var left_region: Vector2i = Spatial.world_to_region_local(Vector3(expected_left_mm) / 1000.0).region_key
	var right_region: Vector2i = Spatial.world_to_region_local(Vector3(expected_right_mm) / 1000.0).region_key
	var pointer_regions_ready := await _wait_region_published(scene, left_region) and await _wait_region_published(scene, right_region)
	_check(pointer_regions_ready, "both deterministic pointer-hit regions are published before their placements")
	var left_id := await _place_from_pointer(scene, left_screen)
	var left_record := _placed_record(stream, left_id)
	_check(not left_id.is_empty(), "B input at the left pointer accepts one placement")
	_check(_record_position(left_record) == expected_left_mm, "left-pointer command persists the exact millimeter-quantized SDF hit (expected=%s actual=%s)" % [expected_left_mm, _record_position(left_record)])
	_check(String(scene.get("_last_placement_aim_mode")) == "pointer", "visible-pointer placement reports pointer aim mode")
	var right_id := await _place_from_pointer(scene, right_screen)
	var right_record := _placed_record(stream, right_id)
	_check(not right_id.is_empty() and right_id != left_id, "a second B creates a distinct identity")
	_check(_record_position(right_record) == expected_right_mm, "right-pointer command persists its own SDF hit")
	var repeated_left_id := await _place_from_pointer(scene, left_screen)
	var repeated_left_record := _placed_record(stream, repeated_left_id)
	_check(repeated_left_id != left_id and _record_position(repeated_left_record) == _record_position(left_record), "repeated aim is stable and allows intentional overlap without jitter")
	var left_visible := await _wait_instance_count(stream, left_id, 1)
	var right_visible := await _wait_instance_count(stream, right_id, 1)
	var repeated_visible := await _wait_instance_count(stream, repeated_left_id, 1)
	_check(left_visible and right_visible and repeated_visible, "each accepted placement publishes exactly one visual for its stable identity (counts=%d/%d/%d errors=%s)" % [stream.get_instance_ids().count(left_id), stream.get_instance_ids().count(right_id), stream.get_instance_ids().count(repeated_left_id), stream.get_error_summary()])
	var marker: Node3D = scene.get_node_or_null("PlacementTargetMarker")
	_check(marker != null and marker.visible and marker.global_position.distance_to(Vector3(left_hit.position)) < 0.1, "visual target indicator marks the same surface hit used by B")
	_assert_global_local_transform(stream, left_id, left_record)

	# A logical viewport resize checks that the picker consumes viewport coordinates,
	# rather than window pixels or a hard-coded placement coordinate.
	var original_viewport_size: Vector2i = viewport.size
	viewport.size = Vector2i(original_viewport_size.x * 3 / 2, original_viewport_size.y * 3 / 2)
	await process_frame
	var scaled_center := viewport.get_visible_rect().get_center()
	var scaled_pointer := scaled_center + Vector2(-viewport.get_visible_rect().size.x * 0.12, 0.0)
	var scaled_hit := _pick(scene, camera, scaled_pointer)
	var scaled_id := await _place_from_pointer(scene, scaled_pointer)
	var scaled_record := _placed_record(stream, scaled_id)
	_check(scaled_hit.get("hit", false) and _record_position(scaled_record) == _to_mm(scaled_hit.position), "scaled viewport coordinates round-trip through input, ray projection and persisted anchor")
	viewport.size = original_viewport_size
	await process_frame

	# Undo/redo must preserve the same explicit placement record and identity.
	var undo_summary: Dictionary = stream.get_entity_command_service().get_history_summary().get("undo", {})
	await _wait_command_ready(scene)
	var undo_result: Dictionary = stream.dispatch_entity_command(_history_command(scene, "ENTITY_UNDO", String(undo_summary.get("history_entry_id", "")), scaled_id))
	_check(undo_result.get("ok", false), "Undo removes the latest placement transactionally (%s)" % undo_result.get("reason", "ok"))
	_check(await _wait_instance_count(stream, scaled_id, 0), "Undo removes only the target identity's visual")
	var redo_summary: Dictionary = stream.get_entity_command_service().get_history_summary().get("redo", {})
	await _wait_command_ready(scene)
	var redo_result: Dictionary = stream.dispatch_entity_command(_history_command(scene, "ENTITY_REDO", String(redo_summary.get("history_entry_id", "")), scaled_id))
	var redo_visible := await _wait_instance_count(stream, scaled_id, 1)
	_check(redo_result.get("ok", false) and redo_visible, "Redo reconstructs the same identity once (%s; count=%d; errors=%s)" % [redo_result.get("reason", "ok"), stream.get_instance_ids().count(scaled_id), stream.get_error_summary()])
	_check(_placed_record(stream, scaled_id) == scaled_record, "Undo/redo preserves exact persisted placement bytes")
	await _wait_command_ready(scene)
	var delete_result: Dictionary = stream.dispatch_entity_command(_entity_command(scene, "ENTITY_DELETE", repeated_left_id))
	_check(delete_result.get("ok", false) and await _wait_instance_count(stream, repeated_left_id, 0), "delete hides only the selected explicit entity")
	await _wait_command_ready(scene)
	var restore_result: Dictionary = stream.dispatch_entity_command(_entity_command(scene, "ENTITY_RESTORE", repeated_left_id))
	var restored_visible := await _wait_instance_count(stream, repeated_left_id, 1)
	_check(restore_result.get("ok", false) and restored_visible, "restore recovers the same identity without a duplicate visual (%s; count=%d; errors=%s)" % [restore_result.get("reason", "ok"), stream.get_instance_ids().count(repeated_left_id), stream.get_error_summary()])

	# A sky ray and a real terrain hit in a not-yet-published distant region both fail closed.
	var snapshot_before_rejections: Dictionary = stream.state_service.snapshot.duplicate(true)
	var selected_before_rejections := String(scene.get("_selected_object_id"))
	var revision_before_no_hit: int = stream.get_command_world_revision()
	scene.set("orbit_target", Vector3(8.0, 80.0, 6.0))
	scene.set("orbit_offset", Vector3(12.0, -18.0, 14.0))
	scene.call("_update_camera")
	await _press_b_at(scene, center)
	_check(stream.get_command_world_revision() == revision_before_no_hit and stream.state_service.snapshot == snapshot_before_rejections and String(scene.get("_selected_object_id")) == selected_before_rejections and String(scene.get("_object_state_action_status")).contains("no terrain surface"), "no-surface rejection has no command, revision, selection or persistent state side effect")
	var distant_target := Vector3(1000.0, 8.0, 1000.0)
	scene.set("orbit_target", distant_target)
	scene.set("orbit_offset", Vector3(12.0, 18.0, 14.0))
	scene.call("_update_camera")
	var distant_hit := _pick(scene, camera, center)
	var distant_region: Vector2i = Spatial.world_to_region_local(Vector3(_to_mm(distant_hit.get("position", Vector3.ZERO))) / 1000.0).region_key if distant_hit.get("hit", false) else Vector2i.ZERO
	_check(distant_hit.get("hit", false) and not stream.has_published_region(distant_region), "unpublished-region rejection fixture has a valid hit in an unpublished region")
	var revision_before_unpublished: int = stream.get_command_world_revision()
	await _press_b_at(scene, center)
	_check(stream.get_command_world_revision() == revision_before_unpublished and stream.state_service.snapshot == snapshot_before_rejections and String(scene.get("_selected_object_id")) == selected_before_rejections and String(scene.get("_object_state_action_status")).contains("not fully published"), "valid but unpublished target is rejected without command, selection or persistent mutation")

	# The positive and negative region planes use floor ownership after millimeter quantization.
	var positive_surface_y := _surface_height(scene, 16.0, 6.0)
	scene.set("orbit_target", Vector3(16.0, positive_surface_y, 6.0))
	scene.set("orbit_offset", Vector3(0.05, 18.0, 0.05))
	scene.call("_update_camera")
	var positive_region_ready := await _wait_region_published(scene, Vector2i(1, 0))
	_check(positive_region_ready, "positive boundary target region is fully published before placement")
	var positive_screen := viewport.get_visible_rect().get_center()
	var positive_hit := _pick(scene, camera, positive_screen)
	var positive_id := await _place_from_pointer(scene, positive_screen)
	var positive_record := _placed_record(stream, positive_id)
	var positive_owner: Vector2i = Spatial.world_to_region_local(Vector3(_record_position(positive_record)) / 1000.0).region_key
	_check(positive_hit.get("hit", false) and not positive_id.is_empty() and positive_owner == Vector2i(1, 0), "quantized hit on the positive X region plane belongs to region (1,0)")
	_assert_global_local_transform(stream, positive_id, positive_record)

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var negative_surface_y := _surface_height(scene, -16.0, -12.0)
	scene.set("orbit_target", Vector3(-16.0, negative_surface_y + 0.05, -12.0))
	scene.set("orbit_offset", Vector3(0.05, 18.0, 0.05))
	scene.call("_update_camera")
	var negative_screen := viewport.get_visible_rect().get_center()
	var negative_region_ready := await _wait_region_published(scene, Vector2i(-1, -1))
	_check(negative_region_ready, "negative boundary region becomes fully published before placement")
	var center_aim: Dictionary = scene.call("_placement_aim_for_cursor", false, negative_screen, viewport.get_visible_rect())
	_check(center_aim.get("mode") == "center" and center_aim.get("screen_position") == negative_screen, "hidden/captured cursor policy explicitly falls back to the viewport center")
	var negative_hit := _pick(scene, camera, negative_screen)
	var negative_id := await _place_from_pointer(scene, negative_screen)
	var negative_record := _placed_record(stream, negative_id)
	var negative_position_mm := _record_position(negative_record)
	var negative_owner: Vector2i = Spatial.world_to_region_local(Vector3(negative_position_mm) / 1000.0).region_key
	_check(negative_hit.get("hit", false) and not negative_id.is_empty() and negative_owner == Vector2i(-1, -1), "captured-center hit at negative X/Z region planes uses floor-based owner (-1,-1)")
	_assert_global_local_transform(stream, negative_id, negative_record)

	# Move far enough to unload the edited region, then revisit it and check identity uniqueness.
	scene.set("orbit_target", Vector3(64.0, 8.0, 6.0))
	scene.call("_update_camera")
	var unloaded := await _wait_region_unpublished(scene, Vector2i(-1, -1))
	_check(unloaded and not stream.get_instance_ids().has(negative_id), "streaming unload removes the negative-region visual while retaining its persistent identity")
	scene.set("orbit_target", Vector3(-16.0, negative_surface_y + 0.05, -12.0))
	scene.call("_update_camera")
	var revisited := await _wait_region_published(scene, Vector2i(-1, -1))
	await _wait_command_ready(scene)
	_check(revisited and stream.get_instance_ids().count(negative_id) == 1, "unload/revisit reconstructs exactly one visual for the same placement ID")
	var persisted_negative_position: Array = _placed_record(stream, negative_id).get("position_mm", [])
	_check(persisted_negative_position == negative_record.get("position_mm", []), "unload/revisit preserves the exact world-space anchor")

	await _finish_scene(scene)
	await _verify_stream_restart(negative_id, negative_position_mm)
	Input.mouse_mode = previous_mouse_mode
	_remove_fixture()
	print("P3_0D_PLACEMENT_%s: assertions=%d failures=%d" % ["PASS" if failures == 0 else "FAIL", assertions, failures])
	quit(0 if failures == 0 else 1)


func _create_isolated_scene() -> Node3D:
	var scene: Node3D = load("res://scenes/terrain_demo.tscn").instantiate()
	scene.set("world_save_store", SaveStore.new(fixture_root.path_join("terrain")))
	scene.set("object_state_directory_override", ProjectSettings.globalize_path(fixture_root.path_join("entities")))
	var package_roots: Array[String] = []
	scene.set("object_package_roots_override", package_roots)
	root.add_child(scene)
	if not await _wait_for_scene_publication(scene):
		_check(false, "isolated scene publishes its initial terrain and entity region")
		await _finish_scene(scene)
		return null
	var stream: Node = scene.get_node("ProceduralObjects")
	if not stream.is_entity_command_ready():
		scene.call("_handle_entity_schema_migration")
		scene.call("_handle_entity_schema_migration")
	if not await _wait_command_ready(scene):
		_check(false, "disposable entity state explicitly migrates to schema 3 before placement")
		await _finish_scene(scene)
		return null
	_check(true, "isolated scene is published and the schema-3 command service is ready")
	return scene


func _verify_stream_restart(entity_id: String, expected_position_mm: Vector3i) -> void:
	var restarted_stream: Node = ObjectStream.new()
	root.add_child(restarted_stream)
	var package_roots: Array[String] = []
	var initialized: Dictionary = restarted_stream.initialize(424242, "sandbox-default", package_roots, ProjectSettings.globalize_path(fixture_root.path_join("entities")))
	_check(initialized.get("ok", false), "fresh object-stream service reopens the isolated persisted entity store")
	if not initialized.get("ok", false):
		restarted_stream.queue_free()
		await process_frame
		return
	var region_key := Vector2i(-1, -1)
	var terrain_state: RefCounted = WorldState.new(424242, region_key)
	var publication: Dictionary = restarted_stream.publish_region(region_key, terrain_state)
	_check(publication.get("ok", false), "fresh stream reconstructs the persisted region from authoritative state")
	var record := _placed_record(restarted_stream, entity_id)
	_check(restarted_stream.get_instance_ids().count(entity_id) == 1, "restart publication contains exactly one visual for the same placement identity")
	_check(_record_position(record) == expected_position_mm, "restart keeps the exact global millimeter anchor")
	_assert_global_local_transform(restarted_stream, entity_id, record)
	restarted_stream.queue_free()
	await process_frame


func _wait_for_scene_publication(scene: Node) -> bool:
	for _frame in range(4000):
		await process_frame
		var active: Dictionary = scene.get("active_regions")
		var stream: Node = scene.get_node("ProceduralObjects")
		if active.has("0,0") and stream.has_published_region(Vector2i.ZERO):
			return true
	return false


func _wait_command_ready(scene: Node) -> bool:
	var stream: Node = scene.get_node("ProceduralObjects")
	for _frame in range(1600):
		await process_frame
		if stream.is_entity_command_ready():
			return true
	return false


func _place_from_pointer(scene: Node, screen_position: Vector2) -> String:
	var command_ready := await _wait_command_ready(scene)
	if not command_ready:
		print("PLACEMENT_DIAGNOSTIC: command service not ready; status=%s stream=%s" % [scene.get("_object_state_action_status"), scene.get_node("ProceduralObjects").get_performance_snapshot()])
		return ""
	var initial_revision: int = scene.get_node("ProceduralObjects").get_command_world_revision()
	await _press_b_at(scene, screen_position)
	var stream: Node = scene.get_node("ProceduralObjects")
	if stream.get_command_world_revision() == initial_revision:
		print("PLACEMENT_DIAGNOSTIC: pointer=%s viewport=%s aim=%s status=%s revision=%d" % [screen_position, scene.get_viewport().get_mouse_position(), scene.call("_placement_aim"), scene.get("_object_state_action_status"), initial_revision])
		return ""
	var id := String(scene.get("_selected_object_id"))
	if id.is_empty():
		print("PLACEMENT_DIAGNOSTIC: pointer=%s viewport=%s aim=%s status=%s" % [screen_position, scene.get_viewport().get_mouse_position(), scene.call("_placement_aim"), scene.get("_object_state_action_status")])
	if not id.is_empty():
		await _wait_instance_count(stream, id, 1)
		await _wait_command_ready(scene)
	return id


func _surface_height(scene: Node, world_x: float, world_z: float) -> float:
	var lower := 0.0
	var upper := 12.0
	for _iteration in range(40):
		var middle := (lower + upper) * 0.5
		if float(scene.call("_sample_world_density", Vector3(world_x, middle, world_z))) >= 0.0:
			lower = middle
		else:
			upper = middle
	return (lower + upper) * 0.5


func _press_b_at(scene: Node, screen_position: Vector2) -> void:
	var viewport: Viewport = scene.get_viewport()
	var motion := InputEventMouseMotion.new()
	motion.position = screen_position
	motion.global_position = screen_position
	viewport.push_input(motion)
	await process_frame
	var key := InputEventKey.new()
	key.keycode = KEY_B
	key.physical_keycode = KEY_B
	key.pressed = true
	viewport.push_input(key)
	await process_frame
	key = InputEventKey.new()
	key.keycode = KEY_B
	key.physical_keycode = KEY_B
	key.pressed = false
	viewport.push_input(key)
	await process_frame


func _wait_instance_count(stream: Node, entity_id: String, expected_count: int) -> bool:
	for _frame in range(500):
		await process_frame
		if stream.get_instance_ids().count(entity_id) == expected_count:
			return true
	return false


func _wait_region_published(scene: Node, region_key: Vector2i) -> bool:
	for _frame in range(4000):
		await process_frame
		var active: Dictionary = scene.get("active_regions")
		var stream: Node = scene.get_node("ProceduralObjects")
		if active.has("%d,%d" % [region_key.x, region_key.y]) and stream.has_published_region(region_key):
			return true
	return false


func _wait_region_unpublished(scene: Node, region_key: Vector2i) -> bool:
	for _frame in range(4000):
		await process_frame
		var active: Dictionary = scene.get("active_regions")
		var stream: Node = scene.get_node("ProceduralObjects")
		if not active.has("%d,%d" % [region_key.x, region_key.y]) and not stream.has_published_region(region_key):
			return true
	return false


func _pick(scene: Node, camera: Camera3D, screen_position: Vector2) -> Dictionary:
	var origin := camera.project_ray_origin(screen_position)
	var direction := camera.project_ray_normal(screen_position)
	return BrushPicker.pick_sdf_v1_surface(origin, direction, Callable(scene, "_sample_world_density"))


func _placed_record(stream: Node, entity_id: String) -> Dictionary:
	if entity_id.is_empty():
		return {}
	return stream.state_service.snapshot.get("placed_entities", {}).get(entity_id, {}).duplicate(true)


func _record_position(record: Dictionary) -> Vector3i:
	var values: Array = record.get("position_mm", [])
	if values.size() != 3:
		return Vector3i(2147483647, 2147483647, 2147483647)
	return Vector3i(int(values[0]), int(values[1]), int(values[2]))


func _find_node(stream: Node, entity_id: String) -> Node3D:
	for region_root in stream.get_children():
		for node in region_root.get_children():
			if node is Node3D and node.get_meta("stable_instance_id", "") == entity_id:
				return node
	return null


func _assert_global_local_transform(stream: Node, entity_id: String, record: Dictionary) -> void:
	var position_mm := _record_position(record)
	var expected_world := Vector3(position_mm) / 1000.0
	var owner: Vector2i = Spatial.world_to_region_local(expected_world).region_key
	var region_origin: Vector3 = Spatial.region_origin_world(owner)
	var node := _find_node(stream, entity_id)
	_check(node != null, "visual node exists for %s" % entity_id)
	if node == null:
		return
	var summary: Dictionary = stream.get_entity_summary(entity_id)
	_check(Vector2i(summary.get("region_key", Vector2i(2147483647, 2147483647))) == owner, "persisted identity owner equals floor-based world owner")
	_check(node.position.distance_to(expected_world - region_origin) < 0.001, "region-local node position is global anchor minus region origin")
	_check(node.get_parent().global_position.distance_to(region_origin) < 0.001 and node.global_position.distance_to(expected_world) < 0.001, "region root plus local node transform applies the world anchor exactly once")


func _entity_command(scene: Node, operation: String, entity_id: String) -> Dictionary:
	var state: Object = scene.get_node("ProceduralObjects").state_service
	return {"schema_version": 1, "command_id": _uuid(), "operation": operation, "origin": {"type": "player", "id": "local.player"}, "world_id": state.world_id, "world_seed": state.world_seed, "generator_version": state.generator_version, "expected_world_revision": state.get_revision(), "expected_entity_revision": state.get_entity_revision(entity_id), "entity_id": entity_id}


func _history_command(scene: Node, operation: String, history_entry_id: String, entity_id: String) -> Dictionary:
	var result := _entity_command(scene, operation, entity_id)
	result["history_entry_id"] = history_entry_id
	return result


func _uuid() -> String:
	var hex := Crypto.new().generate_random_bytes(16).hex_encode()
	return "%s-%s-%s-%s-%s" % [hex.substr(0, 8), hex.substr(8, 4), hex.substr(12, 4), hex.substr(16, 4), hex.substr(20, 12)]


func _to_mm(position: Vector3) -> Vector3i:
	return Vector3i(roundi(position.x * 1000.0), roundi(position.y * 1000.0), roundi(position.z * 1000.0))


func _finish_scene(scene: Node) -> void:
	if is_instance_valid(scene):
		scene.queue_free()
		await process_frame
		await process_frame


func _remove_fixture() -> void:
	_remove_tree(ProjectSettings.globalize_path(fixture_root))


func _remove_tree(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	while true:
		var child := dir.get_next()
		if child.is_empty():
			break
		if child == "." or child == "..":
			continue
		var child_path := path.path_join(child)
		if dir.current_is_dir():
			_remove_tree(child_path)
		else:
			DirAccess.remove_absolute(child_path)
	dir.list_dir_end()
	dir = null
	DirAccess.remove_absolute(path)


func _check(condition: bool, message: String) -> void:
	assertions += 1
	if condition:
		print("PASS: %s" % message)
	else:
		failures += 1
		push_error("FAIL: %s" % message)
