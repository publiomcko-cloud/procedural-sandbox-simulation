extends SceneTree

const BrushStateScript := preload("res://scripts/terrain/sdf_brush_edit_state.gd")
const SurfaceCacheScript := preload("res://scripts/simulation/environment_surface_cache.gd")
const SurfaceJobScript := preload("res://scripts/simulation/environment_surface_cache_job.gd")
const RuntimeScript := preload("res://scripts/simulation/simulation_runtime.gd")
const TierStateScript := preload("res://scripts/simulation/simulation_tier_state.gd")
const ChunkGrid := preload("res://scripts/terrain/terrain_chunk_grid.gd")
const Field := preload("res://scripts/terrain/sdf_world.gd")
const TerrainDemoScript := preload("res://scripts/terrain/terrain_demo.gd")

var assertions := 0
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_base_surface_derivation_is_deterministic()
	_test_edit_changes_surface_and_revision()
	_test_revision_gated_cache_publication()
	_test_worker_pool_execution()
	_test_runtime_transience_and_unload()
	_test_bounds_are_explicit()

	if failures == 0:
		print("P5_0C_SDF_SURFACE_CACHE_PASS: assertions=%d failures=0" % assertions)
		quit(0)
	else:
		push_error(
			"P5_0C_SDF_SURFACE_CACHE_FAIL: assertions=%d failures=%d"
			% [assertions, failures]
		)
		quit(1)


func _test_base_surface_derivation_is_deterministic() -> void:
	var brush: RefCounted = BrushStateScript.new(424242, Field.GENERATOR_VERSION)
	var snapshots := _chunk_snapshots(brush, Vector2i.ZERO)
	_check(snapshots.get("ok", false), "base SDF chunk snapshots build")
	var job_a := SurfaceJobScript.new(
		"region:0,0",
		424242,
		Field.GENERATOR_VERSION,
		Vector2i.ZERO,
		int(brush.revision),
		int(brush.get_instance_id()),
		0,
		snapshots["snapshots"],
		Time.get_ticks_usec()
	)
	job_a.run()
	_check(job_a.result.get("valid", false), "base surface worker succeeds")
	var record_a: Dictionary = job_a.result["record"]
	_check(
		record_a["surface_height_mm"].size()
			== SurfaceCacheScript.DEFAULT_GRID_WIDTH * SurfaceCacheScript.DEFAULT_GRID_HEIGHT,
		"surface cache contains one height per environment cell"
	)
	_check(
		record_a["neighbor_delta_mm"].size()
			== SurfaceCacheScript.DEFAULT_GRID_WIDTH
				* SurfaceCacheScript.DEFAULT_GRID_HEIGHT
				* SurfaceCacheScript.NEIGHBOR_COUNT,
		"surface cache contains explicit four-neighbor deltas"
	)
	_check(
		_count_valid(record_a["surface_valid"])
			== SurfaceCacheScript.DEFAULT_GRID_WIDTH * SurfaceCacheScript.DEFAULT_GRID_HEIGHT,
		"baseline terrain produces valid top surfaces for all environment cells"
	)

	var job_b := SurfaceJobScript.new(
		"region:0,0",
		424242,
		Field.GENERATOR_VERSION,
		Vector2i.ZERO,
		int(brush.revision),
		int(brush.get_instance_id()),
		0,
		snapshots["snapshots"],
		Time.get_ticks_usec()
	)
	job_b.run()
	_check(job_b.result.get("valid", false), "repeat surface worker succeeds")
	_check(
		job_b.result["record"] == record_a,
		"unchanged immutable SDF snapshot derives identical surface cache"
	)
	var downhill_count := 0
	for neighbor in record_a["downhill_neighbor"]:
		if int(neighbor) >= 0:
			downhill_count += 1
	_check(downhill_count > 0, "surface cache exposes deterministic downhill neighbors")


func _test_edit_changes_surface_and_revision() -> void:
	var brush: RefCounted = BrushStateScript.new(424242, Field.GENERATOR_VERSION)
	var before_snapshots := _chunk_snapshots(brush, Vector2i.ZERO)
	var before_job := SurfaceJobScript.new(
		"region:0,0", 424242, Field.GENERATOR_VERSION, Vector2i.ZERO,
		int(brush.revision), int(brush.get_instance_id()), 0,
		before_snapshots["snapshots"], Time.get_ticks_usec()
	)
	before_job.run()
	_check(before_job.result.get("valid", false), "pre-edit surface derives")
	var before: Dictionary = before_job.result["record"]
	var before_height := int(before["surface_height_mm"][0])

	_check(
		brush.add_sphere(
			BrushStateScript.Mode.FILL,
			Vector3(1.0, 6.5, 1.0),
			1.25
		),
		"authoritative SDF fill edit is accepted"
	)
	_check(int(brush.revision) == 1, "terrain edit advances authoritative ledger revision")
	var after_snapshots := _chunk_snapshots(brush, Vector2i.ZERO)
	_check(after_snapshots.get("ok", false), "post-edit SDF snapshots build")
	var after_job := SurfaceJobScript.new(
		"region:0,0", 424242, Field.GENERATOR_VERSION, Vector2i.ZERO,
		int(brush.revision), int(brush.get_instance_id()), 0,
		after_snapshots["snapshots"], Time.get_ticks_usec()
	)
	after_job.run()
	_check(after_job.result.get("valid", false), "post-edit surface derives")
	var after: Dictionary = after_job.result["record"]
	_check(
		int(after["terrain_revision"]) == 1,
		"derived cache carries source terrain revision"
	)
	_check(
		int(after["terrain_cache_scope_id"]) == int(brush.get_instance_id()),
		"derived cache carries source terrain cache identity"
	)
	_check(
		int(after["surface_height_mm"][0]) > before_height,
		"terrain fill edit changes the affected environment surface height"
	)


func _test_revision_gated_cache_publication() -> void:
	var brush: RefCounted = BrushStateScript.new(424242, Field.GENERATOR_VERSION)
	var snapshots0 := _chunk_snapshots(brush, Vector2i.ZERO)
	var job0 := SurfaceJobScript.new(
		"region:0,0", 424242, Field.GENERATOR_VERSION, Vector2i.ZERO,
		0, int(brush.get_instance_id()), 7,
		snapshots0["snapshots"], Time.get_ticks_usec()
	)
	job0.run()
	_check(job0.result.get("valid", false), "revision-zero worker result exists")

	var cache: RefCounted = SurfaceCacheScript.new()
	_check(cache.initialize(4).get("ok", false), "surface cache initializes")
	_check(
		cache.expect_scope(
			"region:0,0", Vector2i.ZERO, 424242, Field.GENERATOR_VERSION,
			0, int(brush.get_instance_id()), 7
		).get("ok", false),
		"surface cache records expected source token"
	)
	_check(
		cache.publish(job0.result["record"]).get("ok", false),
		"matching worker result publishes"
	)
	_check(cache.has_scope("region:0,0"), "published cache becomes readable")

	_check(
		brush.add_sphere(
			BrushStateScript.Mode.FILL,
			Vector3(1.0, 6.0, 1.0),
			1.0
		),
		"second fixture edit is accepted"
	)
	_check(
		cache.expect_scope(
			"region:0,0", Vector2i.ZERO, 424242, Field.GENERATOR_VERSION,
			1, int(brush.get_instance_id()), 7
		).get("ok", false),
		"new terrain token invalidates previous derived cache"
	)
	_check(not cache.has_scope("region:0,0"), "invalidation removes old derived record")
	var stale: Dictionary = cache.publish(job0.result["record"])
	_check(
		stale.get("reason", "") == "surface_cache_result_stale",
		"stale worker result cannot publish after terrain revision changes"
	)
	_check(
		int(cache.get_metrics()["stale_rejections_total"]) == 1,
		"stale publication rejection is observable"
	)

	var snapshots1 := _chunk_snapshots(brush, Vector2i.ZERO)
	var job1 := SurfaceJobScript.new(
		"region:0,0", 424242, Field.GENERATOR_VERSION, Vector2i.ZERO,
		1, int(brush.get_instance_id()), 7,
		snapshots1["snapshots"], Time.get_ticks_usec()
	)
	job1.run()
	_check(job1.result.get("valid", false), "current revision worker succeeds")
	_check(
		cache.publish(job1.result["record"]).get("ok", false),
		"current revision worker publishes after stale rejection"
	)

	_check(
		cache.expect_scope(
			"region:0,0", Vector2i.ZERO, 424242, Field.GENERATOR_VERSION,
			1, int(brush.get_instance_id()), 8
		).get("ok", false),
		"terrain-effect authority revision also invalidates surface cache"
	)
	var stale_effect: Dictionary = cache.publish(job1.result["record"])
	_check(
		stale_effect.get("reason", "") == "surface_cache_result_stale",
		"old terrain-effect revision cannot publish"
	)


func _test_worker_pool_execution() -> void:
	var brush: RefCounted = BrushStateScript.new(424242, Field.GENERATOR_VERSION)
	var snapshots := _chunk_snapshots(brush, Vector2i.ZERO)
	var job := SurfaceJobScript.new(
		"region:0,0", 424242, Field.GENERATOR_VERSION, Vector2i.ZERO,
		0, int(brush.get_instance_id()), 0,
		snapshots["snapshots"], Time.get_ticks_usec()
	)
	var task_id := WorkerThreadPool.add_task(
		Callable(job, "run"), false, "p5.0c surface-cache test"
	)
	_check(task_id >= 0, "surface cache job is accepted by WorkerThreadPool")
	if task_id >= 0:
		WorkerThreadPool.wait_for_task_completion(task_id)
	_check(job.result.get("valid", false), "surface cache job completes off-thread")
	_check(int(job.worker_thread_id) != 0, "surface cache worker records executing thread")
	_check(
		int(job.worker_finished_usec) >= int(job.worker_started_usec),
		"surface cache worker records bounded execution timing"
	)


func _test_runtime_transience_and_unload() -> void:
	var runtime: Node = RuntimeScript.new()
	_check(runtime.initialize_runtime().get("ok", false), "runtime initializes with transient surface cache")
	_check(
		runtime.configure_world_scope_lifecycle("", 4, 16_000, 12_000).get("ok", false),
		"world lifecycle configures for cache integration"
	)
	_check(
		runtime.publish_world_region_scope(Vector2i.ZERO).get("ok", false),
		"world scope publication creates simulation/environment authority"
	)

	var brush: RefCounted = BrushStateScript.new(424242, Field.GENERATOR_VERSION)
	var snapshots := _chunk_snapshots(brush, Vector2i.ZERO)
	var job := SurfaceJobScript.new(
		"region:0,0", 424242, Field.GENERATOR_VERSION, Vector2i.ZERO,
		0, int(brush.get_instance_id()), 0,
		snapshots["snapshots"], Time.get_ticks_usec()
	)
	job.run()
	_check(job.result.get("valid", false), "runtime fixture derives cache")
	_check(
		runtime.expect_environment_surface_cache(
			"region:0,0", Vector2i.ZERO, 424242, Field.GENERATOR_VERSION,
			0, int(brush.get_instance_id()), 0
		).get("ok", false),
		"runtime accepts expected terrain provenance"
	)
	_check(
		runtime.publish_environment_surface_cache(job.result["record"]).get("ok", false),
		"runtime publishes derived surface cache"
	)
	_check(
		not runtime.get_environment_surface_cache("region:0,0").is_empty(),
		"runtime exposes derived cache to later hydrology stages"
	)

	var snapshot: Dictionary = runtime.get_runtime_snapshot()
	_check(
		not snapshot.has("environment_surface_cache"),
		"derived surface cache is absent from persistent runtime snapshot"
	)
	var restored: Node = RuntimeScript.new()
	_check(restored.restore_runtime_snapshot(snapshot).get("ok", false), "runtime snapshot restores")
	_check(
		restored.get_environment_surface_cache("region:0,0").is_empty(),
		"runtime restore reconstructs no derived cache authority"
	)

	_check(
		runtime.unload_world_region_scope(Vector2i.ZERO).get("ok", false),
		"world scope unload succeeds"
	)
	_check(
		runtime.get_environment_surface_cache("region:0,0").is_empty(),
		"stream unload discards derived surface cache"
	)
	_check(
		not runtime.get_environment_scope("region:0,0").is_empty(),
		"stream unload preserves authoritative environment state"
	)
	_check(
		runtime.publish_world_region_scope(Vector2i.ZERO).get("ok", false),
		"unchanged region can publish again after unload"
	)
	_check(
		runtime.expect_environment_surface_cache(
			"region:0,0", Vector2i.ZERO, 424242, Field.GENERATOR_VERSION,
			0, int(brush.get_instance_id()), 0
		).get("ok", false),
		"reload registers the same unchanged terrain token"
	)
	_check(
		runtime.publish_environment_surface_cache(job.result["record"]).get("ok", false),
		"reload republishes cache derived from unchanged terrain"
	)
	_check(
		runtime.get_environment_surface_cache("region:0,0") == job.result["record"],
		"unload/reload reconstructs identical derived surface data"
	)
	runtime.free()
	restored.free()


func _test_bounds_are_explicit() -> void:
	_check(
		TerrainDemoScript.MAX_SURFACE_CACHE_JOBS_IN_FLIGHT == 2,
		"terrain runtime caps surface cache jobs in flight"
	)
	_check(
		TerrainDemoScript.MAX_SURFACE_CACHE_DISPATCHES_PER_FRAME == 1,
		"terrain runtime caps surface cache dispatches per frame"
	)


func _chunk_snapshots(brush: RefCounted, region_key: Vector2i) -> Dictionary:
	var snapshots: Dictionary = {}
	for coordinate in ChunkGrid.all_coordinates():
		var snapshot: Dictionary = brush.get_meshing_snapshot_for_chunk(
			region_key, coordinate
		)
		if not snapshot.get("valid", false):
			return {
				"ok": false,
				"reason": String(snapshot.get("storage_error", "snapshot_invalid")),
			}
		snapshots[coordinate] = snapshot
	return {"ok": true, "snapshots": snapshots}


func _count_valid(values: PackedByteArray) -> int:
	var count := 0
	for value in values:
		if int(value) != 0:
			count += 1
	return count


func _check(condition: bool, description: String) -> void:
	assertions += 1
	if condition:
		print("PASS: " + description)
	else:
		failures += 1
		push_error("FAIL: " + description)
