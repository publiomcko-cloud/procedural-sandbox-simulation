extends SceneTree

const DemoScript := preload("res://scripts/terrain/terrain_demo.gd")

var assertions := 0
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var demo: Node3D = DemoScript.new()
	var test_camera := Camera3D.new()
	var test_ui := CanvasLayer.new()
	var test_status := Label.new()
	var test_marker := MeshInstance3D.new()
	test_camera.position = Vector3(10.0, 8.0, 12.0)
	test_camera.rotation = Vector3(-0.2, 0.35, 0.0)
	test_ui.visible = true

	demo.set("camera", test_camera)
	demo.set("ui_layer", test_ui)
	demo.set("status_label", test_status)
	demo.set("_placement_target_marker", test_marker)
	demo.set("_placement_target_valid", true)

	var previous_mouse_mode := Input.mouse_mode
	var toggle_event := InputEventKey.new()
	toggle_event.keycode = KEY_F10
	toggle_event.pressed = true
	demo.call("_unhandled_input", toggle_event)
	_check(bool(demo.get("free_explore_enabled")), "F10 input enters free exploration")
	_check(not test_ui.visible, "free exploration hides the entire HUD canvas")
	_check(
		Input.mouse_mode == (previous_mouse_mode if DisplayServer.get_name() == "headless" else Input.MOUSE_MODE_CAPTURED),
		"free exploration captures the mouse when a display backend is available"
	)
	demo.call("_update_placement_marker_visual")
	_check(not test_marker.visible, "free exploration hides the placement marker for a clean view")

	var key_event := InputEventKey.new()
	key_event.keycode = KEY_W
	_check(bool(demo.call("_is_free_explore_movement_key", key_event)), "W is consumed by continuous free-flight movement")
	key_event.keycode = KEY_SPACE
	_check(bool(demo.call("_is_free_explore_movement_key", key_event)), "Space is consumed as free-flight ascent")
	key_event.keycode = KEY_SHIFT
	_check(bool(demo.call("_is_free_explore_movement_key", key_event)), "Shift is consumed as free-flight descent")
	key_event.keycode = KEY_F10
	_check(bool(demo.call("_event_matches_key", key_event, KEY_F10)), "F10 is the dedicated free-exploration toggle")

	var before_look := test_camera.rotation
	demo.call("_apply_free_explore_look", Vector2(80.0, -32.0))
	_check(not test_camera.rotation.is_equal_approx(before_look), "captured mouse motion rotates the free camera")

	var before_forward := test_camera.global_position
	demo.call("_apply_free_explore_motion", Vector3(0.0, 0.0, -1.0), 1.0, false)
	var normal_distance := test_camera.global_position.distance_to(before_forward)
	_check(absf(normal_distance - DemoScript.FREE_EXPLORE_SPEED) < 0.01, "W movement uses the configured free-flight speed")
	_check(Vector3(demo.get("orbit_target")).is_equal_approx(test_camera.global_position), "streaming focus follows the free camera position")

	var before_boost := test_camera.global_position
	demo.call("_apply_free_explore_motion", Vector3(1.0, 0.0, 0.0), 1.0, true)
	var boosted_distance := test_camera.global_position.distance_to(before_boost)
	_check(
		absf(boosted_distance - DemoScript.FREE_EXPLORE_SPEED * DemoScript.FREE_EXPLORE_BOOST_MULTIPLIER) < 0.01,
		"Ctrl boost applies the configured creative-flight multiplier"
	)

	var final_free_position := test_camera.global_position
	demo.call("_set_free_explore_enabled", false)
	_check(not bool(demo.get("free_explore_enabled")), "free exploration exits cleanly")
	_check(test_ui.visible, "exiting free exploration restores the prior HUD visibility")
	_check(Input.mouse_mode == previous_mouse_mode, "exiting free exploration restores the prior mouse mode")
	_check(test_camera.global_position.is_equal_approx(final_free_position), "exiting free exploration preserves the explored camera position")
	_check(test_marker.visible, "exiting free exploration restores the valid placement marker")

	Input.mouse_mode = previous_mouse_mode
	demo.free()
	test_camera.free()
	test_ui.free()
	test_status.free()
	test_marker.free()

	if failures == 0:
		print("FREE_EXPLORATION_MODE_PASS: assertions=%d failures=0" % assertions)
	else:
		push_error("FREE_EXPLORATION_MODE_FAIL: assertions=%d failures=%d" % [assertions, failures])
	quit(0 if failures == 0 else 1)


func _check(condition: bool, label: String) -> void:
	assertions += 1
	if condition:
		print("PASS: " + label)
	else:
		failures += 1
		push_error("FAIL: " + label)
