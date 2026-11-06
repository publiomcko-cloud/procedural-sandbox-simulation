extends SceneTree

const TerrainField := preload("res://scripts/terrain/sdf_world.gd")
const TerrainMesher := preload("res://scripts/terrain/marching_tetrahedra.gd")

var assertion_count := 0
var failure_count := 0

const ASYNC_WAIT_TIMEOUT_MSEC := 30000
const ASYNC_WORKER_YIELD_MSEC := 1


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
	var first_normals: PackedVector3Array = first_mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
	var second_vertices: PackedVector3Array = second_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	_check(first_vertices == second_vertices, "regeneration produces identical ordered mesh vertices")
	var normal_samples := 0
	var outward_samples := 0
	var triangle_stride: int = maxi(1, first_vertices.size() / 192)
	for vertex_index in range(0, first_vertices.size(), triangle_stride * 3):
		var point: Vector3 = first_vertices[vertex_index]
		var normal: Vector3 = first_normals[vertex_index].normalized()
		var toward_empty: float = TerrainField.sample_density(424242, Vector2i.ZERO, point + normal * 0.12)
		var toward_solid: float = TerrainField.sample_density(424242, Vector2i.ZERO, point - normal * 0.12)
		if toward_empty < toward_solid:
			outward_samples += 1
		normal_samples += 1
	_check(outward_samples >= int(normal_samples * 0.9), "mesh normals point from solid toward empty space")
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

	# Regression: publishing CPU data must not consume the source Dictionary.
	# Shared-surface cache entries can be read by multiple region owners.
	var reusable_cpu: Dictionary = TerrainMesher.build_chunk_cpu_data(
		424242, Vector2i.ZERO, Vector2i(1, 1), false, {}
	)
	var reusable_positions: PackedVector3Array = reusable_cpu.get("positions", PackedVector3Array()).duplicate()
	var reusable_normals: PackedVector3Array = reusable_cpu.get("normals", PackedVector3Array()).duplicate()
	var first_upload: Dictionary = TerrainMesher.mesh_from_cpu_data(reusable_cpu)
	var second_upload: Dictionary = TerrainMesher.mesh_from_cpu_data(reusable_cpu)
	_check(
		reusable_cpu.get("positions", PackedVector3Array()) == reusable_positions
		and reusable_cpu.get("normals", PackedVector3Array()) == reusable_normals,
		"ArrayMesh publication preserves reusable cached CPU positions and normals"
	)
	_check(
		first_upload.get("mesh", null) is ArrayMesh and second_upload.get("mesh", null) is ArrayMesh,
		"the same cached CPU mesh data can be published more than once"
	)


func _test_scene_contract() -> void:
	var packed := load("res://scenes/terrain_demo.tscn") as PackedScene
	_check(packed != null, "terrain demonstration scene loads")
	if packed == null:
		return
	var scene := packed.instantiate()
	_check(scene.get_node_or_null("TerrainChunks/Terrain") is MeshInstance3D, "demonstration scene has a terrain chunk mesh node")
	_check(scene.get_node_or_null("Camera3D") is Camera3D, "demonstration scene has a camera")
	_check(scene.get_node_or_null("DirectionalLight3D") is DirectionalLight3D, "demonstration scene has lighting")
	var directional := scene.get_node_or_null("DirectionalLight3D") as DirectionalLight3D
	if directional != null:
		_check(directional.rotation_degrees.x > 0.0 and directional.basis.z.y < 0.0, "directional key is oriented down onto terrain in the Compatibility renderer")
		_check(not directional.shadow_enabled, "directional shadow maps remain disabled after the visual cost comparison")
	var camera := scene.get_node_or_null("Camera3D") as Camera3D
	_check(camera != null and camera.get_node_or_null("ViewAlignedLight") is SpotLight3D, "camera carries an auxiliary view-aligned spotlight")
	if camera != null:
		var view_light := camera.get_node("ViewAlignedLight") as SpotLight3D
		_check(view_light.light_energy >= 12.0 and view_light.light_energy <= 16.0, "view-aligned fill has enough bounded energy to show at close inspection range")
		_check(view_light.spot_range == 72.0 and is_equal_approx(view_light.spot_attenuation, 1.0), "view-aligned fill keeps its broad cone range and natural distance falloff")
		_check(not view_light.shadow_enabled, "auxiliary light preserves the established shadow look and cost")
	_check(scene.get_node_or_null("CanvasLayer/Status") is Label, "demonstration scene explains its controls")
	var environment: Environment = scene.get_node("WorldEnvironment").environment
	_check(environment.ambient_light_source == Environment.AMBIENT_SOURCE_COLOR, "environment uses colored ambient lighting")
	_check(environment.ambient_light_sky_contribution == 0.0, "colored ambient light is not overridden by the sky")
	_check(environment.ambient_light_energy > 0.0 and environment.ambient_light_energy <= 1.25 and environment.ambient_light_color != Color.BLACK, "colored ambient fill stays below the directional key so terrain slopes retain contrast")
	if directional != null:
		_check(directional.light_energy > environment.ambient_light_energy, "directional key remains stronger than ambient fill")
	var material: StandardMaterial3D = scene.get_node("TerrainChunks/Terrain").material_override
	_check(material.albedo_color.g > material.albedo_color.r, "terrain material remains green")
	_check(material.shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED, "terrain remains affected by real lighting")
	var status: Label = scene.get_node("CanvasLayer/Status")
	_check(status.mouse_filter == Control.MOUSE_FILTER_IGNORE, "HUD does not consume viewport mouse input")
	scene.free()


func _test_demo_controls() -> void:
	var packed := load("res://scenes/terrain_demo.tscn") as PackedScene
	if packed == null:
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	await _wait_for_region(scene, Vector2i.ZERO)
	var initial_mesh: ArrayMesh = scene.get_node("TerrainChunks/Terrain").mesh
	_check(initial_mesh != null and initial_mesh.get_surface_count() == 1, "demo builds terrain when added to the scene tree")
	var camera: Camera3D = scene.get_node("Camera3D")
	var viewport: Viewport = root
	var initial_camera_position := camera.position
	var begin_orbit := InputEventMouseButton.new()
	begin_orbit.button_index = MOUSE_BUTTON_RIGHT
	begin_orbit.pressed = true
	begin_orbit.position = Vector2(30.0, 30.0)
	viewport.push_input(begin_orbit, true)
	await process_frame
	var drag := InputEventMouseMotion.new()
	drag.position = Vector2(50.0, 40.0)
	drag.relative = Vector2(20.0, 10.0)
	drag.button_mask = MOUSE_BUTTON_MASK_RIGHT
	viewport.push_input(drag, true)
	await process_frame
	_check(not camera.position.is_equal_approx(initial_camera_position), "right-drag routed through the viewport changes the inspection camera")
	var end_orbit := InputEventMouseButton.new()
	end_orbit.button_index = MOUSE_BUTTON_RIGHT
	end_orbit.pressed = false
	end_orbit.position = Vector2(50.0, 40.0)
	viewport.push_input(end_orbit, true)
	await process_frame
	var distance_before_zoom: float = camera.position.distance_to(Vector3(8.0, 3.1, 6.0))
	var zoom := InputEventMouseButton.new()
	zoom.button_index = MOUSE_BUTTON_WHEEL_UP
	zoom.pressed = true
	zoom.position = Vector2(50.0, 40.0)
	viewport.push_input(zoom, true)
	await process_frame
	_check(camera.position.distance_to(Vector3(8.0, 3.1, 6.0)) < distance_before_zoom, "mouse wheel zooms toward the terrain")
	var toggle := InputEventKey.new()
	toggle.keycode = KEY_C
	toggle.pressed = true
	viewport.push_input(toggle)
	await _wait_for_global_rebuild(scene)
	var section_mesh: ArrayMesh = scene.get_node("TerrainChunks/Terrain").mesh
	_check(scene.get("cave_section_enabled"), "C input enables the cave cross-section")
	_check(section_mesh != initial_mesh, "C input rebuilds the terrain mesh")
	_check(scene.get_node("CanvasLayer/Status").text.contains("Global cave section: ON"), "status label reports the global cave section state")
	var regenerate := InputEventKey.new()
	regenerate.keycode = KEY_R
	regenerate.pressed = true
	viewport.push_input(regenerate)
	await _wait_for_global_rebuild(scene)
	_check(scene.get("cave_section_enabled"), "R input preserves the current section mode")
	_check(scene.get_node("TerrainChunks/Terrain").mesh != section_mesh, "R input regenerates the mesh")
	scene.queue_free()
	await process_frame


func _wait_for_region(scene: Node, region_key: Vector2i) -> void:
	var region_id := "%d,%d" % [region_key.x, region_key.y]
	var deadline := Time.get_ticks_msec() + ASYNC_WAIT_TIMEOUT_MSEC
	while Time.get_ticks_msec() < deadline:
		if scene.get("active_regions").has(region_id):
			return
		await process_frame
		OS.delay_msec(ASYNC_WORKER_YIELD_MSEC)
	if not scene.get("active_regions").has(region_id):
		var stream: Node = scene.get_node_or_null("ProceduralObjects")
		print("TERRAIN_SDF_REGION_TIMEOUT: loading=%s queued=%s effect_status=%s object_error=%s object_perf=%s" % [
			str(scene.get("loading_regions")),
			str(scene.call("_queued_chunk_count")),
			str(scene.get("_terrain_effect_status")),
			String(stream.get_error_summary()) if stream != null and stream.has_method("get_error_summary") else "unavailable",
			str(stream.get_performance_snapshot()) if stream != null and stream.has_method("get_performance_snapshot") else "unavailable",
		])
	_check(scene.get("active_regions").has(region_id), "focused region completes its incremental load")


func _wait_for_global_rebuild(scene: Node) -> void:
	var deadline := Time.get_ticks_msec() + ASYNC_WAIT_TIMEOUT_MSEC
	while Time.get_ticks_msec() < deadline:
		if not scene.get("global_rebuild_pending"):
			return
		await process_frame
		OS.delay_msec(ASYNC_WORKER_YIELD_MSEC)
	if scene.get("global_rebuild_pending"):
		print("GLOBAL_REBUILD_TIMEOUT: stages=%d queued=%d targets=%s" % [scene.get("loading_regions").size(), scene.call("_queued_chunk_count"), scene.get("_full_rebuild_target_ids")])
	_check(not scene.get("global_rebuild_pending"), "global rebuild completes through incremental chunk jobs")


func _check(condition: bool, label: String) -> void:
	assertion_count += 1
	if not condition:
		failure_count += 1
		push_error("ASSERTION FAILED: " + label)
