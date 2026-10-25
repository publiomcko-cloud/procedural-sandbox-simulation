extends SceneTree

const HarnessScene := preload("res://scenes/entity_command_harness.tscn")

var assertions := 0
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var harness: Node = HarnessScene.instantiate()
	root.add_child(harness)
	await process_frame
	await process_frame
	var state_service: Object = harness.get("state_service")
	var command_service: Object = harness.get("command_service")
	var nodes: Dictionary = harness.get("_object_nodes")
	_check(state_service != null and command_service != null, "scene input test starts the real harness services")
	_check(nodes.is_empty() and String(harness.get("selected_id")).is_empty(), "scene starts empty so two P inputs create exactly two explicit entities")

	_push_key(KEY_P, KEY_P)
	await process_frame
	var first_id := String(harness.get("selected_id"))
	var first_node: Node3D = (harness.get("_object_nodes") as Dictionary).get(first_id)
	_push_key(KEY_P, KEY_P)
	await process_frame
	var second_id := String(harness.get("selected_id"))
	nodes = harness.get("_object_nodes")
	var second_node: Node3D = nodes.get(second_id)
	var snapshot: Dictionary = state_service.get("snapshot")
	_check(not first_id.is_empty() and not second_id.is_empty() and first_id != second_id, "two viewport P events create distinct identities")
	_check(nodes.size() == 2 and snapshot.get("placed_entities", {}).size() == 2, "two P events commit exactly two placements without a startup extra")
	_check(first_node != null and first_node.visible and second_node != null and second_node.visible, "both placed entities have visible scene nodes")
	_check(String(harness.get("selected_id")) == second_id, "most recently placed entity remains selected")

	var before_delete_world_revision := int(state_service.get_revision())
	_push_key(KEY_NONE, KEY_DELETE)
	await process_frame
	snapshot = state_service.get("snapshot")
	_check(snapshot.get("deleted", {}).has(second_id), "physical-key-only Delete reaches ENTITY_DELETE and persists its tombstone")
	_check(int(state_service.get_revision()) == before_delete_world_revision + 1 and int(state_service.get_entity_revision(second_id)) == 2, "successful delete advances world and entity revisions once")
	_check(second_node != null and not second_node.visible and first_node != null and first_node.visible, "delete hides only the selected second entity")
	_check((harness.get("_object_nodes") as Dictionary).size() == 2 and String(harness.get("selected_id")) == second_id, "delete retains the same node and selection for exact restoration")
	_check(String(harness.get("_operation_label").text).begins_with("Logically deleted %s" % second_id), "HUD confirms committed logical deletion")

	var deleted_snapshot := snapshot.duplicate(true)
	var deleted_node_visible := second_node.visible
	_push_key(KEY_DELETE, KEY_DELETE)
	await process_frame
	snapshot = state_service.get("snapshot")
	_check(String(harness.get("_operation_label").text).contains("ENTITY_DELETE rejected: entity_already_deleted"), "rejected duplicate delete reports its exact reason in the HUD")
	_check(snapshot == deleted_snapshot and second_node.visible == deleted_node_visible and first_node.visible, "rejected command leaves persistent and visual state unchanged")

	_push_key(KEY_NONE, KEY_R)
	await process_frame
	snapshot = state_service.get("snapshot")
	_check(not snapshot.get("deleted", {}).has(second_id), "physical-key-only R removes the exact selected tombstone")
	_check(int(state_service.get_revision()) == before_delete_world_revision + 2 and int(state_service.get_entity_revision(second_id)) == 3, "restore advances revisions once without resetting entity history")
	_check(second_node.visible and first_node.visible and String(harness.get("selected_id")) == second_id, "R restores the selected entity and leaves its sibling unchanged")
	_check((harness.get("_object_nodes") as Dictionary).size() == 2 and (harness.get("_object_nodes") as Dictionary)[second_id] == second_node, "restore reuses the same Node3D without duplicating the entity")
	_check(String(harness.get("_operation_label").text).begins_with("Restored %s" % second_id), "HUD confirms successful restoration")

	var storage_root := String(harness.get("_storage_root"))
	harness.queue_free()
	await process_frame
	_check(not DirAccess.dir_exists_absolute(storage_root), "scene teardown removes only its unique harness state directory")
	if failures == 0:
		print("ENTITY_COMMAND_HARNESS_PASS: assertions=%d failures=0" % assertions)
	else:
		push_error("ENTITY_COMMAND_HARNESS_FAIL: assertions=%d failures=%d" % [assertions, failures])
	quit(0 if failures == 0 else 1)


func _push_key(keycode: int, physical_keycode: int) -> void:
	var event := InputEventKey.new()
	event.pressed = true
	event.keycode = keycode
	event.physical_keycode = physical_keycode
	root.get_viewport().push_input(event)


func _check(condition: bool, description: String) -> void:
	assertions += 1
	if condition:
		print("PASS: %s" % description)
	else:
		failures += 1
		push_error("FAIL: %s" % description)
