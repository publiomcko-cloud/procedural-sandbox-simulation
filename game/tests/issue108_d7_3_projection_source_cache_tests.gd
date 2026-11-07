extends SceneTree

const EffectRuntime := preload("res://scripts/terrain/terrain_object_effect_runtime.gd")

const WORLD_ID := "issue108-d7-3-projection-source-cache"
const WORLD_SEED := 424242
const GENERATOR_VERSION := 1
const STATE_ROOT := "user://issue108-d7-3-projection-source-cache"

var assertions := 0
var failures := 0
var evidence: Dictionary = {}


class FakeGenerationJob:
	extends RefCounted

	var region_key := Vector2i.ZERO
	var result: Dictionary = {}
	var worker_started_usec := 0
	var worker_finished_usec := 0

	func _init(region: Vector2i) -> void:
		region_key = region

	func run() -> void:
		worker_started_usec = Time.get_ticks_usec()
		result = {
			"ok": true,
			"region_key": region_key,
			"instances": [],
			"timings_usec": {"total": 1},
		}
		worker_finished_usec = Time.get_ticks_usec()
		result["worker_usec"] = worker_finished_usec - worker_started_usec


class FakeObjectStream:
	extends Node

	var world_revision := 1
	var generation_job_count := 0
	var finalize_count := 0
	var synchronous_source_count := 0

	func get_command_world_revision() -> int:
		return world_revision

	func create_projection_source_generation_job(
		region_key: Vector2i
	) -> RefCounted:
		generation_job_count += 1
		return FakeGenerationJob.new(region_key)

	func finalize_authoritative_region_projection_source(
		region_key: Vector2i,
		generated: Dictionary
	) -> Dictionary:
		finalize_count += 1
		return _source(region_key, generated)

	func get_authoritative_region_projection_source(
		region_key: Vector2i
	) -> Dictionary:
		synchronous_source_count += 1
		return _source(region_key, {})

	func _source(
		region_key: Vector2i,
		generated: Dictionary
	) -> Dictionary:
		return {
			"ok": true,
			"region_key": region_key,
			"world_revision": world_revision,
			"instances": [{
				"instance_id": "d7-3-source-0",
				"region_key": region_key,
				"content_pin": {
					"content_id": "d7-3-source",
					"mod_id": "test",
					"mod_version": "1",
					"definition_schema_version": 1,
				},
				"terrain_interaction": {},
			}],
			# Keep the entity revision stable when only the global world
			# revision changes. This proves that the existing projection-build
			# cache can rebase while the D.7.3 source cache conservatively
			# rejects the stale world revision.
			"source_revisions": {"d7-3-source-0": 1},
			"generation_worker_usec": int(generated.get("worker_usec", 0)),
			"timings_usec": {
				"base_build_usec": 1,
				"state_resolution_usec": 1,
				"total_usec": 2,
			},
		}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_remove_tree(ProjectSettings.globalize_path(STATE_ROOT))

	var stream := FakeObjectStream.new()
	root.add_child(stream)

	var runtime := EffectRuntime.new()
	var initialized: Dictionary = runtime.initialize(
		WORLD_ID,
		WORLD_SEED,
		GENERATOR_VERSION,
		stream,
		STATE_ROOT
	)
	_check(initialized.get("ok", false), "D7.3 effect runtime initializes")
	if not initialized.get("ok", false):
		stream.queue_free()
		await process_frame
		_finish()
		return

	runtime.set_incremental_prefetch_enabled(true)
	var region := Vector2i.ZERO

	var cold := await _prefetch_region(runtime, region)
	_check(cold.get("ok", false), "cold projection source publishes")
	var cold_perf: Dictionary = runtime.get_performance_snapshot()
	_check(stream.generation_job_count == 1, "cold path dispatches one source generation job")
	_check(stream.finalize_count == 1, "cold path finalizes one authoritative source")
	_check(
		int(cold_perf.get("projection_source_cache_entry_count", 0)) == 1,
		"cold path remembers one bounded projection source"
	)
	_check(
		int(cold_perf.get("projection_build_cache_miss_count", 0)) >= 1,
		"cold path populates the projection-build cache"
	)

	var projection: RefCounted = runtime.get("projection")
	projection.call("release_scope", region, true)
	_check(
		not bool(projection.call("has_scope", region)),
		"revisit fixture evicts the live projection scope"
	)

	var generation_before_revisit := stream.generation_job_count
	var finalize_before_revisit := stream.finalize_count
	var revisit := await _prefetch_region(runtime, region)
	_check(revisit.get("ok", false), "same-revision revisit republishes")
	var revisit_perf: Dictionary = runtime.get_performance_snapshot()
	_check(
		stream.generation_job_count == generation_before_revisit,
		"same-revision revisit skips procedural source generation"
	)
	_check(
		stream.finalize_count == finalize_before_revisit,
		"same-revision revisit skips authoritative source finalization"
	)
	_check(
		int(revisit_perf.get("projection_source_cache_hit_count", 0)) >= 1,
		"same-revision revisit hits the projection-source cache"
	)
	_check(
		int(revisit_perf.get("source_finalize_skipped_count", 0)) >= 1,
		"source-cache hit records skipped finalization"
	)
	_check(
		int(revisit_perf.get("projection_build_cache_key_reuse_count", 0)) >= 1,
		"source-cache hit reuses the canonical projection cache key"
	)
	_check(
		int(revisit_perf.get("projection_build_cache_hit_count", 0)) >= 1,
		"same-revision revisit also reuses the projection-build cache"
	)
	_check(
		int(revisit_perf.get("projection_source_cache_reused_instance_count", 0))
			>= 1,
		"source-cache metrics account for reused source instances"
	)

	# Any accepted world mutation changes this token. D.7.3 must reject the
	# cached source even when this particular region's entity revision did not
	# change, then safely fall through to the established D.7.2 path.
	stream.world_revision = 2
	projection.call("release_scope", region, true)
	var generation_before_revision_change := stream.generation_job_count
	var finalize_before_revision_change := stream.finalize_count
	var revision_changed := await _prefetch_region(runtime, region)
	_check(revision_changed.get("ok", false), "revision-changed revisit republishes")
	var changed_perf: Dictionary = runtime.get_performance_snapshot()
	_check(
		stream.generation_job_count == generation_before_revision_change + 1,
		"world-revision mismatch rejects cached source and regenerates"
	)
	_check(
		stream.finalize_count == finalize_before_revision_change + 1,
		"world-revision mismatch re-finalizes authoritative source"
	)
	_check(
		int(changed_perf.get("projection_source_cache_miss_count", 0)) >= 2,
		"revision mismatch is counted as a source-cache miss"
	)
	_check(
		int(changed_perf.get("projection_build_cache_hit_count", 0)) >= 2,
		"rebuilt source can still reuse the revision-independent projection key"
	)

	# Explicit effect invalidation is an independent correctness gate. It must
	# drop the source cache even when the world revision itself is unchanged.
	runtime.invalidate_source_region(region)
	var generation_before_invalidation := stream.generation_job_count
	var finalize_before_invalidation := stream.finalize_count
	var invalidated := await _prefetch_region(runtime, region)
	_check(invalidated.get("ok", false), "explicitly invalidated region republishes")
	var invalidated_perf: Dictionary = runtime.get_performance_snapshot()
	_check(
		stream.generation_job_count == generation_before_invalidation + 1,
		"explicit invalidation prevents projection-source reuse"
	)
	_check(
		stream.finalize_count == finalize_before_invalidation + 1,
		"explicit invalidation re-finalizes authoritative source"
	)
	_check(
		int(invalidated_perf.get("projection_source_cache_entry_count", 0)) == 1,
		"invalidated source is repopulated only after successful rebuild"
	)

	evidence = {
		"cold_generation_jobs": generation_before_revisit,
		"cold_finalizations": finalize_before_revisit,
		"same_revision_generation_jobs": stream.generation_job_count
			- 2,
		"projection_source_cache_hit_count": int(
			invalidated_perf.get("projection_source_cache_hit_count", -1)
		),
		"projection_source_cache_miss_count": int(
			invalidated_perf.get("projection_source_cache_miss_count", -1)
		),
		"source_finalize_skipped_count": int(
			invalidated_perf.get("source_finalize_skipped_count", -1)
		),
		"projection_build_cache_key_reuse_count": int(
			invalidated_perf.get("projection_build_cache_key_reuse_count", -1)
		),
		"projection_build_cache_hit_count": int(
			invalidated_perf.get("projection_build_cache_hit_count", -1)
		),
		"projection_source_cache_lookup_peak_usec": int(
			invalidated_perf.get("projection_source_cache_lookup_peak_usec", -1)
		),
		"generation_job_count": stream.generation_job_count,
		"finalize_count": stream.finalize_count,
		"synchronous_source_count": stream.synchronous_source_count,
	}

	runtime.wait_for_prefetch_jobs()
	stream.queue_free()
	await process_frame
	_finish()


func _prefetch_region(
	runtime: RefCounted,
	region: Vector2i
) -> Dictionary:
	var regions: Array[Vector2i] = [region]
	runtime.call("_enqueue_prefetch_regions", regions, false)
	for _frame in range(600):
		var step: Dictionary = runtime.process_prefetch_step(1)
		if not step.get("ok", false):
			return step
		var projection: RefCounted = runtime.get("projection")
		if (
			bool(projection.call("has_scope", region))
			and runtime.get_prefetch_pending_count() == 0
		):
			return {"ok": true}
		await process_frame
	return {"ok": false, "reason": "prefetch_timeout"}


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


func _check(condition: bool, message: String) -> void:
	assertions += 1
	if condition:
		print("PASS: " + message)
	else:
		failures += 1
		push_error("FAIL: " + message)


func _finish() -> void:
	print(
		"ISSUE108_D7_3_PROJECTION_SOURCE_CACHE_EVIDENCE="
			+ JSON.stringify(evidence)
	)
	print(
		"ISSUE108_D7_3_PROJECTION_SOURCE_CACHE_%s: assertions=%d failures=%d"
		% ["PASS" if failures == 0 else "FAIL", assertions, failures]
	)
	_remove_tree(ProjectSettings.globalize_path(STATE_ROOT))
	quit(0 if failures == 0 else 1)
