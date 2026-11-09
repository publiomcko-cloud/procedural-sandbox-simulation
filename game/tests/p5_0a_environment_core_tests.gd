extends SceneTree

const EnvironmentStoreScript := preload("res://scripts/simulation/environment_state_store.gd")
const RuntimeScript := preload("res://scripts/simulation/simulation_runtime.gd")
const RuntimeStoreScript := preload("res://scripts/simulation/simulation_runtime_store.gd")

var assertions := 0
var failures := 0
var fixture_dir := ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	fixture_dir = "user://p5_0a_%d" % Time.get_ticks_usec()
	_remove_tree(ProjectSettings.globalize_path(fixture_dir))

	_test_environment_store_contract()
	_test_atomic_multi_scope_commit()
	_test_scheduler_backpressure()
	_test_runtime_schema_migration()
	_test_streaming_lifecycle_binding()
	_test_sidecar_roundtrip()

	_remove_tree(ProjectSettings.globalize_path(fixture_dir))
	if failures == 0:
		print("P5_0A_ENVIRONMENT_CORE_PASS: assertions=%d failures=0" % assertions)
		quit(0)
	else:
		push_error(
			"P5_0A_ENVIRONMENT_CORE_FAIL: assertions=%d failures=%d"
			% [assertions, failures]
		)
		quit(1)


func _test_environment_store_contract() -> void:
	var store: RefCounted = EnvironmentStoreScript.new()
	_check(store.initialize().get("ok", false), "environment store initializes")
	_check(store.get_cell_count() == 48, "default environment grid is 8x6")
	var registered: Dictionary = store.register_scope("region:0,0")
	_check(registered.get("ok", false), "finite environment scope registers")
	var initial: Dictionary = store.get_scope("region:0,0")
	_check(int(initial["state_revision"]) == 0, "new environment scope starts at revision zero")
	_check(_sum_i64(initial["surface_water_ul"]) == 0, "new scope starts with zero finite surface water")

	var surface: PackedInt64Array = initial["surface_water_ul"].duplicate()
	var soil: PackedInt64Array = initial["soil_water_ul"].duplicate()
	var kinds: PackedByteArray = initial["reservoir_kind"].duplicate()
	var levels: PackedInt64Array = initial["reservoir_level_mm"].duplicate()
	kinds[0] = EnvironmentStoreScript.RESERVOIR_RIVER
	levels[0] = 12_000
	kinds[1] = EnvironmentStoreScript.RESERVOIR_OCEAN
	levels[1] = 0
	surface[2] = 4_000_000
	soil[2] = 2_000_000

	var commit: Dictionary = store.commit_batch([
		_update(initial, 1, surface, soil, kinds, levels, 750_000, 250_000)
	])
	_check(commit.get("ok", false), "river/ocean reservoir configuration commits")
	var after: Dictionary = store.get_scope("region:0,0")
	_check(int(after["state_revision"]) == 1, "environment mutation increments revision")
	_check(int(after["reservoir_kind"][0]) == EnvironmentStoreScript.RESERVOIR_RIVER, "river cell remains explicit")
	_check(int(after["reservoir_level_mm"][0]) == 12_000, "river level is fixed authoritative data")
	_check(int(after["reservoir_kind"][1]) == EnvironmentStoreScript.RESERVOIR_OCEAN, "ocean cell remains explicit")
	_check(int(after["surface_water_ul"][0]) == 0 and int(after["soil_water_ul"][0]) == 0, "infinite river stores no finite water")
	_check(int(after["surface_water_ul"][1]) == 0 and int(after["soil_water_ul"][1]) == 0, "infinite ocean stores no finite water")
	_check(int(after["reservoir_inflow_ul_total"]) == 750_000, "finite-to-reservoir exchange is accounted")
	_check(int(after["reservoir_outflow_ul_total"]) == 250_000, "reservoir-to-finite exchange is accounted")
	_check(_sum_i64(after["surface_water_ul"]) == 4_000_000, "finite water remains separate from infinite reservoir volume")

	var invalid_surface: PackedInt64Array = after["surface_water_ul"].duplicate()
	invalid_surface[0] = 1
	var invalid: Dictionary = store.commit_batch([
		_update(
			after,
			2,
			invalid_surface,
			after["soil_water_ul"].duplicate(),
			after["reservoir_kind"].duplicate(),
			after["reservoir_level_mm"].duplicate(),
			0,
			0
		)
	])
	_check(
		invalid.get("reason", "") == "environment_infinite_reservoir_stores_finite_water",
		"infinite reservoir rejects finite stored water"
	)
	_check(store.get_scope("region:0,0") == after, "rejected reservoir mutation leaves authority unchanged")

	var snapshot: Dictionary = store.get_authoritative_snapshot()
	var restored: RefCounted = EnvironmentStoreScript.new()
	_check(restored.restore_snapshot(snapshot).get("ok", false), "environment snapshot restores")
	_check(restored.get_authoritative_snapshot() == snapshot, "environment snapshot roundtrip is exact")
	var metrics: Dictionary = store.get_metrics()
	_check(int(metrics["river_cells"]) == 1 and int(metrics["ocean_cells"]) == 1, "metrics distinguish river and ocean reservoirs")


func _test_atomic_multi_scope_commit() -> void:
	var store: RefCounted = EnvironmentStoreScript.new()
	store.initialize()
	store.register_scope("region:0,0")
	store.register_scope("region:1,0")
	var a: Dictionary = store.get_scope("region:0,0")
	var b: Dictionary = store.get_scope("region:1,0")
	var a_surface: PackedInt64Array = a["surface_water_ul"].duplicate()
	var b_surface: PackedInt64Array = b["surface_water_ul"].duplicate()
	a_surface[0] = 100
	b_surface[0] = 100

	var conflict_b := _update(
		b, 1, b_surface, b["soil_water_ul"].duplicate(),
		b["reservoir_kind"].duplicate(), b["reservoir_level_mm"].duplicate(), 0, 0
	)
	conflict_b["expected_state_revision"] = 99
	var rejected: Dictionary = store.commit_batch([
		_update(
			a, 1, a_surface, a["soil_water_ul"].duplicate(),
			a["reservoir_kind"].duplicate(), a["reservoir_level_mm"].duplicate(), 0, 0
		),
		conflict_b,
	])
	_check(rejected.get("reason", "") == "environment_state_revision_conflict", "multi-scope stale revision rejects whole batch")
	_check(int(store.get_scope("region:0,0")["state_revision"]) == 0, "atomic rejection leaves first scope untouched")
	_check(int(store.get_scope("region:1,0")["state_revision"]) == 0, "atomic rejection leaves second scope untouched")

	var accepted: Dictionary = store.commit_batch([
		_update(
			a, 1, a_surface, a["soil_water_ul"].duplicate(),
			a["reservoir_kind"].duplicate(), a["reservoir_level_mm"].duplicate(), 0, 0
		),
		_update(
			b, 1, b_surface, b["soil_water_ul"].duplicate(),
			b["reservoir_kind"].duplicate(), b["reservoir_level_mm"].duplicate(), 0, 0
		),
	])
	_check(accepted.get("ok", false) and int(accepted["changed_scope_count"]) == 2, "valid cross-region-style batch commits atomically")
	_check(int(store.get_scope("region:0,0")["surface_water_ul"][0]) == 100, "first atomic scope commits")
	_check(int(store.get_scope("region:1,0")["surface_water_ul"][0]) == 100, "second atomic scope commits")


func _test_scheduler_backpressure() -> void:
	var runtime: Node = RuntimeScript.new()
	_check(runtime.initialize_runtime(100_000, 4).get("ok", false), "runtime initializes with P5 environment authority")
	_check(runtime.set_environment_tick_admission_limit(0).get("ok", false), "environment can apply zero-capacity backpressure")
	var blocked: Dictionary = runtime.process_elapsed_usec(500_000)
	_check(int(blocked["admitted_ticks"]) == 0, "zero environment capacity admits no logical ticks")
	_check(int(blocked["backlog_ticks"]) == 5, "backpressured ticks remain deterministic scheduler backlog")
	_check(bool(blocked["backpressure_limited"]), "scheduler reports active backpressure")

	runtime.set_environment_tick_admission_limit(2)
	var partial: Dictionary = runtime.process_elapsed_usec(0)
	_check(int(partial["admitted_ticks"]) == 2 and int(partial["current_tick"]) == 2, "environment capacity admits bounded subset")
	_check(int(partial["backlog_ticks"]) == 3, "remaining logical work stays deferred")

	runtime.set_environment_tick_admission_limit(-1)
	var normal: Dictionary = runtime.process_elapsed_usec(0)
	_check(int(normal["admitted_ticks"]) == 3 and int(normal["current_tick"]) == 5, "removing backpressure restores normal scheduler bound")
	_check(int(normal["backlog_ticks"]) == 0, "backpressure backlog drains without lost ticks")
	var metrics: Dictionary = runtime.get_scheduler_metrics()
	_check(int(metrics["frames_backpressured"]) >= 2, "scheduler telemetry counts backpressured frames")
	runtime.free()


func _test_runtime_schema_migration() -> void:
	var runtime: Node = RuntimeScript.new()
	runtime.initialize_runtime()
	runtime.register_simulation_scope("region:2,3", "active")
	_check(runtime.register_environment_scope("region:2,3").get("ok", false), "runtime environment scope binds to P4 scope")
	var v3: Dictionary = runtime.get_runtime_snapshot()
	_check(int(v3["schema_version"]) == 3, "runtime snapshot advances to schema 3")
	_check((v3["environment_state"] as Dictionary).get("scopes", []).size() == 1, "schema 3 persists environment authority")

	var v2: Dictionary = v3.duplicate(true)
	v2["schema_version"] = 2
	v2.erase("environment_state")
	_check(runtime.validate_runtime_snapshot(v2).get("ok", false), "P4 schema 2 snapshot remains accepted")
	var migrated: Node = RuntimeScript.new()
	var restore: Dictionary = migrated.restore_runtime_snapshot(v2)
	_check(restore.get("ok", false) and int(restore["migrated_from_schema"]) == 2, "schema 2 migrates explicitly to P5 schema 3")
	_check(int(migrated.get_runtime_snapshot()["schema_version"]) == 3, "migrated runtime publishes schema 3")
	_check(migrated.get_environment_state_snapshot().get("scopes", []).is_empty(), "legacy P4 world receives empty deterministic environment authority")
	runtime.free()
	migrated.free()


func _test_streaming_lifecycle_binding() -> void:
	var runtime: Node = RuntimeScript.new()
	runtime.initialize_runtime()
	_check(runtime.configure_world_scope_lifecycle("", 25, 16_000, 12_000).get("ok", false), "P4 lifecycle configures without material profile")
	runtime.update_world_scope_focus(Vector2i.ZERO)
	var published: Dictionary = runtime.publish_world_region_scope(Vector2i(4, -2))
	_check(published.get("ok", false), "streamed region publishes")
	_check(not runtime.get_environment_scope("region:4,-2").is_empty(), "stream publication creates same-id environment authority")
	var before: Dictionary = runtime.get_environment_scope("region:4,-2")
	_check(runtime.unload_world_region_scope(Vector2i(4, -2)).get("ok", false), "streamed region unloads")
	_check(runtime.get_environment_scope("region:4,-2") == before, "unload preserves authoritative environment state")
	var metrics: Dictionary = runtime.get_world_scope_lifecycle_metrics()
	_check(int(metrics["environment_registrations_total"]) == 1, "lifecycle telemetry records environment registration")
	runtime.free()


func _test_sidecar_roundtrip() -> void:
	var runtime: Node = RuntimeScript.new()
	runtime.initialize_runtime()
	runtime.register_simulation_scope("region:0,0", "active")
	runtime.register_environment_scope("region:0,0")
	var record: Dictionary = runtime.get_environment_scope("region:0,0")
	var kinds: PackedByteArray = record["reservoir_kind"].duplicate()
	var levels: PackedInt64Array = record["reservoir_level_mm"].duplicate()
	kinds[0] = EnvironmentStoreScript.RESERVOIR_OCEAN
	levels[0] = 0
	var commit: Dictionary = runtime.commit_environment_batch([
		_update(
			record,
			1,
			record["surface_water_ul"].duplicate(),
			record["soil_water_ul"].duplicate(),
			kinds,
			levels,
			5_000_000,
			7_000_000
		)
	])
	_check(commit.get("ok", false), "sidecar fixture environment mutation commits")
	var snapshot: Dictionary = runtime.get_runtime_snapshot()

	var store: RefCounted = RuntimeStoreScript.new(fixture_dir)
	var saved: Dictionary = store.save_snapshot("p5-test", 42, 7, 3, snapshot)
	_check(saved.get("ok", false), "schema 3 runtime sidecar saves")
	var loaded: Dictionary = store.load_snapshot("p5-test", 42, 7, 3)
	_check(loaded.get("ok", false) and loaded.get("found", false), "schema 3 runtime sidecar loads")
	_check(loaded["snapshot"] == snapshot, "sidecar preserves packed environmental state exactly")

	var restored: Node = RuntimeScript.new()
	var restore: Dictionary = restored.restore_runtime_snapshot(loaded["snapshot"])
	_check(restore.get("ok", false), "sidecar schema 3 restores into fresh runtime")
	_check(restored.get_environment_scope("region:0,0") == runtime.get_environment_scope("region:0,0"), "infinite reservoir authority survives save/restart/load")
	runtime.free()
	restored.free()


func _update(
	record: Dictionary,
	next_tick: int,
	surface: PackedInt64Array,
	soil: PackedInt64Array,
	kinds: PackedByteArray,
	levels: PackedInt64Array,
	inflow_delta: int,
	outflow_delta: int
) -> Dictionary:
	return {
		"scope_id": String(record["scope_id"]),
		"expected_state_revision": int(record["state_revision"]),
		"last_environment_tick": next_tick,
		"surface_water_ul": surface,
		"soil_water_ul": soil,
		"reservoir_kind": kinds,
		"reservoir_level_mm": levels,
		"reservoir_inflow_ul_delta": inflow_delta,
		"reservoir_outflow_ul_delta": outflow_delta,
	}


func _sum_i64(values: PackedInt64Array) -> int:
	var total := 0
	for value in values:
		total += int(value)
	return total


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


func _check(condition: bool, description: String) -> void:
	assertions += 1
	if condition:
		print("PASS: " + description)
	else:
		failures += 1
		push_error("FAIL: " + description)
