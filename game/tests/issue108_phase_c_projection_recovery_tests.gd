extends SceneTree

const Registry := preload("res://scripts/modding/content_definition_registry.gd")
const StateService := preload("res://scripts/objects/procedural_object_state_service.gd")
const CommandService := preload("res://scripts/entities/entity_command_service.gd")
const StateContract := preload("res://scripts/objects/procedural_object_state_contract.gd")
const ProjectionContract := preload("res://scripts/terrain/terrain_object_effect_projection_contract.gd")
const ProjectionStore := preload("res://scripts/terrain/terrain_object_effect_projection_store.gd")
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
	var reconstructed: Dictionary = commands.reconstruct_region(Vector2i.ZERO)
	_check(reconstructed.get("ok", false), "canonical region reconstructs for projection source")

	var projection_abs := ProjectSettings.globalize_path(PROJECTION_DIR)
	_check(not DirAccess.dir_exists_absolute(projection_abs), "old world begins without projection directory")
	var projection: RefCounted = ProjectionService.new()
	var projection_init: Dictionary = projection.initialize(
		WORLD_ID, WORLD_SEED, Field.GENERATOR_VERSION, PROJECTION_DIR
	)
	_check(
		projection_init.get("ok", false)
			and not projection_init.get("found", true)
			and int(projection_init.get("generation", -1)) == 0,
		"missing projection store loads as compatible empty projection"
	)
	_check(
		not DirAccess.dir_exists_absolute(projection_abs),
		"read-only initialization of an old world does not create or rewrite files"
	)

	var initial_reconcile: Dictionary = projection.reconcile_command_region(Vector2i.ZERO, commands)
	_check(initial_reconcile.get("ok", false) and initial_reconcile.get("changed", false), "authoritative region projects durably")
	_check(projection.get_effect_count() > 0, "region projection contains terrain effects")
	_check(DirAccess.dir_exists_absolute(projection_abs), "first reconciliation creates the separate projection store")

	var target := _first_active_effect_source(commands, Vector2i.ZERO)
	_check(target.get("ok", false), "projection fixture finds active interacting entity")
	if not target.get("ok", false):
		_finish()
		return
	var entity_id := String(target["instance"]["instance_id"])
	var initial_effect := _effect_for_source(projection.get_snapshot(), entity_id)
	_check(not initial_effect.is_empty(), "projected effect maps one-to-one to source entity")
	_check(
		initial_effect["terrain_interaction_pin"] == target["instance"]["terrain_interaction_pin"],
		"projection persists exact terrain-interaction pin"
	)
	_check(
		initial_effect["content_pin"] == target["instance"]["content_pin"],
		"projection persists exact source content pin"
	)
	_check(
		not bool(target["instance"].get("terrain_interaction_applied", true)),
		"projection does not mutate terrain_interaction_applied"
	)
	var initial_effect_id := String(initial_effect["effect_id"])
	var initial_fingerprint := String(initial_effect["source_fingerprint_sha256"])

	var no_change: Dictionary = projection.reconcile_command_region(Vector2i.ZERO, commands)
	_check(
		no_change.get("ok", false)
			and not no_change.get("changed", true)
			and no_change.get("reason") == "already_current",
		"repeat reconciliation is an idempotent no-op"
	)

	var negative_reconstruct: Dictionary = commands.reconstruct_region(Vector2i(-1, -1))
	_check(negative_reconstruct.get("ok", false), "negative region reconstructs")
	var negative_reconcile: Dictionary = projection.reconcile_command_region(Vector2i(-1, -1), commands)
	_check(negative_reconcile.get("ok", false), "negative region projection persists")
	_check(
		projection.get_snapshot()["scopes"].has(ProjectionContract.scope_id_for_region(Vector2i(-1, -1))),
		"negative region uses signed deterministic scope identity"
	)

	# Simulate a crash after the generation file has been flushed but before the
	# final rename is observed by the next process.
	var crash_generation := int(projection.storage_generation)
	var crash_final := projection_abs.path_join("projection-%08d.json" % crash_generation)
	var crash_tmp := projection_abs.path_join("projection-%08d.tmp" % crash_generation)
	_check(FileAccess.file_exists(crash_final), "latest projection generation exists before crash simulation")
	var crash_rename := DirAccess.rename_absolute(crash_final, crash_tmp)
	_check(crash_rename == OK, "latest committed generation is converted into recoverable temporary fixture")

	var recovered: RefCounted = ProjectionService.new()
	var recovered_init: Dictionary = recovered.initialize(
		WORLD_ID, WORLD_SEED, Field.GENERATOR_VERSION, PROJECTION_DIR
	)
	_check(
		recovered_init.get("ok", false)
			and recovered_init.get("found", false)
			and recovered_init.get("recovered_temporary", false)
			and int(recovered_init.get("generation", -1)) == crash_generation,
		"startup recovers highest valid temporary generation"
	)
	_check(
		FileAccess.file_exists(crash_final) and not FileAccess.file_exists(crash_tmp),
		"temporary recovery promotes generation back to final path"
	)
	var recovered_effect := _effect_for_source(recovered.get_snapshot(), entity_id)
	_check(
		not recovered_effect.is_empty()
			and recovered_effect["terrain_interaction_pin"] == initial_effect["terrain_interaction_pin"],
		"crash recovery preserves exact effect and interaction pin"
	)

	# Mutate the authoritative entity after the projection commit. The projection
	# must become stale and remain so until explicitly reconciled.
	var set_transform := _set_component(
		"00000000-0000-4000-8000-00000000c001",
		entity_id,
		state.get_revision(),
		state.get_entity_revision(entity_id),
		StateContract.COMPONENT_TRANSFORM,
		_transform([120, 0, -80], [11000, 27000, -7000], [900, 1200, 1100])
	)
	var transformed: Dictionary = commands.dispatch(set_transform)
	_check(
		transformed.get("ok", false)
			and int(transformed.get("world_revision", -1)) == 1
			and int(transformed.get("entity_revision", -1)) == 1,
		"authoritative transform commits independently before projection reconciliation"
	)
	var stale_status: Dictionary = recovered.get_scope_status(Vector2i.ZERO, state.get_revision())
	_check(stale_status.get("status") == "stale", "projection exposes stale scope after source-only commit")
	var transformed_reconcile: Dictionary = recovered.reconcile_command_region(Vector2i.ZERO, commands)
	_check(transformed_reconcile.get("ok", false) and transformed_reconcile.get("changed", false), "stale scope reconciles from authoritative state")
	var transformed_effect := _effect_for_source(recovered.get_snapshot(), entity_id)
	_check(
		String(transformed_effect.get("effect_id", "")) == initial_effect_id,
		"effect identity remains stable across source transform revision"
	)
	_check(
		String(transformed_effect.get("source_fingerprint_sha256", "")) != initial_fingerprint
			and int(transformed_effect.get("source_revision", -1)) == 1,
		"projection advances source revision and fingerprint after transform"
	)
	_check(
		recovered.get_scope_status(Vector2i.ZERO, state.get_revision()).get("status") == "current",
		"reconciled scope is current with authoritative world revision"
	)

	# Same source revision with a different effective effect is an explicit
	# divergence, not a silent rewrite.
	var conflict_sources := _resolved_region_sources(commands, state, Vector2i.ZERO)
	_check(conflict_sources.get("ok", false), "effective region sources can be reconstructed for conflict probe")
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
	var stale_reconcile: Dictionary = recovered.reconcile_scope(
		Vector2i.ZERO, 0, [], {}
	)
	_check(
		not stale_reconcile.get("ok", false)
			and stale_reconcile.get("reason") == "effect_projection_stale_source_world_revision",
		"older authoritative snapshot cannot overwrite newer projection"
	)

	# Delete is authoritative first; reconciliation then garbage-collects the
	# orphaned effect from this regional scope.
	var delete_command := _simple_command(
		"00000000-0000-4000-8000-00000000c002",
		"ENTITY_DELETE",
		entity_id,
		state.get_revision(),
		state.get_entity_revision(entity_id)
	)
	var deleted: Dictionary = commands.dispatch(delete_command)
	_check(deleted.get("ok", false) and int(deleted.get("world_revision", -1)) == 2, "authoritative delete commits")
	_check(
		recovered.get_scope_status(Vector2i.ZERO, state.get_revision()).get("status") == "stale",
		"delete leaves projection detectably stale until reconciliation"
	)
	var delete_reconcile: Dictionary = recovered.reconcile_command_region(Vector2i.ZERO, commands)
	_check(
		delete_reconcile.get("ok", false)
			and int(delete_reconcile.get("removed_effect_count", 0)) >= 1,
		"reconciliation removes orphaned effect after authoritative delete"
	)
	_check(
		_effect_for_source(recovered.get_snapshot(), entity_id).is_empty(),
		"deleted source no longer has persistent projected effect"
	)

	# Restore returns the same source identity and therefore the same stable effect
	# ID at a newer source revision.
	var restore_command := _simple_command(
		"00000000-0000-4000-8000-00000000c003",
		"ENTITY_RESTORE",
		entity_id,
		state.get_revision(),
		state.get_entity_revision(entity_id)
	)
	var restored: Dictionary = commands.dispatch(restore_command)
	_check(restored.get("ok", false) and int(restored.get("world_revision", -1)) == 3, "authoritative restore commits")
	var restore_reconcile: Dictionary = recovered.reconcile_command_region(Vector2i.ZERO, commands)
	_check(restore_reconcile.get("ok", false), "restored entity reprojects")
	var restored_effect := _effect_for_source(recovered.get_snapshot(), entity_id)
	_check(
		String(restored_effect.get("effect_id", "")) == initial_effect_id
			and int(restored_effect.get("source_revision", -1)) == 3,
		"restored source recreates stable effect identity at monotonic revision"
	)
	_check(
		String(restored_effect.get("source_fingerprint_sha256", "")) != initial_fingerprint,
		"source revision participates in recovery fingerprint"
	)

	# Lost projection data is rebuildable from the authoritative command/state
	# services without touching entity persistence.
	var authoritative_snapshot_before_rebuild: Dictionary = state.snapshot.duplicate(true)
	var expected_restored_effect := restored_effect.duplicate(true)
	_remove_tree(projection_abs)
	var rebuilt: RefCounted = ProjectionService.new()
	var rebuilt_init: Dictionary = rebuilt.initialize(
		WORLD_ID, WORLD_SEED, Field.GENERATOR_VERSION, PROJECTION_DIR
	)
	_check(rebuilt_init.get("ok", false) and not rebuilt_init.get("found", true), "lost projection reopens as empty derived state")
	var rebuilt_region: Dictionary = rebuilt.reconcile_command_region(Vector2i.ZERO, commands)
	_check(rebuilt_region.get("ok", false), "empty projection rebuilds from authoritative region")
	var rebuilt_effect := _effect_for_source(rebuilt.get_snapshot(), entity_id)
	_check(
		rebuilt_effect == expected_restored_effect,
		"projection rebuild reproduces exact normalized effect from authoritative source"
	)
	_check(
		state.snapshot == authoritative_snapshot_before_rebuild,
		"projection rebuild never rewrites authoritative entity/object snapshot"
	)

	# A corrupt finalized generation fails closed instead of being silently
	# replaced. This preserves evidentiary recovery semantics.
	var corrupt_dir := ProjectSettings.globalize_path(ROOT + "/corrupt-projection")
	DirAccess.make_dir_recursive_absolute(corrupt_dir)
	var corrupt_file := FileAccess.open(
		corrupt_dir.path_join("projection-00000001.json"), FileAccess.WRITE
	)
	if corrupt_file != null:
		corrupt_file.store_string("{corrupt")
		corrupt_file.flush()
		corrupt_file.close()
	var corrupt_service: RefCounted = ProjectionService.new()
	var corrupt_init: Dictionary = corrupt_service.initialize(
		WORLD_ID, WORLD_SEED, Field.GENERATOR_VERSION, corrupt_dir
	)
	_check(
		not corrupt_init.get("ok", false)
			and corrupt_init.get("reason") == "effect_projection_corrupt_generation",
		"corrupt finalized generation fails closed"
	)

	evidence = {
		"initial_effect_count": int(initial_reconcile.get("effect_count", 0)),
		"negative_scope_effect_count": int(negative_reconcile.get("effect_count", 0)),
		"crash_recovered_generation": crash_generation,
		"final_authoritative_world_revision": state.get_revision(),
		"final_target_source_revision": int(rebuilt_effect.get("source_revision", -1)),
		"rebuild_effect_count": rebuilt.get_effect_count(),
	}
	_finish()


func _first_active_effect_source(commands: RefCounted, region_key: Vector2i) -> Dictionary:
	for base in commands.get_region_base_instances(region_key):
		var entity_id := String(base.get("instance_id", ""))
		var resolved: Dictionary = commands.resolve_entity(entity_id)
		if not resolved.get("ok", false) or resolved.get("deleted", false):
			continue
		var instance: Dictionary = resolved["instance"]
		if not (instance.get("terrain_interaction", {}) as Dictionary).is_empty():
			return {"ok": true, "instance": instance}
	return {"ok": false}


func _resolved_region_sources(
	commands: RefCounted,
	state: RefCounted,
	region_key: Vector2i
) -> Dictionary:
	var instances: Array[Dictionary] = []
	var revisions: Dictionary = {}
	for base in commands.get_region_base_instances(region_key):
		var entity_id := String(base.get("instance_id", ""))
		var resolved: Dictionary = commands.resolve_entity(entity_id)
		if not resolved.get("ok", false):
			return {"ok": false, "reason": resolved.get("reason", "resolve_failed")}
		if resolved.get("deleted", false):
			continue
		instances.append((resolved["instance"] as Dictionary).duplicate(true))
		revisions[entity_id] = state.get_entity_revision(entity_id)
	return {"ok": true, "instances": instances, "source_revisions": revisions}


func _effect_for_source(projection_snapshot: Dictionary, entity_id: String) -> Dictionary:
	for effect_value in (projection_snapshot.get("effects", {}) as Dictionary).values():
		var effect: Dictionary = effect_value
		if String(effect.get("source_instance_id", "")) == entity_id:
			return effect.duplicate(true)
	return {}


func _set_component(
	command_id: String,
	entity_id: String,
	world_revision: int,
	entity_revision: int,
	component_id: String,
	component: Dictionary
) -> Dictionary:
	return {
		"schema_version": 1,
		"command_id": command_id,
		"operation": "ENTITY_SET_COMPONENT",
		"origin": {"type": "player", "id": "phase-c-test"},
		"world_id": WORLD_ID,
		"world_seed": WORLD_SEED,
		"generator_version": Field.GENERATOR_VERSION,
		"expected_world_revision": world_revision,
		"expected_entity_revision": entity_revision,
		"entity_id": entity_id,
		"component_id": component_id,
		"component": component,
	}


func _simple_command(
	command_id: String,
	operation: String,
	entity_id: String,
	world_revision: int,
	entity_revision: int
) -> Dictionary:
	return {
		"schema_version": 1,
		"command_id": command_id,
		"operation": operation,
		"origin": {"type": "player", "id": "phase-c-test"},
		"world_id": WORLD_ID,
		"world_seed": WORLD_SEED,
		"generator_version": Field.GENERATOR_VERSION,
		"expected_world_revision": world_revision,
		"expected_entity_revision": entity_revision,
		"entity_id": entity_id,
	}


func _transform(translation: Array, rotation: Array, scale: Array) -> Dictionary:
	return {
		"schema_version": 1,
		"properties": {
			"translation_mm": translation,
			"rotation_mdeg": rotation,
			"scale_milli": scale,
		},
	}


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
