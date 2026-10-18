extends SceneTree

const Mesher := preload("res://scripts/terrain/marching_tetrahedra.gd")
const BrushState := preload("res://scripts/terrain/sdf_brush_edit_state.gd")
const WorldState := preload("res://scripts/terrain/terrain_world_state.gd")
const Grid := preload("res://scripts/terrain/terrain_chunk_grid.gd")
const MeshJob := preload("res://scripts/terrain/terrain_mesh_job.gd")
const SEED := 424242
const REPEATS := 5
var assertion_count := 0
var failure_count := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("TERRAIN_PERF_BENCH: godot=%s seed=%d repeats=%d chunk=(1,1)" % [Engine.get_version_info().string, SEED, REPEATS])
	for edit_count in [0, 1, 32]:
		var ledger := BrushState.new(SEED)
		for index in range(edit_count):
			var mode := BrushState.Mode.CARVE if index % 2 == 0 else BrushState.Mode.FILL
			var offset := float(index % 4) * 0.08
			var accepted: bool = ledger.add_sphere(mode, Vector3(5.5 + offset, 2.0, 4.0 + offset), 0.85)
			if not accepted:
				push_error("PERF_BENCH_SETUP_FAIL: operation %d rejected" % index)
				quit(1)
		var elapsed := PackedInt64Array()
		var stage_samples: Dictionary = {
			"sdf_and_ledger": PackedInt64Array(),
			"triangulation_and_face_normals": PackedInt64Array(),
			"shared_gradient_normals": PackedInt64Array(),
			"array_mesh_build": PackedInt64Array(),
		}
		var vertex_counts := PackedInt32Array()
		for repetition in range(REPEATS + 1):
			var started := Time.get_ticks_usec()
			var result: Dictionary = Mesher.build_chunk_mesh(
				SEED, Vector2i.ZERO, Vector2i(1, 1), false, ledger if edit_count > 0 else null
			)
			var duration := Time.get_ticks_usec() - started
			if not result.get("valid", false):
				push_error("PERF_BENCH_BUILD_FAIL: edit_count=%d" % edit_count)
				quit(1)
				return
			if repetition == 0:
				continue # warm-up is excluded from the reported distribution
			elapsed.append(duration)
			vertex_counts.append(int(result["vertex_count"]))
			for key in stage_samples:
				stage_samples[key].append(int(result.get("timings_usec", {}).get(key, 0)))
		var sorted_elapsed := _sorted(elapsed)
		print("TERRAIN_PERF_KERNEL: ledger=%d samples=%d total_p50/p95_ms=%.3f/%.3f vertices=%d sdf_p50_ms=%.3f triangulation_p50_ms=%.3f shared_normals_p50_ms=%.3f arraymesh_p50_ms=%.3f" % [
			edit_count, REPEATS, _percentile(sorted_elapsed, 0.50) / 1000.0, _percentile(sorted_elapsed, 0.95) / 1000.0,
			vertex_counts[0], _percentile(_sorted(stage_samples["sdf_and_ledger"]), 0.50) / 1000.0,
			_percentile(_sorted(stage_samples["triangulation_and_face_normals"]), 0.50) / 1000.0,
			_percentile(_sorted(stage_samples["shared_gradient_normals"]), 0.50) / 1000.0,
			_percentile(_sorted(stage_samples["array_mesh_build"]), 0.50) / 1000.0,
		])
		var snapshot: Dictionary = ledger.get_meshing_snapshot()
		var direct: Dictionary = Mesher.build_chunk_mesh(SEED, Vector2i.ZERO, Vector2i(1, 1), false, ledger if edit_count > 0 else null)
		var worker: MeshJob = MeshJob.new(SEED, Vector2i.ZERO, Vector2i(1, 1), false, snapshot if edit_count > 0 else null, Time.get_ticks_usec())
		var task_id := WorkerThreadPool.add_task(Callable(worker, "run"), false, "terrain equivalence")
		await _wait_for_tasks([task_id])
		_check(task_id >= 0 and not worker.result.has("mesh"), "worker returns CPU-only arrays for ledger %d" % edit_count)
		var worker_mesh: Dictionary = Mesher.mesh_from_cpu_data(worker.result)
		_check(_meshes_exactly_equal(direct["mesh"], worker_mesh["mesh"]), "threaded CPU mesh exactly matches serial geometry and normals for ledger %d" % edit_count)
	var parallel_jobs: Array[MeshJob] = []
	var parallel_task_ids: Array[int] = []
	var parallel_coords: Array[Vector2i] = [Vector2i(0, 0), Vector2i(3, 0), Vector2i(0, 3), Vector2i(3, 3)]
	for coordinate in parallel_coords:
		var job: MeshJob = MeshJob.new(SEED, Vector2i(-1, 0), coordinate, false, null, Time.get_ticks_usec())
		parallel_jobs.append(job)
		parallel_task_ids.append(WorkerThreadPool.add_task(Callable(job, "run"), false, "terrain parallel equivalence"))
	await _wait_for_tasks(parallel_task_ids)
	var worker_threads: Dictionary = {}
	for index in range(parallel_jobs.size()):
		var job := parallel_jobs[index]
		worker_threads[job.worker_thread_id] = true
		var threaded_mesh: Dictionary = Mesher.mesh_from_cpu_data(job.result)
		var serial_mesh: Dictionary = Mesher.build_chunk_mesh(SEED, Vector2i(-1, 0), parallel_coords[index])
		_check(_meshes_exactly_equal(threaded_mesh["mesh"], serial_mesh["mesh"]), "parallel task preserves exact chunk geometry %s" % parallel_coords[index])
	_check(parallel_task_ids.all(func(task_id: int) -> bool: return task_id >= 0), "four CPU mesh tasks are accepted by the worker pool")
	_check(worker_threads.size() >= 2, "worker mesh calculations execute concurrently on multiple worker threads")
	if failure_count == 0:
		print("TERRAIN_PERF_BENCH_PASS: assertions=%d failures=0" % assertion_count)
		quit(0)
	else:
		push_error("TERRAIN_PERF_BENCH_FAIL: assertions=%d failures=%d" % [assertion_count, failure_count])
		quit(1)


func _sorted(values: PackedInt64Array) -> PackedInt64Array:
	var result := values.duplicate()
	result.sort()
	return result


func _percentile(values: PackedInt64Array, fraction: float) -> int:
	if values.is_empty():
		return 0
	var index := clampi(ceili(float(values.size()) * fraction) - 1, 0, values.size() - 1)
	return values[index]


func _wait_for_tasks(task_ids: Array[int]) -> void:
	while true:
		var all_complete := true
		for task_id in task_ids:
			if task_id >= 0 and not WorkerThreadPool.is_task_completed(task_id):
				all_complete = false
				break
		if all_complete:
			break
		await process_frame
	for task_id in task_ids:
		if task_id >= 0:
			WorkerThreadPool.wait_for_task_completion(task_id)


func _meshes_exactly_equal(left: ArrayMesh, right: ArrayMesh) -> bool:
	if left.get_surface_count() != right.get_surface_count():
		return false
	if left.get_surface_count() == 0:
		return true
	var left_arrays: Array = left.surface_get_arrays(0)
	var right_arrays: Array = right.surface_get_arrays(0)
	return left_arrays[Mesh.ARRAY_VERTEX] == right_arrays[Mesh.ARRAY_VERTEX] \
		and left_arrays[Mesh.ARRAY_NORMAL] == right_arrays[Mesh.ARRAY_NORMAL]


func _check(condition: bool, message: String) -> void:
	assertion_count += 1
	if not condition:
		failure_count += 1
		push_error("PERF_BENCH_ASSERTION_FAILED: " + message)
