extends SceneTree

const Grid := preload("res://scripts/terrain/terrain_chunk_grid.gd")
const Mesher := preload("res://scripts/terrain/marching_tetrahedra.gd")
const BrushState := preload("res://scripts/terrain/sdf_brush_edit_state.gd")
const WorldState := preload("res://scripts/terrain/terrain_world_state.gd")
const MAX_FRAMES := 3000

var assertions := 0
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load("res://scenes/terrain_demo.tscn") as PackedScene
	_check(packed != null, "cancellation test scene loads")
	if packed == null:
		_finish()
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	for _frame in range(10):
		if scene.get("_mesh_jobs").size() > 0:
			break
		await process_frame
	var old_inflight: int = scene.get("_mesh_jobs").size()
	_check(old_inflight > 0 and old_inflight <= 4, "streaming submits a bounded worker set before cancellation")
	scene.call("_move_focus", Vector3(64.0, 0.0, 0.0))
	_check(not scene.get("loading_regions").has("0,0"), "unrequested stage is removed from publication eligibility immediately")
	await _wait_for_window(scene)
	_check(not scene.get("active_regions").has("0,0"), "completed obsolete worker results never publish into an out-of-window region")
	_check(scene.get("active_regions").size() == 9, "new requested region window completes after canceled jobs")
	scene.call("_move_focus", Vector3(-64.0, 0.0, 0.0))
	await _wait_for_window(scene)
	var old_mesh: ArrayMesh = scene.get("chunk_nodes")[Grid.stable_id(Vector2i.ZERO, Vector2i(2, 2))].mesh
	var accepted: bool = scene.call("_accept_brush_at_world", Vector3(8.0, 4.0, 6.0))
	_check(accepted, "stale-publication fixture accepts one canonical brush command")
	await process_frame
	var edit_inflight: int = scene.get("_mesh_jobs").size()
	scene.call("_start_global_rebuild", "cancel_obsolete_edit_stage_test")
	_check(scene.get("_edit_transaction").is_empty(), "full rebuild invalidates the old edit transaction")
	await _wait_for_global_rebuild(scene)
	# The scalable runtime materializes historical edits and exposes an immutable
	# per-chunk meshing snapshot. The legacy build_chunk_mesh RefCounted path only
	# understands SdfBrushEditState, so using the scalable state object directly
	# silently falls back to the base field and produces a false reference mesh.
	var expected_snapshot: Dictionary = scene.get("edit_ledger").get_meshing_snapshot_for_chunk(
		Vector2i.ZERO, Vector2i(2, 2)
	)
	_check(expected_snapshot.get("valid", false), "latest scalable ledger snapshot is available after cancellation")
	var expected_cpu: Dictionary = Mesher.build_chunk_cpu_data(
		WorldState.DEMO_SEED, Vector2i.ZERO, Vector2i(2, 2), false, expected_snapshot
	)
	var expected: Dictionary = Mesher.mesh_from_cpu_data(expected_cpu)
	var actual: ArrayMesh = scene.get("chunk_nodes")[Grid.stable_id(Vector2i.ZERO, Vector2i(2, 2))].mesh
	_check(_meshes_equal(actual, expected["mesh"]), "latest ledger revision wins after cancellation and atomic full rebuild")
	_check(actual != old_mesh, "accepted edit becomes visible only through the replacement mesh set")
	_check(edit_inflight <= 4, "edit cancellation retains the fixed in-flight worker cap")
	_check(scene.get("last_mesh_diagnostics").get("mesh_jobs_in_flight", 0) <= 4, "diagnostics report bounded worker concurrency")
	scene.queue_free()
	await process_frame
	_finish()


func _wait_for_window(scene: Node) -> void:
	for _frame in range(MAX_FRAMES):
		if scene.get("active_regions").size() == 9 and scene.get("loading_regions").is_empty():
			return
		await process_frame
	_check(false, "requested region window completes before timeout")


func _wait_for_global_rebuild(scene: Node) -> void:
	for _frame in range(MAX_FRAMES):
		if not scene.get("global_rebuild_pending") and scene.get("loading_regions").is_empty():
			return
		await process_frame
	_check(false, "global rebuild completes before timeout")


func _meshes_equal(left: ArrayMesh, right: ArrayMesh) -> bool:
	if left.get_surface_count() != right.get_surface_count():
		return false
	if left.get_surface_count() == 0:
		return true
	var a: Array = left.surface_get_arrays(0)
	var b: Array = right.surface_get_arrays(0)
	return a[Mesh.ARRAY_VERTEX] == b[Mesh.ARRAY_VERTEX] and a[Mesh.ARRAY_NORMAL] == b[Mesh.ARRAY_NORMAL]


func _check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error("TERRAIN_CONCURRENCY_ASSERTION_FAILED: " + message)


func _finish() -> void:
	if failures == 0:
		print("TERRAIN_CONCURRENCY_PASS: assertions=%d failures=0" % assertions)
		quit(0)
	else:
		push_error("TERRAIN_CONCURRENCY_FAIL: assertions=%d failures=%d" % [assertions, failures])
		quit(1)
