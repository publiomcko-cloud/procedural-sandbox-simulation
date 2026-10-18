extends SceneTree

const DEMO_SCENE := preload("res://scenes/terrain_demo.tscn")
const INITIAL_ORBIT := Vector3(34.0, 24.0, 40.0)
const CLOSE_ORBIT := Vector3(2.0, 5.0, 14.0)
const CAVE_TARGET := Vector3(8.0, 1.15, 6.0)
const CAVE_ORBIT := Vector3(1.0, 0.5, 8.0)
const FRAME_SAMPLES := 180

var _capture_dir := ""
var _report: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run_capture")


func _run_capture() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("Usage: -- <absolute output directory>")
		quit(2)
		return
	_capture_dir = args[0]
	var mkdir_error := DirAccess.make_dir_recursive_absolute(_capture_dir)
	if mkdir_error != OK:
		push_error("Could not create capture directory; error=%d" % mkdir_error)
		quit(2)
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)

	var demo := DEMO_SCENE.instantiate()
	root.add_child(demo)
	await process_frame
	var loaded := false
	for _frame in range(12000):
		if demo.active_regions.size() == 9 and demo._queued_chunk_count() == 0 and not demo.global_rebuild_pending:
			loaded = true
			break
		await process_frame
	if not loaded:
		push_error("Timed out waiting for the nine-region baseline window")
		quit(3)
		return

	var camera: Camera3D = demo.get_node("Camera3D")
	var environment_node: WorldEnvironment = demo.get_node("WorldEnvironment")
	var directional: DirectionalLight3D = demo.get_node("DirectionalLight3D")
	var fill: SpotLight3D = camera.get_node("ViewAlignedLight")
	var environment := environment_node.environment
	var material: StandardMaterial3D = demo.get_node("TerrainChunks/Terrain").material_override
	var sample_chunk: MeshInstance3D = demo.chunk_nodes.values()[0]
	if args.size() >= 4:
		environment.ambient_light_energy = float(args[1])
		directional.light_energy = float(args[2])
		fill.light_energy = float(args[3])
	if args.size() >= 5:
		if args[4] == "old_key":
			directional.rotation_degrees = Vector3(-48.0, -28.0, 0.0)
	_report = {
		"godot_version": Engine.get_version_info(),
		"viewport_size": [root.size.x, root.size.y],
		"seed": 424242,
		"focus_region": [0, 0],
		"target": [demo.orbit_target.x, demo.orbit_target.y, demo.orbit_target.z],
		"ambient_energy": environment.ambient_light_energy,
		"directional_energy": directional.light_energy,
		"view_light_energy": fill.light_energy,
		"view_light_ray_direction": [fill.global_basis.z.x, fill.global_basis.z.y, fill.global_basis.z.z],
		"view_light_range": fill.spot_range,
		"view_light_angle": fill.spot_angle,
		"view_light_shadows": fill.shadow_enabled,
		"view_light_visible": fill.is_visible_in_tree(),
		"view_light_cull_mask": fill.light_cull_mask,
		"sample_mesh_layers": sample_chunk.layers,
		"view_light_specular": fill.light_specular,
		"view_light_attenuation": fill.spot_attenuation,
		"camera_ray_direction": [camera.global_basis.z.x, camera.global_basis.z.y, camera.global_basis.z.z],
		"material_shading_mode": material.shading_mode,
		"material_albedo": [material.albedo_color.r, material.albedo_color.g, material.albedo_color.b],
		"directional_visible": directional.is_visible_in_tree(),
		"directional_ray_direction": [
			directional.global_basis.z.x, directional.global_basis.z.y, directional.global_basis.z.z,
		],
		"mesh_normal_stats": _mesh_normal_stats(demo),
		"captures": [],
		"frame_samples": [],
	}

	demo.orbit_offset = INITIAL_ORBIT
	demo.call("_update_camera")
	await _settle_frames()
	directional.shadow_enabled = false
	await _save_capture("wide_exterior_shadow_off", demo)
	await _measure_frames("wide_exterior_shadow_off", demo)
	fill.visible = false
	await _save_capture("wide_exterior_fill_off", demo)
	fill.visible = true
	directional.shadow_enabled = true
	await _settle_frames()
	await _save_capture("wide_exterior_shadow_on", demo)
	await _measure_frames("wide_exterior_shadow_on", demo)
	directional.shadow_enabled = false

	demo.orbit_offset = CLOSE_ORBIT
	demo.call("_update_camera")
	await _settle_frames()
	await _save_capture("close_exterior_shadow_off", demo)
	await _measure_frames("close_exterior_shadow_off", demo)
	directional.shadow_enabled = true
	await _settle_frames()
	await _save_capture("close_exterior_shadow_on", demo)
	await _measure_frames("close_exterior_shadow_on", demo)
	directional.shadow_enabled = false

	demo.cave_section_enabled = true
	demo.orbit_target = CAVE_TARGET
	demo.orbit_offset = CAVE_ORBIT
	demo.call("_update_camera")
	demo.call("_start_global_rebuild", "lighting_capture_cave")
	var cave_ready := false
	for _frame in range(12000):
		if not demo.global_rebuild_pending and demo.loading_regions.is_empty():
			cave_ready = true
			break
		await process_frame
	if not cave_ready:
		push_error("Timed out waiting for the global cave-section rebuild")
		quit(4)
		return
	await _settle_frames()
	await _save_capture("close_cave_shadow_off", demo)
	await _measure_frames("close_cave_shadow_off", demo)
	fill.visible = false
	await _save_capture("close_cave_fill_off", demo)
	fill.visible = true
	directional.shadow_enabled = true
	await _settle_frames()
	await _save_capture("close_cave_shadow_on", demo)
	await _measure_frames("close_cave_shadow_on", demo)
	_report["image_comparisons"] = [
		_compare_pair("wide_exterior_fill_off", "wide_exterior_shadow_off"),
		_compare_pair("wide_exterior_shadow_off", "wide_exterior_shadow_on"),
		_compare_pair("close_exterior_shadow_off", "close_exterior_shadow_on"),
		_compare_pair("close_cave_fill_off", "close_cave_shadow_off"),
		_compare_pair("close_cave_shadow_off", "close_cave_shadow_on"),
	]

	var json_path := _capture_dir.path_join("lighting_capture.json")
	var json_file := FileAccess.open(json_path, FileAccess.WRITE)
	if json_file == null:
		push_error("Could not write capture report; error=%d" % FileAccess.get_open_error())
		quit(5)
		return
	json_file.store_string(JSON.stringify(_report, "  "))
	json_file.close()
	print("LIGHTING_CAPTURE_COMPLETE: %s" % json_path)
	quit(0)


func _settle_frames() -> void:
	for _frame in range(4):
		await process_frame
	await RenderingServer.frame_post_draw


func _save_capture(label: String, demo: Node) -> void:
	for _frame in range(2):
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var path := _capture_dir.path_join(label + ".png")
	var error := image.save_png(path)
	if error != OK:
		push_error("Capture save failed for %s; error=%d" % [label, error])
		return
	var lighting_stats := _terrain_luminance_stats(image)
	_report["captures"].append({
		"name": label,
		"file": label + ".png",
		"width": image.get_width(),
		"height": image.get_height(),
		"cave_section": demo.cave_section_enabled,
		"directional_shadows": demo.get_node("DirectionalLight3D").shadow_enabled,
		"camera_position": [demo.camera.global_position.x, demo.camera.global_position.y, demo.camera.global_position.z],
		"camera_rotation": [demo.camera.global_rotation.x, demo.camera.global_rotation.y, demo.camera.global_rotation.z],
		"camera_target": [demo.orbit_target.x, demo.orbit_target.y, demo.orbit_target.z],
		"terrain_luminance": lighting_stats,
	})
	print("LIGHTING_CAPTURE: %s %dx%d cave=%s shadows=%s terrain_pixels=%d luma_mean=%.2f luma_std=%.2f p10/p50/p90=%d/%d/%d" % [
		label, image.get_width(), image.get_height(), demo.cave_section_enabled,
		demo.get_node("DirectionalLight3D").shadow_enabled,
		lighting_stats["pixels"], lighting_stats["mean"], lighting_stats["std_dev"],
		lighting_stats["p10"], lighting_stats["p50"], lighting_stats["p90"],
	])


func _measure_frames(label: String, demo: Node) -> void:
	var elapsed := PackedFloat64Array()
	for _warmup in range(30):
		await process_frame
	for _sample in range(FRAME_SAMPLES):
		var started := Time.get_ticks_usec()
		await process_frame
		elapsed.append(float(Time.get_ticks_usec() - started) / 1000.0)
	var sorted := elapsed.duplicate()
	sorted.sort()
	var total := 0.0
	for value in elapsed:
		total += value
	var measurement := {
		"name": label,
		"samples": elapsed.size(),
		"mean_frame_interval_ms": total / float(elapsed.size()),
		"p95_frame_interval_ms": sorted[mini(int(floor(float(sorted.size() - 1) * 0.95)), sorted.size() - 1)],
		"min_frame_interval_ms": sorted[0],
		"max_frame_interval_ms": sorted[sorted.size() - 1],
		"fps_monitor": Performance.get_monitor(Performance.TIME_FPS),
		"active_regions": demo.active_regions.size(),
		"queued_mesh_jobs": demo._queued_mesh_job_count(),
	}
	_report["frame_samples"].append(measurement)
	print("LIGHTING_FRAME_METRICS: %s mean=%.3fms p95=%.3fms min=%.3fms max=%.3fms fps=%s" % [
		label, measurement["mean_frame_interval_ms"], measurement["p95_frame_interval_ms"],
		measurement["min_frame_interval_ms"], measurement["max_frame_interval_ms"],
		str(measurement["fps_monitor"]),
	])


func _compare_pair(shadows_off_name: String, shadows_on_name: String) -> Dictionary:
	var off_image := Image.load_from_file(_capture_dir.path_join(shadows_off_name + ".png"))
	var on_image := Image.load_from_file(_capture_dir.path_join(shadows_on_name + ".png"))
	if off_image == null or on_image == null or off_image.get_size() != on_image.get_size():
		return {"off": shadows_off_name, "on": shadows_on_name, "valid": false}
	var changed_pixels := 0
	var terrain_pixels := 0
	var total_delta := 0.0
	var max_delta := 0.0
	for y in range(off_image.get_height()):
		for x in range(off_image.get_width()):
			var off_color: Color = off_image.get_pixel(x, y)
			var on_color: Color = on_image.get_pixel(x, y)
			if off_color.g <= off_color.b or off_color.g <= off_color.r * 1.15:
				continue
			terrain_pixels += 1
			var delta := (absf(off_color.r - on_color.r) + absf(off_color.g - on_color.g) + absf(off_color.b - on_color.b)) / 3.0
			total_delta += delta
			max_delta = maxf(max_delta, delta)
			if delta > 0.01:
				changed_pixels += 1
	var comparison := {
		"off": shadows_off_name,
		"on": shadows_on_name,
		"valid": terrain_pixels > 0,
		"terrain_pixels": terrain_pixels,
		"pixels_changed_over_1_percent": changed_pixels,
		"mean_absolute_rgb_delta": total_delta / float(maxi(terrain_pixels, 1)),
		"max_absolute_rgb_delta": max_delta,
	}
	print("LIGHTING_IMAGE_COMPARE: %s vs %s terrain_pixels=%d changed=%d mean_rgb_delta=%.5f max=%.5f" % [
		shadows_off_name, shadows_on_name, terrain_pixels, changed_pixels,
		comparison["mean_absolute_rgb_delta"], max_delta,
	])
	return comparison


func _terrain_luminance_stats(image: Image) -> Dictionary:
	var histogram := PackedInt32Array()
	histogram.resize(256)
	histogram.fill(0)
	var count := 0
	var total := 0.0
	var total_squared := 0.0
	for y in range(260, image.get_height()):
		for x in range(image.get_width()):
			var color: Color = image.get_pixel(x, y)
			if color.g <= color.b or color.g <= color.r * 1.15:
				continue
			var luma := clampi(int(round((0.2126 * color.r + 0.7152 * color.g + 0.0722 * color.b) * 255.0)), 0, 255)
			histogram[luma] += 1
			count += 1
			total += float(luma)
			total_squared += float(luma * luma)
	if count == 0:
		return {"pixels": 0, "mean": 0.0, "std_dev": 0.0, "p10": 0, "p50": 0, "p90": 0}
	var percentiles: Array[int] = []
	for percentile in [0.10, 0.50, 0.90]:
		var target := int(floor(float(count - 1) * percentile))
		var cumulative := 0
		var value := 0
		for bin in range(histogram.size()):
			cumulative += histogram[bin]
			if cumulative > target:
				value = bin
				break
		percentiles.append(value)
	var mean := total / float(count)
	var variance := maxf(total_squared / float(count) - mean * mean, 0.0)
	return {
		"pixels": count,
		"mean": mean,
		"std_dev": sqrt(variance),
		"p10": percentiles[0],
		"p50": percentiles[1],
		"p90": percentiles[2],
	}


func _mesh_normal_stats(demo: Node) -> Dictionary:
	var sum := Vector3.ZERO
	var sum_squared := 0.0
	var count := 0
	var min_up := 1.0
	var max_up := -1.0
	for node_value in demo.chunk_nodes.values():
		var node: MeshInstance3D = node_value
		if node.mesh == null or node.mesh.get_surface_count() == 0:
			continue
		var arrays: Array = node.mesh.surface_get_arrays(0)
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		for normal in normals:
			var up := normal.normalized().y
			sum += normal
			sum_squared += up * up
			count += 1
			min_up = minf(min_up, up)
			max_up = maxf(max_up, up)
	if count == 0:
		return {"count": 0}
	var mean_up := sum.y / float(count)
	return {
		"count": count,
		"mean_normal": [sum.x / float(count), mean_up, sum.z / float(count)],
		"up_std_dev": sqrt(maxf(sum_squared / float(count) - mean_up * mean_up, 0.0)),
		"min_up": min_up,
		"max_up": max_up,
	}
