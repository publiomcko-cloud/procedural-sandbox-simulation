extends SceneTree

const Registry := preload("res://scripts/modding/content_definition_registry.gd")
const StateService := preload("res://scripts/objects/procedural_object_state_service.gd")
const CommandService := preload("res://scripts/entities/entity_command_service.gd")
const StateContract := preload("res://scripts/objects/procedural_object_state_contract.gd")
const ProjectionContract := preload("res://scripts/terrain/terrain_object_effect_projection_contract.gd")
const ProjectionService := preload("res://scripts/terrain/terrain_object_effect_projection_service.gd")
const Field := preload("res://scripts/terrain/sdf_world.gd")

const WORLD_ID := "issue108-phase-c"
const WORLD_SEED := 424242
const ROOT := "user://issue108-phase-c-tests"
const OBJECT_STATE_DIR := ROOT + "/object-state"
const PROJECTION_DIR := ROOT + "/terrain-object-effects"

var assertions := 0
var failures := 0
var evidence: Dictionary = {}


class FailingProjectionStore:
	extends RefCounted

	func save_validated_snapshot(_snapshot: Dictionary) -> Dictionary:
		return {"ok": false, "reason": "injected_projection_store_failure"}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_remove_tree(ProjectSettings.globalize_path(ROOT))
	var registry := Registry.new()
	var registered: Dictionary = registry.discover_and_register(["res://mods/first-party"])
	_check(registered.get("ok", false), "first-party registry initializes")
	if not registered.get("ok", false):
		_finish()
		return

	var state: RefCounted = StateService.new()
	var state_init: Dictionary = state.initialize(
		WORLD_ID, WORLD_SEED, Field.GENERATOR_VERSION, OBJECT_STATE_DIR
	)
	_check(state_init.get("ok", false), "authoritative object state initializes")
	var upgraded: Dictionary = state.upgrade_history_snapshot_schema()
	_check(upgraded.get("ok", false), "authoritative object state upgrades explicitly to history schema")

	var commands: RefCounted = CommandService.new()
	_check(commands.initialize(state, registry).get("ok", false), "entity command service binds authoritative state")
	_check(commands.reconstruct_region(Vector2i.ZERO).get("ok", false), "canonical region reconstructs for projection source")

	var projection_abs := ProjectSettings.globalize_path(PROJECTION_DIR)
	_check(not DirAccess.dir_exists_absolute(projection_abs), "old world begins without projection directory")
	var projection: RefCounted = ProjectionService.new()
	var projection_init: Dictionary = projection.initialize(
		WORLD_ID, WORLD_SEED, Field.GENERATOR_VERSION, PROJECTION_DIR
	)
	_check(projection_init.get("ok", false), "projection service initializes without loading global state")
	_check(
		not DirAccess.dir_exists_absolute(projection_abs),
		"old-world projection initialization performs no write or migration"
	)
	_check(projection.get_loaded_scope_count() == 0, "projection starts with zero resident scopes")

	var initial_reconcile: Dictionary = projection.reconcile_command_region(Vector2i.ZERO, commands)
	_check(initial_reconcile.get("ok", false) and initial_reconcile.get("changed", false), "authoritative region projects durably")
	var initial_scope: Dictionary = projection.get_scope_snapshot(Vector2i.ZERO)
	_check(not initial_scope.is_empty() and (initial_scope["effects"] as Dictionary).size() > 0, "regional projection contains terrain effects")
	_check(
		FileAccess.file_exists(projection_abs.path_join("regions/r_0_0/projection-00000001.json")),
		"region scope persists at spatially computable path"
	)
	_check(
		not FileAccess.file_exists(projection_abs.path_join("head.json"))
			and not FileAccess.file_exists(projection_abs.path_join("projection-00000001.json")),
		"projection store has no world-global growing manifest or snapshot"
	)

	var target := _first_active_effect_source(commands, Vector2i.ZERO)
	_check(target.get("ok", false), "projection fixture finds active interacting entity")
	if not target.get("ok", false):
		_finish()
		return
	var entity_id := String(target["instance"]["instance_id"])
	var initial_effect := _effect_for_source(initial_scope, entity_id)
	_check(not initial_effect.is_empty(), "projected effect maps one-to-one to source entity")
	_check(initial_effect["terrain_interaction_pin"] == target["instance"]["terrain_interaction_pin"], "projection persists exact terrain-interaction pin")
	_check(initial_effect["content_pin"] == target["instance"]["content_pin"], "projection persists exact source content pin")
	_check(not bool(target["instance"].get("terrain_interaction_applied", true)), "projection does not mutate terrain_interaction_applied")
	var initial_effect_id := String(initial_effect["effect_id"])
	var initial_fingerprint := String(initial_effect["source_fingerprint_sha256"])

	var no_change: Dictionary = projection.reconcile_command_region(Vector2i.ZERO, commands)
	_check(
		no_change.get("ok", false)
			and not no_change.get("changed", true)
			and no_change.get("reason") == "already_current",
		"repeat regional reconciliation is an idempotent no-op"
	)

	# A second signed region is persisted independently and can be released from
	# memory without losing its durable projection.
	_check(commands.reconstruct_region(Vector2i(-1, -1)).get("ok", false), "negative region reconstructs")
	var negative_reconcile: Dictionary = projection.reconcile_command_region(Vector2i(-1, -1), commands)
	_check(negative_reconcile.get("ok", false), "negative region projection persists")
	_check(
		FileAccess.file_exists(projection_abs.path_join("regions/r_-1_-1/projection-00000001.json")),
		"negative region has independent signed shard path"
	)
	_check(projection.get_loaded_scope_count() == 2, "two reconciled regions are independently resident")
	var resident_effects_before_release: int = projection.get_effect_count()
	projection.release_scope(Vector2i(-1, -1))
	_check(
		projection.get_loaded_scope_count() == 1
			and projection.get_effect_count() < resident_effects_before_release,
		"release_scope removes a region from resident projection/index memory"
	)
	var negative_reload: Dictionary = projection.load_scope(Vector2i(-1, -1))
	_check(
		negative_reload.get("ok", false)
			and negative_reload.get("found", false)
			and int(negative_reload.get("generation", 0)) == 1,
		"released signed scope reloads independently from disk"
	)
	projection.release_scope(Vector2i(-1, -1))

	# Simulate crash after the regional generation bytes exist but before final
	# visibility to the next process.
	var crash_generation: int = projection.storage_generation_for_scope(Vector2i.ZERO)
	var region_zero_dir := projection_abs.path_join("regions/r_0_0")
	var crash_final := region_zero_dir.path_join("projection-%08d.json" % crash_generation)
	var crash_tmp := region_zero_dir.path_join("projection-%08d.tmp" % crash_generation)
	_check(DirAccess.rename_absolute(crash_final, crash_tmp) == OK, "latest regional generation becomes recoverable temporary fixture")
	var recovered: RefCounted = ProjectionService.new()
	_check(recovered.initialize(WORLD_ID, WORLD_SEED, Field.GENERATOR_VERSION, PROJECTION_DIR).get("ok", false), "fresh service initializes before scoped recovery")
	var recovered_load: Dictionary = recovered.load_scope(Vector2i.ZERO)
	_check(
		recovered_load.get("ok", false)
			and recovered_load.get("found", false)
			and recovered_load.get("recovered_temporary", false)
			and int(recovered_load.get("generation", -1)) == crash_generation,
		"scope load recovers highest valid temporary generation"
	)
	_check(FileAccess.file_exists(crash_final) and not FileAccess.file_exists(crash_tmp), "temporary recovery promotes regional generation back to final path")
	var recovered_effect := _effect_for_source(recovered.get_scope_snapshot(Vector2i.ZERO), entity_id)
	var initial_effect_sha := ProjectionContract.canonical_sha256(initial_effect)
	var recovered_effect_sha := ProjectionContract.canonical_sha256(recovered_effect)
	if initial_effect_sha != recovered_effect_sha 		or recovered_effect.get("content_pin", {}) != initial_effect.get("content_pin", {}) 		or recovered_effect.get("terrain_interaction_pin", {}) != initial_effect.get("terrain_interaction_pin", {}):
		print("ISSUE108_PHASE_C_RECOVERY_CANONICAL_DIAGNOSTIC=" + JSON.stringify({
			"initial_sha": initial_effect_sha,
			"recovered_sha": recovered_effect_sha,
			"content_pin_equal": recovered_effect.get("content_pin", {}) == initial_effect.get("content_pin", {}),
			"interaction_pin_equal": recovered_effect.get("terrain_interaction_pin", {}) == initial_effect.get("terrain_interaction_pin", {}),
			"initial_content_pin": initial_effect.get("content_pin", {}),
			"recovered_content_pin": recovered_effect.get("content_pin", {}),
			"initial_interaction_pin": initial_effect.get("terrain_interaction_pin", {}),
			"recovered_interaction_pin": recovered_effect.get("terrain_interaction_pin", {}),
		}))
	_check(
		not recovered_effect.is_empty()
			and recovered_effect_sha == initial_effect_sha
			and recovered_effect["content_pin"] == initial_effect["content_pin"]
			and recovered_effect["terrain_interaction_pin"]
				== initial_effect["terrain_interaction_pin"],
		"crash recovery preserves exact canonical effect bytes and pins"
	)

	# Source commit precedes projection commit. Revision comparison makes the gap
	# explicit and recoverable rather than requiring distributed atomicity.
	var transformed: Dictionary = commands.dispatch(_set_component(
		"00000000-0000-4000-8000-00000000c001",
		entity_id,
		state.get_revision(),
		state.get_entity_revision(entity_id),
		StateContract.COMPONENT_TRANSFORM,
		_transform([120, 0, -80], [11000, 27000, -7000], [900, 1200, 1100])
	))
	_check(transformed.get("ok", false) and int(transformed.get("world_revision", -1)) == 1, "authoritative transform commits before projection")
	_check(recovered.get_scope_status(Vector2i.ZERO, state.get_revision()).get("status") == "stale", "source-only commit makes regional projection observably stale")
	var transformed_reconcile: Dictionary = recovered.reconcile_command_region(Vector2i.ZERO, commands)
	_check(transformed_reconcile.get("ok", false) and transformed_reconcile.get("changed", false), "stale scope reconciles from authoritative state")
	var transformed_effect := _effect_for_source(recovered.get_scope_snapshot(Vector2i.ZERO), entity_id)
	_check(String(transformed_effect.get("effect_id", "")) == initial_effect_id, "effect identity remains stable across source transform revision")
	_check(
		String(transformed_effect.get("source_fingerprint_sha256", "")) != initial_fingerprint
			and int(transformed_effect.get("source_revision", -1)) == 1,
		"projection advances source revision and fingerprint after transform"
	)

	# Same revision plus a different fingerprint is a conflict, not an implicit
	# content migration.
	var conflict_sources := _resolved_region_sources(commands, state, Vector2i.ZERO)
	_check(conflict_sources.get("ok", false), "effective sources reconstruct for divergence probe")
	if conflict_sources.get("ok", false):
		var conflict_instances: Array[Dictionary] = conflict_sources["instances"]
		for instance in conflict_instances:
			if String(instance.get("instance_id", "")) == entity_id:
				instance["instance_components"]["core.transform"]["properties"]["translation_mm"] = [121, 0, -80]
		var conflict: Dictionary = recovered.reconcile_scope(
			Vector2i.ZERO,
			state.get_revision(),
			conflict_instances,
			conflict_sources["source_revisions"]
		)
		_check(
			not conflict.get("ok", false)
				and conflict.get("reason") == "effect_projection_same_revision_fingerprint_conflict",
			"same-revision divergent fingerprint fails closed"
		)
	var stale_sources := _resolved_region_sources(commands, state, Vector2i.ZERO)
	if stale_sources.get("ok", false):
		var stale: Dictionary = recovered.reconcile_scope(
			Vector2i.ZERO,
			0,
			stale_sources["instances"],
			stale_sources["source_revisions"]
		)
		_check(
			not stale.get("ok", false)
				and stale.get("reason") == "effect_projection_stale_scope_revision",
			"older authoritative scope cannot overwrite newer regional projection"
		)

	# Delete removes the source from the authoritative active set; reconciliation
	# garbage-collects only this scope's orphaned effect.
	var deleted: Dictionary = commands.dispatch(_simple_command(
		"00000000-0000-4000-8000-00000000c002",
		"ENTITY_DELETE",
		entity_id,
		state.get_revision(),
		state.get_entity_revision(entity_id)
	))
	_check(deleted.get("ok", false) and int(deleted.get("world_revision", -1)) == 2, "authoritative delete commits")
	var delete_reconcile: Dictionary = recovered.reconcile_command_region(Vector2i.ZERO, commands)
	_check(
		delete_reconcile.get("ok", false)
			and int(delete_reconcile.get("removed_effect_count", 0)) >= 1,
		"regional reconciliation garbage-collects orphan after delete"
	)
	_check(_effect_for_source(recovered.get_scope_snapshot(Vector2i.ZERO), entity_id).is_empty(), "deleted source no longer has projected effect")

	var restored: Dictionary = commands.dispatch(_simple_command(
		"00000000-0000-4000-8000-00000000c003",
		"ENTITY_RESTORE",
		entity_id,
		state.get_revision(),
		state.get_entity_revision(entity_id)
	))
	_check(restored.get("ok", false) and int(restored.get("world_revision", -1)) == 3, "authoritative restore commits")
	_check(recovered.reconcile_command_region(Vector2i.ZERO, commands).get("ok", false), "restored source reprojects")
	var restored_effect := _effect_for_source(recovered.get_scope_snapshot(Vector2i.ZERO), entity_id)
	_check(
		String(restored_effect.get("effect_id", "")) == initial_effect_id
			and int(restored_effect.get("source_revision", -1)) == 3,
		"restore recreates stable effect identity at monotonic source revision"
	)

	# Lost scope data is rebuilt from authority without touching neighboring
	# shards or the object-state store.
	var authoritative_snapshot_before_rebuild: Dictionary = state.snapshot.duplicate(true)
	var expected_restored_effect := restored_effect.duplicate(true)
	_remove_tree(region_zero_dir)
	var rebuilt: RefCounted = ProjectionService.new()
	_check(rebuilt.initialize(WORLD_ID, WORLD_SEED, Field.GENERATOR_VERSION, PROJECTION_DIR).get("ok", false), "rebuild service initializes")
	var missing_scope_load: Dictionary = rebuilt.load_scope(Vector2i.ZERO)
	_check(missing_scope_load.get("ok", false) and not missing_scope_load.get("found", true), "missing regional shard loads as empty derived scope")
	_check(rebuilt.reconcile_command_region(Vector2i.ZERO, commands).get("ok", false), "missing regional shard rebuilds from authority")
	var rebuilt_effect := _effect_for_source(rebuilt.get_scope_snapshot(Vector2i.ZERO), entity_id)
	_check(rebuilt_effect == expected_restored_effect, "rebuild reproduces exact normalized effect")
	_check(state.snapshot == authoritative_snapshot_before_rebuild, "projection rebuild never rewrites authoritative object state")
	var neighbor_survives: Dictionary = rebuilt.load_scope(Vector2i(-1, -1))
	_check(neighbor_survives.get("ok", false) and neighbor_survives.get("found", false), "rebuilding one shard leaves neighboring signed shard intact")

	# Commit uncertainty invalidates the service before candidate publication.
	var faulted: RefCounted = ProjectionService.new()
	_check(faulted.initialize(WORLD_ID, WORLD_SEED, Field.GENERATOR_VERSION, ROOT + "/fault-projection").get("ok", false), "fault-injection service initializes")
	_check(faulted.load_scope(Vector2i.ZERO).get("ok", false), "fault-injection scope loads empty before store replacement")
	var fault_scope_before: Dictionary = faulted.get_scope_snapshot(Vector2i.ZERO)
	faulted.store = FailingProjectionStore.new()
	var fault_result: Dictionary = faulted.reconcile_command_region(Vector2i.ZERO, commands)
	_check(
		not fault_result.get("ok", false)
			and String(fault_result.get("reason", "")).begins_with("effect_projection_commit_uncertain:")
			and not bool(faulted.initialized),
		"uncertain persistence invalidates projection service until recovery"
	)
	_check(faulted.get_scope_snapshot(Vector2i.ZERO) == fault_scope_before, "failed commit never publishes candidate scope")

	# A corrupt finalized generation fails closed only when that spatial scope is
	# requested; initialization remains lazy and unrelated scopes need no scan.
	var corrupt_root := ProjectSettings.globalize_path(ROOT + "/corrupt-projection")
	var corrupt_scope := corrupt_root.path_join("regions/r_0_0")
	DirAccess.make_dir_recursive_absolute(corrupt_scope)
	var corrupt_file := FileAccess.open(corrupt_scope.path_join("projection-00000001.json"), FileAccess.WRITE)
	if corrupt_file != null:
		corrupt_file.store_string("{corrupt")
		corrupt_file.flush()
		corrupt_file.close()
	var corrupt_service: RefCounted = ProjectionService.new()
	_check(corrupt_service.initialize(WORLD_ID, WORLD_SEED, Field.GENERATOR_VERSION, corrupt_root).get("ok", false), "corrupt store does not force global scan at initialize")
	var corrupt_load: Dictionary = corrupt_service.load_scope(Vector2i.ZERO)
	_check(
		not corrupt_load.get("ok", false)
			and corrupt_load.get("reason") == "effect_projection_corrupt_generation",
		"corrupt finalized regional generation fails closed on scoped load"
	)

	evidence = {
		"initial_scope_effect_count": (initial_scope["effects"] as Dictionary).size(),
		"crash_recovered_generation": crash_generation,
		"final_authoritative_world_revision": state.get_revision(),
		"final_target_source_revision": int(rebuilt_effect.get("source_revision", -1)),
		"resident_scope_limit": ProjectionService.MAX_RESIDENT_SCOPES,
		"per_scope_source_limit": ProjectionContract.MAX_SOURCES_PER_SCOPE,
	}
	_finish()


func _first_active_effect_source(commands: RefCounted, region_key: Vector2i) -> Dictionary:
	var bases: Array = commands.call("get_region_base_instances", region_key)
	for base_value in bases:
		var base: Dictionary = base_value
		var entity_id := String(base.get("instance_id", ""))
		var resolved: Dictionary = commands.call("resolve_entity", entity_id)
		if not resolved.get("ok", false) or resolved.get("deleted", false):
			continue
		var instance: Dictionary = resolved["instance"]
		if not (instance.get("terrain_interaction", {}) as Dictionary).is_empty():
			return {"ok": true, "instance": instance}
	return {"ok": false}


func _resolved_region_sources(commands: RefCounted, state: RefCounted, region_key: Vector2i) -> Dictionary:
	var instances: Array[Dictionary] = []
	var revisions: Dictionary = {}
	var bases: Array = commands.call("get_region_base_instances", region_key)
	for base_value in bases:
		var base: Dictionary = base_value
		var entity_id := String(base.get("instance_id", ""))
		var resolved: Dictionary = commands.call("resolve_entity", entity_id)
		if not resolved.get("ok", false):
			return {"ok": false, "reason": resolved.get("reason", "resolve_failed")}
		if resolved.get("deleted", false):
			continue
		instances.append((resolved["instance"] as Dictionary).duplicate(true))
		revisions[entity_id] = int(state.call("get_entity_revision", entity_id))
	return {"ok": true, "instances": instances, "source_revisions": revisions}


func _effect_for_source(scope_snapshot: Dictionary, entity_id: String) -> Dictionary:
	for effect_value in (scope_snapshot.get("effects", {}) as Dictionary).values():
		var effect: Dictionary = effect_value
		if String(effect.get("source_instance_id", "")) == entity_id:
			return effect.duplicate(true)
	return {}


func _set_component(command_id: String, entity_id: String, world_revision: int, entity_revision: int, component_id: String, component: Dictionary) -> Dictionary:
	return {
		"schema_version": 1, "command_id": command_id, "operation": "ENTITY_SET_COMPONENT",
		"origin": {"type": "player", "id": "phase-c-test"}, "world_id": WORLD_ID, "world_seed": WORLD_SEED,
		"generator_version": Field.GENERATOR_VERSION, "expected_world_revision": world_revision,
		"expected_entity_revision": entity_revision, "entity_id": entity_id, "component_id": component_id,
		"component": component,
	}


func _simple_command(command_id: String, operation: String, entity_id: String, world_revision: int, entity_revision: int) -> Dictionary:
	return {
		"schema_version": 1, "command_id": command_id, "operation": operation,
		"origin": {"type": "player", "id": "phase-c-test"}, "world_id": WORLD_ID, "world_seed": WORLD_SEED,
		"generator_version": Field.GENERATOR_VERSION, "expected_world_revision": world_revision,
		"expected_entity_revision": entity_revision, "entity_id": entity_id,
	}


func _transform(translation: Array, rotation: Array, scale: Array) -> Dictionary:
	return {"schema_version": 1, "properties": {"translation_mm": translation, "rotation_mdeg": rotation, "scale_milli": scale}}


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
		if name == "." or name == "..":
			continue
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
	print("ISSUE108_PHASE_C_EVIDENCE=" + JSON.stringify(evidence))
	print("ISSUE108_PHASE_C_%s: assertions=%d failures=%d" % [
		"PASS" if failures == 0 else "FAIL",
		assertions,
		failures,
	])
	_remove_tree(ProjectSettings.globalize_path(ROOT))
	quit(0 if failures == 0 else 1)
