extends SceneTree

const Registry := preload("res://scripts/modding/content_definition_registry.gd")
const ObjectWorld := preload("res://scripts/objects/procedural_object_world.gd")
const ObjectStream := preload("res://scripts/objects/procedural_object_stream.gd")
const RockMeshAdapter := preload("res://scripts/objects/procedural_rock_mesh_adapter.gd")
const WorldState := preload("res://scripts/terrain/terrain_world_state.gd")
const BrushState := preload("res://scripts/terrain/sdf_brush_edit_state.gd")
const StateContract := preload("res://scripts/objects/procedural_object_state_contract.gd")

const SEED := 424242
const WORLD_ID := "issue108-d7-2-worker-batch-preparation"
const STATE_ROOT := "user://issue108-d7-2-worker-batch-state"

var assertions := 0
var failures := 0
var evidence: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_remove_tree(ProjectSettings.globalize_path(STATE_ROOT))

	var registry := Registry.new()
	var registered: Dictionary = registry.discover_and_register([
		"res://mods/first-party"
	])
	_check(registered.get("ok", false), "first-party registry initializes")
	if not registered.get("ok", false):
		_finish()
		return

	var region := Vector2i.ZERO
	var generated: Dictionary = ObjectWorld.build_region_instances(
		SEED, WORLD_ID, region, registry
	)
	_check(generated.get("ok", false), "reference region generates")
	if not generated.get("ok", false):
		_finish()
		return

	var cpu_by_instance: Dictionary = {}
	for value in generated.get("instances", []):
		var instance: Dictionary = value
		var cpu: Dictionary = RockMeshAdapter.build_cpu_data(
			instance.get("geometry", {}),
			instance.get("geometry_seeds", {})
		)
		_check(
			cpu.get("ok", false),
			"reference CPU geometry builds for %s"
				% String(instance.get("instance_id", ""))
		)
		if cpu.get("ok", false):
			cpu_by_instance[String(instance["instance_id"])] = cpu
	generated["geometry_cpu_by_instance"] = cpu_by_instance
	generated["geometry_cpu_usec"] = 1

	var stream := ObjectStream.new()
	var initialized: Dictionary = stream.initialize(
		SEED,
		WORLD_ID,
		["res://mods/first-party"],
		STATE_ROOT
	)
	_check(initialized.get("ok", false), "D7.2 stream initializes")
	if not initialized.get("ok", false):
		stream.free()
		_finish()
		return
	root.add_child(stream)

	var state: RefCounted = WorldState.new(
		SEED, region, BrushState.new(SEED)
	)
	var first: Dictionary = stream.publish_region(
		region,
		state,
		false,
		-1,
		generated
	)
	_check(first.get("ok", false), "baseline region publishes")
	var records: Array[Dictionary] = stream.get_region_instance_records(region)
	_check(records.size() >= 2, "baseline contains multiple procedural objects")
	if records.is_empty():
		stream.queue_free()
		await process_frame
		_finish()
		return

	var target: Dictionary = records[0]
	var target_id := String(target["instance_id"])
	var transform_result: Dictionary = stream.set_instance_component(
		target_id,
		StateContract.COMPONENT_TRANSFORM,
		{
			"schema_version": 1,
			"properties": {
				"translation_mm": [250, 125, -100],
				"rotation_mdeg": [9000, -12000, 7000],
				"scale_milli": [1100, 950, 1050],
			},
		}
	)
	_check(transform_result.get("ok", false), "stateful transform mutation commits")
	var appearance_result: Dictionary = stream.set_instance_component(
		target_id,
		StateContract.COMPONENT_APPEARANCE,
		{
			"schema_version": 1,
			"properties": {
				"tint_milli": [800, 900, 700],
				"label": "d7-2-worker-batch",
			},
		}
	)
	_check(appearance_result.get("ok", false), "stateful appearance mutation commits")

	var request := {
		"region_key": region,
		"world_state": state,
		"publication_token": -1,
		"force_rebuild": true,
		"request_serial": 7202,
	}
	stream.call(
		"_queue_region_visual_preparation",
		"0,0",
		request,
		generated
	)

	var main_thread_id := OS.get_thread_caller_id()
	var prepared_snapshot: Dictionary = {}
	var final_metrics: Dictionary = {}
	for _frame in range(600):
		stream.process_queued_publications()
		var preparations: Dictionary = stream.get(
			"_region_visual_preparations"
		)
		if preparations.has("0,0"):
			var record: Dictionary = preparations["0,0"]
			var prepared_generated: Dictionary = record.get(
				"generated", {}
			)
			if prepared_generated.has("_visual_batch_prepared"):
				prepared_snapshot = (
					prepared_generated["_visual_batch_prepared"]
					as Dictionary
				).duplicate(true)
		final_metrics = stream.get_performance_snapshot().get(
			"last_region", {}
		)
		if (
			bool(final_metrics.get("batch_prepare_reused", false))
			and bool(final_metrics.get("prepared_base_adopted", false))
		):
			break
		await process_frame

	_check(
		not prepared_snapshot.is_empty()
			and prepared_snapshot.get("ok", false),
		"worker produces a reusable regional batch preparation"
	)
	if not prepared_snapshot.is_empty():
		var static_prepared: Dictionary = prepared_snapshot.get("static", {})
		_check(
			not static_prepared.has("mesh")
				and static_prepared.has("positions")
				and static_prepared.has("normals"),
			"worker output contains CPU arrays and no ArrayMesh resource"
		)
		for group_key in (
			prepared_snapshot.get("mutable", {}) as Dictionary
		):
			var mutable_prepared: Dictionary = (
				prepared_snapshot["mutable"] as Dictionary
			)[group_key]
			_check(
				not mutable_prepared.has("mesh"),
				"mutable worker batch contains no render resource"
			)

	_check(
		bool(final_metrics.get("batch_prepare_reused", false)),
		"publication commits the worker-prepared batch arrays"
	)
	_check(
		bool(final_metrics.get("prepared_base_adopted", false)),
		"publication adopts the revision-gated prepared base list"
	)
	_check(
		int(final_metrics.get("batch_prepare_worker_thread_id", 0)) > 0
			and int(final_metrics.get("batch_prepare_worker_thread_id", 0))
				!= main_thread_id,
		"regional batch preparation executes off the main thread"
	)
	_check(
		int(final_metrics.get("resolved_reuse_count", 0)) > 0,
		"prepared state resolutions are reused during publication"
	)
	_check(
		int(final_metrics.get("individual_mesh_node_count", -1)) == 0,
		"D7.2 preserves zero supported-rock individual mesh nodes"
	)
	_check(
		int(final_metrics.get("mutable_batched_instance_count", -1)) == 1,
		"stateful target remains in one mutable regional batch"
	)
	_check(
		int(final_metrics.get("total_render_batched_instance_count", -1))
			== records.size(),
		"all active supported rocks remain render-batched"
	)
	_check(
		int(final_metrics.get("geometry_cache_misses", -1)) == 0,
		"prepared publication performs zero individual ArrayMesh cache misses"
	)

	evidence = {
		"instance_count": records.size(),
		"batch_prepare_worker_usec": int(
			final_metrics.get("batch_prepare_worker_usec", -1)
		),
		"batch_prepare_worker_thread_id": int(
			final_metrics.get("batch_prepare_worker_thread_id", -1)
		),
		"main_thread_id": main_thread_id,
		"batch_commit_usec": int(
			final_metrics.get("batch_commit_usec", -1)
		),
		"batch_build_usec": int(
			final_metrics.get("batch_build_usec", -1)
		),
		"main_thread_reconstruction_usec": int(
			final_metrics.get("main_thread_reconstruction_usec", -1)
		),
		"prepared_base_adoption_usec": int(
			final_metrics.get("prepared_base_adoption_usec", -1)
		),
		"publication_usec": int(
			final_metrics.get("publication_usec", -1)
		),
		"resolved_reuse_count": int(
			final_metrics.get("resolved_reuse_count", -1)
		),
		"batch_prepare_reused": bool(
			final_metrics.get("batch_prepare_reused", false)
		),
		"prepared_base_adopted": bool(
			final_metrics.get("prepared_base_adopted", false)
		),
	}

	stream.queue_free()
	await process_frame
	_finish()


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
	print("ISSUE108_D7_2_WORKER_BATCH_EVIDENCE=" + JSON.stringify(evidence))
	print("ISSUE108_D7_2_WORKER_BATCH_%s: assertions=%d failures=%d" % [
		"PASS" if failures == 0 else "FAIL",
		assertions,
		failures,
	])
	_remove_tree(ProjectSettings.globalize_path(STATE_ROOT))
	quit(0 if failures == 0 else 1)
