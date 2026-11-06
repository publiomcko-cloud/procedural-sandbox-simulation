extends SceneTree

const Registry := preload("res://scripts/modding/content_definition_registry.gd")
const ObjectWorld := preload("res://scripts/objects/procedural_object_world.gd")
const BrushState := preload("res://scripts/terrain/sdf_brush_edit_state.gd")
const Runtime := preload("res://scripts/terrain/terrain_object_effect_runtime.gd")
const Grid := preload("res://scripts/terrain/terrain_chunk_grid.gd")
const Spatial := preload("res://scripts/terrain/terrain_spatial_ownership.gd")
const Field := preload("res://scripts/terrain/sdf_world.gd")

const WORLD_ID := "issue108-d1-performance"
const WORLD_SEED := 424242
const ROOT := "user://issue108-d1-performance"
const REQUEST_RADIUS := 1
const RETAINED_RADIUS := 2
const TRAVERSAL_STEPS := 8

var assertions := 0
var failures := 0
var evidence: Dictionary = {}


class FakeObjectStream:
	extends Node

	var sources: Dictionary = {}
	var world_revision := 0

	func get_command_world_revision() -> int:
		return world_revision

	func get_authoritative_region_projection_source(region_key: Vector2i) -> Dictionary:
		var key := "%d,%d" % [region_key.x, region_key.y]
		var instances: Array[Dictionary] = []
		var revisions: Dictionary = {}
		if sources.has(key):
			var instance: Dictionary = (sources[key] as Dictionary).duplicate(true)
			instances.append(instance)
			revisions[String(instance["instance_id"])] = 0
		return {
			"ok": true,
			"region_key": region_key,
			"world_revision": world_revision,
			"instances": instances,
			"source_revisions": revisions,
		}


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
	_check(not source.is_empty(), "interacting source exists")
	if source.is_empty():
		_finish()
		return

	var fake := FakeObjectStream.new()
	for z in range(-4, 5):
		for x in range(-4, TRAVERSAL_STEPS + 5):
			var region := Vector2i(x, z)
			fake.sources["%d,%d" % [x, z]] = _relocate(source, region)

	var runtime := Runtime.new()
	var initialized: Dictionary = runtime.initialize(
		WORLD_ID,
		WORLD_SEED,
		Field.GENERATOR_VERSION,
		fake,
		ROOT + "/projection"
	)
	_check(initialized.get("ok", false), "runtime initializes")
	if not initialized.get("ok", false):
		_finish()
		return
	var ledger := BrushState.new(WORLD_SEED, Field.GENERATOR_VERSION)

	var initial_started := Time.get_ticks_usec()
	var initial := _exercise_focus(runtime, ledger, Vector2i.ZERO, true)
	var initial_usec := Time.get_ticks_usec() - initial_started
	_check(initial.get("ok", false), "initial retained 5x5 window prepares")
	var initial_perf: Dictionary = runtime.get_performance_snapshot()
	var initial_projection: Dictionary = initial_perf.get("projection", {})
	var initial_calls := int(initial_projection.get("snapshot_call_count", 0))
	var initial_peak_resident := int(initial_projection.get("peak_resident_scope_count", 0))
	var initial_actual_lookups := int(
		initial_projection.get("lookup_scope_index_examined_count", 0)
	)
	var initial_legacy_scan := initial_calls * initial_peak_resident
	_check(
		int(initial_perf.get("hot_path_eviction_count", -1)) == 0,
		"initial working set has zero hot-path scope eviction"
	)
	_check(
		int(initial_perf.get("resident_scope_count", -1)) == 81
			and int(initial_perf.get("protected_scope_count", -1)) == 81,
		"retained 5x5 plus effect halo produces exact bounded 81-scope working set"
	)
	_check(
		initial_legacy_scan > 0
			and initial_actual_lookups * 8 < initial_legacy_scan,
		"reverse routing examines at least 8x fewer scope indexes than legacy resident scan"
	)

	# Warm steady-state: no scope generation, reconciliation, release, or load.
	runtime.reset_performance_metrics()
	var warm_started := Time.get_ticks_usec()
	var warm := _exercise_focus(runtime, ledger, Vector2i.ZERO, true)
	var warm_usec := Time.get_ticks_usec() - warm_started
	_check(warm.get("ok", false), "warm stationary window prepares")
	var warm_perf: Dictionary = runtime.get_performance_snapshot()
	var warm_projection: Dictionary = warm_perf.get("projection", {})
	_check(
		int(warm_perf.get("scope_reconcile_count", -1)) == 0,
		"warm hot path performs zero source reconciliations"
	)
	_check(
		int(warm_projection.get("scope_load_count", -1)) == 0
			and int(warm_projection.get("scope_release_count", -1)) == 0,
		"warm hot path performs zero scope load/release churn"
	)
	_check(
		int(warm_perf.get("hot_path_eviction_count", -1)) == 0,
		"warm hot path performs zero capacity evictions"
	)

	# Traverse eight region steps, then return. A one-region shift of the 9x9
	# source working set should replace one strip of 9 scopes per step.
	runtime.reset_performance_metrics()
	var traversal_started := Time.get_ticks_usec()
	for x in range(1, TRAVERSAL_STEPS + 1):
		var moved := _exercise_focus(runtime, ledger, Vector2i(x, 0), true)
		if not moved.get("ok", false):
			_check(false, "forward traversal focus %d prepares" % x)
			_finish()
			return
	for x in range(TRAVERSAL_STEPS - 1, -1, -1):
		var returned := _exercise_focus(runtime, ledger, Vector2i(x, 0), true)
		if not returned.get("ok", false):
			_check(false, "return traversal focus %d prepares" % x)
			_finish()
			return
	var traversal_usec := Time.get_ticks_usec() - traversal_started
	var travel_perf: Dictionary = runtime.get_performance_snapshot()
	var travel_projection: Dictionary = travel_perf.get("projection", {})
	var travel_calls := int(travel_projection.get("snapshot_call_count", 0))
	var travel_peak_resident := int(
		travel_projection.get("peak_resident_scope_count", 0)
	)
	var travel_actual_lookups := int(
		travel_projection.get("lookup_scope_index_examined_count", 0)
	)
	var travel_legacy_scan := travel_calls * travel_peak_resident
	_check(
		int(travel_perf.get("hot_path_eviction_count", -1)) == 0,
		"stream traversal has zero hot-path eviction thrashing"
	)
	_check(
		int(travel_perf.get("window_eviction_count", 999999))
			<= TRAVERSAL_STEPS * 2 * 9,
		"stream traversal eviction is bounded by one 9-scope strip per region step"
	)
	_check(
		int(travel_projection.get("peak_resident_scope_count", 999999)) <= 81,
		"stream traversal never exceeds the derived 81-scope working set"
	)
	_check(
		travel_legacy_scan > 0
			and travel_actual_lookups * 8 < travel_legacy_scan,
		"traversal reverse routing remains at least 8x below legacy resident-scan work"
	)

	evidence = {
		"initial_usec": initial_usec,
		"warm_usec": warm_usec,
		"traversal_usec": traversal_usec,
		"initial_snapshot_calls": initial_calls,
		"initial_legacy_scope_scans": initial_legacy_scan,
		"initial_routed_scope_scans": initial_actual_lookups,
		"warm_prepare_calls": int(warm_perf.get("prepare_call_count", 0)),
		"warm_reconciles": int(warm_perf.get("scope_reconcile_count", 0)),
		"warm_scope_loads": int(warm_projection.get("scope_load_count", 0)),
		"warm_scope_releases": int(warm_projection.get("scope_release_count", 0)),
		"traversal_snapshot_calls": travel_calls,
		"traversal_legacy_scope_scans": travel_legacy_scan,
		"traversal_routed_scope_scans": travel_actual_lookups,
		"traversal_window_evictions": int(
			travel_perf.get("window_eviction_count", 0)
		),
		"traversal_hot_path_evictions": int(
			travel_perf.get("hot_path_eviction_count", 0)
		),
		"traversal_scope_loads": int(
			travel_projection.get("scope_load_count", 0)
		),
		"traversal_scope_releases": int(
			travel_projection.get("scope_release_count", 0)
		),
		"peak_resident_scopes": int(
			travel_projection.get("peak_resident_scope_count", 0)
		),
	}
	_finish()


func _exercise_focus(
	runtime: RefCounted,
	ledger: RefCounted,
	focus: Vector2i,
	include_retained_probe: bool
) -> Dictionary:
	var window := runtime.update_resident_target_regions(
		_regions_within_radius(focus, RETAINED_RADIUS)
	)
	if not window.get("ok", false):
		return window
	for region in _regions_within_radius(focus, REQUEST_RADIUS):
		for coordinate in Grid.all_coordinates():
			var prepared: Dictionary = runtime.prepare_chunk_snapshot(
				ledger.get_meshing_snapshot_for_chunk(region, coordinate),
				region,
				coordinate
			)
			if not prepared.get("ok", false):
				return prepared
	if include_retained_probe:
		for region in _regions_within_radius(focus, RETAINED_RADIUS):
			var prepared: Dictionary = runtime.prepare_chunk_snapshot(
				ledger.get_meshing_snapshot_for_chunk(region, Vector2i(1, 1)),
				region,
				Vector2i(1, 1)
			)
			if not prepared.get("ok", false):
				return prepared
	return {"ok": true}


func _regions_within_radius(center: Vector2i, radius: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for z in range(center.y - radius, center.y + radius + 1):
		for x in range(center.x - radius, center.x + radius + 1):
			result.append(Vector2i(x, z))
	return result


func _relocate(source: Dictionary, region_key: Vector2i) -> Dictionary:
	var instance := source.duplicate(true)
	instance["instance_id"] = "%s/seed-%d/d1/%d/%d" % [
		WORLD_ID, WORLD_SEED, region_key.x, region_key.y
	]
	instance["world_id"] = WORLD_ID
	instance["world_seed"] = WORLD_SEED
	instance["generator_version"] = Field.GENERATOR_VERSION
	instance["region_key"] = region_key
	var original: Vector3i = source["position_mm"]
	var local := Vector3i(
		clampi(original.x, 2000, roundi(Spatial.REGION_SIZE_X * 1000.0) - 2000),
		original.y,
		clampi(original.z, 2000, roundi(Spatial.REGION_SIZE_Z * 1000.0) - 2000)
	)
	instance["position_mm"] = local
	instance["world_position_mm"] = Vector3i(
		region_key.x * roundi(Spatial.REGION_SIZE_X * 1000.0) + local.x,
		local.y,
		region_key.y * roundi(Spatial.REGION_SIZE_Z * 1000.0) + local.z
	)
	return instance


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
	print("ISSUE108_D1_EVIDENCE=" + JSON.stringify(evidence))
	print("ISSUE108_D1_%s: assertions=%d failures=%d" % [
		"PERFORMANCE_PASS" if failures == 0 else "PERFORMANCE_FAIL",
		assertions,
		failures,
	])
	_remove_tree(ProjectSettings.globalize_path(ROOT))
	quit(0 if failures == 0 else 1)
