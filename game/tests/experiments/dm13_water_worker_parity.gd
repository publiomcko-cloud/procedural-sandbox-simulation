extends SceneTree

const Visual := preload("res://scripts/simulation/environment_visual_presentation.gd")
const Job := preload("res://scripts/simulation/dm13_water_geometry_job.gd")
const EnvironmentStore := preload("res://scripts/simulation/environment_state_store.gd")

class FakeRuntime:
	extends Node
	var environment: Dictionary = {}
	var surface: Dictionary = {}
	func get_environment_scope(_id: String) -> Dictionary:
		return environment.duplicate(true)
	func get_environment_surface_cache(_id: String) -> Dictionary:
		return surface.duplicate(true)
	func has_environment_hydrology() -> bool:
		return true

var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for region in [Vector2i.ZERO, Vector2i(-3, 2), Vector2i(1, 30)]:
		var surface := _surface(region)
		var environment := _environment(region)
		var shoreline := _shoreline(region)
		for mode in ["normal", "sources", "ocean-only"]:
			var baseline: Dictionary = Visual.derive_shoreline_geometry(
				region, environment, surface, shoreline, mode, true, {}
			)
			var original_env := environment.duplicate(true)
			var original_surface := surface.duplicate(true)
			var original_shoreline := shoreline.duplicate(true)
			var job := Job.new(region, environment, surface, shoreline, mode, true, {})
			# Change input ownership only *after* job construction; the worker
			# must see the original, deep-copied immutable water/shore snapshots.
			var arr: PackedInt64Array = environment["surface_water_ul"]
			arr[0] += 11111111
			environment["surface_water_ul"] = arr
			var t := WorkerThreadPool.add_task(Callable(job, "run"), false,
				"DM13 exact water parity test")
			_check(t >= 0, "worker accepted")
			if t >= 0:
				WorkerThreadPool.wait_for_task_completion(t)
				_check(job.result == baseline, "exact all geometry and metadata")
				_check(job.environment == original_env, "worker immutable environment")
				_check(job.surface_cache == original_surface, "worker immutable SDF")
				_check(job.shoreline == original_shoreline, "worker immutable shoreline")
				_check(job.finished_usec >= job.started_usec, "worker measured")
			var native := Job.new(region, original_env, original_surface,
				original_shoreline, mode, true, {})
			var lane := Thread.new()
			var launched := lane.start(Callable(native, "run"), Thread.PRIORITY_LOW)
			_check(launched == OK, "native worker low-priority thread launched")
			if launched == OK:
				lane.wait_to_finish()
				_check(native.result == baseline, "native low-priority geometry parity exact")
				_check(native.worker_thread_id != 0, "native caller identity recorded")
			environment = original_env
	_check(Visual.derive_shoreline_geometry(Vector2i.ZERO, {}, {}, {}).get("ok", false)
		== false, "invalid input remains invalid")
	var visual := Visual.new()
	var runtime := FakeRuntime.new()
	get_root().add_child(runtime)
	get_root().add_child(visual)
	var region_key := Vector2i.ZERO
	runtime.environment = _environment(region_key)
	runtime.surface = _surface(region_key)
	visual._dm13_water_workers = true
	visual.configure_environment(runtime)
	visual.register_region(region_key)
	_check(visual.install_region_shoreline_samples(
		region_key, runtime.surface, _shoreline(region_key)
	), "shoreline accepted")
	var id := "region:0,0"
	var row: Dictionary = visual._regions[id]
	var source_token: String = Visual._surface_identity(runtime.surface)
	var signature: PackedInt64Array = Visual._water_visual_signature(
		region_key, runtime.environment, runtime.surface, "normal", true, 0
	)
	var expected := {
		"epoch": visual._dm13_epoch,
		"node": row["node"],
		"token": source_token,
		"shoreline_token": source_token,
		"signature": signature,
		"neighbor_signature": PackedByteArray([0, 0, 0, 0]),
	}
	# Use the actual empty-neighbor signature (four fixed edge masks).
	expected["neighbor_signature"] = Visual._neighbor_ocean_signature({})
	_check(visual._dm13_water_current(id, expected), "current revision accepted")
	runtime.environment["state_revision"] = 2
	var wet: PackedInt64Array = runtime.environment["surface_water_ul"]
	wet[0] += 400000000
	runtime.environment["surface_water_ul"] = wet
	_check(not visual._dm13_water_current(id, expected), "hydrology signature rejects stale plan")
	runtime.environment = _environment(region_key)
	runtime.surface["terrain_revision"] = 3
	_check(not visual._dm13_water_current(id, expected), "terrain revision rejects stale plan")
	runtime.surface = _surface(region_key)
	visual.set_water_debug_mode("sources")
	_check(not visual._dm13_water_current(id, expected), "mode epoch rejects stale plan")
	visual.unregister_region(region_key)
	_check(not visual._dm13_water_current(id, expected), "region unload rejects stale plan")
	visual.queue_free()
	runtime.queue_free()
	print("DM13_WATER_PARITY_RESULT=" + JSON.stringify({
		"checks": checks, "failures": failures, "cases": 9,
		"exact_plan_arrays": failures == 0,
		"revision_gating": failures == 0
	}))
	print("DM13_WATER_PARITY_%s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)


func _environment(region: Vector2i) -> Dictionary:
	var water := PackedInt64Array()
	var kinds := PackedByteArray()
	var levels := PackedInt64Array()
	water.resize(48)
	kinds.resize(48)
	levels.resize(48)
	water[0] = 2_000_000_000
	water[3] = 1200000000
	kinds[1] = EnvironmentStore.RESERVOIR_RIVER
	kinds[2] = EnvironmentStore.RESERVOIR_OCEAN
	levels[1] = 3500
	levels[2] = 4000
	return {
		"scope_id": "region:%d,%d" % [region.x, region.y],
		"state_revision": 1,
		"surface_water_ul": water,
		"reservoir_kind": kinds, "reservoir_level_mm": levels,
	}


func _surface(region: Vector2i) -> Dictionary:
	var heights := PackedInt64Array()
	var valid := PackedByteArray()
	heights.resize(48)
	valid.resize(48)
	heights.fill(3000)
	valid.fill(1)
	return {
		"scope_id": "region:%d,%d" % [region.x, region.y],
		"region_key": region, "grid_width": 8, "grid_height": 6,
		"cell_size_x_mm": 2000, "cell_size_z_mm": 2000,
		"world_seed": 424242, "generator_version": 1,
		"terrain_revision": 0, "terrain_cache_scope_id": 1000,
		"terrain_effect_revision": 0,
		"surface_height_mm": heights, "surface_valid": valid,
	}


func _shoreline(region: Vector2i) -> Dictionary:
	var heights := PackedInt32Array()
	var valid := PackedByteArray()
	heights.resize(17 * 13)
	valid.resize(17 * 13)
	heights.fill(3000)
	valid.fill(1)
	return {
		"ok": true, "region_key": region,
		"width": 17, "height": 13,
		"height_mm": heights, "valid": valid,
		"world_seed": 424242, "generator_version": 1,
		"terrain_revision": 0, "terrain_cache_scope_id": 1000,
		"terrain_effect_revision": 0,
	}


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("DM13_WATER_PARITY_FAIL: " + description)
