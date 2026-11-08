extends SceneTree

const MaterializedStore := preload("res://scripts/terrain/terrain_materialized_sdf_store.gd")
const Spatial := preload("res://scripts/terrain/terrain_spatial_ownership.gd")
const Field := preload("res://scripts/terrain/sdf_world.gd")
const RuntimeScript := preload("res://scripts/simulation/simulation_runtime.gd")
const DomainScript := preload("res://scripts/simulation/material_environment_domain.gd")
const RegistryScript := preload("res://scripts/modding/content_definition_registry.gd")

const WAIT_TIMEOUT_MSEC := 90000
const WORKER_YIELD_MSEC := 1
const TRAVERSAL_STEPS := 6
const PROFILE_ID := "p4h.environment:temperate"

var assertions := 0
var failures := 0
var fixture_root := ""
var package_path := ""
var evidence: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	fixture_root = "user://p4_0h_%d" % Time.get_ticks_usec()
	package_path = "user://mods/p4_0h_environment"
	_remove_tree(ProjectSettings.globalize_path(fixture_root))
	_remove_tree(ProjectSettings.globalize_path(package_path))
	_write_material_package()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(fixture_root))

	await _test_max_resident_runtime()
	await _test_real_scene_campaign()

	_remove_tree(ProjectSettings.globalize_path(package_path))
	_remove_tree(ProjectSettings.globalize_path(fixture_root))
	print("P4_0H_EVIDENCE=" + JSON.stringify(evidence, "", true, true))
	if failures == 0:
		print("P4_0H_FINAL_PASS: assertions=%d failures=0" % assertions)
		quit(0)
	else:
		push_error("P4_0H_FINAL_FAIL: assertions=%d failures=%d" % [assertions, failures])
		quit(1)


func _test_max_resident_runtime() -> void:
	var fixture := _registry_fixture()
	var registry: ContentDefinitionRegistry = fixture["registry"]
	var runtime: SimulationRuntime = RuntimeScript.new()
	_check(runtime.initialize_runtime(100000, 4, 0, false, 2, 128).get("ok", false), "25-scope runtime initializes")
	_check(runtime.configure_material_environment(registry, PROFILE_ID, 32, 128).get("ok", false), "25-scope material bridge configures")
	_check(runtime.configure_world_scope_lifecycle(PROFILE_ID, 25, 16000, 12000, 128).get("ok", false), "25-scope lifecycle configures")
	_check(runtime.update_world_scope_focus(Vector2i.ZERO).get("ok", false), "25-scope focus configures")
	for z in range(-2, 3):
		for x in range(-2, 3):
			var published := runtime.publish_world_region_scope(Vector2i(x, z), 0)
			_check(published.get("ok", false), "bounded scope %d,%d publishes" % [x, z])
	var rejected := runtime.publish_world_region_scope(Vector2i(3, 0), 0)
	_check(rejected.get("reason", "") == "world_scope_resident_limit_reached", "26th resident fails closed")
	var frames := 0
	while frames < 16:
		var frame := runtime.process_elapsed_usec(0)
		_check(frame.get("ok", false), "25-scope initialization frame %d succeeds" % frames)
		if runtime.get_persistence_preflight().get("ok", false):
			break
		frames += 1
	var lifecycle := runtime.get_world_scope_lifecycle_metrics()
	var material := runtime.get_material_environment_metrics()
	_check(int(lifecycle.get("resident_count", 0)) == 25, "maximum resident set reaches exactly 25")
	_check(int(lifecycle.get("peak_resident_scopes", 0)) == 25, "maximum resident telemetry is exactly 25")
	_check(int(material.get("queue", {}).get("pending_count", -1)) == 0, "25-scope initialization backlog drains")
	_check(runtime.get_persistence_preflight().get("ok", false), "25-scope authority reaches quiescent persistence boundary")
	evidence["max_resident"] = {
		"resident_count": int(lifecycle.get("resident_count", 0)),
		"initialization_frames": frames + 1,
		"queue_metrics": material.get("queue", {}),
	}
	runtime.free()


func _test_real_scene_campaign() -> void:
	var paths := _scene_paths()
	var packed := load("res://scenes/terrain_demo.tscn") as PackedScene
	_check(packed != null, "terrain demo scene loads")
	if packed == null:
		return

	var scene: Node3D = _instantiate_scene(packed, paths)
	var cold_started := Time.get_ticks_usec()
	root.add_child(scene)
	var initial_ok := await _wait_stream_idle(scene, Vector2i.ZERO)
	var cold_usec := Time.get_ticks_usec() - cold_started
	_check(initial_ok, "cold scene reaches stable published focus with P4 lifecycle")
	if not initial_ok:
		await _finish_scene(scene)
		return

	var runtime: SimulationRuntime = scene.get_node("SimulationRuntime")
	_check(runtime.get_material_environment_metrics().get("enabled", false), "real scene auto-binds discovered mod-first material profile")
	var initial_lifecycle := runtime.get_world_scope_lifecycle_metrics()
	_check(int(initial_lifecycle.get("resident_count", 0)) > 0, "cold scene publishes resident P4 scopes")
	var origin_before := runtime.get_simulation_scope("region:0,0")
	_check(origin_before.get("state", {}).has("material_environment"), "origin has real material/environment state")

	var forward_usec: Array[int] = []
	for x in range(1, TRAVERSAL_STEPS + 1):
		var started := Time.get_ticks_usec()
		scene.call("_move_focus", Vector3(Spatial.REGION_SIZE_X, 0.0, 0.0))
		var ok := await _wait_stream_idle(scene, Vector2i(x, 0))
		forward_usec.append(Time.get_ticks_usec() - started)
		_check(ok, "forward streaming step %d stabilizes" % x)
		if not ok:
			await _finish_scene(scene)
			return

	var warm_return_usec: Array[int] = []
	for x in range(TRAVERSAL_STEPS - 1, -1, -1):
		var started := Time.get_ticks_usec()
		scene.call("_move_focus", Vector3(-Spatial.REGION_SIZE_X, 0.0, 0.0))
		var ok := await _wait_stream_idle(scene, Vector2i(x, 0))
		warm_return_usec.append(Time.get_ticks_usec() - started)
		_check(ok, "warm revisit step %d stabilizes" % x)
		if not ok:
			await _finish_scene(scene)
			return

	var origin_after_revisit := runtime.get_simulation_scope("region:0,0")
	_check(not origin_after_revisit.is_empty(), "warm revisit reuses original deterministic scope")
	_check(
		String(origin_after_revisit.get("state", {}).get("material_environment", {}).get("profile_id", "")) == PROFILE_ID,
		"warm revisit preserves material profile identity"
	)
	_check(
		int(origin_after_revisit.get("state_revision", -1)) >= int(origin_before.get("state_revision", -1)),
		"warm revisit preserves monotonic authoritative state revision"
	)

	var fast_started := Time.get_ticks_usec()
	scene.call("_move_focus", Vector3(Spatial.REGION_SIZE_X * 8.0, 0.0, 0.0))
	var fast_ok := await _wait_stream_idle(scene, Vector2i(8, 0))
	var fast_usec := Time.get_ticks_usec() - fast_started
	_check(fast_ok, "eight-region fast movement converges without unbounded catch-up")
	var fast_lifecycle := runtime.get_world_scope_lifecycle_metrics()
	_check(int(fast_lifecycle.get("resident_count", 0)) <= 25, "fast movement respects resident cap")
	_check(int(runtime.get_material_environment_metrics().get("queue", {}).get("pending_count", -1)) == 0, "fast movement material queue drains")

	var back_started := Time.get_ticks_usec()
	scene.call("_move_focus", Vector3(-Spatial.REGION_SIZE_X * 8.0, 0.0, 0.0))
	var back_ok := await _wait_stream_idle(scene, Vector2i.ZERO)
	var fast_return_usec := Time.get_ticks_usec() - back_started
	_check(back_ok, "fast return to origin stabilizes")

	_check(runtime.set_simulation_paused(true).get("ok", false), "simulation pauses before save/restart qualification")
	_check(await _wait_simulation_quiescent(scene), "paused simulation reaches quiescent save boundary")

	var target_x := 7.25
	var target_z := 3.0
	var target := Vector3(target_x, _surface_height(scene, target_x, target_z), target_z)
	var edit_ok: bool = scene.call("_accept_brush_at_world", target)
	_check(edit_ok, "real terrain edit accepted before durable save")
	_check(await _wait_transaction(scene), "terrain edit becomes coherently visible before save")

	var save_queued: bool = scene.call("_save_world_to_storage")
	_check(save_queued, "real world save/checkpoint accepted")
	_check(await _wait_persistence_commit(scene), "terrain and simulation sidecar commit coherently")
	var saved_terrain_generation := int(scene.get("_checkpoint_generation"))
	var saved_simulation_generation := int(scene.get("_simulation_storage_generation"))
	var saved_snapshot := runtime.get_runtime_snapshot()
	var saved_scope := runtime.get_simulation_scope("region:0,0")
	_check(saved_terrain_generation > 0, "real save creates nonzero terrain generation")
	_check(saved_simulation_generation > 0, "real save creates nonzero simulation sidecar generation")
	_check(int(scene.get("_pending_simulation_save_terrain_generation")) < 0, "no simulation save remains pending")

	var scene_perf: Dictionary = scene.get("last_mesh_diagnostics").duplicate(true)
	var final_stream_error := String(scene.get("last_stream_error"))
	var final_lifecycle := runtime.get_world_scope_lifecycle_metrics()
	evidence["scene"] = {
		"cold_start_usec": cold_usec,
		"forward_step_usec": forward_usec,
		"warm_return_step_usec": warm_return_usec,
		"fast_jump_usec": fast_usec,
		"fast_return_usec": fast_return_usec,
		"forward_p50_usec": _percentile(forward_usec, 0.50),
		"forward_p95_usec": _percentile(forward_usec, 0.95),
		"warm_p50_usec": _percentile(warm_return_usec, 0.50),
		"warm_p95_usec": _percentile(warm_return_usec, 0.95),
		"peak_process_work_ms": float(scene.get("_peak_process_work_ms")),
		"peak_frame_ms": float(scene.get("_peak_frame_ms")),
		"frame_time_p95_ms": float(scene_perf.get("frame_time_p95_ms", 0.0)),
		"frame_time_p99_ms": float(scene_perf.get("frame_time_p99_ms", 0.0)),
		"lifecycle": final_lifecycle,
		"saved_terrain_generation": saved_terrain_generation,
		"saved_simulation_generation": saved_simulation_generation,
	}

	_check(final_stream_error.is_empty(), "final streaming campaign has no terrain stream error")
	_check(int(final_lifecycle.get("peak_resident_scopes", 0)) <= 25, "real scene never exceeds P4 resident cap")
	_check(float(scene.get("_peak_process_work_ms")) <= 50.0, "real scene main process peak remains below 50 ms qualification ceiling")
	_check(float(scene_perf.get("frame_time_p99_ms", 0.0)) <= 50.0, "real scene frame p99 remains below 50 ms qualification ceiling")

	await _finish_scene(scene)

	var restarted: Node3D = _instantiate_scene(packed, paths)
	var restart_started := Time.get_ticks_usec()
	root.add_child(restarted)
	var restart_ok := await _wait_stream_idle(restarted, Vector2i.ZERO)
	var restart_usec := Time.get_ticks_usec() - restart_started
	_check(restart_ok, "fresh terrain scene instance restarts from saved world")
	if not restart_ok:
		await _finish_scene(restarted)
		return

	var restarted_runtime: SimulationRuntime = restarted.get_node("SimulationRuntime")
	var restored_scope := restarted_runtime.get_simulation_scope("region:0,0")
	_check(int(restarted.get("_checkpoint_generation")) == saved_terrain_generation, "restart loads exact terrain generation")
	_check(int(restarted.get("_simulation_storage_generation")) == saved_simulation_generation, "restart loads matching simulation sidecar generation")
	_check(bool(restarted_runtime.get_scheduler_snapshot().get("paused", false)), "scheduler pause authority survives restart")
	_check(
		int(restarted_runtime.get_scheduler_snapshot().get("current_tick", -1))
			== int(saved_snapshot.get("scheduler", {}).get("current_tick", -2)),
		"scheduler logical tick survives real restart"
	)
	_check(not restored_scope.is_empty(), "restored scene reconstructs origin scope")
	_check(
		restored_scope.get("state", {}).get("material_environment", {})
			== saved_scope.get("state", {}).get("material_environment", {}),
		"material/environment authority survives real save/restart/load"
	)
	_check(
		String(restarted.get("_simulation_persistence_status")).contains("Loaded simulation generation"),
		"restart reports matched simulation sidecar load"
	)
	evidence["restart"] = {
		"restart_usec": restart_usec,
		"terrain_generation": int(restarted.get("_checkpoint_generation")),
		"simulation_generation": int(restarted.get("_simulation_storage_generation")),
		"scheduler_tick": int(restarted_runtime.get_scheduler_snapshot().get("current_tick", -1)),
		"resident_count": int(restarted_runtime.get_world_scope_lifecycle_metrics().get("resident_count", 0)),
	}

	await _finish_scene(restarted)


func _instantiate_scene(packed: PackedScene, paths: Dictionary) -> Node3D:
	var scene := packed.instantiate() as Node3D
	scene.set("world_save_store", MaterializedStore.new(String(paths["terrain"])))
	scene.set("simulation_state_directory_override", String(paths["simulation"]))
	scene.set("object_state_directory_override", String(paths["objects"]))
	scene.set("terrain_effect_directory_override", String(paths["effects"]))
	var roots: Array[String] = ["res://mods/first-party", "user://mods"]
	scene.set("object_package_roots_override", roots)
	return scene


func _scene_paths() -> Dictionary:
	var base := ProjectSettings.globalize_path(fixture_root)
	return {
		"terrain": base.path_join("terrain"),
		"simulation": base.path_join("simulation"),
		"objects": base.path_join("objects"),
		"effects": base.path_join("effects"),
	}


func _wait_stream_idle(scene: Node, expected_focus: Vector2i) -> bool:
	var deadline := Time.get_ticks_msec() + WAIT_TIMEOUT_MSEC
	var stream: Node = scene.get_node("ProceduralObjects")
	var runtime: SimulationRuntime = scene.get_node("SimulationRuntime")
	var expected_id := "%d,%d" % [expected_focus.x, expected_focus.y]
	var stable_frames := 0
	while Time.get_ticks_msec() < deadline:
		await process_frame
		OS.delay_msec(WORKER_YIELD_MSEC)
		var active: Dictionary = scene.get("active_regions")
		var loading: Dictionary = scene.get("loading_regions")
		var mesh_jobs: Dictionary = scene.get("_mesh_jobs")
		var stream_perf: Dictionary = stream.get_performance_snapshot()
		var material_pending := int(
			runtime.get_material_environment_metrics().get("queue", {}).get(
				"pending_count", 0
			)
		)
		var router_pending := int(runtime.get_simulation_router_metrics().get("pending_count", 0))
		var stable: bool = (
			active.has(expected_id)
			and stream.has_published_region(expected_focus)
			and loading.is_empty()
			and mesh_jobs.is_empty()
			and int(stream_perf.get("pending_region_publication_count", 0)) == 0
			and material_pending == 0
			and router_pending == 0
			and not bool(scene.get("global_rebuild_pending"))
		)
		if stable:
			stable_frames += 1
			if stable_frames >= 3:
				return true
		else:
			stable_frames = 0
	print("P4_0H_STREAM_TIMEOUT: expected=%s focus=%s active=%d loading=%d mesh_jobs=%d material_pending=%d router_pending=%d stream_error=%s sim=%s" % [
		expected_focus,
		scene.get("focus_region_key"),
		(scene.get("active_regions") as Dictionary).size(),
		(scene.get("loading_regions") as Dictionary).size(),
		(scene.get("_mesh_jobs") as Dictionary).size(),
		int(runtime.get_material_environment_metrics().get("queue", {}).get("pending_count", 0)),
		int(runtime.get_simulation_router_metrics().get("pending_count", 0)),
		String(scene.get("last_stream_error")),
		str(runtime.get_world_scope_lifecycle_metrics()),
	])
	return false


func _wait_simulation_quiescent(scene: Node) -> bool:
	var deadline := Time.get_ticks_msec() + WAIT_TIMEOUT_MSEC
	var runtime: SimulationRuntime = scene.get_node("SimulationRuntime")
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if runtime.get_persistence_preflight().get("ok", false):
			return true
	return false


func _wait_transaction(scene: Node) -> bool:
	var deadline := Time.get_ticks_msec() + WAIT_TIMEOUT_MSEC
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if (
			(scene.get("_edit_transaction") as Dictionary).is_empty()
			and not bool(scene.get("global_rebuild_pending"))
			and (scene.get("loading_regions") as Dictionary).is_empty()
		):
			return true
	return false


func _wait_persistence_commit(scene: Node) -> bool:
	var deadline := Time.get_ticks_msec() + WAIT_TIMEOUT_MSEC
	while Time.get_ticks_msec() < deadline:
		await process_frame
		OS.delay_msec(WORKER_YIELD_MSEC)
		if (
			int(scene.get("_checkpoint_task_id")) < 0
			and int(scene.get("_pending_simulation_save_terrain_generation")) < 0
			and int(scene.get("_checkpoint_generation")) > 0
			and int(scene.get("_simulation_storage_generation")) > 0
			and not bool(scene.get("_simulation_persistence_blocked"))
		):
			return true
	return false


func _surface_height(scene: Node, world_x: float, world_z: float) -> float:
	var low := Field.MIN_Y
	var high := 7.0
	for _iteration in range(30):
		var middle := (low + high) * 0.5
		var density: float = scene.call(
			"_sample_world_density", Vector3(world_x, middle, world_z)
		)
		if density >= 0.0:
			low = middle
		else:
			high = middle
	return (low + high) * 0.5


func _registry_fixture() -> Dictionary:
	var domain: MaterialEnvironmentDomain = DomainScript.new()
	var registry: ContentDefinitionRegistry = RegistryScript.new()
	registry.register_engine_content_type_handler(domain.create_content_handler())
	var registered := registry.discover_and_register(["user://mods"])
	_check(registered.get("ok", false), "25-scope fixture discovers environment mod")
	return {"registry": registry, "domain": domain}


func _write_material_package() -> void:
	var env_dir := ProjectSettings.globalize_path(package_path.path_join("environment"))
	DirAccess.make_dir_recursive_absolute(env_dir)
	var manifest := {
		"id": "p4h.environment",
		"version": "1.0.0",
		"schema_version": 1,
		"requires_engine": "4.7.2",
		"dependencies": [],
		"content_roots": ["environment/"],
		"script_policy": "data_only",
	}
	var profile := {
		"schema_version": 1,
		"type": DomainScript.PROFILE_TYPE,
		"id": PROFILE_ID,
		"ambient_temperature_milli_c": 18000,
		"relaxation_milli_per_due_step": 125,
	}
	_write_text(
		package_path.path_join("manifest.json"),
		JSON.stringify(manifest, "  ", true, true)
	)
	_write_text(
		package_path.path_join("environment/temperate.json"),
		JSON.stringify(profile, "  ", true, true)
	)


func _write_text(path: String, value: String) -> void:
	var absolute := ProjectSettings.globalize_path(path)
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	var file := FileAccess.open(absolute, FileAccess.WRITE)
	if file == null:
		_check(false, "fixture file opens: " + path)
		return
	file.store_string(value)
	file.flush()
	file.close()


func _percentile(values: Array[int], fraction: float) -> int:
	if values.is_empty():
		return 0
	var sorted := values.duplicate()
	sorted.sort()
	var index := clampi(
		ceili(float(sorted.size()) * fraction) - 1, 0, sorted.size() - 1
	)
	return int(sorted[index])


func _finish_scene(scene: Node) -> void:
	if is_instance_valid(scene):
		scene.queue_free()
		await process_frame
		OS.delay_msec(20)


func _remove_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	var directory := DirAccess.open(path)
	if directory == null:
		return
	directory.list_dir_begin()
	while true:
		var name := directory.get_next()
		if name.is_empty():
			break
		var child := path.path_join(name)
		if directory.current_is_dir():
			_remove_tree(child)
		else:
			DirAccess.remove_absolute(child)
	directory.list_dir_end()
	DirAccess.remove_absolute(path)


func _check(condition: bool, description: String) -> void:
	assertions += 1
	if condition:
		print("PASS: " + description)
	else:
		failures += 1
		push_error("FAIL: " + description)
