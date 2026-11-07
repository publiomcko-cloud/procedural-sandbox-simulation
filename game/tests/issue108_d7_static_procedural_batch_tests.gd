extends SceneTree

const Registry := preload("res://scripts/modding/content_definition_registry.gd")
const ObjectWorld := preload("res://scripts/objects/procedural_object_world.gd")
const ObjectStream := preload("res://scripts/objects/procedural_object_stream.gd")
const RockMeshAdapter := preload("res://scripts/objects/procedural_rock_mesh_adapter.gd")
const StaticBatch := preload("res://scripts/objects/procedural_object_static_batch.gd")
const WorldState := preload("res://scripts/terrain/terrain_world_state.gd")
const BrushState := preload("res://scripts/terrain/sdf_brush_edit_state.gd")

const SEED := 424242
const WORLD_ID := "issue108-d7-static-procedural-batch"
const STATE_ROOT := "user://issue108-d7-static-batch-state"

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

	var instances: Array = generated.get("instances", [])
	_check(instances.size() >= 2, "reference region contains multiple procedural objects")
	var cpu_by_instance: Dictionary = {}
	var legacy_count := 0
	for value in instances:
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var instance: Dictionary = value
		if (
			String(instance.get("population_rule_id", "")).is_empty()
			and String(instance.get("population_algorithm", ""))
				!= "explicit_place_v1"
		):
			legacy_count += 1
		var cpu: Dictionary = RockMeshAdapter.build_cpu_data(
			instance.get("geometry", {}),
			instance.get("geometry_seeds", {})
		)
		_check(
			cpu.get("ok", false),
			"worker-equivalent CPU geometry builds for %s"
				% String(instance.get("instance_id", ""))
		)
		if cpu.get("ok", false):
			cpu_by_instance[String(instance.get("instance_id", ""))] = cpu
	_check(legacy_count > 0, "reference region contains legacy procedural compatibility objects")
	_check(
		cpu_by_instance.size() == instances.size(),
		"CPU geometry is available for every generated procedural object"
	)

	generated["geometry_cpu_by_instance"] = cpu_by_instance
	generated["geometry_cpu_usec"] = 1

	var stream := ObjectStream.new()
	var initialized: Dictionary = stream.initialize(
		SEED,
		WORLD_ID,
		["res://mods/first-party"],
		STATE_ROOT
	)
	_check(initialized.get("ok", false), "D7 stream initializes")
	if not initialized.get("ok", false):
		stream.free()
		_finish()
		return

	var legacy_candidate: Dictionary = {}
	for value in instances:
		var instance: Dictionary = value
		if (
			String(instance.get("population_rule_id", "")).is_empty()
			and String(instance.get("population_algorithm", ""))
				!= "explicit_place_v1"
		):
			legacy_candidate = instance.duplicate(true)
			break
	_check(
		not legacy_candidate.is_empty()
			and bool(stream.call("_is_static_batch_candidate", legacy_candidate)),
		"unmodified legacy procedural objects are batch candidates"
	)
	var placed_like: Dictionary = legacy_candidate.duplicate(true)
	placed_like["population_algorithm"] = "explicit_place_v1"
	_check(
		not bool(stream.call("_is_static_batch_candidate", placed_like)),
		"explicitly placed entities remain outside the static procedural batch"
	)
	var stateful_like: Dictionary = legacy_candidate.duplicate(true)
	stateful_like["instance_components"] = {
		"core.appearance": {
			"schema_version": 1,
			"properties": {"tint_milli": [900, 900, 900], "label": "stateful"},
		},
	}
	_check(
		not bool(stream.call("_is_static_batch_candidate", stateful_like)),
		"component-bearing procedural objects remain individual"
	)

	var reference_items_cpu: Array[Dictionary] = []
	var reference_items_mesh: Array[Dictionary] = []
	for index in range(mini(2, instances.size())):
		var instance: Dictionary = instances[index]
		var instance_id := String(instance["instance_id"])
		var cpu: Dictionary = cpu_by_instance[instance_id]
		var mesh_result: Dictionary = RockMeshAdapter.mesh_from_cpu_data(cpu)
		_check(mesh_result.get("ok", false), "reference individual mesh commits")
		var common: Dictionary = {
			"instance_id": instance_id,
			"position": Vector3(instance["position_mm"]) / 1000.0,
			"scale_milli": instance.get(
				"default_scale_milli", Vector3i(1000, 1000, 1000)
			),
			"yaw_mdeg": int(instance.get("default_yaw_mdeg", 0)),
		}
		var cpu_item: Dictionary = common.duplicate(true)
		cpu_item["cpu_data"] = cpu
		reference_items_cpu.append(cpu_item)
		var mesh_item: Dictionary = common.duplicate(true)
		mesh_item["mesh"] = mesh_result["mesh"]
		reference_items_mesh.append(mesh_item)

	var cpu_batch: Dictionary = StaticBatch.build(reference_items_cpu)
	var mesh_batch: Dictionary = StaticBatch.build(reference_items_mesh)
	_check(
		cpu_batch.get("ok", false) and mesh_batch.get("ok", false),
		"CPU-direct and legacy mesh-source static batches both build"
	)
	if cpu_batch.get("ok", false) and mesh_batch.get("ok", false):
		var cpu_arrays: Array = cpu_batch["mesh"].surface_get_arrays(0)
		var mesh_arrays: Array = mesh_batch["mesh"].surface_get_arrays(0)
		_check(
			cpu_arrays[Mesh.ARRAY_VERTEX] == mesh_arrays[Mesh.ARRAY_VERTEX]
				and cpu_arrays[Mesh.ARRAY_NORMAL]
					== mesh_arrays[Mesh.ARRAY_NORMAL],
			"CPU-direct batching preserves exact rendered positions and normals"
		)
		_check(
			int(cpu_batch.get("cpu_source_count", 0))
				== reference_items_cpu.size()
				and int(cpu_batch.get("mesh_source_count", -1)) == 0,
			"CPU-direct batch reports no intermediate mesh sources"
		)

	var state: RefCounted = WorldState.new(
		SEED, region, BrushState.new(SEED)
	)
	var published: Dictionary = stream.publish_region(
		region,
		state,
		false,
		-1,
		generated
	)
	_check(published.get("ok", false), "reference region publishes through D7")
	var metrics: Dictionary = stream.get_performance_snapshot().get(
		"last_region", {}
	)
	_check(
		int(metrics.get("batched_instance_count", -1)) == instances.size()
			and int(metrics.get("individual_node_count", -1)) == 0,
		"all unmodified generated procedural objects publish in one static batch"
	)
	_check(
		int(metrics.get("batch_cpu_source_count", -1)) == instances.size()
			and int(metrics.get("batch_mesh_source_count", -1)) == 0,
		"region batch consumes worker CPU geometry without intermediate ArrayMeshes"
	)
	_check(
		int(metrics.get("geometry_cache_misses", -1)) == 0
			and int(metrics.get("geometry_cache_variant_count", -1)) == 0,
		"static procedural publication performs zero individual geometry mesh commits"
	)
	_check(
		int(metrics.get("batch_vertex_count", 0)) > 0
			and int(metrics.get("batch_vertex_count", 0))
				<= StaticBatch.MAX_BATCH_VERTICES,
		"regional static batch remains inside the explicit vertex budget"
	)

	var batch_node: Node = stream.get_node_or_null(
		"Objects_0_0/StaticPopulationBatch"
	)
	_check(batch_node != null, "regional static batch node is published")
	if batch_node != null:
		var stable_ids: Array = batch_node.get_meta(
			"stable_instance_ids", []
		)
		var selection_records: Array = batch_node.get_meta(
			"selection_records", []
		)
		_check(
			stable_ids.size() == instances.size()
				and selection_records.size() == instances.size(),
			"batch preserves per-entity identity and selection metadata"
		)

	evidence = {
		"instance_count": instances.size(),
		"legacy_procedural_count": legacy_count,
		"batched_instance_count": int(metrics.get(
			"batched_instance_count", -1
		)),
		"individual_node_count": int(metrics.get(
			"individual_node_count", -1
		)),
		"batch_cpu_source_count": int(metrics.get(
			"batch_cpu_source_count", -1
		)),
		"batch_mesh_source_count": int(metrics.get(
			"batch_mesh_source_count", -1
		)),
		"geometry_cache_misses": int(metrics.get(
			"geometry_cache_misses", -1
		)),
		"geometry_cache_variant_count": int(metrics.get(
			"geometry_cache_variant_count", -1
		)),
		"batch_vertex_count": int(metrics.get("batch_vertex_count", -1)),
		"publication_usec": int(metrics.get("publication_usec", -1)),
		"batch_build_usec": int(metrics.get("batch_build_usec", -1)),
	}

	stream.free()
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
	print("ISSUE108_D7_STATIC_BATCH_EVIDENCE=" + JSON.stringify(evidence))
	print("ISSUE108_D7_STATIC_BATCH_%s: assertions=%d failures=%d" % [
		"PASS" if failures == 0 else "FAIL",
		assertions,
		failures,
	])
	_remove_tree(ProjectSettings.globalize_path(STATE_ROOT))
	quit(0 if failures == 0 else 1)
