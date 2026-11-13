extends SceneTree

const Projection := preload("res://scripts/terrain/terrain_object_effect_projection_service.gd")
const Contract := preload("res://scripts/terrain/terrain_object_effect_projection_contract.gd")
const Grid := preload("res://scripts/terrain/terrain_chunk_grid.gd")

class FakeIndex:
	extends RefCounted
	var keys: Array[String] = []

	func _init(chunks: Array[String]) -> void:
		keys = chunks.duplicate()

	func get_all_indexed_chunk_ids() -> Array[String]:
		var sorted := keys.duplicate()
		sorted.sort()
		return sorted

	func get_all_indexed_chunk_ids_unsorted() -> Array[String]:
		return keys.duplicate()

	func get_frames_for_chunk(_region: Vector2i, _chunk: Vector2i) -> Array[Dictionary]:
		return []

var checks := 0
var fails := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var previous := OS.get_environment("SANDBOX_DM14_LAZY_ROUTES")
	OS.set_environment("SANDBOX_DM14_LAZY_ROUTES", "1")
	var service := Projection.new()
	var init: Dictionary = service.initialize(
		"dm14-lazy-route-contract", 424242, 1, "user://dm14-lazy-routes"
	)
	_check(init.get("ok", false), "projection initializes")
	var region := Vector2i(1, -2)
	var id := Contract.scope_id_for_region(region)
	var first_chunk := Grid.stable_id(region, Vector2i.ZERO)
	var second_chunk := Grid.stable_id(region + Vector2i(1, 0), Vector2i.ZERO)
	var initial_index := FakeIndex.new([first_chunk, second_chunk])
	var snapshot := {
		"effects": {}, "local_frames": {}, "projection_revision": 0,
		"source_world_revision": 0
	}
	_install_fake(service, id, snapshot, initial_index)
	_check(service.get_loaded_scope_count() == 1, "one active scope")
	_check(service.snapshot_for_chunk(region, Vector2i.ZERO).get("routed_scope_count") == 1,
		"original active reverse route visible")
	service.release_scope(region, true)
	_check(service.get_loaded_scope_count() == 0, "authority removed in release_scope")
	_check(not service._scope_indexes.has(id), "source route index immediately inactive")
	_check(service._scope_ids_by_chunk.has(first_chunk), "inactive membership deferred")
	_check(int(service.snapshot_for_chunk(region, Vector2i.ZERO).get("routed_scope_count")) == 0,
		"tombstoned member excluded from exact routed source count")
	_check(service.get_frames_for_chunk(region, Vector2i.ZERO).is_empty(),
		"inactive source cannot leak frames during deferred cleanup")
	_check(service._dm14_route_cleanup.size() == 1, "one pending inactive index")
	var step: Dictionary = service.process_route_cleanup_step(1, 1000000)
	_check(step.get("ok", false), "bounded cleanup succeeds")
	_check(int(step.get("cleaned", 0)) <= 1, "one key max per frame")
	_check(service._dm14_route_cleanup.size() == 1, "cleanup resumes across frames")
	step = service.process_route_cleanup_step(1, 1000000)
	_check(service._dm14_route_cleanup.is_empty(), "second slice drains pending index")
	_check(not service._scope_ids_by_chunk.has(first_chunk)
		and not service._scope_ids_by_chunk.has(second_chunk),
		"no orphan routes remain after drain")
	var new_index := FakeIndex.new([first_chunk, second_chunk])
	_install_fake(service, id, snapshot, new_index)
	service.release_scope(region, true)
	# A scope can be reactivated before cleanup catches up. In this case,
	# the old index routes MUST be flushed prior to inserting a different
	# route set for the same scope ID.
	var different_index := FakeIndex.new([second_chunk])
	_install_fake(service, id, snapshot, different_index)
	_check(service._dm14_route_cleanup.is_empty(), "revisit flushes old pending scope")
	_check(not service._scope_ids_by_chunk.has(first_chunk), "old-only route removed on revisit")
	_check(service._scope_ids_by_chunk.has(second_chunk), "new scoped route installed")
	_check(service.get_frames_for_chunk(region, Vector2i.ZERO).is_empty(),
		"revisit never leaks old frames")
	_check(service.get_performance_snapshot()["dm14_cleanup_revisit_flushes"] >= 1,
		"revisit safety instrumented")
	OS.set_environment("SANDBOX_DM14_LAZY_ROUTES", "0")
	var control := Projection.new()
	_check(control.initialize("dm14-control", 424242, 1,
		"user://dm14-control-routes").get("ok", false), "synchronous control initialized")
	_install_fake(control, id, snapshot, FakeIndex.new([first_chunk]))
	control.release_scope(region, true)
	_check(not control._scope_ids_by_chunk.has(first_chunk),
		"disabled flag preserves synchronous legacy route deletion")
	_check(control._dm14_route_cleanup.is_empty(), "no pending cleanup in control")
	OS.set_environment("SANDBOX_DM14_LAZY_ROUTES", previous)
	print("DM14_ROUTE_CONTRACT_RESULT=" + JSON.stringify({
		"checks": checks, "failures": fails,
		"immediate_scope_invalidation": fails == 0,
		"revisit_flush": fails == 0,
		"exact_routing": fails == 0
	}))
	print("DM14_ROUTE_CONTRACT_%s" % ("PASS" if fails == 0 else "FAIL"))
	quit(0 if fails == 0 else 1)


func _install_fake(service: RefCounted, scope_id: String, snapshot: Dictionary, index: RefCounted) -> void:
	service._scopes[scope_id] = snapshot.duplicate(true)
	service._install_scope_index(scope_id, index)
	service._storage_generations[scope_id] = 0


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		push_error("DM14_ROUTE_CONTRACT_FAIL: " + message)
