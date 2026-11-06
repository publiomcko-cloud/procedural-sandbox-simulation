extends SceneTree

const Registry := preload("res://scripts/modding/content_definition_registry.gd")
const ObjectWorld := preload("res://scripts/objects/procedural_object_world.gd")
const Effect := preload("res://scripts/terrain/terrain_object_effect.gd")
const Frame := preload("res://scripts/terrain/terrain_object_effect_local_frame.gd")
const FrameIndex := preload("res://scripts/terrain/terrain_object_effect_local_frame_index.gd")
const Projection := preload("res://scripts/terrain/terrain_object_effect_projection_service.gd")
const Grid := preload("res://scripts/terrain/terrain_chunk_grid.gd")
const Spatial := preload("res://scripts/terrain/terrain_spatial_ownership.gd")
const Field := preload("res://scripts/terrain/sdf_world.gd")

const WORLD_ID := "issue108-pre-d"
const WORLD_SEED := 424242
const ROOT := "user://issue108-pre-d-tests"

var assertions := 0
var failures := 0
var evidence: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_remove_tree(ProjectSettings.globalize_path(ROOT))
	var registry := Registry.new()
	var registered: Dictionary = registry.discover_and_register(["res://mods/first-party"])
	_check(registered.get("ok", false), "registry initializes")
	if not registered.get("ok", false):
		_finish()
		return
	var generated: Dictionary = ObjectWorld.build_region_instances(
		WORLD_SEED, WORLD_ID, Vector2i.ZERO, registry
	)
	_check(generated.get("ok", false), "reference region generates")
	var source := _first_interacting(generated.get("instances", []))
	_check(not source.is_empty(), "reference interacting instance exists")
	if source.is_empty():
		_finish()
		return

	var baseline := _relocate(source, Vector2i.ZERO, source["position_mm"], "baseline")
	var far_positive := _relocate(
		source, Vector2i(100000000, 100000000), source["position_mm"], "far-positive"
	)
	var far_negative := _relocate(
		source, Vector2i(-100000000, -100000000), source["position_mm"], "far-negative"
	)
	var baseline_pair := _build_pair(baseline)
	var positive_pair := _build_pair(far_positive)
	var negative_pair := _build_pair(far_negative)
	_check(baseline_pair.get("ok", false), "baseline effect/frame build")
	_check(positive_pair.get("ok", false), "far-positive effect/frame build")
	_check(negative_pair.get("ok", false), "far-negative effect/frame build")
	if not baseline_pair.get("ok", false) 		or not positive_pair.get("ok", false) 		or not negative_pair.get("ok", false):
		_finish()
		return

	var baseline_frame: Dictionary = baseline_pair["frame"]
	var positive_frame: Dictionary = positive_pair["frame"]
	var negative_frame: Dictionary = negative_pair["frame"]
	_check(
		baseline_frame["local_planes"] == positive_frame["local_planes"]
			and baseline_frame["local_planes"] == negative_frame["local_planes"],
		"local planes are invariant under extreme signed region translation"
	)
	_check(
		baseline_frame["bounds_min_local"] == positive_frame["bounds_min_local"]
			and baseline_frame["bounds_max_local"] == positive_frame["bounds_max_local"]
			and baseline_frame["bounds_min_local"] == negative_frame["bounds_min_local"]
			and baseline_frame["bounds_max_local"] == negative_frame["bounds_max_local"],
		"local bounds are invariant under extreme signed region translation"
	)
	var probe: Vector3 = _array_to_vector3(baseline_frame["interior_point_local"])
	var d0 := Frame.sample_cutter_prevalidated(
		baseline_frame, Vector2i.ZERO, probe
	)
	var dp := Frame.sample_cutter_prevalidated(
		positive_frame, Vector2i(100000000, 100000000), probe
	)
	var dn := Frame.sample_cutter_prevalidated(
		negative_frame, Vector2i(-100000000, -100000000), probe
	)
	_check(is_finite(d0) and d0 < 0.0, "interior local probe is inside cutter")
	_check(
		absf(d0 - dp) <= 0.000000000001
			and absf(d0 - dn) <= 0.000000000001,
		"sampling is translation-invariant at +/-100M regions"
	)

	# Same physical point expressed from the source region and its right neighbor.
	var edge_instance := _relocate(
		source,
		Vector2i(100000000, -100000000),
		Vector3i(
			roundi(Spatial.REGION_SIZE_X * 1000.0) - 100,
			(source["position_mm"] as Vector3i).y,
			(source["position_mm"] as Vector3i).z
		),
		"edge"
	)
	var edge_pair := _build_pair(edge_instance)
	_check(edge_pair.get("ok", false), "edge effect/frame build")
	var edge_frame: Dictionary = edge_pair.get("frame", {})
	if not edge_frame.is_empty():
		var source_key: Vector2i = edge_instance["region_key"]
		var source_local_probe := Vector3(
			Spatial.REGION_SIZE_X + 0.125,
			_array_to_vector3(edge_frame["interior_point_local"]).y,
			_array_to_vector3(edge_frame["interior_point_local"]).z
		)
		var neighbor_probe := Vector3(
			0.125,
			source_local_probe.y,
			source_local_probe.z
		)
		var source_value := Frame.sample_cutter_prevalidated(
			edge_frame, source_key, source_local_probe
		)
		var neighbor_value := Frame.sample_cutter_prevalidated(
			edge_frame, source_key + Vector2i.RIGHT, neighbor_probe
		)
		_check(
			absf(source_value - neighbor_value) <= 0.000000000001,
			"cross-region representation of one point samples identically"
		)

	var frame_index := FrameIndex.new()
	var indexed: Dictionary = frame_index.replace_frame(edge_frame)
	_check(indexed.get("ok", false), "edge frame indexes without world floats")
	var indexed_ids: Array[String] = frame_index.get_indexed_chunk_ids(
		String(edge_frame.get("effect_id", ""))
	)
	var has_source_region := false
	var has_right_region := false
	for chunk_id in indexed_ids:
		if chunk_id.begins_with("%d,%d/" % [
			(edge_instance["region_key"] as Vector2i).x,
			(edge_instance["region_key"] as Vector2i).y,
		]):
			has_source_region = true
		if chunk_id.begins_with("%d,%d/" % [
			(edge_instance["region_key"] as Vector2i).x + 1,
			(edge_instance["region_key"] as Vector2i).y,
		]):
			has_right_region = true
	_check(
		has_source_region and has_right_region,
		"local-frame index preserves cross-region influence at extreme coordinates"
	)

	var projection := Projection.new()
	_check(
		projection.initialize(
			WORLD_ID, WORLD_SEED, Field.GENERATOR_VERSION, ROOT + "/projection"
		).get("ok", false),
		"projection initializes"
	)
	var source_id := String(far_positive["instance_id"])
	var reconcile: Dictionary = projection.reconcile_scope(
		far_positive["region_key"], 7, [far_positive], {source_id: 7}
	)
	_check(reconcile.get("ok", false), "extreme region reconciles into persisted projection")
	var scope: Dictionary = projection.get_scope_snapshot(far_positive["region_key"])
	_check(
		(scope.get("local_frames", {}) as Dictionary).size() == 1,
		"projection persists one precision-safe local frame"
	)
	var persisted_frame: Dictionary = (scope["local_frames"] as Dictionary).values()[0]
	_check(
		persisted_frame["local_planes"] == positive_frame["local_planes"],
		"persisted frame preserves precision-safe geometry"
	)
	projection.release_scope(far_positive["region_key"])
	var reloaded: Dictionary = projection.load_scope(far_positive["region_key"])
	_check(
		reloaded.get("ok", false) and reloaded.get("found", false),
		"extreme region local frame reloads from regional shard"
	)
	var reloaded_scope: Dictionary = projection.get_scope_snapshot(
		far_positive["region_key"]
	)
	var reloaded_frame: Dictionary = (
		reloaded_scope["local_frames"] as Dictionary
	).values()[0]
	_check(
		reloaded_frame["frame_sha256"] == persisted_frame["frame_sha256"]
			and reloaded_frame["local_planes"] == persisted_frame["local_planes"],
		"local frame persistence is canonical across reload"
	)

	evidence = {
		"positive_region": [100000000, 100000000],
		"negative_region": [-100000000, -100000000],
		"baseline_cutter": d0,
		"positive_cutter": dp,
		"negative_cutter": dn,
		"edge_indexed_chunk_count": indexed_ids.size(),
		"projection_schema_version": int(scope.get("schema_version", -1)),
	}
	_finish()


func _build_pair(instance: Dictionary) -> Dictionary:
	var built := Effect.build_from_instance(instance, 7)
	if not built.get("ok", false):
		return built
	var frame := Frame.build_from_instance(instance, built["effect"], 7)
	if not frame.get("ok", false):
		return frame
	return {"ok": true, "effect": built["effect"], "frame": frame["frame"]}


func _first_interacting(instances_value: Variant) -> Dictionary:
	if typeof(instances_value) != TYPE_ARRAY:
		return {}
	for value in instances_value:
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var instance: Dictionary = value
		if not (instance.get("terrain_interaction", {}) as Dictionary).is_empty():
			return instance.duplicate(true)
	return {}


func _relocate(
	source: Dictionary,
	region_key: Vector2i,
	position_mm: Vector3i,
	suffix: String
) -> Dictionary:
	var instance := source.duplicate(true)
	instance["instance_id"] = "%s/seed-%d/pre-d/%s" % [WORLD_ID, WORLD_SEED, suffix]
	instance["world_id"] = WORLD_ID
	instance["world_seed"] = WORLD_SEED
	instance["generator_version"] = Field.GENERATOR_VERSION
	instance["region_key"] = region_key
	instance["position_mm"] = position_mm
	var region_size_x_mm := roundi(Spatial.REGION_SIZE_X * 1000.0)
	var region_size_z_mm := roundi(Spatial.REGION_SIZE_Z * 1000.0)
	instance["world_position_mm"] = Vector3i(
		region_key.x * region_size_x_mm + position_mm.x,
		position_mm.y,
		region_key.y * region_size_z_mm + position_mm.z
	)
	return instance


func _array_to_vector3(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))


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
	print("ISSUE108_PRE_D_EVIDENCE=" + JSON.stringify(evidence))
	print("ISSUE108_PRE_D_%s: assertions=%d failures=%d" % [
		"PASS" if failures == 0 else "FAIL", assertions, failures
	])
	_remove_tree(ProjectSettings.globalize_path(ROOT))
	quit(0 if failures == 0 else 1)
