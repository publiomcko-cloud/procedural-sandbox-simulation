extends SceneTree

const Loader := preload("res://scripts/modding/declarative_mod_loader.gd")
const Registry := preload("res://scripts/modding/content_definition_registry.gd")
const StateService := preload("res://scripts/objects/procedural_object_state_service.gd")
const StateContract := preload("res://scripts/objects/procedural_object_state_contract.gd")
const CommandService := preload("res://scripts/entities/entity_command_service.gd")
const CommandContract := preload("res://scripts/entities/entity_command_contract.gd")
const ObjectWorld := preload("res://scripts/objects/procedural_object_world.gd")
const Field := preload("res://scripts/terrain/sdf_world.gd")

const WORLD_ID := "p3-command-test"
const WORLD_SEED := 424242
const DEFINITION_ID := "firstparty.core_rocks:granite"
const COMMAND_1 := "00000000-0000-4000-8000-000000000001"
const COMMAND_2 := "00000000-0000-4000-8000-000000000002"
const COMMAND_3 := "00000000-0000-4000-8000-000000000003"

var assertions := 0
var failures := 0
var _root := ""
var _mod_root := ""


func _initialize() -> void:
	await _run()
	if failures == 0:
		print("ENTITY_COMMAND_PASS: assertions=%d failures=0" % assertions)
	else:
		push_error("ENTITY_COMMAND_FAIL: assertions=%d failures=%d" % [assertions, failures])
	quit(0 if failures == 0 else 1)


func _run() -> void:
	_root = ProjectSettings.globalize_path("user://p3_0a_entity_commands_%d" % Time.get_ticks_usec())
	_mod_root = "user://mods/p3_0a_command_test_%d" % Time.get_ticks_usec()
	var state_path := _root.path_join("state")
	var registry := _registry()
	_check(registry != null, "first-party declarative package registers without executable mod code")
	if registry == null:
		return
	var state: ProceduralObjectStateService = StateService.new()
	var initialized: Dictionary = state.initialize(WORLD_ID, WORLD_SEED, Field.GENERATOR_VERSION, state_path)
	_check(initialized.get("ok", false) and int(state.snapshot.schema_version) == 1, "P2.0B schema-1 empty snapshot loads unchanged")
	var commands: EntityCommandService = CommandService.new()
	var pre_migration: Dictionary = commands.initialize(state, registry)
	_check(not pre_migration.get("ok", false) and pre_migration.reason == "command_snapshot_migration_required", "command dispatch fails closed until caller explicitly upgrades snapshot schema")
	_check(int(state.snapshot.schema_version) == 1 and not FileAccess.file_exists(state_path.path_join("objects-00000001.json")), "failed migration preflight does not rewrite an existing save")
	var upgrade: Dictionary = state.upgrade_command_snapshot_schema()
	_check(upgrade.get("ok", false) and int(state.snapshot.schema_version) == 2 and state.get_revision() == 0, "explicit schema-2 upgrade preserves world revision")
	_check(commands.initialize(state, registry).get("ok", false), "central command service binds to the existing P2.0B state service")
	var reconstructed := commands.reconstruct_region(Vector2i.ZERO)
	_check(reconstructed.get("ok", false), "canonical region baseline reconstructs without scene nodes (%s)" % reconstructed.get("reason", "ok"))

	var place := _place(COMMAND_1, "player", "player-1", 0, [1000, 0, 1000], [0, 0])
	var placed: Dictionary = _timed_dispatch(commands, state, place)
	_check(placed.get("ok", false) and placed.get("operation") == "ENTITY_PLACE" and int(placed.get("world_revision", -1)) == 1 and int(placed.get("entity_revision", -1)) == 1, "registered explicit definition places atomically with its own revisioned identity (%s)" % placed.get("reason", "ok"))
	var entity_id := String(placed.get("entity_id", ""))
	_check(entity_id == "%s/seed-%d/placed/%s" % [WORLD_ID, WORLD_SEED, COMMAND_1], "placed identity uses a separate command-derived namespace")
	_check(not entity_id.contains("/region/") and state.snapshot.placed_entities.has(entity_id), "placed ID cannot alias a procedural region/slot/population ID")
	_check(int(state.snapshot.revision) == 1 and int(state.snapshot.entity_revisions[entity_id]) == 1, "place increments global and entity revisions in the same persisted snapshot")
	_check(state.snapshot.command_receipts[COMMAND_1].undo_metadata.inverse_operation == "ENTITY_DELETE" and state.snapshot.command_receipts[COMMAND_1].undo_metadata.identity.instance_id == entity_id, "place receipt retains a bounded inverse descriptor and stable identity")
	var replay_place: Dictionary = commands.dispatch(place)
	_check(replay_place.get("ok", false) and replay_place.get("duplicate", false) and state.get_revision() == 1, "exact retry after commit returns durable receipt without reapplying")
	var conflicting_place: Dictionary = place.duplicate(true)
	conflicting_place.position_mm = [2000, 0, 1000]
	_check(commands.dispatch(conflicting_place).get("reason") == "idempotency_key_payload_conflict" and state.get_revision() == 1, "same command ID with different payload is rejected without effects")
	var placed_reconstruction := commands.reconstruct_region(Vector2i.ZERO)
	_check(placed_reconstruction.get("ok", false), "placed entity reconstructs from persisted explicit identity and recipe (%s)" % placed_reconstruction.get("reason", "ok"))

	var invalid := _set_component(COMMAND_2, entity_id, "player", "player-1", 1, 1, StateContract.COMPONENT_APPEARANCE, _appearance("Changed"))
	invalid["unexpected"] = true
	_check(commands.dispatch(invalid).get("reason") == "command_fields_invalid" and state.get_revision() == 1, "unknown command fields fail before state mutation")
	var bad_component := _set_component(COMMAND_2, entity_id, "player", "player-1", 1, 1, "core.executable", _appearance("bad"))
	_check(not commands.dispatch(bad_component).get("ok", false) and state.get_revision() == 1, "unknown component is rejected without a receipt or partial write")
	var stale_world := _set_component(COMMAND_2, entity_id, "player", "player-1", 0, 1, StateContract.COMPONENT_APPEARANCE, _appearance("stale"))
	_check(commands.dispatch(stale_world).get("reason") == "stale_world_revision", "stale world revision fails before component validation or persistence")
	var stale_entity := _set_component(COMMAND_2, entity_id, "player", "player-1", 1, 0, StateContract.COMPONENT_APPEARANCE, _appearance("stale"))
	_check(commands.dispatch(stale_entity).get("reason") == "stale_entity_revision" and state.get_revision() == 1, "stale entity revision is independently rejected")

	var set_player := _set_component(COMMAND_2, entity_id, "player", "player-1", 1, 1, StateContract.COMPONENT_TRANSFORM, _transform([250, 0, 0], [0, 15000, 0], [1250, 1250, 1250]))
	var set_result: Dictionary = _timed_dispatch(commands, state, set_player)
	_check(set_result.get("ok", false) and int(set_result.world_revision) == 2 and int(set_result.entity_revision) == 2, "player-origin component command commits with optimistic revisions")
	_check(state.snapshot.command_receipts[COMMAND_2].undo_metadata.prior_component_present == false and state.snapshot.command_receipts[COMMAND_2].undo_metadata.component_id == StateContract.COMPONENT_TRANSFORM, "component receipt records whether a sparse value existed before the write")
	var replay_set: Dictionary = commands.dispatch(set_player)
	_check(replay_set.get("duplicate", false) and state.get_revision() == 2, "same set-component command replay is idempotent after global revision advanced")
	var set_editor := _set_component(COMMAND_3, entity_id, "editor", "editor-1", 2, 2, StateContract.COMPONENT_APPEARANCE, _appearance("Editor"))
	_check(commands.dispatch(set_editor).get("ok", false), "editor origin uses the same validated command path")
	var set_mod := _set_component("00000000-0000-4000-8000-000000000004", entity_id, "mod", "firstparty.core_rocks", 3, 3, StateContract.COMPONENT_LOGICAL, _logical({"edited": true}))
	_check(commands.dispatch(set_mod).get("ok", false), "registered declarative mod origin uses the same command semantics without executing scripts")
	var no_external_registry := Registry.new()
	var first_party_discovery: Dictionary = Loader.discover_and_validate(["res://mods/first-party"])
	_check(no_external_registry.register_discovered(first_party_discovery).get("ok", false), "retry fixture registers only first-party content after the originating mod is absent")
	var retry_without_origin := CommandService.new()
	_check(retry_without_origin.initialize(state, no_external_registry).get("ok", false), "idempotency retry uses the same authoritative state with a reduced registry")
	var replay_missing_origin: Dictionary = retry_without_origin.dispatch(set_mod)
	_check(replay_missing_origin.get("ok", false) and replay_missing_origin.get("duplicate", false) and state.get_revision() == 4, "durable exact retry returns its receipt even when the originating mod is no longer registered")
	var missing_mod := _set_component("00000000-0000-4000-8000-000000000005", entity_id, "mod", "missing.package", 4, 4, StateContract.COMPONENT_LOGICAL, _logical({"edited": false}))
	_check(commands.dispatch(missing_mod).get("reason") == "command_origin_mod_missing" and state.get_revision() == 4, "missing mod origin is rejected without changing revision")

	var delete_command := _simple_command("00000000-0000-4000-8000-000000000006", "ENTITY_DELETE", entity_id, "player", "player-1", 4, 4)
	var deleted: Dictionary = _timed_dispatch(commands, state, delete_command)
	_check(deleted.get("ok", false) and state.snapshot.deleted.has(entity_id) and not state.snapshot.overrides.has(entity_id), "delete atomically writes logical tombstone and clears sparse overrides")
	_check(state.snapshot.command_receipts[delete_command.command_id].undo_metadata.inverse_operation == "ENTITY_RESTORE" and not state.snapshot.command_receipts[delete_command.command_id].undo_metadata.prior_override.is_empty(), "delete receipt preserves the prior sparse override required for future reversal")
	var set_deleted := _set_component("00000000-0000-4000-8000-000000000007", entity_id, "player", "player-1", 5, 5, StateContract.COMPONENT_APPEARANCE, _appearance("blocked"))
	_check(commands.dispatch(set_deleted).get("reason") == "deleted_entity_requires_restore" and state.get_revision() == 5, "deleted entity cannot be changed before restore")
	var restore_command := _simple_command("00000000-0000-4000-8000-000000000008", "ENTITY_RESTORE", entity_id, "editor", "editor-1", 5, 5)
	var restored: Dictionary = _timed_dispatch(commands, state, restore_command)
	_check(restored.get("ok", false) and not state.snapshot.deleted.has(entity_id) and not state.snapshot.overrides.has(entity_id), "restore removes tombstone and returns the placed entity to its exact base components")
	_check(state.snapshot.command_receipts[restore_command.command_id].undo_metadata.inverse_operation == "ENTITY_DELETE" and state.snapshot.command_receipts[restore_command.command_id].undo_metadata.identity.instance_id == entity_id, "restore receipt retains its inverse identity and operation metadata")
	_check(state.get_entity_revision(entity_id) == 6 and state.get_revision() == 6, "entity revision remains monotonic after restoring an entity without sparse overrides")

	var racer_a := _set_component("00000000-0000-4000-8000-000000000009", entity_id, "player", "player-1", 6, 6, StateContract.COMPONENT_LOGICAL, _logical({"winner": true}))
	var racer_b := _set_component("00000000-0000-4000-8000-00000000000a", entity_id, "editor", "editor-1", 6, 6, StateContract.COMPONENT_LOGICAL, _logical({"loser": true}))
	_check(commands.dispatch(racer_a).get("ok", false), "first command at a shared expected revision commits")
	var after_first := state.snapshot.duplicate(true)
	_check(commands.dispatch(racer_b).get("reason") == "stale_world_revision" and state.snapshot == after_first, "logical race loser is rejected without partial state")

	var boundary_wrong := _place("00000000-0000-4000-8000-00000000000b", "player", "player-1", state.get_revision(), [-1, 0, -1], [0, 0])
	_check(commands.dispatch(boundary_wrong).get("reason") == "place_region_ownership_mismatch" and state.get_revision() == 7, "negative boundary owner mismatch is rejected")
	var boundary_place := _place("00000000-0000-4000-8000-00000000000b", "player", "player-1", state.get_revision(), [-1, 0, -1], [-1, -1])
	var boundary_result: Dictionary = commands.dispatch(boundary_place)
	_check(boundary_result.get("ok", false) and Vector2i(state.snapshot.placed_entities[boundary_result.entity_id].identity.region_key[0], state.snapshot.placed_entities[boundary_result.entity_id].identity.region_key[1]) == Vector2i(-1, -1), "negative millimeter coordinates use floor-based region ownership")
	var negative_reconstruct := commands.reconstruct_region(Vector2i(-1, -1))
	_check(negative_reconstruct.get("ok", false) and commands.resolve_entity(String(boundary_result.entity_id)).get("ok", false), "negative region explicit placement reconstructs deterministically")

	var missing_definition := _place("00000000-0000-4000-8000-00000000000c", "player", "player-1", state.get_revision(), [1000, 0, 1000], [0, 0])
	missing_definition.definition_id = "missing.package:rock"
	_check(commands.dispatch(missing_definition).get("reason") == "place_definition_missing", "definition absent from registry cannot be placed")
	var not_loaded_id := "%s/seed-%d/object/firstparty.core_rocks:granite/region/7,7/slot/0" % [WORLD_ID, WORLD_SEED]
	var missing_entity := _simple_command("00000000-0000-4000-8000-00000000000d", "ENTITY_DELETE", not_loaded_id, "player", "player-1", state.get_revision(), 0)
	_check(commands.dispatch(missing_entity).get("reason") == "entity_not_reconstructed_or_content_missing", "absent or unloaded entity cannot be mutated by guessed identity")
	commands.release_region(Vector2i(-1, -1))
	var released_command := _simple_command("00000000-0000-4000-8000-00000000000e", "ENTITY_DELETE", String(boundary_result.entity_id), "player", "player-1", state.get_revision(), state.get_entity_revision(String(boundary_result.entity_id)))
	_check(commands.dispatch(released_command).get("reason") == "entity_not_reconstructed_or_content_missing", "unloaded explicit entity must be reconstructed before a command")

	var prior_revision := state.get_revision()
	var state_after_restart: ProceduralObjectStateService = StateService.new()
	_check(state_after_restart.initialize(WORLD_ID, WORLD_SEED, Field.GENERATOR_VERSION, state_path).get("ok", false), "P2B-backed command state reloads after service restart")
	_check(int(state_after_restart.snapshot.schema_version) == 2 and state_after_restart.get_revision() == prior_revision, "restart preserves schema, world revision, placements, receipts and tombstones")
	var command_after_restart: EntityCommandService = CommandService.new()
	_check(command_after_restart.initialize(state_after_restart, registry).get("ok", false), "command service reinitializes from durable P2B state")
	_check(command_after_restart.reconstruct_region(Vector2i.ZERO).get("ok", false), "post-restart deterministic region reconstruction succeeds")
	var duplicate_after_restart: Dictionary = command_after_restart.dispatch(restore_command)
	_check(duplicate_after_restart.get("ok", false) and duplicate_after_restart.get("duplicate", false) and state_after_restart.get_revision() == prior_revision, "durable command receipt prevents reapplication after restart")
	_check(state_after_restart.snapshot.placed_entities.has(entity_id), "place record survives restart and remains separate from procedural population")
	_check(StateContract.validate_snapshot(state_after_restart.snapshot, WORLD_ID, WORLD_SEED, Field.GENERATOR_VERSION).get("ok", false), "extended snapshot validates as a complete one-to-one entity/command record")
	var invalid_undo: Dictionary = state_after_restart.snapshot.duplicate(true)
	invalid_undo.command_receipts[COMMAND_1].undo_metadata.inverse_operation = "ENTITY_PLACE"
	_check(not StateContract.validate_snapshot(invalid_undo, WORLD_ID, WORLD_SEED, Field.GENERATOR_VERSION).get("ok", false), "corrupt or unsupported inverse metadata fails closed during snapshot validation")

	_test_failed_write_is_atomic(registry)
	_test_legacy_state_migration(registry)
	_test_contract_rejections()
	_remove_tree(ProjectSettings.globalize_path(_mod_root))
	_remove_tree(_root)


func _test_failed_write_is_atomic(registry: ContentDefinitionRegistry) -> void:
	var path := _root.path_join("write_failure")
	var state: ProceduralObjectStateService = StateService.new()
	_check(state.initialize(WORLD_ID, WORLD_SEED, Field.GENERATOR_VERSION, path).get("ok", false), "write-failure fixture initializes on its own temporary storage root")
	_check(state.upgrade_command_snapshot_schema().get("ok", false), "write-failure fixture explicitly upgrades its isolated state")
	var command_service: EntityCommandService = CommandService.new()
	_check(command_service.initialize(state, registry).get("ok", false), "write-failure dispatcher initializes")
	_check(command_service.reconstruct_region(Vector2i.ZERO).get("ok", false), "write-failure region is reconstructed before failure injection")
	_remove_tree(path)
	_write_bytes(path, "block-directory".to_utf8_buffer())
	var command := _place(COMMAND_1, "player", "player-1", 0, [1000, 0, 1000], [0, 0])
	var result: Dictionary = command_service.dispatch(command)
	_check(not result.get("ok", false) and String(result.get("reason", "")).begins_with("command_commit_uncertain:"), "storage write failure is surfaced and forces dispatcher reinitialization")
	_check(not state.initialized and int(state.snapshot.revision) == 0 and state.snapshot.placed_entities.is_empty() and state.snapshot.command_receipts.is_empty(), "failed command does not publish partial in-memory state")


func _test_legacy_state_migration(registry: ContentDefinitionRegistry) -> void:
	var path := _root.path_join("legacy_state")
	var state: ProceduralObjectStateService = StateService.new()
	_check(state.initialize(WORLD_ID, WORLD_SEED + 2, Field.GENERATOR_VERSION, path).get("ok", false), "legacy migration starts from a P2.0B schema-1 save")
	var generated: Dictionary = ObjectWorld.build_region_instances(WORLD_SEED + 2, WORLD_ID, Vector2i.ZERO, registry)
	_check(generated.get("ok", false) and not generated.instances.is_empty(), "legacy migration fixture uses a canonical procedural baseline")
	if generated.get("ok", false) and not generated.instances.is_empty():
		var base: Dictionary = generated.instances[0]
		state.resolve_instance(base)
		var appearance := _appearance("legacy override")
		var mutation := state.set_component(base, StateContract.COMPONENT_APPEARANCE, appearance)
		_check(mutation.get("ok", false) and state.get_revision() == 1, "existing P2.0B override is committed before explicit upgrade")
	var old_snapshot: Dictionary = state.snapshot.duplicate(true)
	var upgrade := state.upgrade_command_snapshot_schema()
	_check(upgrade.get("ok", false) and state.snapshot.overrides == old_snapshot.overrides and state.snapshot.deleted == old_snapshot.deleted and state.get_revision() == int(old_snapshot.revision), "explicit migration carries existing overrides and deletions without semantic reinterpretation")
	var reload: ProceduralObjectStateService = StateService.new()
	_check(reload.initialize(WORLD_ID, WORLD_SEED + 2, Field.GENERATOR_VERSION, path).get("ok", false) and int(reload.snapshot.schema_version) == 2, "migrated generation remains readable after restart while prior immutable generation was preserved by store policy")
	_remove_tree(path)


func _test_contract_rejections() -> void:
	var unsupported: Dictionary = _empty_v2_snapshot()
	unsupported.schema_version = 4
	_check(StateContract.validate_snapshot(unsupported, WORLD_ID, WORLD_SEED, Field.GENERATOR_VERSION).get("reason") == "snapshot_schema_unsupported", "unknown future snapshot version is rejected without migration")
	var malformed: Dictionary = _empty_v2_snapshot()
	malformed.entity_revisions["forged"] = 1
	_check(not StateContract.validate_snapshot(malformed, WORLD_ID, WORLD_SEED, Field.GENERATOR_VERSION).get("ok", false), "malformed per-entity revision identifier is rejected")
	var command: Dictionary = _place(COMMAND_1, "player", "player-1", 0, [0, 0, 0], [0, 0])
	command.schema_version = 9
	_check(CommandContract.validate(command, WORLD_ID, WORLD_SEED, Field.GENERATOR_VERSION).get("reason") == "command_schema_unsupported", "unsupported command version is rejected")
	command = _place(COMMAND_1, "player", "player-1", 0, [-1, 0, -1], [-1, 0])
	_check(CommandContract.validate(command, WORLD_ID, WORLD_SEED, Field.GENERATOR_VERSION).get("reason") == "place_region_ownership_mismatch", "region ownership is checked at the exact negative boundary")
	command = _place(COMMAND_1, "player", "player-1", 0, [0, 0, 0], [0, 0])
	command.expected_entity_revision = 1
	_check(CommandContract.validate(command, WORLD_ID, WORLD_SEED, Field.GENERATOR_VERSION).get("reason") == "place_expected_entity_revision_must_be_zero", "placement cannot claim an existing entity revision")
	command = _place(COMMAND_1, "unknown", "player-1", 0, [0, 0, 0], [0, 0])
	_check(CommandContract.validate(command, WORLD_ID, WORLD_SEED, Field.GENERATOR_VERSION).get("reason") == "command_origin_invalid", "unknown origin type is rejected")


func _registry() -> ContentDefinitionRegistry:
	var package_path := _mod_root
	var package_absolute := ProjectSettings.globalize_path(package_path)
	var mkdir_result := DirAccess.make_dir_recursive_absolute(package_absolute.path_join("objects"))
	if mkdir_result != OK and mkdir_result != ERR_ALREADY_EXISTS:
		_check(false, "external mod package is copied into a unique disposable user:// root")
		return null
	DirAccess.make_dir_recursive_absolute(package_absolute.path_join("populations"))
	DirAccess.make_dir_recursive_absolute(package_absolute.path_join("interactions"))
	var source_root := ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir().path_join("mods/examples/procedural-rock")
	for relative_path in [
		"manifest.json",
		"objects/procedural_rock.json",
		"populations/basalt_legacy.json",
		"populations/basalt_population.json",
		"interactions/basalt_ground_imprint.json",
	]:
		var bytes: PackedByteArray = FileAccess.get_file_as_bytes(source_root.path_join(relative_path))
		if bytes.is_empty() or not _write_bytes(package_absolute.path_join(relative_path), bytes):
			_check(false, "external declarative package fixture copied from repository data")
			return null
	var roots: Array[String] = ["res://mods/first-party", "user://mods"]
	var discovered: Dictionary = Loader.discover_and_validate(roots)
	if not discovered.get("ok", false):
		_check(false, "first-party package discovery succeeds (%s)" % discovered.get("reason", "unknown"))
		return null
	var value: ContentDefinitionRegistry = Registry.new()
	var registered: Dictionary = value.register_discovered(discovered)
	if not registered.get("ok", false):
		_check(false, "first-party package registry succeeds (%s)" % registered.get("reason", "unknown"))
		return null
	return value


func _place(command_id: String, origin_type: String, origin_id: String, world_revision: int, position_mm: Array, region_key: Array) -> Dictionary:
	return {
		"schema_version": 1, "command_id": command_id, "operation": "ENTITY_PLACE",
		"origin": {"type": origin_type, "id": origin_id}, "world_id": WORLD_ID, "world_seed": WORLD_SEED,
		"generator_version": Field.GENERATOR_VERSION, "expected_world_revision": world_revision,
		"expected_entity_revision": 0, "definition_id": DEFINITION_ID, "position_mm": position_mm,
		"region_key": region_key, "recipe_seed": 99117,
		"components": {
			StateContract.COMPONENT_TRANSFORM: _transform([0, 0, 0], [0, 0, 0], [1000, 1000, 1000]),
			StateContract.COMPONENT_APPEARANCE: _appearance("placed rock"),
			StateContract.COMPONENT_LOGICAL: _logical({}),
		},
	}


func _set_component(command_id: String, entity_id: String, origin_type: String, origin_id: String, world_revision: int, entity_revision: int, component_id: String, component: Dictionary) -> Dictionary:
	return {
		"schema_version": 1, "command_id": command_id, "operation": "ENTITY_SET_COMPONENT",
		"origin": {"type": origin_type, "id": origin_id}, "world_id": WORLD_ID, "world_seed": WORLD_SEED,
		"generator_version": Field.GENERATOR_VERSION, "expected_world_revision": world_revision,
		"expected_entity_revision": entity_revision, "entity_id": entity_id, "component_id": component_id,
		"component": component,
	}


func _simple_command(command_id: String, operation: String, entity_id: String, origin_type: String, origin_id: String, world_revision: int, entity_revision: int) -> Dictionary:
	return {
		"schema_version": 1, "command_id": command_id, "operation": operation,
		"origin": {"type": origin_type, "id": origin_id}, "world_id": WORLD_ID, "world_seed": WORLD_SEED,
		"generator_version": Field.GENERATOR_VERSION, "expected_world_revision": world_revision,
		"expected_entity_revision": entity_revision, "entity_id": entity_id,
	}


func _transform(translation: Array, rotation: Array, scale: Array) -> Dictionary:
	return {"schema_version": 1, "properties": {"translation_mm": translation, "rotation_mdeg": rotation, "scale_milli": scale}}


func _appearance(label: String) -> Dictionary:
	return {"schema_version": 1, "properties": {"tint_milli": [500, 700, 400], "label": label}}


func _logical(values: Dictionary) -> Dictionary:
	return {"schema_version": 1, "properties": {"values": values}}


func _empty_v2_snapshot() -> Dictionary:
	return {"schema_version": 2, "world_id": WORLD_ID, "world_seed": WORLD_SEED, "generator_version": Field.GENERATOR_VERSION, "revision": 0, "overrides": {}, "deleted": {}, "placed_entities": {}, "entity_revisions": {}, "command_receipts": {}}


func _write_bytes(path: String, bytes: PackedByteArray) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_buffer(bytes)
	file.flush()
	file.flush()
	var result := file.get_error() == OK
	file.close()
	return result


func _timed_dispatch(commands: EntityCommandService, state: ProceduralObjectStateService, command: Dictionary) -> Dictionary:
	var started := Time.get_ticks_usec()
	var result: Dictionary = commands.dispatch(command)
	print("P3_COMMAND_TIMING_JSON:" + JSON.stringify({
		"operation": command.operation,
		"dispatch_and_persist_usec": Time.get_ticks_usec() - started,
		"persist_usec": state.last_persist_duration_usec if result.get("ok", false) else null,
		"result": result.get("reason", "unknown"),
	}))
	return result


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


func _check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error("ASSERTION FAILED: " + label)
