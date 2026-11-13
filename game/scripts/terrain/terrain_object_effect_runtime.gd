class_name TerrainObjectEffectRuntime
extends RefCounted

## Live Phase-D coordinator. It owns no terrain or entity authority.
## It derives immutable per-job local-frame snapshots from the authoritative
## object stream and the region-sharded projection.
const ProjectionService := preload("res://scripts/terrain/terrain_object_effect_projection_service.gd")
const Contract := preload("res://scripts/terrain/terrain_object_effect_projection_contract.gd")
const Grid := preload("res://scripts/terrain/terrain_chunk_grid.gd")
const LocalFrameIndex := preload("res://scripts/terrain/terrain_object_effect_local_frame_index.gd")
const ProjectionBuildJob := preload("res://scripts/terrain/terrain_object_effect_projection_build_job.gd")
const PerformanceTrace := preload("res://scripts/diagnostics/performance_trace.gd")
const LookaheadPolicy := preload("res://scripts/terrain/terrain_stream_lookahead_policy.gd")
const DM14DenseWindow := preload("res://scripts/terrain/dm14_effect_dense_window.gd")

# Public v1 contracts bound horizontal reach:
# translation <= 8 m, half extent <= 1.8 m, scale <= 5x, roughness <= 0.1 m.
# With 16x12 m regions, +/-2 source regions conservatively covers any effect
# that can touch a target chunk, including the chunk-normal halo.
const SOURCE_REGION_RADIUS := 2
const MAX_PREFETCH_GENERATION_JOBS_IN_FLIGHT := 2
const MAX_PREFETCH_PROJECTION_JOBS_IN_FLIGHT := 2
const MAX_PROJECTION_BUILD_CACHE_ENTRIES := 256
const MAX_PROJECTION_SOURCE_CACHE_ENTRIES := 256

var world_id := ""
var world_seed := -1
var generator_version := -1
var object_stream: Node
var projection: RefCounted
var initialized := false
var initialization_error := ""
var last_prepare_metrics: Dictionary = {}
var _invalidated_scope_ids: Dictionary = {}
var _pre_invalidation_frames: Dictionary = {}
var _protected_scope_ids: Dictionary = {}
var _required_regions_cache: Dictionary = {}
var incremental_prefetch_enabled := false
var _prefetch_queue: Array[Vector2i] = []
var _prefetch_scope_ids: Dictionary = {}
var _prefetch_urgent_scope_ids: Dictionary = {}
var _lookahead_last_motion_pair := ""
var _lookahead_reorders := 0
var _prefetch_generation_jobs: Dictionary = {}
var _prefetch_task_by_scope: Dictionary = {}
var _prefetch_projection_jobs: Dictionary = {}
var _prefetch_projection_task_by_scope: Dictionary = {}
var _prefetch_projection_ready: Array[Dictionary] = []
var _projection_build_cache: Dictionary = {}
var _projection_build_cache_order: Array[String] = []
# D.7.3: immutable authoritative projection sources are reusable while the
# command-world revision remains exactly unchanged. This sits ahead of the
# projection-build cache so revisits can skip source generation, base
# reconstruction/state resolution, and the canonical projection cache-key hash.
var _projection_source_cache: Dictionary = {}
var _projection_source_cache_order: Array[String] = []
var _prefetch_error := ""
var _perf_trace_enabled := false
# DM14 hotspot diagnostics, separate from the normal performance summary.
var _dm14_effect_trace := false
var _dm14_dense_enabled := false
var _performance := {
	"prepare_call_count": 0,
	"prepare_total_usec": 0,
	"prepare_peak_usec": 0,
	"required_scope_check_count": 0,
	"scope_reconcile_count": 0,
	"scope_eviction_count": 0,
	"hot_path_eviction_count": 0,
	"window_eviction_count": 0,
	"window_update_count": 0,
	"window_target_region_count": 0,
	"protected_scope_count": 0,
	"prefetch_scope_count": 0,
	"prefetch_total_usec": 0,
	"prefetch_peak_usec": 0,
	"prefetch_pending_peak": 0,
	"prefetch_worker_dispatch_count": 0,
	"prefetch_worker_complete_count": 0,
	"prefetch_worker_total_usec": 0,
	"prefetch_worker_peak_usec": 0,
	"prefetch_finalize_total_usec": 0,
	"prefetch_finalize_peak_usec": 0,
	"prefetch_source_finalize_total_usec": 0,
	"prefetch_source_finalize_peak_usec": 0,
	"prefetch_projection_worker_dispatch_count": 0,
	"prefetch_projection_worker_complete_count": 0,
	"prefetch_projection_worker_total_usec": 0,
	"prefetch_projection_worker_peak_usec": 0,
	"prefetch_projection_publish_total_usec": 0,
	"prefetch_projection_publish_peak_usec": 0,
	"projection_build_cache_hit_count": 0,
	"projection_build_cache_miss_count": 0,
	"projection_build_cache_eviction_count": 0,
	"projection_build_cache_lookup_total_usec": 0,
	"projection_build_cache_lookup_peak_usec": 0,
	"projection_build_cache_reused_effect_count": 0,
	"projection_source_cache_hit_count": 0,
	"projection_source_cache_miss_count": 0,
	"projection_source_cache_eviction_count": 0,
	"projection_source_cache_lookup_total_usec": 0,
	"projection_source_cache_lookup_peak_usec": 0,
	"projection_source_cache_reused_instance_count": 0,
	"source_finalize_skipped_count": 0,
	"projection_build_cache_key_reuse_count": 0,
}


func initialize(
	world_identifier: String,
	seed_value: int,
	generator: int,
	object_stream_value: Node,
	directory_override: String = ""
) -> Dictionary:
	initialized = false
	initialization_error = ""
	_perf_trace_enabled = PerformanceTrace.is_enabled()
	_dm14_effect_trace = _perf_trace_enabled and OS.get_environment(
		"SANDBOX_DM14_EFFECT_TRACE"
	) == "1"
	_dm14_dense_enabled = OS.get_environment("SANDBOX_DM14_DENSE_REQUIRED") == "1"
	if object_stream_value == null 		or not object_stream_value.has_method("get_authoritative_region_projection_source") 		or not object_stream_value.has_method("get_command_world_revision"):
		initialization_error = "terrain_effect_runtime_object_stream_invalid"
		return _failure(initialization_error)
	world_id = world_identifier
	world_seed = seed_value
	generator_version = generator
	object_stream = object_stream_value
	_invalidated_scope_ids.clear()
	_pre_invalidation_frames.clear()
	_protected_scope_ids.clear()
	_required_regions_cache.clear()
	_prefetch_queue.clear()
	_prefetch_scope_ids.clear()
	_prefetch_urgent_scope_ids.clear()
	_lookahead_last_motion_pair = ""
	_lookahead_reorders = 0
	_prefetch_generation_jobs.clear()
	_prefetch_task_by_scope.clear()
	_prefetch_projection_jobs.clear()
	_prefetch_projection_task_by_scope.clear()
	_prefetch_projection_ready.clear()
	_projection_build_cache.clear()
	_projection_build_cache_order.clear()
	_projection_source_cache.clear()
	_projection_source_cache_order.clear()
	_prefetch_error = ""
	incremental_prefetch_enabled = false
	_reset_performance_metrics()
	projection = ProjectionService.new()
	var init: Dictionary = projection.initialize(
		world_id, world_seed, generator_version, directory_override
	)
	if not init.get("ok", false):
		initialization_error = String(
			init.get("reason", "terrain_effect_projection_initialize_failed")
		)
		return _failure(initialization_error)
	initialized = true
	if _perf_trace_enabled:
		PerformanceTrace.emit("effect_runtime_initialize", {
			"world_id": world_id,
			"generator_version": generator_version,
			"max_resident_scopes": ProjectionService.MAX_RESIDENT_SCOPES,
			"incremental_prefetch": incremental_prefetch_enabled,
		})
	return {"ok": true, "reason": "ok"}


func set_incremental_prefetch_enabled(enabled: bool) -> void:
	if incremental_prefetch_enabled and not enabled:
		wait_for_prefetch_jobs()
	incremental_prefetch_enabled = enabled
	if not enabled:
		_prefetch_queue.clear()
		_prefetch_scope_ids.clear()
		_prefetch_urgent_scope_ids.clear()
		_lookahead_last_motion_pair = ""
		_prefetch_generation_jobs.clear()
		_prefetch_task_by_scope.clear()
		_prefetch_projection_jobs.clear()
		_prefetch_projection_task_by_scope.clear()
		_prefetch_projection_ready.clear()
		_prefetch_error = ""


func process_prefetch_step(max_scopes: int = 1) -> Dictionary:
	if not initialized:
		return _failure("terrain_effect_runtime_not_initialized")
	if not incremental_prefetch_enabled:
		return {"ok": true, "processed": 0, "pending": 0}
	if not _prefetch_error.is_empty():
		return _failure(_prefetch_error)

	var processed := 0
	var started_usec := Time.get_ticks_usec()

	# Stage 3: publish completed pure projection builds or cached rebuilds. This
	# is the only stage that mutates projection residency/routes and remains
	# bounded by max_scopes per frame.
	while processed < maxi(max_scopes, 0) and not _prefetch_projection_ready.is_empty():
		var ready_record: Dictionary = _prefetch_projection_ready.pop_front()
		var ready_prebuilt: Dictionary = ready_record.get("prebuilt", {})
		var ready_published := _publish_prebuilt_projection_record(
			ready_record, ready_prebuilt, 0, true
		)
		if not ready_published.get("ok", false):
			return ready_published
		processed += int(ready_published.get("processed", 0))

	if processed < maxi(max_scopes, 0):
		var completed_projection: Array[int] = []
		for task_id_value in _prefetch_projection_jobs:
			var task_id := int(task_id_value)
			if WorkerThreadPool.is_task_completed(task_id):
				completed_projection.append(task_id)
		completed_projection.sort()
		for task_id in completed_projection:
			if processed >= maxi(max_scopes, 0):
				break
			WorkerThreadPool.wait_for_task_completion(task_id)
			var record: Dictionary = _prefetch_projection_jobs[task_id]
			_prefetch_projection_jobs.erase(task_id)
			var job: RefCounted = record["job"]
			var prebuilt: Dictionary = job.get("result")
			var worker_usec := int(prebuilt.get(
				"worker_usec",
				int(job.get("worker_finished_usec")) - int(job.get("worker_started_usec"))
			))
			_performance["prefetch_projection_worker_complete_count"] = int(
				_performance["prefetch_projection_worker_complete_count"]
			) + 1
			_performance["prefetch_projection_worker_total_usec"] = int(
				_performance["prefetch_projection_worker_total_usec"]
			) + worker_usec
			_performance["prefetch_projection_worker_peak_usec"] = maxi(
				int(_performance["prefetch_projection_worker_peak_usec"]),
				worker_usec
			)
			if not prebuilt.get("ok", false):
				_prefetch_error = "terrain_effect_runtime_projection_build_failed:%s" \
					% prebuilt.get("reason", "unknown")
				return _failure(_prefetch_error)
			var cache_key := String(record.get("cache_key", ""))
			if not cache_key.is_empty():
				_remember_projection_build(cache_key, prebuilt)
			var published := _publish_prebuilt_projection_record(
				record, prebuilt, worker_usec, false
			)
			if not published.get("ok", false):
				return published
			processed += int(published.get("processed", 0))

	# Stage 2: finalize one completed procedural source on main, then dispatch
	# pure Effect/LocalFrame construction to a worker.
	if _prefetch_projection_jobs.size() + _prefetch_projection_ready.size() \
		< MAX_PREFETCH_PROJECTION_JOBS_IN_FLIGHT:
		var completed_generation: Array[int] = []
		for task_id_value in _prefetch_generation_jobs:
			var task_id := int(task_id_value)
			if WorkerThreadPool.is_task_completed(task_id):
				completed_generation.append(task_id)
		completed_generation.sort()
		if not completed_generation.is_empty():
			var task_id := completed_generation[0]
			WorkerThreadPool.wait_for_task_completion(task_id)
			var record: Dictionary = _prefetch_generation_jobs[task_id]
			_prefetch_generation_jobs.erase(task_id)
			var region: Vector2i = record["region"]
			var scope_id := String(record["scope_id"])
			_prefetch_task_by_scope.erase(scope_id)
			if bool(record.get("cancelled", false)) 				or (
					not _protected_scope_ids.is_empty()
						and not _protected_scope_ids.has(scope_id)
				):
				_prefetch_scope_ids.erase(scope_id)
			else:
				var job: RefCounted = record["job"]
				var generated: Dictionary = job.get("result")
				var worker_usec := int(generated.get(
					"worker_usec",
					int(job.get("worker_finished_usec")) 						- int(job.get("worker_started_usec"))
				))
				_performance["prefetch_worker_complete_count"] = int(
					_performance["prefetch_worker_complete_count"]
				) + 1
				_performance["prefetch_worker_total_usec"] = int(
					_performance["prefetch_worker_total_usec"]
				) + worker_usec
				_performance["prefetch_worker_peak_usec"] = maxi(
					int(_performance["prefetch_worker_peak_usec"]),
					worker_usec
				)
				if not generated.get("ok", false):
					_prefetch_error = "terrain_effect_runtime_prefetch_generation_failed:%s" 						% generated.get("reason", "unknown")
					return _failure(_prefetch_error)
				var source_started_usec := Time.get_ticks_usec()
				var source_value: Variant = object_stream.call(
					"finalize_authoritative_region_projection_source",
					region,
					generated
				)
				var source_usec := Time.get_ticks_usec() - source_started_usec
				_performance["prefetch_source_finalize_total_usec"] = int(
					_performance["prefetch_source_finalize_total_usec"]
				) + source_usec
				_performance["prefetch_source_finalize_peak_usec"] = maxi(
					int(_performance["prefetch_source_finalize_peak_usec"]),
					source_usec
				)
				if typeof(source_value) != TYPE_DICTIONARY:
					_prefetch_error = "terrain_effect_runtime_prefetch_finalize_invalid"
					return _failure(_prefetch_error)
				var source: Dictionary = source_value
				if not source.get("ok", false):
					_prefetch_error = "terrain_effect_runtime_source_failed:%s" 						% source.get("reason", "unknown")
					return _failure(_prefetch_error)
				var projection_queue := _queue_projection_build(
					region, scope_id, source
				)
				if not projection_queue.get("ok", false):
					_prefetch_error = String(projection_queue.get(
						"reason", "terrain_effect_runtime_projection_worker_rejected"
					))
					return _failure(_prefetch_error)
				_remember_projection_source(
					region,
					source,
					String(projection_queue.get("cache_key", ""))
				)

				if _perf_trace_enabled:
					PerformanceTrace.emit("effect_source_ready", {
						"scope_id": scope_id,
						"region": [region.x, region.y],
						"source_generation_worker_usec": worker_usec,
						"source_generation_timings_usec": generated.get("timings_usec", {}),
						"source_finalize_usec": source_usec,
						"source_finalize_timings_usec": source.get("timings_usec", {}),
						"instance_count": int((source.get("instances", []) as Array).size()),
						"projection_cache_hit": bool(projection_queue.get("cache_hit", false)),
						"queued": _prefetch_queue.size(),
						"generation_in_flight": _prefetch_generation_jobs.size(),
						"projection_in_flight": _prefetch_projection_jobs.size(),
					})

	# Stage 1: keep two deterministic source-generation jobs in flight.
	while _prefetch_generation_jobs.size() 		< MAX_PREFETCH_GENERATION_JOBS_IN_FLIGHT 		and not _prefetch_queue.is_empty():
		var region: Vector2i = _prefetch_queue.pop_front()
		var scope_id := Contract.scope_id_for_region(region)
		_prefetch_urgent_scope_ids.erase(scope_id)
		if not _protected_scope_ids.is_empty() 			and not _protected_scope_ids.has(scope_id):
			_prefetch_scope_ids.erase(scope_id)
			continue
		if projection.has_scope(region) 			and not _invalidated_scope_ids.has(scope_id):
			_prefetch_scope_ids.erase(scope_id)
			continue
		if _prefetch_task_by_scope.has(scope_id) 			or _prefetch_projection_task_by_scope.has(scope_id):
			continue

		var has_async_source_pipeline := (
			object_stream.has_method("create_projection_source_generation_job")
			and object_stream.has_method(
				"finalize_authoritative_region_projection_source"
			)
		)
		# D.7.3 fast revisit path. The global command revision is deliberately
		# conservative: any accepted entity mutation invalidates reuse until a
		# source is rebuilt at the new revision. Explicit source invalidation
		# also removes the affected entry immediately. Keep legacy streams on
		# their existing synchronous path.
		var authority_revision := int(
			object_stream.call("get_command_world_revision")
		)
		var cached_source_record: Dictionary = {}
		if has_async_source_pipeline:
			var raw_cached_source: Dictionary = _projection_source_cache.get(
				scope_id, {}
			)
			var exact_source_candidate := (
				not raw_cached_source.is_empty()
				and int(raw_cached_source.get("world_revision", -1))
					== authority_revision
			)
			# Do not count a cache hit until the bounded projection stage can
			# actually consume it. Cold misses may still dispatch generation in
			# parallel, preserving the established pipeline overlap.
			if (
				exact_source_candidate
				and _prefetch_projection_jobs.size()
					+ _prefetch_projection_ready.size()
					>= MAX_PREFETCH_PROJECTION_JOBS_IN_FLIGHT
			):
				_prefetch_queue.push_front(region)
				break
			cached_source_record = _projection_source_cache_lookup(
				region, authority_revision
			)
		if not cached_source_record.is_empty():
			var cached_source: Dictionary = cached_source_record.get(
				"source", {}
			)
			var cached_projection_key := String(
				cached_source_record.get("projection_cache_key", "")
			)
			var source_cache_queue := _queue_projection_build(
				region,
				scope_id,
				cached_source,
				cached_projection_key
			)
			if not source_cache_queue.get("ok", false):
				_prefetch_error = String(source_cache_queue.get(
					"reason",
					"terrain_effect_runtime_projection_worker_rejected"
				))
				return _failure(_prefetch_error)
			_performance["source_finalize_skipped_count"] = int(
				_performance["source_finalize_skipped_count"]
			) + 1
			if _perf_trace_enabled:
				PerformanceTrace.emit("effect_projection_source_cache_hit", {
					"scope_id": scope_id,
					"region": [region.x, region.y],
					"world_revision": authority_revision,
					"instance_count": int(
						(cached_source.get("instances", []) as Array).size()
					),
					"projection_cache_key_reused":
						not cached_projection_key.is_empty(),
					"projection_cache_hit": bool(
						source_cache_queue.get("cache_hit", false)
					),
					"queued": _prefetch_queue.size(),
					"generation_in_flight": _prefetch_generation_jobs.size(),
					"projection_in_flight": _prefetch_projection_jobs.size(),
					"projection_ready": _prefetch_projection_ready.size(),
				})
			continue

		if not has_async_source_pipeline:
			var scope_started_usec := Time.get_ticks_usec()
			var reconciled := _reconcile_source_region(region, false)
			var scope_usec := Time.get_ticks_usec() - scope_started_usec
			_prefetch_scope_ids.erase(scope_id)
			if not reconciled.get("ok", false):
				_prefetch_error = String(reconciled.get(
					"reason", "terrain_effect_runtime_prefetch_failed"
				))
				return _failure(_prefetch_error)
			_performance["prefetch_scope_count"] = int(
				_performance["prefetch_scope_count"]
			) + 1
			_performance["prefetch_total_usec"] = int(
				_performance["prefetch_total_usec"]
			) + scope_usec
			_performance["prefetch_peak_usec"] = maxi(
				int(_performance["prefetch_peak_usec"]), scope_usec
			)
			processed += 1
			if processed >= maxi(max_scopes, 0):
				break
			continue
		var job_value: Variant = object_stream.call(
			"create_projection_source_generation_job", region
		)
		if job_value == null or not job_value is RefCounted:
			_prefetch_error = "terrain_effect_runtime_prefetch_job_unavailable"
			return _failure(_prefetch_error)
		var job: RefCounted = job_value
		var task_id := WorkerThreadPool.add_task(
			Callable(job, "run"),
			false,
			"terrain-object projection source generation"
		)
		if task_id < 0:
			_prefetch_error = "terrain_effect_runtime_prefetch_worker_rejected"
			return _failure(_prefetch_error)
		_prefetch_generation_jobs[task_id] = {
			"job": job,
			"region": region,
			"scope_id": scope_id,
			"cancelled": false,
			"submitted_usec": Time.get_ticks_usec(),
		}
		_prefetch_task_by_scope[scope_id] = task_id
		_performance["prefetch_worker_dispatch_count"] = int(
			_performance["prefetch_worker_dispatch_count"]
		) + 1
		if _perf_trace_enabled:
			PerformanceTrace.emit("effect_source_dispatched", {
				"scope_id": scope_id,
				"region": [region.x, region.y],
				"queued_after_dispatch": _prefetch_queue.size(),
				"generation_in_flight": _prefetch_generation_jobs.size(),
				"projection_in_flight": _prefetch_projection_jobs.size(),
			})

	var pending := _prefetch_queue.size() \
		+ _prefetch_generation_jobs.size() \
		+ _prefetch_projection_jobs.size() \
		+ _prefetch_projection_ready.size()
	_performance["prefetch_pending_peak"] = maxi(
		int(_performance["prefetch_pending_peak"]), pending
	)
	var step_duration_usec := Time.get_ticks_usec() - started_usec
	if _perf_trace_enabled and (
		processed > 0 or step_duration_usec >= PerformanceTrace.min_usec()
	):
		PerformanceTrace.emit("effect_prefetch_tick", {
			"duration_usec": step_duration_usec,
			"processed": processed,
			"pending": pending,
			"queued": _prefetch_queue.size(),
			"generation_in_flight": _prefetch_generation_jobs.size(),
			"projection_in_flight": _prefetch_projection_jobs.size(),
			"projection_ready": _prefetch_projection_ready.size(),
		})
	return {
		"ok": true,
		"processed": processed,
		"pending": pending,
		"queued": _prefetch_queue.size(),
		"generation_in_flight": _prefetch_generation_jobs.size(),
		"projection_in_flight": _prefetch_projection_jobs.size(),
		"projection_ready": _prefetch_projection_ready.size(),
		"duration_usec": step_duration_usec,
	}


func _publish_prebuilt_projection_record(
	record: Dictionary,
	prebuilt: Dictionary,
	worker_usec: int,
	cache_hit: bool
) -> Dictionary:
	var region: Vector2i = record["region"]
	var scope_id := String(record["scope_id"])
	_prefetch_projection_task_by_scope.erase(scope_id)
	_prefetch_scope_ids.erase(scope_id)
	if bool(record.get("cancelled", false)) or (
		not _protected_scope_ids.is_empty()
		and not _protected_scope_ids.has(scope_id)
	):
		return {"ok": true, "processed": 0}
	if not prebuilt.get("ok", false):
		return _failure(
			"terrain_effect_runtime_projection_build_failed:%s"
				% prebuilt.get("reason", "unknown")
		)
	var publish_started_usec := Time.get_ticks_usec()
	var reconciled: Dictionary = projection.reconcile_prebuilt_scope(
		region,
		prebuilt,
		true,
		false,
		false,
		true
	)
	var publish_usec := Time.get_ticks_usec() - publish_started_usec
	if not reconciled.get("ok", false):
		_prefetch_error = "terrain_effect_runtime_reconcile_failed:%s" \
			% reconciled.get("reason", "unknown")
		return _failure(_prefetch_error)
	_performance["scope_reconcile_count"] = int(
		_performance["scope_reconcile_count"]
	) + 1
	_invalidated_scope_ids.erase(scope_id)
	_pre_invalidation_frames.erase(scope_id)
	_performance["prefetch_scope_count"] = int(
		_performance["prefetch_scope_count"]
	) + 1
	_performance["prefetch_total_usec"] = int(
		_performance["prefetch_total_usec"]
	) + publish_usec
	_performance["prefetch_peak_usec"] = maxi(
		int(_performance["prefetch_peak_usec"]), publish_usec
	)
	_performance["prefetch_finalize_total_usec"] = int(
		_performance["prefetch_finalize_total_usec"]
	) + publish_usec
	_performance["prefetch_finalize_peak_usec"] = maxi(
		int(_performance["prefetch_finalize_peak_usec"]), publish_usec
	)
	_performance["prefetch_projection_publish_total_usec"] = int(
		_performance["prefetch_projection_publish_total_usec"]
	) + publish_usec
	_performance["prefetch_projection_publish_peak_usec"] = maxi(
		int(_performance["prefetch_projection_publish_peak_usec"]),
		publish_usec
	)
	if _perf_trace_enabled:
		PerformanceTrace.emit("effect_scope_published", {
			"scope_id": scope_id,
			"region": [region.x, region.y],
			"projection_cache_hit": cache_hit,
			"projection_worker_usec": worker_usec,
			"projection_worker_timings_usec": prebuilt.get("timings_usec", {}),
			"projection_cache_source_timings_usec": prebuilt.get(
				"cache_source_timings_usec", {}
			),
			"projection_worker_counts": prebuilt.get("work_counts", {}),
			"publish_usec": publish_usec,
			"storage_load_bypassed": bool(
				reconciled.get("storage_load_bypassed", false)
			),
			"worker_prevalidated": bool(
				reconciled.get("worker_prevalidated", false)
			),
			"main_validation_skipped": bool(
				reconciled.get("main_validation_skipped", false)
			),
			"reconcile_timings_usec": projection.last_reconcile_metrics.duplicate(
				true
			),
			"effect_count": int(reconciled.get("effect_count", 0)),
			"source_count": int(prebuilt.get("source_instance_ids", []).size()),
			"resident_scopes": projection.get_loaded_scope_count(),
			"queued": _prefetch_queue.size(),
			"generation_in_flight": _prefetch_generation_jobs.size(),
			"projection_in_flight": _prefetch_projection_jobs.size(),
			"projection_ready": _prefetch_projection_ready.size(),
		})
	return {"ok": true, "processed": 1}


func _queue_projection_build(
	region: Vector2i,
	scope_id: String,
	source: Dictionary,
	known_cache_key: String = ""
) -> Dictionary:
	var cache_key_started_usec := Time.get_ticks_usec()
	var cache_key := known_cache_key
	var cache_key_reused := not cache_key.is_empty()
	if cache_key_reused:
		_performance["projection_build_cache_key_reuse_count"] = int(
			_performance["projection_build_cache_key_reuse_count"]
		) + 1
	else:
		cache_key = _projection_build_cache_key(region, source)
	var cache_key_usec := Time.get_ticks_usec() - cache_key_started_usec
	var lookup_started_usec := Time.get_ticks_usec()
	var cached := _projection_build_cache_lookup(cache_key)
	var lookup_usec := Time.get_ticks_usec() - lookup_started_usec
	_performance["projection_build_cache_lookup_total_usec"] = int(
		_performance["projection_build_cache_lookup_total_usec"]
	) + cache_key_usec + lookup_usec
	_performance["projection_build_cache_lookup_peak_usec"] = maxi(
		int(_performance["projection_build_cache_lookup_peak_usec"]),
		cache_key_usec + lookup_usec
	)
	if not cached.is_empty():
		var rebase_started_usec := Time.get_ticks_usec()
		var rebased := _rebase_cached_projection(region, source, cached)
		var rebase_usec := Time.get_ticks_usec() - rebase_started_usec
		if rebased.get("ok", false):
			_performance["projection_build_cache_hit_count"] = int(
				_performance["projection_build_cache_hit_count"]
			) + 1
			_performance["projection_build_cache_reused_effect_count"] = int(
				_performance["projection_build_cache_reused_effect_count"]
			) + int((rebased.get("effects", {}) as Dictionary).size())
			_prefetch_projection_ready.append({
				"region": region,
				"scope_id": scope_id,
				"prebuilt": rebased,
				"cache_key": cache_key,
				"cancelled": false,
				"submitted_usec": Time.get_ticks_usec(),
			})
			if _perf_trace_enabled:
				PerformanceTrace.emit("effect_projection_cache_hit", {
					"scope_id": scope_id,
					"region": [region.x, region.y],
					"cache_key_usec": cache_key_usec,
					"cache_key_reused": cache_key_reused,
					"lookup_usec": lookup_usec,
					"rebase_usec": rebase_usec,
					"effect_count": int((rebased.get("effects", {}) as Dictionary).size()),
					"source_count": int((rebased.get("source_instance_ids", []) as Array).size()),
					"cached_effect_frame_build_usec": int((
						rebased.get("cache_source_timings_usec", {}) as Dictionary
					).get("effect_frame_build", 0)),
					"cache_entry_count": _projection_build_cache.size(),
				})
			return {
				"ok": true,
				"cache_hit": true,
				"cache_key": cache_key,
				"cache_key_reused": cache_key_reused,
			}
		_projection_build_cache.erase(cache_key)
		_projection_build_cache_order.erase(cache_key)
	_performance["projection_build_cache_miss_count"] = int(
		_performance["projection_build_cache_miss_count"]
	) + 1
	var build_job := ProjectionBuildJob.new(
		world_id,
		world_seed,
		generator_version,
		region,
		source
	)
	var build_task_id := WorkerThreadPool.add_task(
		Callable(build_job, "run"),
		false,
		"terrain-object projection build"
	)
	if build_task_id < 0:
		return _failure("terrain_effect_runtime_projection_worker_rejected")
	_prefetch_projection_jobs[build_task_id] = {
		"job": build_job,
		"region": region,
		"scope_id": scope_id,
		"cache_key": cache_key,
		"cancelled": false,
		"submitted_usec": Time.get_ticks_usec(),
	}
	_prefetch_projection_task_by_scope[scope_id] = build_task_id
	_performance["prefetch_projection_worker_dispatch_count"] = int(
		_performance["prefetch_projection_worker_dispatch_count"]
	) + 1
	return {
		"ok": true,
		"cache_hit": false,
		"cache_key": cache_key,
		"cache_key_reused": cache_key_reused,
	}


func _projection_source_cache_lookup(
	region: Vector2i,
	world_revision: int
) -> Dictionary:
	var started_usec := Time.get_ticks_usec()
	var scope_id := Contract.scope_id_for_region(region)
	var record: Dictionary = _projection_source_cache.get(scope_id, {})
	var hit := (
		not record.is_empty()
		and int(record.get("world_revision", -1)) == world_revision
	)
	if not hit and not record.is_empty():
		_projection_source_cache.erase(scope_id)
		_projection_source_cache_order.erase(scope_id)
	if hit:
		_projection_source_cache_order.erase(scope_id)
		_projection_source_cache_order.append(scope_id)
		_performance["projection_source_cache_hit_count"] = int(
			_performance["projection_source_cache_hit_count"]
		) + 1
		var source: Dictionary = record.get("source", {})
		_performance["projection_source_cache_reused_instance_count"] = int(
			_performance["projection_source_cache_reused_instance_count"]
		) + int((source.get("instances", []) as Array).size())
	else:
		_performance["projection_source_cache_miss_count"] = int(
			_performance["projection_source_cache_miss_count"]
		) + 1
	var lookup_usec := Time.get_ticks_usec() - started_usec
	_performance["projection_source_cache_lookup_total_usec"] = int(
		_performance["projection_source_cache_lookup_total_usec"]
	) + lookup_usec
	_performance["projection_source_cache_lookup_peak_usec"] = maxi(
		int(_performance["projection_source_cache_lookup_peak_usec"]),
		lookup_usec
	)
	return record if hit else {}


func _remember_projection_source(
	region: Vector2i,
	source: Dictionary,
	projection_cache_key: String
) -> void:
	if not source.get("ok", false):
		return
	var source_region: Vector2i = source.get("region_key", region)
	if source_region != region:
		return
	var world_revision := int(source.get("world_revision", -1))
	if world_revision < 0 or world_revision > Contract.MAX_REVISION:
		return
	var scope_id := Contract.scope_id_for_region(region)
	# The finalized source is immutable after construction. Keep the original
	# reference rather than deep-copying 10-20 entity dictionaries on the cold
	# path; consumers only read it and ProjectionBuildJob copies its own input.
	_projection_source_cache[scope_id] = {
		"world_revision": world_revision,
		"source": source,
		"projection_cache_key": projection_cache_key,
	}
	_projection_source_cache_order.erase(scope_id)
	_projection_source_cache_order.append(scope_id)
	while (
		_projection_source_cache_order.size()
			> MAX_PROJECTION_SOURCE_CACHE_ENTRIES
	):
		var evicted_scope_id: String = _projection_source_cache_order.pop_front()
		if _projection_source_cache.has(evicted_scope_id):
			_projection_source_cache.erase(evicted_scope_id)
			_performance["projection_source_cache_eviction_count"] = int(
				_performance["projection_source_cache_eviction_count"]
			) + 1


func _forget_projection_source(scope_id: String) -> void:
	_projection_source_cache.erase(scope_id)
	_projection_source_cache_order.erase(scope_id)


func _projection_build_cache_key(
	region: Vector2i,
	source: Dictionary
) -> String:
	return Contract.canonical_sha256({
		"schema_version": 1,
		"world_id": world_id,
		"world_seed": world_seed,
		"generator_version": generator_version,
		"region_key": [region.x, region.y],
		"instances": source.get("instances", []),
		"source_revisions": source.get("source_revisions", {}),
	})


func _projection_build_cache_lookup(cache_key: String) -> Dictionary:
	if cache_key.is_empty() or not _projection_build_cache.has(cache_key):
		return {}
	_projection_build_cache_order.erase(cache_key)
	_projection_build_cache_order.append(cache_key)
	# Cache entries are immutable. Rebase performs the single deep copy needed
	# before changing the current global revision/digest.
	return _projection_build_cache[cache_key] as Dictionary


func _remember_projection_build(
	cache_key: String,
	prebuilt: Dictionary
) -> void:
	if cache_key.is_empty() or not prebuilt.get("ok", false):
		return
	_projection_build_cache[cache_key] = prebuilt
	_projection_build_cache_order.erase(cache_key)
	_projection_build_cache_order.append(cache_key)
	while _projection_build_cache_order.size() > MAX_PROJECTION_BUILD_CACHE_ENTRIES:
		var evicted_key: String = _projection_build_cache_order.pop_front()
		if _projection_build_cache.has(evicted_key):
			_projection_build_cache.erase(evicted_key)
			_performance["projection_build_cache_eviction_count"] = int(
				_performance["projection_build_cache_eviction_count"]
			) + 1


func _rebase_cached_projection(
	region: Vector2i,
	source: Dictionary,
	cached: Dictionary
) -> Dictionary:
	var started_usec := Time.get_ticks_usec()
	var source_world_revision := int(source.get("world_revision", -1))
	if source_world_revision < 0 or source_world_revision > Contract.MAX_REVISION:
		return _failure("effect_projection_source_world_revision_invalid")
	var revisions_value: Variant = source.get("source_revisions", {})
	if typeof(revisions_value) != TYPE_DICTIONARY:
		return _failure("effect_projection_source_payload_invalid")
	for revision_value in (revisions_value as Dictionary).values():
		var source_revision := int(revision_value)
		if source_revision < 0 or source_revision > source_world_revision:
			return _failure("effect_projection_source_revision_invalid")
	var entries_value: Variant = cached.get("source_digest_entries", [])
	if typeof(entries_value) != TYPE_ARRAY:
		return _failure("effect_projection_cache_digest_entries_invalid")
	var rebased := cached.duplicate(false)
	var source_timings: Dictionary = (
		cached.get("timings_usec", {}) as Dictionary
	).duplicate(false)
	var digest_started_usec := Time.get_ticks_usec()
	var rebased_digest := Contract.source_digest(
		Contract.scope_id_for_region(region),
		region,
		source_world_revision,
		entries_value as Array
	)
	var digest_usec := Time.get_ticks_usec() - digest_started_usec
	rebased["source_world_revision"] = source_world_revision
	rebased["source_digest_sha256"] = rebased_digest
	if (
		bool(cached.get("worker_prevalidated", false))
		and typeof(cached.get("prevalidated_snapshot")) == TYPE_DICTIONARY
	):
		var prevalidated: Dictionary = (
			cached["prevalidated_snapshot"] as Dictionary
		).duplicate(false)
		prevalidated["source_world_revision"] = source_world_revision
		prevalidated["source_digest_sha256"] = rebased_digest
		rebased["prevalidated_snapshot"] = prevalidated
	rebased["cache_hit"] = true
	rebased["cache_source_timings_usec"] = source_timings
	rebased["worker_usec"] = 0
	rebased["worker_thread_id"] = OS.get_thread_caller_id()
	rebased["timings_usec"] = {
		"prepare_sort": 0,
		"effect_frame_build": 0,
		"digest": digest_usec,
		"validate_snapshot": 0,
		"total": Time.get_ticks_usec() - started_usec,
	}
	return rebased


## DM14: bounded main-thread maintenance of tombstoned reverse routes.
## The source authority is removed during update_resident_target_regions;
## cleaning inactive route strings is not required before admitting new
## authoritative projections, and cannot expose stale effect frames.
func process_route_cleanup_step(
	max_chunk_keys: int = 24, budget_usec: int = 1200
) -> Dictionary:
	if not initialized or projection == null:
		return {"ok": false, "reason": "terrain_effect_runtime_not_initialized"}
	return projection.process_route_cleanup_step(max_chunk_keys, budget_usec)

func get_prefetch_pending_count() -> int:
	return _prefetch_queue.size() \
		+ _prefetch_generation_jobs.size() \
		+ _prefetch_projection_jobs.size() \
		+ _prefetch_projection_ready.size()


func wait_for_prefetch_jobs() -> void:
	var wait_started_usec := Time.get_ticks_usec()
	var task_ids: Array[int] = []
	for task_id_value in _prefetch_generation_jobs:
		task_ids.append(int(task_id_value))
	for task_id_value in _prefetch_projection_jobs:
		task_ids.append(int(task_id_value))
	task_ids.sort()
	for task_id in task_ids:
		WorkerThreadPool.wait_for_task_completion(task_id)
	_prefetch_generation_jobs.clear()
	_prefetch_task_by_scope.clear()
	_prefetch_projection_jobs.clear()
	_prefetch_projection_task_by_scope.clear()
	_prefetch_projection_ready.clear()
	_prefetch_queue.clear()
	_prefetch_scope_ids.clear()
	if _perf_trace_enabled and not task_ids.is_empty():
		PerformanceTrace.emit("effect_prefetch_join", {
			"duration_usec": Time.get_ticks_usec() - wait_started_usec,
			"task_count": task_ids.size(),
		})


func _reconcile_source_region(
	source_region: Vector2i,
	persist_projection: bool = true
) -> Dictionary:
	var authority_revision := int(
		object_stream.call("get_command_world_revision")
	)
	var cached_record := _projection_source_cache_lookup(
		source_region, authority_revision
	)
	var source: Dictionary = cached_record.get("source", {})
	if source.is_empty():
		source = object_stream.call(
			"get_authoritative_region_projection_source", source_region
		)
		if not source.get("ok", false):
			return _failure(
				"terrain_effect_runtime_source_failed:%s" 					% source.get("reason", "unknown")
			)
		_remember_projection_source(source_region, source, "")
	else:
		_performance["source_finalize_skipped_count"] = int(
			_performance["source_finalize_skipped_count"]
		) + 1
	return _reconcile_prebuilt_source_region(
		source_region, source, persist_projection
	)


func _reconcile_prebuilt_source_region(
	source_region: Vector2i,
	source: Dictionary,
	persist_projection: bool = true
) -> Dictionary:
	var scope_id := Contract.scope_id_for_region(source_region)
	var reconciled: Dictionary = projection.reconcile_scope(
		source_region,
		int(source.get("world_revision", -1)),
		source.get("instances", []),
		source.get("source_revisions", {}),
		true,
		persist_projection
	)
	if not reconciled.get("ok", false):
		return _failure(
			"terrain_effect_runtime_reconcile_failed:%s" 				% reconciled.get("reason", "unknown")
		)
	_performance["scope_reconcile_count"] = int(
		_performance["scope_reconcile_count"]
	) + 1
	_invalidated_scope_ids.erase(scope_id)
	_pre_invalidation_frames.erase(scope_id)
	return reconciled


func _enqueue_prefetch_regions(
	regions: Array[Vector2i],
	high_priority: bool
) -> void:
	var to_add: Array[Vector2i] = []
	for region in regions:
		var scope_id := Contract.scope_id_for_region(region)
		if projection.has_scope(region) and not _invalidated_scope_ids.has(scope_id):
			continue
		if _prefetch_task_by_scope.has(scope_id) 			or _prefetch_projection_task_by_scope.has(scope_id):
			continue
		if _prefetch_scope_ids.has(scope_id):
			if high_priority:
				# Move an existing background request to the front deterministically.
				for index in range(_prefetch_queue.size()):
					if _prefetch_queue[index] == region:
						_prefetch_queue.remove_at(index)
						to_add.append(region)
						break
			continue
		_prefetch_scope_ids[scope_id] = true
		to_add.append(region)
	if high_priority:
		for index in range(to_add.size() - 1, -1, -1):
			_prefetch_queue.push_front(to_add[index])
		for region in to_add:
			_prefetch_urgent_scope_ids[Contract.scope_id_for_region(region)] = true
	else:
		for region in to_add:
			_prefetch_queue.append(region)
	_performance["prefetch_pending_peak"] = maxi(
		int(_performance["prefetch_pending_peak"]), _prefetch_queue.size()
	)


func _filter_prefetch_to_protected() -> void:
	if _protected_scope_ids.is_empty():
		return
	var kept: Array[Vector2i] = []
	var kept_ids: Dictionary = {}
	for region in _prefetch_queue:
		var scope_id := Contract.scope_id_for_region(region)
		if _protected_scope_ids.has(scope_id):
			kept.append(region)
			kept_ids[scope_id] = true
	_prefetch_queue = kept
	for jobs in [_prefetch_generation_jobs, _prefetch_projection_jobs]:
		for task_id_value in jobs:
			var task_id := int(task_id_value)
			var record: Dictionary = jobs[task_id]
			var scope_id := String(record["scope_id"])
			if not _protected_scope_ids.has(scope_id):
				record["cancelled"] = true
				jobs[task_id] = record
			else:
				kept_ids[scope_id] = true
	var kept_ready: Array[Dictionary] = []
	for ready_record in _prefetch_projection_ready:
		var ready_scope_id := String(ready_record.get("scope_id", ""))
		if _protected_scope_ids.has(ready_scope_id):
			kept_ready.append(ready_record)
			kept_ids[ready_scope_id] = true
	_prefetch_projection_ready = kept_ready
	_prefetch_scope_ids = kept_ids
	var kept_urgent: Dictionary = {}
	for region in _prefetch_queue:
		var scope_id := Contract.scope_id_for_region(region)
		if _prefetch_urgent_scope_ids.has(scope_id):
			kept_urgent[scope_id] = true
	_prefetch_urgent_scope_ids = kept_urgent


## Reprioritize only already-required effect source regions. Caller controls
## when this is used (F10 + experimental lookahead profile only). No change
## to the protected 9x9 source set, cache validity, in-flight jobs, or
## explicit high-priority requests from blocked mesh stages.
func prioritize_prefetch_for_motion(
	focus: Vector2i, proposed_ahead: Vector2i
) -> Dictionary:
	if not initialized or not incremental_prefetch_enabled:
		return {"ok": true, "changed": false, "reason": "prefetch_disabled"}
	var ahead := LookaheadPolicy.clamp_lead(focus, proposed_ahead)
	if ahead == focus or _prefetch_queue.size() <= 1:
		return {"ok": true, "changed": false, "reason": "no_motion_or_queue"}
	var pair := "%d,%d:%d,%d" % [focus.x, focus.y, ahead.x, ahead.y]
	# Reorder when the motion target changes, not every rendered frame.
	if pair == _lookahead_last_motion_pair:
		return {"ok": true, "changed": false, "reason": "same_target"}
	_lookahead_last_motion_pair = pair
	var original := _prefetch_queue.duplicate()
	_prefetch_queue = LookaheadPolicy.ordered_queue(
		_prefetch_queue, focus, ahead, _prefetch_urgent_scope_ids
	)
	var changed := _prefetch_queue != original
	if changed:
		_lookahead_reorders += 1
	if _perf_trace_enabled:
		PerformanceTrace.emit("effect_motion_prefetch_priority", {
			"focus": [focus.x, focus.y],
			"ahead": [ahead.x, ahead.y],
			"changed": changed,
			"queued": _prefetch_queue.size(),
			"urgent_queued": _prefetch_urgent_scope_ids.size(),
			"reorders_total": _lookahead_reorders,
		})
	return {"ok": true, "changed": changed, "queued": _prefetch_queue.size()}


func prepare_chunk_snapshot(
	base_snapshot: Dictionary,
	region_key: Vector2i,
	chunk_coordinate: Vector2i
) -> Dictionary:
	return prepare_targets_snapshot(base_snapshot, [{
		"region_key": region_key,
		"chunk_coordinate": chunk_coordinate,
	}])


func prepare_targets_snapshot(
	base_snapshot: Dictionary,
	targets_value: Array
) -> Dictionary:
	var started_usec := Time.get_ticks_usec()
	if not initialized:
		return _failure("terrain_effect_runtime_not_initialized")
	if base_snapshot.has("valid") and not bool(base_snapshot["valid"]):
		return _failure("terrain_effect_runtime_base_snapshot_invalid")
	var targets_check := _normalize_targets(targets_value)
	if not targets_check.get("ok", false):
		return targets_check
	var targets: Array[Dictionary] = targets_check["targets"]
	var required_source_regions := _required_source_regions(targets)
	if required_source_regions.size() > ProjectionService.MAX_RESIDENT_SCOPES:
		return _failure("terrain_effect_runtime_required_scope_budget_exceeded")

	var capacity := _make_projection_capacity(required_source_regions)
	if not capacity.get("ok", false):
		return capacity
	var authority_revision := int(object_stream.call("get_command_world_revision"))
	var reconciled_count := 0
	var missing_regions: Array[Vector2i] = []
	for source_region in required_source_regions:
		_performance["required_scope_check_count"] = int(
			_performance["required_scope_check_count"]
		) + 1
		var scope_id := Contract.scope_id_for_region(source_region)
		var must_reconcile: bool = not projection.has_scope(source_region) 			or _invalidated_scope_ids.has(scope_id)
		if must_reconcile:
			missing_regions.append(source_region)
	if incremental_prefetch_enabled and not missing_regions.is_empty():
		_enqueue_prefetch_regions(missing_regions, true)
		return {
			"ok": false,
			"pending": true,
			"reason": "terrain_effect_runtime_prefetch_pending",
			"missing_scope_count": missing_regions.size(),
			"prefetch_pending_count": _prefetch_queue.size(),
		}
	for source_region in missing_regions:
		var reconciled := _reconcile_source_region(source_region)
		if not reconciled.get("ok", false):
			return reconciled
		reconciled_count += 1

	var by_effect_id: Dictionary = {}
	var target_rows: Array[Dictionary] = []
	var routed_scope_count := 0
	for target in targets:
		var effect_snapshot: Dictionary = projection.snapshot_for_chunk(
			target["region_key"], target["chunk_coordinate"]
		)
		if not effect_snapshot.get("ok", false):
			return _failure(
				"terrain_effect_runtime_chunk_snapshot_failed:%s" 					% effect_snapshot.get("reason", "unknown")
			)
		routed_scope_count += int(effect_snapshot.get("routed_scope_count", 0))
		var effect_ids: Array[String] = []
		for frame_value in effect_snapshot.get("local_frames", []):
			if typeof(frame_value) != TYPE_DICTIONARY:
				return _failure("terrain_effect_runtime_frame_invalid")
			var frame: Dictionary = frame_value
			var effect_id := String(frame.get("effect_id", ""))
			if effect_id.is_empty():
				return _failure("terrain_effect_runtime_frame_identity_invalid")
			by_effect_id[effect_id] = frame.duplicate(true)
			effect_ids.append(effect_id)
		effect_ids.sort()
		target_rows.append({
			"region_key": [
				(target["region_key"] as Vector2i).x,
				(target["region_key"] as Vector2i).y,
			],
			"chunk_coordinate": [
				(target["chunk_coordinate"] as Vector2i).x,
				(target["chunk_coordinate"] as Vector2i).y,
			],
			"effect_ids": effect_ids,
			"source_snapshot_sha256": String(
				effect_snapshot.get("snapshot_sha256", "")
			),
		})
	target_rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return JSON.stringify(a, "", true, true) < JSON.stringify(b, "", true, true)
	)
	var effect_ids: Array[String] = []
	for effect_id_value in by_effect_id:
		effect_ids.append(String(effect_id_value))
	effect_ids.sort()
	var frames: Array[Dictionary] = []
	var frame_hashes: Array[String] = []
	for effect_id in effect_ids:
		var frame: Dictionary = by_effect_id[effect_id]
		frames.append(frame)
		frame_hashes.append(String(frame["frame_sha256"]))

	var prepared := base_snapshot.duplicate(true)
	prepared["terrain_object_effect_frames"] = frames
	# Snapshot identity is content-local. Unrelated entity revisions or unrelated
	# resident scope churn must not invalidate terrain/shared-surface caches.
	prepared["terrain_effect_snapshot_sha256"] = Contract.canonical_sha256({
		"schema_version": 2,
		"world_id": world_id,
		"world_seed": world_seed,
		"generator_version": generator_version,
		"targets": target_rows,
		"effect_ids": effect_ids,
		"frame_hashes": frame_hashes,
	})
	prepared["terrain_effect_authority_revision"] = authority_revision
	prepared["terrain_effect_frame_count"] = frames.size()
	var duration_usec := Time.get_ticks_usec() - started_usec
	_performance["prepare_call_count"] = int(_performance["prepare_call_count"]) + 1
	_performance["prepare_total_usec"] = int(_performance["prepare_total_usec"]) + duration_usec
	_performance["prepare_peak_usec"] = maxi(
		int(_performance["prepare_peak_usec"]), duration_usec
	)
	last_prepare_metrics = {
		"target_count": targets.size(),
		"required_source_scope_count": required_source_regions.size(),
		"reconciled_scope_count": reconciled_count,
		"routed_scope_count": routed_scope_count,
		"frame_count": frames.size(),
		"duration_usec": duration_usec,
	}
	if _perf_trace_enabled and duration_usec >= PerformanceTrace.min_usec():
		PerformanceTrace.emit("effect_snapshot_prepare", last_prepare_metrics)
	return {
		"ok": true,
		"snapshot": prepared,
		"effect_count": frames.size(),
		"snapshot_sha256": prepared["terrain_effect_snapshot_sha256"],
		"authority_revision": authority_revision,
		"metrics": last_prepare_metrics.duplicate(true),
	}


func invalidate_source_region(source_region: Vector2i) -> void:
	if not initialized or projection == null:
		return
	var scope_id := Contract.scope_id_for_region(source_region)
	_forget_projection_source(scope_id)
	if not _pre_invalidation_frames.has(scope_id):
		var scope: Dictionary = projection.get_scope_snapshot(source_region)
		_pre_invalidation_frames[scope_id] = (
			scope.get("local_frames", {}) as Dictionary
		).duplicate(true) if not scope.is_empty() else {}
	_invalidated_scope_ids[scope_id] = true


func refresh_invalidated_source_region(
	source_region: Vector2i
) -> Dictionary:
	if not initialized:
		return _failure("terrain_effect_runtime_not_initialized")
	var scope_id := Contract.scope_id_for_region(source_region)
	var old_frames: Dictionary = (
		_pre_invalidation_frames.get(scope_id, {}) as Dictionary
	).duplicate(true)
	var source: Dictionary = object_stream.call(
		"get_authoritative_region_projection_source", source_region
	)
	if not source.get("ok", false):
		return _failure(
			"terrain_effect_runtime_source_failed:%s" 				% source.get("reason", "unknown")
		)
	var reconciled: Dictionary = projection.reconcile_scope(
		source_region,
		int(source.get("world_revision", -1)),
		source.get("instances", []),
		source.get("source_revisions", {}),
		true
	)
	if not reconciled.get("ok", false):
		return _failure(
			"terrain_effect_runtime_reconcile_failed:%s" 				% reconciled.get("reason", "unknown")
		)
	_remember_projection_source(source_region, source, "")
	var new_scope: Dictionary = projection.get_scope_snapshot(source_region)
	var new_frames: Dictionary = (
		new_scope.get("local_frames", {}) as Dictionary
	).duplicate(true)
	var targets := _changed_frame_targets(old_frames, new_frames)
	_invalidated_scope_ids.erase(scope_id)
	_pre_invalidation_frames.erase(scope_id)
	return {
		"ok": true,
		"targets": targets,
		"changed_target_count": targets.size(),
		"projection_changed": bool(reconciled.get("changed", false)),
	}


func _changed_frame_targets(
	old_frames: Dictionary,
	new_frames: Dictionary
) -> Array[Dictionary]:
	var changed_ids: Dictionary = {}
	for effect_id_value in old_frames:
		var effect_id := String(effect_id_value)
		if not new_frames.has(effect_id) 			or String((old_frames[effect_id] as Dictionary).get("frame_sha256", "")) 				!= String((new_frames[effect_id] as Dictionary).get("frame_sha256", "")):
			changed_ids[effect_id] = true
	for effect_id_value in new_frames:
		var effect_id := String(effect_id_value)
		if not old_frames.has(effect_id) 			or String((old_frames[effect_id] as Dictionary).get("frame_sha256", "")) 				!= String((new_frames[effect_id] as Dictionary).get("frame_sha256", "")):
			changed_ids[effect_id] = true

	var chunk_ids: Dictionary = {}
	for frames in [old_frames, new_frames]:
		var index := LocalFrameIndex.new()
		for effect_id in changed_ids:
			if not frames.has(effect_id):
				continue
			var indexed: Dictionary = index.replace_frame(frames[effect_id])
			if not indexed.get("ok", false):
				continue
		for chunk_id in index.get_all_indexed_chunk_ids():
			chunk_ids[String(chunk_id)] = true

	var ids: Array[String] = []
	for chunk_id in chunk_ids:
		ids.append(String(chunk_id))
	ids.sort()
	var targets: Array[Dictionary] = []
	for chunk_id in ids:
		var parsed := _target_from_chunk_id(chunk_id)
		if parsed.get("ok", false):
			targets.append({
				"region_key": parsed["region_key"],
				"chunk_coordinate": parsed["chunk_coordinate"],
			})
	return targets


func _target_from_chunk_id(chunk_id: String) -> Dictionary:
	if not chunk_id.begins_with("region:") or not chunk_id.contains("/chunk:"):
		return {"ok": false}
	var sides := chunk_id.split("/chunk:")
	if sides.size() != 2:
		return {"ok": false}
	var region_parts := sides[0].trim_prefix("region:").split(",")
	var chunk_parts := sides[1].split(",")
	if region_parts.size() != 2 or chunk_parts.size() != 2 		or not region_parts[0].is_valid_int() 		or not region_parts[1].is_valid_int() 		or not chunk_parts[0].is_valid_int() 		or not chunk_parts[1].is_valid_int():
		return {"ok": false}
	var coordinate := Vector2i(int(chunk_parts[0]), int(chunk_parts[1]))
	if not Grid.is_valid_coordinate(coordinate):
		return {"ok": false}
	return {
		"ok": true,
		"region_key": Vector2i(
			int(region_parts[0]), int(region_parts[1])
		),
		"chunk_coordinate": coordinate,
	}


func update_resident_target_regions(
	target_regions_value: Array
) -> Dictionary:

	var window_started_usec := Time.get_ticks_usec()
	if not initialized:
		return _failure("terrain_effect_runtime_not_initialized")
	var dm14_stage_started := Time.get_ticks_usec()
	var dm14_normalize_usec := 0
	var dm14_required_usec := 0
	var dm14_prioritize_usec := 0
	var dm14_protected_usec := 0
	var dm14_filter_usec := 0
	var dm14_get_loaded_usec := 0
	var dm14_scope_parse_usec := 0
	var dm14_release_usec := 0
	var dm14_enqueue_usec := 0
	var dm14_evict_considered := 0
	var dm14_release_max_usec := 0
	var target_regions: Array[Vector2i] = []
	var seen: Dictionary = {}
	for value in target_regions_value:
		if not value is Vector2i:
			return _failure("terrain_effect_runtime_window_region_invalid")
		var region: Vector2i = value
		var id := Contract.scope_id_for_region(region)
		if not seen.has(id):
			seen[id] = true
			target_regions.append(region)
	target_regions.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y < b.y or (a.y == b.y and a.x < b.x)
	)
	dm14_normalize_usec = Time.get_ticks_usec() - dm14_stage_started
	dm14_stage_started = Time.get_ticks_usec()
	var required: Array[Vector2i] = []
	var dm14_dense_used := false
	if _dm14_dense_enabled and SOURCE_REGION_RADIUS == DM14DenseWindow.SOURCE_RADIUS:
		var fast_window: Dictionary = DM14DenseWindow.ordered_required(target_regions)
		if bool(fast_window.get("ok", false)):
			required = fast_window["regions"]
			dm14_dense_used = true
	if not dm14_dense_used:
		required = _required_source_regions_for_regions(target_regions)
	dm14_required_usec = Time.get_ticks_usec() - dm14_stage_started
	dm14_stage_started = Time.get_ticks_usec()
	# Loading the nearest effect sources first avoids blocking the 3x3
	# rendered terrain window behind distant sources in the 9x9 halo.
	# Same required set and hard caps; only prefetch dispatch order changes.
	if not dm14_dense_used and not target_regions.is_empty():
		var minimum := target_regions[0]
		var maximum := target_regions[0]
		for region in target_regions:
			minimum.x = mini(minimum.x, region.x)
			minimum.y = mini(minimum.y, region.y)
			maximum.x = maxi(maximum.x, region.x)
			maximum.y = maxi(maximum.y, region.y)
		var center := Vector2i(
			int((minimum.x + maximum.x) / 2.0),
			int((minimum.y + maximum.y) / 2.0)
		)
		required.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			var da := maxi(absi(a.x - center.x), absi(a.y - center.y))
			var db := maxi(absi(b.x - center.x), absi(b.y - center.y))
			if da != db:
				return da < db
			var ma := absi(a.x - center.x) + absi(a.y - center.y)
			var mb := absi(b.x - center.x) + absi(b.y - center.y)
			if ma != mb:
				return ma < mb
			return a.y < b.y or (a.y == b.y and a.x < b.x)
		)
	dm14_prioritize_usec = Time.get_ticks_usec() - dm14_stage_started
	dm14_stage_started = Time.get_ticks_usec()
	if required.size() > ProjectionService.MAX_RESIDENT_SCOPES:
		return _failure("terrain_effect_runtime_window_scope_budget_exceeded")
	var next_protected: Dictionary = {}
	for region in required:
		next_protected[Contract.scope_id_for_region(region)] = true
	_protected_scope_ids = next_protected
	dm14_protected_usec = Time.get_ticks_usec() - dm14_stage_started
	dm14_stage_started = Time.get_ticks_usec()
	_filter_prefetch_to_protected()
	dm14_filter_usec = Time.get_ticks_usec() - dm14_stage_started
	_prefetch_error = ""
	_performance["window_update_count"] = int(_performance["window_update_count"]) + 1
	_performance["window_target_region_count"] = target_regions.size()
	_performance["protected_scope_count"] = required.size()

	# Release scopes that cannot contribute to the current requested terrain
	# window. No source generation/reconciliation is performed here.
	var evicted_now := 0
	dm14_stage_started = Time.get_ticks_usec()
	var dm14_loaded_ids: Array[String] = projection.get_loaded_scope_ids()
	dm14_get_loaded_usec = Time.get_ticks_usec() - dm14_stage_started
	for scope_id in dm14_loaded_ids:
		if _protected_scope_ids.has(scope_id):
			continue
		if _invalidated_scope_ids.has(scope_id):
			continue

		dm14_evict_considered += 1
		dm14_stage_started = Time.get_ticks_usec()
		var parsed := _region_from_scope_id(scope_id)
		dm14_scope_parse_usec += Time.get_ticks_usec() - dm14_stage_started
		if parsed.get("ok", false):
			dm14_stage_started = Time.get_ticks_usec()
			projection.release_scope(parsed["region_key"], true)
			var dm14_one_release_usec := Time.get_ticks_usec() - dm14_stage_started
			dm14_release_usec += dm14_one_release_usec
			dm14_release_max_usec = maxi(dm14_release_max_usec, dm14_one_release_usec)
			_performance["scope_eviction_count"] = int(
				_performance["scope_eviction_count"]
			) + 1
			_performance["window_eviction_count"] = int(
				_performance["window_eviction_count"]
			) + 1
			evicted_now += 1

	dm14_stage_started = Time.get_ticks_usec()
	if incremental_prefetch_enabled:
		_enqueue_prefetch_regions(required, false)
	dm14_enqueue_usec = Time.get_ticks_usec() - dm14_stage_started
	var window_duration_usec := Time.get_ticks_usec() - window_started_usec
	if _perf_trace_enabled:
		var dm15_dormant_rollup: Dictionary = projection.take_dormant_store_rollup()
		if not dm15_dormant_rollup.is_empty():
			dm15_dormant_rollup["window_target_count"] = target_regions.size()
			PerformanceTrace.emit("dm15_dormant_store_rollup", dm15_dormant_rollup)
	if _dm14_effect_trace:
		PerformanceTrace.emit("dm14_effect_window_stages", {
			"window_duration_usec": window_duration_usec,
			"normalize_usec": dm14_normalize_usec,
			"required_usec": dm14_required_usec,
			"priority_sort_usec": dm14_prioritize_usec,
			"protected_set_usec": dm14_protected_usec,
			"prefetch_filter_usec": dm14_filter_usec,
			"loaded_enumeration_usec": dm14_get_loaded_usec,
			"eviction_parse_usec": dm14_scope_parse_usec,
			"eviction_release_usec": dm14_release_usec,
			"eviction_release_max_usec": dm14_release_max_usec,
			"prefetch_enqueue_usec": dm14_enqueue_usec,
			"target_count": target_regions.size(),
			"required_count": required.size(),
			"dm14_dense_used": dm14_dense_used,
			"loaded_before": dm14_loaded_ids.size(),
			"eviction_considered": dm14_evict_considered,
			"evicted_now": evicted_now,
			"prefetch_pending": get_prefetch_pending_count(),
			"scope_count": projection.get_loaded_scope_count(),
		})
	if _perf_trace_enabled:
		PerformanceTrace.emit("effect_window_update", {
			"duration_usec": window_duration_usec,
			"target_region_count": target_regions.size(),
			"protected_scope_count": required.size(),
			"resident_scope_count": projection.get_loaded_scope_count(),
			"evicted_scope_count": evicted_now,
			"prefetch_pending": get_prefetch_pending_count(),
		})
	return {
		"ok": true,
		"target_region_count": target_regions.size(),
		"protected_scope_count": required.size(),
		"resident_scope_count": projection.get_loaded_scope_count(),
	}


func get_performance_snapshot() -> Dictionary:
	var result := _performance.duplicate(true)
	var calls := int(result["prepare_call_count"])
	result["prepare_average_usec"] = (
		float(result["prepare_total_usec"]) / float(calls)
		if calls > 0 else 0.0
	)
	result["resident_scope_count"] = projection.get_loaded_scope_count() 		if projection != null else 0
	result["prefetch_pending_count"] = _prefetch_queue.size() \
		+ _prefetch_generation_jobs.size() \
		+ _prefetch_projection_jobs.size() \
		+ _prefetch_projection_ready.size()
	result["prefetch_in_flight_count"] = _prefetch_generation_jobs.size() \
		+ _prefetch_projection_jobs.size()
	result["prefetch_generation_in_flight_count"] = _prefetch_generation_jobs.size()
	result["prefetch_projection_in_flight_count"] = _prefetch_projection_jobs.size()
	result["prefetch_projection_ready_count"] = _prefetch_projection_ready.size()
	result["projection_build_cache_entry_count"] = _projection_build_cache.size()
	result["projection_build_cache_capacity"] = MAX_PROJECTION_BUILD_CACHE_ENTRIES
	result["projection_source_cache_entry_count"] = _projection_source_cache.size()
	result["projection_source_cache_capacity"] = MAX_PROJECTION_SOURCE_CACHE_ENTRIES
	result["prefetch_error"] = _prefetch_error
	result["projection"] = projection.get_performance_snapshot() 		if projection != null else {}
	return result


func reset_performance_metrics() -> void:
	_reset_performance_metrics()
	if projection != null:
		projection.reset_performance_metrics()


func _reset_performance_metrics() -> void:
	_performance = {
		"prepare_call_count": 0,
		"prepare_total_usec": 0,
		"prepare_peak_usec": 0,
		"required_scope_check_count": 0,
		"scope_reconcile_count": 0,
		"scope_eviction_count": 0,
		"hot_path_eviction_count": 0,
		"window_eviction_count": 0,
		"window_update_count": 0,
		"window_target_region_count": 0,
		"protected_scope_count": 0,
		"prefetch_scope_count": 0,
		"prefetch_total_usec": 0,
		"prefetch_peak_usec": 0,
		"prefetch_pending_peak": 0,
		"prefetch_worker_dispatch_count": 0,
		"prefetch_worker_complete_count": 0,
		"prefetch_worker_total_usec": 0,
		"prefetch_worker_peak_usec": 0,
		"prefetch_finalize_total_usec": 0,
		"prefetch_finalize_peak_usec": 0,
		"prefetch_source_finalize_total_usec": 0,
		"prefetch_source_finalize_peak_usec": 0,
		"prefetch_projection_worker_dispatch_count": 0,
		"prefetch_projection_worker_complete_count": 0,
		"prefetch_projection_worker_total_usec": 0,
		"prefetch_projection_worker_peak_usec": 0,
		"prefetch_projection_publish_total_usec": 0,
		"prefetch_projection_publish_peak_usec": 0,
		"projection_build_cache_hit_count": 0,
		"projection_build_cache_miss_count": 0,
		"projection_build_cache_eviction_count": 0,
		"projection_build_cache_lookup_total_usec": 0,
		"projection_build_cache_lookup_peak_usec": 0,
		"projection_build_cache_reused_effect_count": 0,
		"projection_source_cache_hit_count": 0,
		"projection_source_cache_miss_count": 0,
		"projection_source_cache_eviction_count": 0,
		"projection_source_cache_lookup_total_usec": 0,
		"projection_source_cache_lookup_peak_usec": 0,
		"projection_source_cache_reused_instance_count": 0,
		"source_finalize_skipped_count": 0,
		"projection_build_cache_key_reuse_count": 0,
	}


func release_all_scopes() -> void:
	wait_for_prefetch_jobs()
	_prefetch_queue.clear()
	_prefetch_scope_ids.clear()
	_projection_source_cache.clear()
	_projection_source_cache_order.clear()
	_prefetch_error = ""
	if projection == null:
		return
	for scope_id in projection.get_loaded_scope_ids():
		var parsed := _region_from_scope_id(scope_id)
		if parsed.get("ok", false):
			projection.release_scope(parsed["region_key"])
	if projection.has_method("purge_dormant_scopes"):
		projection.purge_dormant_scopes()


func get_loaded_scope_count() -> int:
	return projection.get_loaded_scope_count() 		if projection != null and initialized else 0


func _make_projection_capacity(
	required_regions: Array[Vector2i]
) -> Dictionary:
	var required_ids: Dictionary = {}
	for region in required_regions:
		required_ids[Contract.scope_id_for_region(region)] = true
	var loaded_ids: Array[String] = projection.get_loaded_scope_ids()
	var missing_count := 0
	for region in required_regions:
		if not projection.has_scope(region):
			missing_count += 1
	var needed := loaded_ids.size() + missing_count 		- ProjectionService.MAX_RESIDENT_SCOPES
	if needed <= 0:
		return {"ok": true, "released": 0}
	var released := 0
	# Never evict the stable window working set or scopes needed by this job.
	for scope_id in loaded_ids:
		if required_ids.has(scope_id) or _protected_scope_ids.has(scope_id):
			continue
		if _invalidated_scope_ids.has(scope_id):
			continue
		var parsed := _region_from_scope_id(scope_id)
		if not parsed.get("ok", false):
			continue
		projection.release_scope(parsed["region_key"], true)
		released += 1
		_performance["scope_eviction_count"] = int(
			_performance["scope_eviction_count"]
		) + 1
		_performance["hot_path_eviction_count"] = int(
			_performance["hot_path_eviction_count"]
		) + 1
		if released >= needed:
			break
	if projection.get_loaded_scope_count() + missing_count 		> ProjectionService.MAX_RESIDENT_SCOPES:
		return _failure("terrain_effect_runtime_scope_eviction_failed")
	if _perf_trace_enabled and released > 0:
		PerformanceTrace.emit("effect_hot_path_eviction", {
			"released": released,
			"missing_scope_count": missing_count,
			"resident_scope_count": projection.get_loaded_scope_count(),
		})
	return {"ok": true, "released": released}


func _required_source_regions(
	targets: Array[Dictionary]
) -> Array[Vector2i]:
	var target_regions: Array[Vector2i] = []
	var seen: Dictionary = {}
	for target in targets:
		var region: Vector2i = target["region_key"]
		var id := Contract.scope_id_for_region(region)
		if not seen.has(id):
			seen[id] = true
			target_regions.append(region)
	return _required_source_regions_for_regions(target_regions)


func _required_source_regions_for_regions(
	target_regions: Array[Vector2i]
) -> Array[Vector2i]:
	var by_id: Dictionary = {}
	for center in target_regions:
		var center_id := Contract.scope_id_for_region(center)
		var cached: Variant = _required_regions_cache.get(center_id)
		if cached is Array:
			for region_value in cached:
				var region: Vector2i = region_value
				by_id[Contract.scope_id_for_region(region)] = region
			continue
		var local: Array[Vector2i] = []
		for z in range(
			center.y - SOURCE_REGION_RADIUS,
			center.y + SOURCE_REGION_RADIUS + 1
		):
			for x in range(
				center.x - SOURCE_REGION_RADIUS,
				center.x + SOURCE_REGION_RADIUS + 1
			):
				var region := Vector2i(x, z)
				local.append(region)
				by_id[Contract.scope_id_for_region(region)] = region
		_required_regions_cache[center_id] = local
	var result: Array[Vector2i] = []
	var ids: Array[String] = []
	for scope_id in by_id:
		ids.append(String(scope_id))
	ids.sort()
	for scope_id in ids:
		result.append(by_id[scope_id])
	return result


func _normalize_targets(value: Array) -> Dictionary:
	if value.is_empty() or value.size() > 64:
		return _failure("terrain_effect_runtime_targets_invalid")
	var by_id: Dictionary = {}
	for target_value in value:
		if typeof(target_value) != TYPE_DICTIONARY:
			return _failure("terrain_effect_runtime_target_invalid")
		var target: Dictionary = target_value
		if not target.get("region_key") is Vector2i 			or not target.get("chunk_coordinate") is Vector2i:
			return _failure("terrain_effect_runtime_target_fields_invalid")
		var region: Vector2i = target["region_key"]
		var coordinate: Vector2i = target["chunk_coordinate"]
		if not Grid.is_valid_coordinate(coordinate):
			return _failure("terrain_effect_runtime_target_chunk_invalid")
		var id := Grid.stable_id(region, coordinate)
		by_id[id] = {
			"region_key": region,
			"chunk_coordinate": coordinate,
		}
	var ids: Array[String] = []
	for id in by_id:
		ids.append(String(id))
	ids.sort()
	var targets: Array[Dictionary] = []
	for id in ids:
		targets.append(by_id[id])
	return {"ok": true, "targets": targets}


func _region_from_scope_id(scope_id: String) -> Dictionary:
	if not scope_id.begins_with("region:"):
		return {"ok": false}
	var parts := scope_id.trim_prefix("region:").split(",")
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return {"ok": false}
	return {
		"ok": true,
		"region_key": Vector2i(int(parts[0]), int(parts[1])),
	}


func _failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
