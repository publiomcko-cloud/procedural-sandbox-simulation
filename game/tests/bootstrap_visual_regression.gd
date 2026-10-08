extends SceneTree

var assertion_count := 0
var failure_count := 0


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	_test_project_entry()
	_test_instantiated_bootstrap()
	if failure_count == 0:
		print("BOOTSTRAP_STRUCTURE_PASS: assertions=%d failures=0; rendered pixels are not assessed" % assertion_count)
	else:
		push_error("BOOTSTRAP_STRUCTURE_FAIL: assertions=%d failures=%d" % [assertion_count, failure_count])
	quit(0 if failure_count == 0 else 1)


func _test_project_entry() -> void:
	_check(
		ProjectSettings.get_setting("application/run/main_scene", "") == "res://scenes/main.tscn",
		"configured project entry points at the bootstrap scene"
	)
	_check(
		ProjectSettings.get_setting("rendering/renderer/rendering_method", "") == "gl_compatibility",
		"bootstrap uses the configured Compatibility renderer"
	)


func _test_instantiated_bootstrap() -> void:
	var packed_scene := load("res://scenes/main.tscn") as PackedScene
	_check(packed_scene != null, "main scene loads as PackedScene")
	if packed_scene == null:
		return
	var scene := packed_scene.instantiate() as Node3D
	_check(scene != null, "main scene instantiates as Node3D")
	if scene == null:
		return
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1152, 648)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	viewport.add_child(scene)

	var camera := scene.get_node_or_null("Camera3D") as Camera3D
	_check(camera != null, "bootstrap scene contains its Camera3D")
	if camera != null:
		_check(camera.current and camera.is_current(), "bootstrap camera is enabled and current")
		_check(camera.is_visible_in_tree(), "bootstrap camera is in the active scene tree")
		_check(not camera.is_position_behind(Vector3.ZERO), "camera faces the reference mesh at the origin")
		var viewport_size := camera.get_viewport().get_visible_rect().size
		var projected_origin := camera.unproject_position(Vector3.ZERO)
		_check(viewport_size.x > 0.0 and viewport_size.y > 0.0, "runtime viewport has a non-zero size")
		_check(
			projected_origin.distance_to(viewport_size * 0.5) < 2.0,
			"reference mesh origin projects to the viewport center"
		)
		print("BOOTSTRAP_CAMERA_DIAGNOSTIC: position=%s forward=%s viewport=%s projected_origin=%s" % [
			camera.global_position,
			-camera.global_transform.basis.z,
			viewport_size,
			projected_origin,
		])

	var cube := scene.get_node_or_null("BootstrapReferenceCube") as MeshInstance3D
	_check(cube != null, "bootstrap script instantiates the reference MeshInstance3D")
	if cube != null:
		_check(cube.is_visible_in_tree(), "reference mesh is visible in the scene tree")
		_check(cube.mesh is BoxMesh, "reference mesh uses a BoxMesh")
		_check(cube.mesh.get_aabb().size.is_equal_approx(Vector3.ONE), "reference box has non-zero unit bounds")
		_check(cube.global_position.is_equal_approx(Vector3.ZERO), "reference mesh is positioned at the camera target")
		print("BOOTSTRAP_MESH_DIAGNOSTIC: visible=%s mesh=%s bounds=%s position=%s material=%s" % [
			cube.is_visible_in_tree(),
			cube.mesh,
			cube.mesh.get_aabb(),
			cube.global_position,
			cube.material_override,
		])

	var light := scene.get_node_or_null("DirectionalLight3D") as DirectionalLight3D
	_check(light != null, "bootstrap scene contains a DirectionalLight3D")
	if light != null:
		_check(light.is_visible_in_tree() and light.light_energy > 0.0, "directional light is enabled with positive energy")
		_check((-light.global_transform.basis.z).y < 0.0, "directional light points down toward the reference mesh")


func _check(condition: bool, label: String) -> void:
	assertion_count += 1
	if not condition:
		failure_count += 1
		push_error("ASSERTION FAILED: " + label)
