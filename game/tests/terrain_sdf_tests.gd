extends SceneTree

const TerrainField := preload("res://scripts/terrain/sdf_world.gd")
const TerrainMesher := preload("res://scripts/terrain/marching_tetrahedra.gd")

var assertion_count := 0
var failure_count := 0


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	_test_field_contract()
	_test_mesh_generation()
	_test_scene_contract()
	await _test_demo_controls()
	if failure_count == 0:
		print("TERRAIN_SDF_PASS: assertions=%d failures=0" % assertion_count)
	else:
		push_error("TERRAIN_SDF_FAIL: assertions=%d failures=%d" % [assertion_count, failure_count])
	quit(0 if failure_count == 0 else 1)


func _test_field_contract() -> void:
	var region := Vector2i(2, -1)
	var sample_position := Vector3(5.25, 2.75, 7.5)
	var sample_a: float = TerrainField.sample_density(424242, region, sample_position)
	var sample_b: float = TerrainField.sample_density(424242, region, sample_position)
	_check(TerrainField.GENERATOR_VERSION == 1, "generator version is explicit and stable")
	_check(is_equal_approx(sample_a, sample_b), "fixed seed and coordinates produce repeatable samples")
	_check(absf(sample_a - 0.288093626) < 0.00001, "version 1 sample matches its golden value")
	_check(not is_equal_approx(sample_a, TerrainField.sample_density(424243, region, sample_position)), "seed changes terrain samples")
	var elevation_a: float = TerrainField.sample_density(424242, Vector2i.ZERO, Vector3(2.0, 6.0, 3.0))
	var elevation_b: float = TerrainField.sample_density(424242, Vector2i.ZERO, Vector3(12.0, 6.0, 10.0))
	_check(not is_equal_approx(elevation_a, elevation_b), "surface elevations vary across the region")
	var cave_center: Vector2 = TerrainField.cave_center(424242, Vector2i.ZERO, 8.0)
	var cave_sample := Vector3(8.0, cave_center.y, cave_center.x)
	var cave_density: float = TerrainField.sample_density(424242, Vector2i.ZERO, cave_sample)
	_check(cave_density < 0.0, "cave center is an empty SDF sample")
	var roof_density: float = TerrainField.sample_density(
		424242, Vector2i.ZERO, Vector3(8.0, cave_center.y + 1.5, cave_center.x)
	)
	_check(roof_density > 0.0, "solid terrain remains above the cave")
	var edge_a: float = TerrainField.sample_density(424242, Vector2i.ZERO, Vector3(16.0, 2.0, 4.0))
	var edge_b: float = TerrainField.sample_density(424242, Vector2i(1, 0), Vector3(0.0, 2.0, 4.0))
	_check(is_equal_approx(edge_a, edge_b), "neighboring regions agree at their shared world coordinate")
	var beyond_a: float = TerrainField.sample_density(424242, Vector2i.ZERO, Vector3(16.25, 2.0, 4.0))
	var beyond_b: float = TerrainField.sample_density(424242, Vector2i(1, 0), Vector3(0.25, 2.0, 4.0))
	_check(is_equal_approx(beyond_a, beyond_b), "neighbor regions remain continuous across their boundary")
	var cut_density: float = TerrainField.sample_density(424242, Vector2i.ZERO, Vector3(8.0, 3.0, 8.0), true)
	_check(cut_density < 0.0, "cross-section removes the configured half-space")


func _test_mesh_generation() -> void:
	var first: Dictionary = TerrainMesher.build_mesh(424242, Vector2i.ZERO)
	var second: Dictionary = TerrainMesher.build_mesh(424242, Vector2i.ZERO)
	var first_mesh: ArrayMesh = first["mesh"]
	var second_mesh: ArrayMesh = second["mesh"]
	_check(first["sample_count"] > 1000, "bounded mesher samples a finite 3D grid")
	_check(first["triangle_count"] > 0 and first["vertex_count"] > 0, "SDF produces visible triangle geometry")
	_check(first_mesh.get_surface_count() == 1, "nonempty output is a single triangle surface")
	var first_vertices: PackedVector3Array = first_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var second_vertices: PackedVector3Array = second_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	_check(first_vertices == second_vertices, "regeneration produces identical ordered mesh vertices")
	var has_cave_surface := false
	for vertex in first_vertices:
		var center: Vector2 = TerrainField.cave_center(424242, Vector2i.ZERO, vertex.x)
		var radial_distance := Vector2(vertex.y - center.y, vertex.z - center.x).length()
		if absf(radial_distance - 0.92) < 0.18 and vertex.x > 1.0 and vertex.x < 15.0:
			has_cave_surface = true
			break
	_check(has_cave_surface, "extracted mesh contains the internal cave wall")
	var cut: Dictionary = TerrainMesher.build_mesh(424242, Vector2i.ZERO, true)
	var cut_mesh: ArrayMesh = cut["mesh"]
	_check(cut["triangle_count"] > 0, "cave cross-section remains a renderable mesh")
	var cut_vertices: PackedVector3Array = cut_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	_check(cut_vertices != first_vertices, "cross-section rebuild changes the generated surface")


func _test_scene_contract() -> void:
	var packed := load("res://scenes/terrain_demo.tscn") as PackedScene
	_check(packed != null, "terrain demonstration scene loads")
	if packed == null:
		return
	var scene := packed.instantiate()
	_check(scene.get_node_or_null("Terrain") is MeshInstance3D, "demonstration scene has a terrain mesh node")
	_check(scene.get_node_or_null("Camera3D") is Camera3D, "demonstration scene has a camera")
	_check(scene.get_node_or_null("DirectionalLight3D") is DirectionalLight3D, "demonstration scene has lighting")
	_check(scene.get_node_or_null("CanvasLayer/Status") is Label, "demonstration scene explains its controls")
	scene.free()


func _test_demo_controls() -> void:
	var packed := load("res://scenes/terrain_demo.tscn") as PackedScene
	if packed == null:
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	await process_frame
	var initial_mesh: ArrayMesh = scene.get_node("Terrain").mesh
	_check(initial_mesh != null and initial_mesh.get_surface_count() == 1, "demo builds terrain when added to the scene tree")
	var camera: Camera3D = scene.get_node("Camera3D")
	var initial_camera_position := camera.position
	var begin_orbit := InputEventMouseButton.new()
	begin_orbit.button_index = MOUSE_BUTTON_RIGHT
	begin_orbit.pressed = true
	scene.call("_unhandled_input", begin_orbit)
	var drag := InputEventMouseMotion.new()
	drag.relative = Vector2(20.0, -5.0)
	scene.call("_unhandled_input", drag)
	_check(not camera.position.is_equal_approx(initial_camera_position), "right-drag changes the inspection camera")
	var distance_before_zoom: float = camera.position.distance_to(Vector3(8.0, 3.1, 6.0))
	var zoom := InputEventMouseButton.new()
	zoom.button_index = MOUSE_BUTTON_WHEEL_UP
	zoom.pressed = true
	scene.call("_unhandled_input", zoom)
	_check(camera.position.distance_to(Vector3(8.0, 3.1, 6.0)) < distance_before_zoom, "mouse wheel zooms toward the terrain")
	var toggle := InputEventKey.new()
	toggle.keycode = KEY_C
	toggle.pressed = true
	scene.call("_unhandled_input", toggle)
	var section_mesh: ArrayMesh = scene.get_node("Terrain").mesh
	_check(scene.get("cave_section_enabled"), "C input enables the cave cross-section")
	_check(section_mesh != initial_mesh, "C input rebuilds the terrain mesh")
	_check(scene.get_node("CanvasLayer/Status").text.contains("Cave section: ON"), "status label reports the cave section state")
	var regenerate := InputEventKey.new()
	regenerate.keycode = KEY_R
	regenerate.pressed = true
	scene.call("_unhandled_input", regenerate)
	_check(scene.get("cave_section_enabled"), "R input preserves the current section mode")
	_check(scene.get_node("Terrain").mesh != section_mesh, "R input regenerates the mesh")
	scene.queue_free()
	await process_frame


func _check(condition: bool, label: String) -> void:
	assertion_count += 1
	if not condition:
		failure_count += 1
		push_error("ASSERTION FAILED: " + label)
