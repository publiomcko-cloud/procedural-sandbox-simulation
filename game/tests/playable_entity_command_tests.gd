extends SceneTree

const ObjectStream := preload("res://scripts/objects/procedural_object_stream.gd")
const TerrainState := preload("res://scripts/terrain/terrain_world_state.gd")
const BrushState := preload("res://scripts/terrain/sdf_brush_edit_state.gd")
const Spatial := preload("res://scripts/terrain/terrain_spatial_ownership.gd")
const StateContract := preload("res://scripts/objects/procedural_object_state_contract.gd")
const WORLD_ID := "procedural-object-test-world"
const WORLD_SEED := 424242
const BATCH_REGION := Vector2i(-2, 3)

var assertions := 0
var failures := 0
var fixture_root := ""
var stream: ProceduralObjectStream
var command_timing_samples: Dictionary = {}
var region_timing_samples: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	fixture_root = ProjectSettings.globalize_path("user://p3_0b_entity_fixture_%d" % Time.get_ticks_usec())
	var state_root := fixture_root.path_join("object-state")
	DirAccess.make_dir_recursive_absolute(fixture_root)
	stream = ObjectStream.new()
	root.add_child(stream)
	var initialized: Dictionary = stream.initialize(WORLD_SEED, WORLD_ID, [], state_root)
	_check(initialized.get("ok", false), "object stream uses registered first-party and external definitions with disposable state")
	if not initialized.get("ok", false):
		_finish()
		return
	var center := Vector2i.ZERO
	var negative := Vector2i(-1, -1)
	_check(_publish(negative) and _publish(center) and _publish(BATCH_REGION), "positive and negative test regions publish through the existing object stream")
	var records: Array[Dictionary] = stream.get_region_instance_records(center)
	var batch_records: Array[Dictionary] = stream.get_region_instance_records(BATCH_REGION)
	var individual_id := ""
	var batched_id := ""
	for record in records:
		if bool(record.get("population_batched", false)) and String(record.get("instance_id", "")) != "":
			batched_id = String(record.instance_id)
		elif individual_id.is_empty():
			individual_id = String(record.get("instance_id", ""))
	for record in batch_records:
		if bool(record.get("population_batched", false)) and String(record.get("instance_id", "")) != "":
			batched_id = String(record.instance_id)
	_check(not individual_id.is_empty() and not batched_id.is_empty(), "fixture exposes both a compatibility individual and a P2.0C static batch member")
	if not individual_id.is_empty() and not batched_id.is_empty():
		var individual_pick := _ray_pick(center, _record_for(center, individual_id))
		var batch_pick := _ray_pick(BATCH_REGION, _record_for(BATCH_REGION, batched_id))
		_check(individual_pick.get("ok", false) and String(individual_pick.get("entity_id", "")) == individual_id and not bool(individual_pick.get("batched", true)), "ray selection resolves the stable ID of an individual procedural representative")
		_check(batch_pick.get("ok", false) and String(batch_pick.get("entity_id", "")) == batched_id and bool(batch_pick.get("batched", false)), "ray selection resolves a batch member ID without unbatching its static geometry")

	# Build a real schema-1 save generation through the P2-compatible state API.
	var legacy_base := _base_for(center, individual_id)
	var legacy_mutation: Dictionary = stream.state_service.set_component(legacy_base, StateContract.COMPONENT_APPEARANCE, _appearance([850, 900, 1000], "legacy-preserved"))
	_check(legacy_mutation.get("ok", false) and int(stream.state_service.get("storage_generation")) == 1 and int(stream.state_service.snapshot.get("schema_version", 0)) == 1, "P2 schema-1 override is written without an implicit P3 migration")
	var old_snapshot: Dictionary = stream.state_service.snapshot.duplicate(true)
	var preflight: Dictionary = stream.get_command_migration_preflight()
	_check(preflight.get("ok", false) and int(preflight.get("source_schema", -1)) == 1 and int(preflight.get("target_schema", -1)) == 3 and int(preflight.get("initial_history_depth", -1)) == 0, "migration preflight validates schema, revision and the complete history candidate without committing")
	_check(int(stream.state_service.get("storage_generation")) == 1 and stream.state_service.snapshot == old_snapshot and not stream.is_entity_command_ready(), "preflight and ordinary initialization preserve the original schema-1 state")
	var pre_migration: Dictionary = stream.dispatch_entity_command({})
	_check(not pre_migration.get("ok", false) and pre_migration.get("reason") == "command_snapshot_migration_required", "new command controls fail closed before explicit migration")
	var migration: Dictionary = stream.migrate_command_snapshot_explicitly()
	_check(migration.get("ok", false) and not stream.is_entity_command_ready() and int(migration.get("backup_generation", 0)) == 1 and int(migration.get("generation", 0)) == 2 and int(stream.state_service.snapshot.get("schema_version", 0)) == 3, "explicit migration commits schema 3 and waits for all resident representations to synchronize")
	_check(stream.state_service.snapshot.get("overrides", {}).has(individual_id), "schema migration preserves prior P2 sparse overrides")
	var migration_pending_snapshot: Dictionary = stream.state_service.snapshot.duplicate(true)
	_check(stream.dispatch_entity_command({}).get("reason") == "command_region_rebuild_pending" and stream.state_service.snapshot == migration_pending_snapshot, "commands fail closed while migration-triggered region publications are pending")
	await _drain_publications(stream)
	_check(stream.get_active_region_count() == 3 and stream.is_entity_command_ready(), "migration republishes the three resident regions before enabling the command path")

	var negative_world_position := Vector3i(-1, 125, -1)
	var place_command := _place_command("11111111-1111-4111-8111-111111111111", negative_world_position, negative)
	var expected_region: Vector2i = Spatial.world_to_region_local(Vector3(negative_world_position) / 1000.0).get("region_key", Vector2i.ZERO)
	_check(expected_region == negative, "negative world anchor resolves through canonical floor-based ownership")
	var placed: Dictionary = stream.dispatch_entity_command(place_command)
	_check(placed.get("ok", false) and placed.get("committed", false) and placed.get("visual_status") == "queued", "ENTITY_PLACE commits persistently before queuing the visual representative")
	_record_command_timings(placed)
	var placed_id := String(placed.get("entity_id", ""))
	_check(placed_id.begins_with("%s/seed-%d/placed/" % [WORLD_ID, WORLD_SEED]) and not placed_id.contains("population"), "explicit placement identity is separate from deterministic procedural population IDs")
	var first_world_revision := int(placed.get("world_revision", -1))
	var duplicate: Dictionary = stream.dispatch_entity_command(place_command)
	_check(duplicate.get("ok", false) and duplicate.get("duplicate", false) and String(duplicate.get("entity_id", "")) == placed_id and stream.get_command_world_revision() == first_world_revision, "exact command retry returns the durable receipt without duplicating the entity")
	var conflict := place_command.duplicate(true)
	conflict.recipe_seed = int(conflict.recipe_seed) + 1
	var conflicting_retry: Dictionary = stream.dispatch_entity_command(conflict)
	_check(not conflicting_retry.get("ok", false) and conflicting_retry.get("reason") == "idempotency_key_payload_conflict", "reusing a command ID with a different payload is rejected")
	await _drain_publications(stream)
	var visual_result := stream.consume_last_command_visual_result()
	_check(visual_result.get("ok", false) and String(visual_result.get("entity_id", "")) == placed_id, "successful committed placement receives a matching asynchronous visual-publication result")
	var placed_pick := _ray_pick(negative, _record_for(negative, placed_id))
	_check(placed_pick.get("ok", false) and String(placed_pick.get("entity_id", "")) == placed_id and not bool(placed_pick.get("batched", true)), "explicitly placed entity remains selectable by its stable identity")
	var placed_node := _find_entity_node(placed_id)
	_check(placed_node != null and placed_node.global_position.is_equal_approx(Vector3(negative_world_position) / 1000.0), "negative-region visual uses the persisted world anchor exactly once, not region origin twice")
	_check(stream.get_instance_ids().count(placed_id) == 1, "region publication creates exactly one visual identity for the placement")

	var transform_command := _component_command("22222222-2222-4222-8222-222222222222", placed_id, StateContract.COMPONENT_TRANSFORM, _transform([0, 250, 0], [0, 0, 12000], [1100, 1000, 900]))
	var transformed: Dictionary = stream.dispatch_entity_command(transform_command)
	_check(transformed.get("ok", false) and int(transformed.get("entity_revision", -1)) == 2, "ENTITY_SET_COMPONENT accepts a valid transform at the current world and entity revisions")
	_record_command_timings(transformed)
	await _drain_publications(stream)
	_record_region_timings()
	var transformed_node := _find_entity_node(placed_id)
	_check(transformed_node != null and transformed_node.position.y > 0.3, "committed transform is applied to the rebuilt individual representation")
	var appearance_command := _component_command("33333333-3333-4333-8333-333333333333", placed_id, StateContract.COMPONENT_APPEARANCE, _appearance([1000, 620, 420], "p3b-test"))
	var appearance_result: Dictionary = stream.dispatch_entity_command(appearance_command)
	_check(appearance_result.get("ok", false) and stream.state_service.snapshot.overrides[placed_id].components.has(StateContract.COMPONENT_APPEARANCE), "appearance changes use the same persisted command contract")
	_record_command_timings(appearance_result)
	await _drain_publications(stream)
	_record_region_timings()

	var visual_ids_before_rejections := stream.get_instance_ids()
	var before_stale: Dictionary = stream.state_service.snapshot.duplicate(true)
	var stale_world := _component_command("44444444-4444-4444-8444-444444444444", placed_id, StateContract.COMPONENT_LOGICAL, _logical({"test": true}))
	stale_world.expected_world_revision = maxi(0, stream.get_command_world_revision() - 1)
	var stale_world_result: Dictionary = stream.dispatch_entity_command(stale_world)
	_check(not stale_world_result.get("ok", false) and stale_world_result.get("reason") == "stale_world_revision" and stream.state_service.snapshot == before_stale, "stale world revision rejects before persistent or visual effects")
	var stale_entity := _component_command("55555555-5555-4555-8555-555555555555", placed_id, StateContract.COMPONENT_LOGICAL, _logical({"test": true}))
	stale_entity.expected_entity_revision = int(stale_entity.expected_entity_revision) - 1
	var stale_entity_result: Dictionary = stream.dispatch_entity_command(stale_entity)
	_check(not stale_entity_result.get("ok", false) and stale_entity_result.get("reason") == "stale_entity_revision" and stream.state_service.snapshot == before_stale, "stale entity revision rejects without partial snapshot mutation")
	var crossing := _component_command("66666666-6666-4666-8666-666666666666", placed_id, StateContract.COMPONENT_TRANSFORM, _transform([8000, 0, 0], [0, 0, 0], [1000, 1000, 1000]))
	var crossing_result: Dictionary = stream.dispatch_entity_command(crossing)
	_check(not crossing_result.get("ok", false) and crossing_result.get("reason") == "component_transform_region_transfer_not_supported" and stream.state_service.snapshot == before_stale, "transform crossing the negative region boundary is rejected without implicit identity migration")
	var missing_pin := _place_command("77777777-7777-4777-8777-777777777777", Vector3i(-2, 125, -2), negative)
	missing_pin.definition_id = "missing.package:unknown"
	var before_missing_pin: Dictionary = stream.state_service.snapshot.duplicate(true)
	var missing_pin_result: Dictionary = stream.dispatch_entity_command(missing_pin)
	_check(not missing_pin_result.get("ok", false) and stream.state_service.snapshot == before_missing_pin, "missing content definition/pin rejects ENTITY_PLACE before commit")
	var missing_mod := _component_command("88888888-8888-4888-8888-888888888888", placed_id, StateContract.COMPONENT_LOGICAL, _logical({"mod": true}))
	missing_mod.origin = {"type": "mod", "id": "missing.mod"}
	var missing_mod_result: Dictionary = stream.dispatch_entity_command(missing_mod)
	_check(not missing_mod_result.get("ok", false) and missing_mod_result.get("reason") == "command_origin_mod_missing", "unregistered mod origin cannot submit commands")
	_check(stream.get_instance_ids() == visual_ids_before_rejections and int(stream.get_performance_snapshot().get("pending_region_publication_count", 0)) == 0, "rejected revisions, ownership, pins and origins do not queue or alter any visual identity")

	stream.debug_fail_next_visual_publication = true
	var visual_failure_command := _component_command("99999999-9999-4999-8999-999999999999", placed_id, StateContract.COMPONENT_LOGICAL, _logical({"visual_failure": true}))
	var visual_failure_commit: Dictionary = stream.dispatch_entity_command(visual_failure_command)
	_record_command_timings(visual_failure_commit)
	var prior_root: Node = stream.get_node_or_null("Objects_-1_-1")
	await _drain_publications(stream)
	_record_region_timings()
	var visual_failure_result := stream.consume_last_command_visual_result()
	_check(visual_failure_commit.get("ok", false) and visual_failure_result.get("ok") == false and stream.state_service.snapshot.overrides[placed_id].components.has(StateContract.COMPONENT_LOGICAL), "post-commit visual failure reports persisted state and does not imply rollback")
	_check(prior_root != null and stream.get_node_or_null("Objects_-1_-1") == prior_root, "failed visual synchronization retains the previous complete region representation")

	var delete_command := _operation_command("aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", "ENTITY_DELETE", placed_id)
	var deleted: Dictionary = stream.dispatch_entity_command(delete_command)
	_record_command_timings(deleted)
	await _drain_publications(stream)
	_record_region_timings()
	_check(deleted.get("ok", false) and stream.state_service.snapshot.get("deleted", {}).has(placed_id) and not stream.get_instance_ids().has(placed_id), "ENTITY_DELETE persists a tombstone and removes the batched or individual representation")
	stream.unload_region(negative)
	var restore_command := _operation_command("bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb", "ENTITY_RESTORE", placed_id)
	var restored: Dictionary = stream.dispatch_entity_command(restore_command)
	_record_command_timings(restored)
	_check(restored.get("ok", false) and restored.get("visual_status") == "not_resident_rebuild_on_next_load" and not stream.state_service.snapshot.get("deleted", {}).has(placed_id), "ENTITY_RESTORE commits the same identity while its region is unloaded")
	_check(_publish(negative), "unloaded negative region can be reconstructed after restore")
	_record_region_timings()
	_check(stream.get_instance_ids().count(placed_id) == 1 and _find_entity_node(placed_id) != null, "revisit reconstructs one restored explicit entity without duplication")

	var stale_state := _world_state(Vector2i(6, -5))
	stream.expect_region_publication(Vector2i(6, -5), 12)
	var stale_publication: Dictionary = stream.enqueue_region_publication(Vector2i(6, -5), stale_state, 11)
	_check(not stale_publication.get("ok", false) and stale_publication.get("reason") == "stale_object_region_publication" and not stream.has_published_region(Vector2i(6, -5)), "obsolete region publications are discarded without becoming visible")

	var store_directory := String(stream.state_service.store.get("_directory"))
	var blocker_path := fixture_root.path_join("not-a-directory")
	var blocker := FileAccess.open(blocker_path, FileAccess.WRITE)
	if blocker != null:
		blocker.store_string("fixture")
		blocker.close()
	var before_io_failure: Dictionary = stream.state_service.snapshot.duplicate(true)
	stream.state_service.store.set("_directory", blocker_path)
	var persist_failure_command := _component_command("cccccccc-cccc-4ccc-8ccc-cccccccccccc", placed_id, StateContract.COMPONENT_LOGICAL, _logical({"persist_failure": true}))
	var persist_failure: Dictionary = stream.dispatch_entity_command(persist_failure_command)
	_check(not persist_failure.get("ok", false) and stream.state_service.snapshot == before_io_failure and not stream.state_service.get("initialized"), "failed persistence leaves authoritative memory unchanged and poisons the service until reload")
	stream.state_service.store.set("_directory", store_directory)

	stream.queue_free()
	await process_frame
	var restarted: ProceduralObjectStream = ObjectStream.new()
	root.add_child(restarted)
	var restarted_init: Dictionary = restarted.initialize(WORLD_SEED, WORLD_ID, [], state_root)
	_check(restarted_init.get("ok", false) and restarted.is_entity_command_ready(), "restart reopens schema-2 state and reinitializes the command service")
	if restarted_init.get("ok", false):
		_check(_publish_with_stream(restarted, negative), "restarted stream republishes a signed region from the same isolated state store")
		_check(restarted.get_instance_ids().count(placed_id) == 1, "restart reconstructs the persisted placement once from its pin and explicit record")
		var restored_revision := restarted.get_command_world_revision()
		var after_restart_duplicate: Dictionary = restarted.dispatch_entity_command(place_command)
		_check(after_restart_duplicate.get("ok", false) and after_restart_duplicate.get("duplicate", false) and restarted.get_command_world_revision() == restored_revision, "durable idempotency receipt remains effective after process-style service restart")
		var performance: Dictionary = restarted.get_performance_snapshot()
		_check(int(performance.get("active_region_count", 0)) <= ObjectStream.MAX_RESIDENT_REGIONS and int(performance.get("publications_last_process_tick", 0)) <= ObjectStream.MAX_REGION_PUBLICATIONS_PER_FRAME, "entity reconstruction preserves the existing object residency and per-frame publication limits")
		restarted.queue_free()
		await process_frame

	_remove_fixture(fixture_root)
	_print_exploratory_metrics()
	if failures == 0:
		print("PLAYABLE_ENTITY_COMMAND_PASS: assertions=%d failures=0" % assertions)
	else:
		push_error("PLAYABLE_ENTITY_COMMAND_FAIL: assertions=%d failures=%d" % [assertions, failures])
	quit(0 if failures == 0 else 1)


func _drain_publications(target: ProceduralObjectStream, max_frames: int = 600) -> void:
	for _frame in range(max_frames):
		target.process_queued_publications()
		if int(target.get_performance_snapshot().get("pending_region_publication_count", 0)) == 0:
			return
		await process_frame
	_check(false, "asynchronous object publication queue drains before timeout")


func _publish(region_key: Vector2i) -> bool:
	return _publish_with_stream(stream, region_key)


func _publish_with_stream(target: ProceduralObjectStream, region_key: Vector2i) -> bool:
	var state := _world_state(region_key)
	var result: Dictionary = target.publish_region(region_key, state, false, -1)
	return bool(result.get("ok", false))


func _world_state(region_key: Vector2i) -> RefCounted:
	return TerrainState.new(WORLD_SEED, region_key, BrushState.new(WORLD_SEED, TerrainState.FIELD.GENERATOR_VERSION))


func _record_for(region_key: Vector2i, instance_id: String) -> Dictionary:
	for record in stream.get_region_instance_records(region_key):
		if String(record.get("instance_id", "")) == instance_id:
			return record
	return {}


func _base_for(region_key: Vector2i, instance_id: String) -> Dictionary:
	var entry: Dictionary = stream._regions.get("%d,%d" % [region_key.x, region_key.y], {})
	for record in entry.get("base_instances", []):
		if String(record.get("instance_id", "")) == instance_id:
			return record
	return {}


func _ray_pick(region_key: Vector2i, record: Dictionary) -> Dictionary:
	if record.is_empty():
		return {"ok": false}
	var origin := Spatial.region_origin_world(region_key) + Vector3(record.position_mm) / 1000.0 + Vector3(0.0, 4.0, 0.0)
	return stream.find_instance_along_ray(origin, Vector3.DOWN, 20.0)


func _find_entity_node(instance_id: String) -> Node3D:
	for region_root in stream.get_children():
		if not region_root is Node3D:
			continue
		for child in region_root.get_children():
			if child.get_meta("stable_instance_id", "") == instance_id:
				return child
	return null


func _place_command(command_id: String, position_mm: Vector3i, region_key: Vector2i) -> Dictionary:
	return {
		"schema_version": 1,
		"command_id": command_id,
		"operation": "ENTITY_PLACE",
		"origin": {"type": "player", "id": "p3.test"},
		"world_id": WORLD_ID,
		"world_seed": WORLD_SEED,
		"generator_version": TerrainState.FIELD.GENERATOR_VERSION,
		"expected_world_revision": stream.get_command_world_revision(),
		"expected_entity_revision": 0,
		"definition_id": "firstparty.core_rocks:granite",
		"position_mm": [position_mm.x, position_mm.y, position_mm.z],
		"region_key": [region_key.x, region_key.y],
		"recipe_seed": 44123,
		"components": {
			StateContract.COMPONENT_TRANSFORM: _transform([0, 0, 0], [0, 0, 0], [1000, 1000, 1000]),
			StateContract.COMPONENT_APPEARANCE: _appearance([1000, 1000, 1000], "p3b placed"),
			StateContract.COMPONENT_LOGICAL: _logical({"created_by": "test"}),
		},
	}


func _component_command(command_id: String, entity_id: String, component_id: String, component: Dictionary) -> Dictionary:
	return {
		"schema_version": 1, "command_id": command_id, "operation": "ENTITY_SET_COMPONENT",
		"origin": {"type": "player", "id": "p3.test"}, "world_id": WORLD_ID, "world_seed": WORLD_SEED,
		"generator_version": TerrainState.FIELD.GENERATOR_VERSION, "expected_world_revision": stream.get_command_world_revision(),
		"expected_entity_revision": int(stream.state_service.get_entity_revision(entity_id)), "entity_id": entity_id,
		"component_id": component_id, "component": component,
	}


func _operation_command(command_id: String, operation: String, entity_id: String) -> Dictionary:
	return {
		"schema_version": 1, "command_id": command_id, "operation": operation,
		"origin": {"type": "player", "id": "p3.test"}, "world_id": WORLD_ID, "world_seed": WORLD_SEED,
		"generator_version": TerrainState.FIELD.GENERATOR_VERSION, "expected_world_revision": stream.get_command_world_revision(),
		"expected_entity_revision": int(stream.state_service.get_entity_revision(entity_id)), "entity_id": entity_id,
	}


func _transform(translation: Array, rotation: Array, scale: Array) -> Dictionary:
	return {"schema_version": 1, "properties": {"translation_mm": translation, "rotation_mdeg": rotation, "scale_milli": scale}}


func _appearance(tint: Array, label: String) -> Dictionary:
	return {"schema_version": 1, "properties": {"tint_milli": tint, "label": label}}


func _logical(values: Dictionary) -> Dictionary:
	return {"schema_version": 1, "properties": {"values": values}}


func _remove_fixture(path: String) -> void:
	var normalized := path.replace("\\", "/")
	var root_path := ProjectSettings.globalize_path("user://").replace("\\", "/").trim_suffix("/") + "/"
	if not normalized.begins_with(root_path + "p3_0b_entity_fixture_"):
		push_error("refusing cleanup outside unique p3-0b fixture root")
		return
	var directory := DirAccess.open(normalized)
	if directory == null:
		return
	directory.list_dir_begin()
	while true:
		var entry := directory.get_next()
		if entry.is_empty():
			break
		if entry == "." or entry == "..":
			continue
		var child := normalized.path_join(entry)
		if directory.current_is_dir():
			_remove_fixture(child)
		else:
			DirAccess.remove_absolute(child)
	directory.list_dir_end()
	directory = null
	DirAccess.remove_absolute(normalized)


func _finish() -> void:
	_remove_fixture(fixture_root)
	if failures == 0:
		print("PLAYABLE_ENTITY_COMMAND_PASS: assertions=%d failures=0" % assertions)
	else:
		push_error("PLAYABLE_ENTITY_COMMAND_FAIL: assertions=%d failures=%d" % [assertions, failures])
	quit(0 if failures == 0 else 1)


func _check(condition: bool, description: String) -> void:
	assertions += 1
	if condition:
		print("PASS: " + description)
	else:
		failures += 1
		push_error("FAIL: " + description)


func _record_command_timings(result: Dictionary) -> void:
	var timings: Dictionary = result.get("timings_usec", {})
	for key in ["validation_prepare_usec", "persistence_usec", "visual_queue_usec", "command_total_usec"]:
		if timings.has(key):
			if not command_timing_samples.has(key):
				command_timing_samples[key] = []
			command_timing_samples[key].append(int(timings[key]))


func _record_region_timings() -> void:
	var metrics: Dictionary = stream.get_performance_snapshot().get("last_region", {})
	for key in ["logical_reconstruction_usec", "mesh_build_usec", "batch_build_usec", "publication_usec"]:
		if metrics.has(key):
			if not region_timing_samples.has(key):
				region_timing_samples[key] = []
			region_timing_samples[key].append(int(metrics[key]))


func _print_exploratory_metrics() -> void:
	var summary: Dictionary = {}
	for key in command_timing_samples:
		var samples: Array = command_timing_samples[key]
		summary[key] = _percentile_triplet(samples)
	for key in region_timing_samples:
		var samples: Array = region_timing_samples[key]
		summary[key] = _percentile_triplet(samples)
	print("P3B_EXPLORATORY_METRICS: samples=%d values_usec=%s; headless fixture, not presented-frame/GPU acceptance" % [command_timing_samples.get("command_total_usec", []).size(), JSON.stringify(summary)])


func _percentile_triplet(samples: Array) -> Dictionary:
	if samples.is_empty():
		return {"count": 0, "p50": 0, "p95": 0, "max": 0}
	var ordered: Array = samples.duplicate()
	ordered.sort()
	var p50_index := clampi(ceili(float(ordered.size()) * 0.50) - 1, 0, ordered.size() - 1)
	var p95_index := clampi(ceili(float(ordered.size()) * 0.95) - 1, 0, ordered.size() - 1)
	return {"count": ordered.size(), "p50": ordered[p50_index], "p95": ordered[p95_index], "max": ordered.back()}
