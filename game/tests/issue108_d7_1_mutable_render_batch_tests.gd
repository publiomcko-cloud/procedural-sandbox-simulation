extends SceneTree

const Registry := preload("res://scripts/modding/content_definition_registry.gd")
const ObjectWorld := preload("res://scripts/objects/procedural_object_world.gd")
const ObjectStream := preload("res://scripts/objects/procedural_object_stream.gd")
const RockMeshAdapter := preload("res://scripts/objects/procedural_rock_mesh_adapter.gd")
const VisualGeometryJob := preload("res://scripts/objects/procedural_object_visual_geometry_job.gd")
const WorldState := preload("res://scripts/terrain/terrain_world_state.gd")
const BrushState := preload("res://scripts/terrain/sdf_brush_edit_state.gd")
const StateContract := preload("res://scripts/objects/procedural_object_state_contract.gd")

const SEED := 424242
const WORLD_ID := "issue108-d7-1-mutable-render-batch"
const STATE_ROOT := "user://issue108-d7-1-mutable-render-batch-state"

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
	_check(initialized.get("ok", false), "D7.1 stream initializes")
	if not initialized.get("ok", false):
		stream.free()
		_finish()
		return

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
	var baseline_metrics: Dictionary = stream.get_performance_snapshot().get(
		"last_region", {}
	)
	var records: Array[Dictionary] = stream.get_region_instance_records(region)
	_check(records.size() >= 2, "baseline contains multiple procedural objects")
	_check(
		int(baseline_metrics.get("batched_instance_count", -1))
			== records.size()
			and int(baseline_metrics.get("individual_mesh_node_count", -1)) == 0,
		"baseline remains fully static-batched"
	)
	if records.is_empty():
		stream.free()
		_finish()
		return

	var target: Dictionary = records[0]
	var target_id := String(target["instance_id"])
	var translation := Vector3i(400, 250, -150)
	var rotation := Vector3i(12000, -18000, 15000)
	var scale := Vector3i(1200, 900, 1100)
	var transform_result: Dictionary = stream.set_instance_component(
		target_id,
		StateContract.COMPONENT_TRANSFORM,
		{
			"schema_version": 1,
			"properties": {
				"translation_mm": [
					translation.x, translation.y, translation.z
				],
				"rotation_mdeg": [
					rotation.x, rotation.y, rotation.z
				],
				"scale_milli": [scale.x, scale.y, scale.z],
			},
		}
	)
	_check(transform_result.get("ok", false), "transform mutation commits")

	var appearance_result: Dictionary = stream.set_instance_component(
		target_id,
		StateContract.COMPONENT_APPEARANCE,
		{
			"schema_version": 1,
			"properties": {
				"tint_milli": [700, 800, 900],
				"label": "d7-1-batched",
			},
		}
	)
	_check(appearance_result.get("ok", false), "appearance mutation commits")

	var final_metrics: Dictionary = stream.get_performance_snapshot().get(
		"last_region", {}
	)
	var target_cpu: Dictionary = cpu_by_instance[target_id]
	var mutated_record: Dictionary = {}
	for record in stream.get_region_instance_records(region):
		if String(record.get("instance_id", "")) == target_id:
			mutated_record = record
			break
	_check(not mutated_record.is_empty(), "mutated authoritative record remains available")
	_check(
		int(final_metrics.get("batched_instance_count", -1))
			== records.size() - 1,
		"mutated representative leaves the immutable static batch"
	)
	_check(
		int(final_metrics.get("mutable_batched_instance_count", -1)) == 1
			and int(final_metrics.get("total_render_batched_instance_count", -1))
				== records.size(),
		"mutated representative moves into the mutable render batch"
	)
	_check(
		int(final_metrics.get("individual_node_count", -1)) == 1
			and int(final_metrics.get("individual_mesh_node_count", -1)) == 0,
		"identity node remains while its individual MeshInstance3D is eliminated"
	)
	_check(
		int(final_metrics.get("mutable_batch_group_count", -1)) == 1
			and int(final_metrics.get("mutable_batch_cpu_source_count", -1)) == 1,
		"mutable appearance group consumes one CPU geometry source"
	)
	_check(
		int(final_metrics.get("geometry_cache_misses", -1)) == 0,
		"mutable rebuild performs zero individual ArrayMesh cache misses"
	)

	var identity_node := _find_identity_node(stream, target_id)
	_check(identity_node != null, "mutable identity Node3D remains published")
	if identity_node != null:
		var expected_position := (
			Vector3(target["position_mm"]) + Vector3(translation)
		) / 1000.0
		_check(
			identity_node.position.distance_to(expected_position) < 0.0001,
			"identity Node3D preserves the component-adjusted position"
		)
		_check(
			identity_node.get_child_count() == 0,
			"identity Node3D carries no individual mesh child"
		)
		if not mutated_record.is_empty():
			var render_state: Dictionary = stream.call(
				"_batch_render_state", mutated_record
			)
			var expected_basis: Basis = render_state["basis"]
			_check(
				identity_node.transform.basis.is_equal_approx(expected_basis),
				"identity Node3D and mutable batch share the same effective Basis"
			)
		_check(
			String(identity_node.get_meta("instance_label", ""))
				== "d7-1-batched",
			"identity Node3D preserves appearance metadata"
		)

	var mutable_batch := _find_batch_for_id(stream, target_id)
	_check(mutable_batch != null, "mutable render batch contains the target identity")
	if mutable_batch != null:
		_check(
			int(mutable_batch.get_meta("mutable_render_batch_version", 0)) == 1,
			"mutable render batch carries its versioned representation marker"
		)
		_check(
			mutable_batch.get_child_count() == 1
				and mutable_batch.get_child(0) is MeshInstance3D,
			"mutable render batch owns exactly one MeshInstance3D"
		)
		if (
			mutable_batch.get_child_count() == 1
			and mutable_batch.get_child(0) is MeshInstance3D
		):
			var mesh_instance: MeshInstance3D = mutable_batch.get_child(0)
			_check(
				mesh_instance.mesh != null
					and mesh_instance.mesh.get_surface_count() == 1,
				"mutable render batch publishes one valid surface"
			)
			if mesh_instance.mesh != null and not mutated_record.is_empty():
				var arrays: Array = mesh_instance.mesh.surface_get_arrays(0)
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var source_positions: PackedVector3Array = (
					target_cpu.get("positions", PackedVector3Array())
				)
				var render_state: Dictionary = stream.call(
					"_batch_render_state", mutated_record
				)
				var expected_first_vertex: Vector3 = (
					(render_state["basis"] as Basis) * source_positions[0]
					+ (render_state["position"] as Vector3)
				)
				_check(
					not vertices.is_empty()
						and vertices[0].distance_to(expected_first_vertex)
							< 0.0001,
					"mutable batch bakes the authoritative transform into geometry"
				)
			var material := (
				mesh_instance.material_override as StandardMaterial3D
			)
			var base_material: StandardMaterial3D = stream.get(
				"_rock_material"
			)
			_check(
				material != null
					and base_material != null
					and material.albedo_color.r
						< base_material.albedo_color.r,
				"appearance tint is represented by the mutable batch material"
			)

	var cache_key := String(stream.call("_geometry_cache_key", target))
	var worker_variant: Array[Dictionary] = [{
		"cache_key": cache_key,
		"geometry": (target.get("geometry", {}) as Dictionary).duplicate(true),
		"geometry_seeds": (
			target.get("geometry_seeds", {}) as Dictionary
		).duplicate(true),
	}]
	var visual_job := VisualGeometryJob.new(worker_variant)
	visual_job.run()
	var visual_result: Dictionary = visual_job.result
	_check(
		visual_result.get("ok", false)
			and int(visual_result.get("variant_count", -1)) == 1,
		"mutable/placed visual geometry job prepares one variant off the render path"
	)
	if visual_result.get("ok", false):
		var worker_cpu: Dictionary = (
			visual_result.get("cpu_by_cache_key", {}) as Dictionary
		).get(cache_key, {})
		_check(
			worker_cpu.get("ok", false)
				and worker_cpu.get("positions", PackedVector3Array())
					== target_cpu.get("positions", PackedVector3Array())
				and worker_cpu.get("normals", PackedVector3Array())
					== target_cpu.get("normals", PackedVector3Array()),
			"visual geometry worker preserves deterministic CPU geometry"
		)

	evidence = {
		"instance_count": records.size(),
		"static_batched_instance_count": int(
			final_metrics.get("batched_instance_count", -1)
		),
		"mutable_batched_instance_count": int(
			final_metrics.get("mutable_batched_instance_count", -1)
		),
		"mutable_batch_group_count": int(
			final_metrics.get("mutable_batch_group_count", -1)
		),
		"individual_node_count": int(
			final_metrics.get("individual_node_count", -1)
		),
		"individual_mesh_node_count": int(
			final_metrics.get("individual_mesh_node_count", -1)
		),
		"geometry_cache_misses": int(
			final_metrics.get("geometry_cache_misses", -1)
		),
		"geometry_cpu_cache_variant_count": int(
			final_metrics.get("geometry_cpu_cache_variant_count", -1)
		),
		"mutable_batch_vertex_count": int(
			final_metrics.get("mutable_batch_vertex_count", -1)
		),
		"publication_usec": int(
			final_metrics.get("publication_usec", -1)
		),
		"visual_job_worker_usec": int(
			visual_result.get("worker_usec", -1)
		),
	}

	stream.free()
	_finish()


func _find_identity_node(stream: Node, instance_id: String) -> Node3D:
	for region_root in stream.get_children():
		for child in region_root.get_children():
			if (
				child is Node3D
				and String(child.get_meta("stable_instance_id", ""))
					== instance_id
			):
				return child
	return null


func _find_batch_for_id(stream: Node, instance_id: String) -> Node3D:
	for region_root in stream.get_children():
		for child in region_root.get_children():
			if not child is Node3D:
				continue
			var ids: Array = child.get_meta("stable_instance_ids", [])
			if ids.has(instance_id):
				return child
	return null


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
	print("ISSUE108_D7_1_MUTABLE_BATCH_EVIDENCE=" + JSON.stringify(evidence))
	print("ISSUE108_D7_1_MUTABLE_BATCH_%s: assertions=%d failures=%d" % [
		"PASS" if failures == 0 else "FAIL",
		assertions,
		failures,
	])
	_remove_tree(ProjectSettings.globalize_path(STATE_ROOT))
	quit(0 if failures == 0 else 1)
