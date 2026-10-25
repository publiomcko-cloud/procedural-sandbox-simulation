extends SceneTree

const Loader := preload("res://scripts/modding/declarative_mod_loader.gd")
const RegistryScript := preload("res://scripts/modding/content_definition_registry.gd")
const StateServiceScript := preload("res://scripts/objects/procedural_object_state_service.gd")
const StateContract := preload("res://scripts/objects/procedural_object_state_contract.gd")
const CommandServiceScript := preload("res://scripts/entities/entity_command_service.gd")
const CommandContract := preload("res://scripts/entities/entity_command_contract.gd")
const ObjectWorld := preload("res://scripts/objects/procedural_object_world.gd")
const Field := preload("res://scripts/terrain/sdf_world.gd")
const WORLD_ID := "p3-history-contract"
const WORLD_SEED := 928374
const DEF_ID := "firstparty.core_rocks:granite"

var assertions := 0
var failures := 0
var root_path := ""
var mod_root_uri := ""
var registry: ContentDefinitionRegistry
var active_state: ProceduralObjectStateService

class CommitThenFailStore extends RefCounted:
	var inner: RefCounted
	func _init(store: RefCounted) -> void:
		inner = store
	func save_snapshot(snapshot: Dictionary) -> Dictionary:
		var committed: Dictionary = inner.save_snapshot(snapshot)
		if committed.get("ok", false):
			return {"ok": false, "reason": "injected_failure_after_durable_rename"}
		return committed

class MemorySnapshotStore extends RefCounted:
	var generation := 0
	func save_snapshot(_snapshot: Dictionary) -> Dictionary:
		generation += 1
		return {"ok": true, "generation": generation}

class FailBeforeStore extends RefCounted:
	func save_snapshot(_snapshot: Dictionary) -> Dictionary:
		return {"ok": false, "reason": "injected_failure_before_write"}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root_path = ProjectSettings.globalize_path("user://p3_0c_entity_history_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(root_path)
	registry = _make_registry()
	_check(registry != null, "first-party declarative definitions register for disposable history tests")
	if registry == null:
		_finish()
		return
	_test_schema_one_and_component_history()
	_test_delete_restore_place_and_restart()
	_test_restore_active_overrides()
	_test_branch_stale_idempotency_and_legacy_paths()
	_test_schema_two_migration_and_old_receipts()
	_test_migration_failures_and_commit_uncertainty()
	_test_history_and_receipt_limits()
	_remove_tree(root_path)
	if not mod_root_uri.is_empty():
		_remove_tree(ProjectSettings.globalize_path(mod_root_uri))
	_finish()


func _test_schema_one_and_component_history() -> void:
	var path := root_path.path_join("schema1")
	var state: ProceduralObjectStateService = StateServiceScript.new()
	active_state = state
	_check(state.initialize(WORLD_ID, WORLD_SEED, Field.GENERATOR_VERSION, path).get("ok", false), "P2 schema-1 object state opens in an isolated directory")
	var before_bytes := DirAccess.get_files_at(path) if DirAccess.dir_exists_absolute(path) else PackedStringArray()
	var preflight: Dictionary = state.preflight_history_snapshot_upgrade()
	_check(preflight.get("ok", false) and int(preflight.source_schema) == 1 and int(preflight.target_schema) == 3 and int(preflight.initial_history_depth) == 0, "schema-1 migration preflight directly prepares schema 3 with an empty history")
	_check(state.snapshot.schema_version == 1 and state.get_revision() == 0 and before_bytes.is_empty(), "preflight has no persistent or in-memory side effects")
	var migrated: Dictionary = state.upgrade_history_snapshot_schema()
	_check(migrated.get("ok", false) and state.snapshot.schema_version == 3 and state.snapshot.history_cursor == 0 and migrated.backup_generation == 0, "explicit first migration commits schema 3 without changing terrain or object schema-1 files")
	var commands: EntityCommandService = CommandServiceScript.new()
	_check(commands.initialize(state, registry).get("ok", false), "history dispatcher initializes only after explicit schema-3 migration")
	var initial_reconstruction: Dictionary = commands.reconstruct_region(Vector2i.ZERO)
	_check(initial_reconstruction.get("ok", false), "canonical origin region reconstructs before commands (%s)" % initial_reconstruction.get("reason", "ok"))
	var baseline := _first_instance(Vector2i.ZERO)
	var entity_id := String(baseline.instance_id)
	var empty_undo := _history_command(commands, "ENTITY_UNDO", _uuid(9001), entity_id)
	_check(commands.dispatch(empty_undo).get("reason") == "entity_undo_history_empty", "Undo with no history fails without revision or receipt")
	var empty_redo := _history_command(commands, "ENTITY_REDO", _uuid(9002), entity_id)
	_check(commands.dispatch(empty_redo).get("reason") == "entity_redo_history_empty", "Redo with no unapplied entry fails without revision or receipt")
	var absent_transform := _transform([250, 0, 0], [0, 0, 12000], [1100, 1000, 900])
	var first_set := _component_command(_uuid(1), entity_id, "core.transform", absent_transform)
	var first_result: Dictionary = commands.dispatch(first_set)
	_check(first_result.get("ok", false) and first_result.history_depth == 1 and first_result.history_cursor == 1, "first component command and history entry commit in one snapshot (%s)" % first_result.get("reason", "unknown"))
	var appearance_a := _appearance("appearance A", [700, 800, 900])
	_check(commands.dispatch(_component_command(_uuid(2), entity_id, "core.appearance", appearance_a)).get("ok", false), "appearance override is accepted after the transform")
	var appearance_b := _appearance("appearance B", [900, 600, 400])
	_check(commands.dispatch(_component_command(_uuid(3), entity_id, "core.appearance", appearance_b)).get("ok", false), "replacing an existing component override appends one linear history entry")
	var undo_b := _history_command(commands, "ENTITY_UNDO", _uuid(4), entity_id)
	var undo_b_result: Dictionary = commands.dispatch(undo_b)
	_check(undo_b_result.get("ok", false) and int(state.snapshot.history_cursor) == 2 and state.snapshot.overrides[entity_id].components["core.appearance"] == appearance_a, "Undo of an override replacement restores the exact prior component (%s)" % undo_b_result.get("reason", "unknown"))
	_check(undo_b_result.get("timings_usec", {}).has("history_validation_usec") and undo_b_result.get("timings_usec", {}).has("persistence_usec"), "Undo exposes separate history-validation and persistence timing fields")
	var valid_before_precondition_probe: Dictionary = state.snapshot.duplicate(true)
	state.snapshot.overrides[entity_id].components["core.appearance"] = _appearance("tampered current", [100, 100, 100])
	var mismatched_redo := _history_command(commands, "ENTITY_REDO", _uuid(5001), entity_id)
	var mismatched_result: Dictionary = commands.dispatch(mismatched_redo)
	_check(mismatched_result.get("reason") == "entity_history_redo_component_precondition_mismatch", "Redo rejects state that no longer matches its recorded prior component without changing the cursor or receipt set")
	state.snapshot = valid_before_precondition_probe
	var redo_b := _history_command(commands, "ENTITY_REDO", _uuid(5), entity_id)
	_check(commands.dispatch(redo_b).get("ok", false) and state.snapshot.overrides[entity_id].components["core.appearance"] == appearance_b, "Redo reapplies the original component payload")
	var undo_b_again := _history_command(commands, "ENTITY_UNDO", _uuid(6), entity_id)
	_check(commands.dispatch(undo_b_again).get("ok", false), "history navigation can reverse the same entry again with a new command ID")
	var undo_a := _history_command(commands, "ENTITY_UNDO", _uuid(7), entity_id)
	var undo_a_result: Dictionary = commands.dispatch(undo_a)
	_check(undo_a_result.get("ok", false) and not state.snapshot.overrides[entity_id].components.has("core.appearance") and state.snapshot.overrides[entity_id].components.has("core.transform"), "Undo of a component created from absence removes only that component")
	var redo_a := _history_command(commands, "ENTITY_REDO", _uuid(8), entity_id)
	_check(commands.dispatch(redo_a).get("ok", false) and state.snapshot.overrides[entity_id].components["core.appearance"] == appearance_a, "Redo restores the component whose prior state was absent")
	var current_history: Dictionary = StateContract.validate_snapshot(state.snapshot, WORLD_ID, WORLD_SEED, Field.GENERATOR_VERSION)
	_check(current_history.get("ok", false), "schema-3 history and receipts satisfy the strict snapshot contract")
	var corrupt := state.snapshot.duplicate(true)
	corrupt.history_cursor = int(corrupt.history_cursor) + 1
	_check(not StateContract.validate_snapshot(corrupt, WORLD_ID, WORLD_SEED, Field.GENERATOR_VERSION).get("ok", false), "history cursor inconsistent with APPLIED/UNDONE flags is rejected")
	var corrupt_receipt := state.snapshot.duplicate(true)
	corrupt_receipt.entity_history[0].inverse_metadata_sha256 = "0".repeat(64)
	_check(not StateContract.validate_snapshot(corrupt_receipt, WORLD_ID, WORLD_SEED, Field.GENERATOR_VERSION).get("ok", false), "history whose inverse metadata hash disagrees with its same-snapshot receipt is rejected")


func _test_delete_restore_place_and_restart() -> void:
	var path := root_path.path_join("delete-place")
	var state: ProceduralObjectStateService = StateServiceScript.new()
	active_state = state
	_check(state.initialize(WORLD_ID, WORLD_SEED + 1, Field.GENERATOR_VERSION, path).get("ok", false), "delete fixture uses a separate world seed and directory")
	_check(state.upgrade_history_snapshot_schema().get("ok", false), "delete fixture explicitly migrates to schema 3")
	var commands: EntityCommandService = CommandServiceScript.new()
	commands.initialize(state, registry)
	commands.reconstruct_region(Vector2i.ZERO)
	var baseline := _first_instance(Vector2i.ZERO, WORLD_SEED + 1)
	var entity_id := String(baseline.instance_id)
	var transform_value := _transform([500, 250, -200], [0, 0, 37000], [1400, 900, 1200])
	var appearance_value := _appearance("pre-delete", [420, 780, 990])
	var logical_value := _logical({"owner_tag": "before-delete", "active": true})
	_check(commands.dispatch(_component_command(_uuid(101), entity_id, "core.transform", transform_value)).get("ok", false), "transform state is committed before deletion")
	_check(commands.dispatch(_component_command(_uuid(102), entity_id, "core.appearance", appearance_value)).get("ok", false), "appearance state is committed before deletion")
	_check(commands.dispatch(_component_command(_uuid(103), entity_id, "core.logical", logical_value)).get("ok", false), "logical component state is committed before deletion")
	var before_delete_override: Dictionary = state.snapshot.overrides[entity_id].duplicate(true)
	var delete_command := _simple_command(_uuid(104), "ENTITY_DELETE", entity_id)
	var delete_result: Dictionary = commands.dispatch(delete_command)
	_check(delete_result.get("ok", false) and state.snapshot.deleted.has(entity_id) and not state.snapshot.overrides.has(entity_id), "ENTITY_DELETE writes the tombstone and removes sparse overrides transactionally")
	var undo_delete := _history_command(commands, "ENTITY_UNDO", _uuid(105), entity_id)
	var undo_delete_result: Dictionary = commands.dispatch(undo_delete)
	_check(undo_delete_result.get("ok", false) and not state.snapshot.deleted.has(entity_id) and state.snapshot.overrides.get(entity_id, {}) == before_delete_override, "Undo Delete removes the tombstone and restores the entire pre-delete override set (%s)" % undo_delete_result.get("reason", "unknown"))
	_check(commands.resolve_entity(entity_id).get("instance", {}).get("instance_components", {}).get("core.logical", {}) == logical_value, "Undo Delete restores logical state as well as transform and appearance")
	var duplicate_undo: Dictionary = commands.dispatch(undo_delete)
	_check(duplicate_undo.get("ok", false) and duplicate_undo.get("duplicate", false) and state.get_revision() == int(undo_delete_result.world_revision), "exact Undo command retry returns its persistent receipt without another cursor move")
	var conflicting_undo := undo_delete.duplicate(true)
	conflicting_undo.history_entry_id = _uuid(9999)
	_check(commands.dispatch(conflicting_undo).get("reason") == "idempotency_key_payload_conflict", "reusing an Undo command ID for a different history entry is rejected")
	var redo_delete := _history_command(commands, "ENTITY_REDO", _uuid(106), entity_id)
	_check(commands.dispatch(redo_delete).get("ok", false) and state.snapshot.deleted.has(entity_id) and not state.snapshot.overrides.has(entity_id), "Redo Delete reapplies only the logical deletion and preserves its inverse receipt")
	var undo_delete_again := _history_command(commands, "ENTITY_UNDO", _uuid(107), entity_id)
	_check(commands.dispatch(undo_delete_again).get("ok", false) and state.snapshot.overrides[entity_id] == before_delete_override, "repeated Redo/Undo Delete cycles restore the same exact component state")
	var redo_delete_again := _history_command(commands, "ENTITY_REDO", _uuid(108), entity_id)
	_check(commands.dispatch(redo_delete_again).get("ok", false), "delete is applied again before testing the distinct Restore operation")
	var restore_command := _simple_command(_uuid(109), "ENTITY_RESTORE", entity_id)
	var restore_result: Dictionary = commands.dispatch(restore_command)
	_check(restore_result.get("ok", false) and not state.snapshot.deleted.has(entity_id) and not state.snapshot.overrides.has(entity_id), "ENTITY_RESTORE remains a baseline restore that discards overrides")
	var undo_restore := _history_command(commands, "ENTITY_UNDO", _uuid(110), entity_id)
	_check(commands.dispatch(undo_restore).get("ok", false) and state.snapshot.deleted.has(entity_id) and not state.snapshot.overrides.has(entity_id), "Undo Restore recreates the exact prior tombstone state rather than the pre-delete object state")
	var redo_restore := _history_command(commands, "ENTITY_REDO", _uuid(111), entity_id)
	_check(commands.dispatch(redo_restore).get("ok", false) and not state.snapshot.deleted.has(entity_id) and not state.snapshot.overrides.has(entity_id), "Redo Restore returns to the procedural baseline with no sparse overrides")
	var undo_restore_again := _history_command(commands, "ENTITY_UNDO", _uuid(112), entity_id)
	_check(commands.dispatch(undo_restore_again).get("ok", false), "Undo Restore can be replayed with a new command ID")
	var undo_delete_after_restore := _history_command(commands, "ENTITY_UNDO", _uuid(113), entity_id)
	_check(commands.dispatch(undo_delete_after_restore).get("ok", false) and state.snapshot.overrides[entity_id] == before_delete_override, "Undo Delete still restores pre-delete state after Undo Restore and Undo Delete sequence")
	commands.release_region(Vector2i.ZERO)
	_check(commands.reconstruct_region(Vector2i.ZERO).get("ok", false) and commands.resolve_entity(entity_id).get("ok", false), "unload/revisit after history navigation reconstructs the same stable entity state")
	var restart_state: ProceduralObjectStateService = StateServiceScript.new()
	_check(restart_state.initialize(WORLD_ID, WORLD_SEED + 1, Field.GENERATOR_VERSION, path).get("ok", false) and restart_state.snapshot.history_cursor == state.snapshot.history_cursor, "reinitialization persists history cursor, receipts and entity state")
	var restart_commands: EntityCommandService = CommandServiceScript.new()
	_check(restart_commands.initialize(restart_state, registry).get("ok", false) and restart_commands.reconstruct_region(Vector2i.ZERO).get("ok", false), "history dispatcher resumes after restart and region reconstruction")
	var process_output: Array = []
	var project_root := ProjectSettings.globalize_path("res://")
	var region_key := Vector2i.ZERO
	var child_args: PackedStringArray = ["--headless", "--path", project_root, "--script", "res://tests/entity_history_process_probe.gd", "--", "read", WORLD_ID, str(WORLD_SEED + 1), str(Field.GENERATOR_VERSION), path, mod_root_uri, entity_id, "5", "3", str(region_key.x), str(region_key.y)]
	var child_exit := OS.execute(OS.get_executable_path(), child_args, process_output, true, false)
	var child_text := "\n".join(PackedStringArray(process_output))
	_check(child_exit == 0 and child_text.contains("ENTITY_HISTORY_PROCESS_RESTART_PASS depth=5 cursor=3"), "separate Godot process reloads schema-3 history, pending Redo and the exact pre-delete entity overrides (%s)" % child_text.strip_edges())
	var redo_after_restart := _history_command(restart_commands, "ENTITY_REDO", _uuid(114), entity_id)
	_check(restart_commands.dispatch(redo_after_restart).get("ok", false), "Redo after restart uses the persisted next history entry")

	var place_state: ProceduralObjectStateService = StateServiceScript.new()
	active_state = place_state
	var place_path := root_path.path_join("place")
	place_state.initialize(WORLD_ID, WORLD_SEED + 2, Field.GENERATOR_VERSION, place_path)
	place_state.upgrade_history_snapshot_schema()
	var place_service: EntityCommandService = CommandServiceScript.new()
	place_service.initialize(place_state, registry)
	place_service.reconstruct_region(Vector2i(-1, -1))
	var place := _place_command(_uuid(201), WORLD_SEED + 2, [-1, 120, -1], [-1, -1])
	var placed_result: Dictionary = place_service.dispatch(place)
	var placed_id := String(placed_result.get("entity_id", ""))
	_check(placed_result.get("ok", false) and not placed_id.is_empty() and place_state.snapshot.placed_entities.has(placed_id), "ENTITY_PLACE stores a stable explicit identity before undo")
	var undo_place := _history_command(place_service, "ENTITY_UNDO", _uuid(202), placed_id)
	var undo_place_result: Dictionary = place_service.dispatch(undo_place)
	_check(undo_place_result.get("ok", false) and place_state.snapshot.deleted.has(placed_id) and place_state.snapshot.placed_entities.has(placed_id), "Undo Place tombstones the explicit entity while reserving its original identity")
	var redo_place := _history_command(place_service, "ENTITY_REDO", _uuid(203), placed_id)
	_check(place_service.dispatch(redo_place).get("ok", false) and not place_state.snapshot.deleted.has(placed_id) and place_state.snapshot.placed_entities.has(placed_id), "Redo Place restores the same command-derived identity without duplication")
	_check(place_state.snapshot.placed_entities.size() == 1 and place_state.get_entity_revision(placed_id) == 3, "place undo/redo preserves one identity and monotonic entity revisions")


func _test_restore_active_overrides() -> void:
	var path := root_path.path_join("active-restore")
	var state: ProceduralObjectStateService = StateServiceScript.new()
	active_state = state
	_check(state.initialize(WORLD_ID, WORLD_SEED + 11, Field.GENERATOR_VERSION, path).get("ok", false), "active Restore fixture uses a separate schema-1 save root")
	_check(state.upgrade_history_snapshot_schema().get("ok", false), "active Restore fixture explicitly migrates to history schema 3")
	var commands: EntityCommandService = CommandServiceScript.new()
	_check(commands.initialize(state, registry).get("ok", false) and commands.reconstruct_region(Vector2i.ZERO).get("ok", false), "active Restore entity is reconstructed before mutation")
	var base := _first_instance(Vector2i.ZERO, WORLD_SEED + 11)
	var entity_id := String(base.instance_id)
	var prior_appearance := _appearance("restore-active", [810, 620, 430])
	_check(commands.dispatch(_component_command(_uuid(801), entity_id, "core.appearance", prior_appearance)).get("ok", false), "active Restore fixture commits a visible sparse override")
	var restored := commands.dispatch(_simple_command(_uuid(802), "ENTITY_RESTORE", entity_id))
	_check(restored.get("ok", false) and not state.snapshot.deleted.has(entity_id) and not state.snapshot.overrides.has(entity_id), "ENTITY_RESTORE clears active overrides and keeps the procedural identity active")
	var undo_restore := commands.dispatch(_history_command(commands, "ENTITY_UNDO", _uuid(803), entity_id))
	_check(undo_restore.get("ok", false) and not state.snapshot.deleted.has(entity_id) and state.snapshot.overrides.get(entity_id, {}).get("components", {}).get("core.appearance", {}) == prior_appearance, "Undo Restore recovers the exact active pre-restore override without creating a tombstone")
	var redo_restore := commands.dispatch(_history_command(commands, "ENTITY_REDO", _uuid(804), entity_id))
	_check(redo_restore.get("ok", false) and not state.snapshot.deleted.has(entity_id) and not state.snapshot.overrides.has(entity_id), "Redo Restore returns the active entity to its procedural baseline")
	_check(not commands.dispatch(_simple_command(_uuid(805), "ENTITY_RESTORE", entity_id)).get("ok", false), "Restore of an already-baseline active entity is rejected without a redundant history entry")


func _test_branch_stale_idempotency_and_legacy_paths() -> void:
	var path := root_path.path_join("branch")
	var state: ProceduralObjectStateService = StateServiceScript.new()
	active_state = state
	state.initialize(WORLD_ID, WORLD_SEED + 3, Field.GENERATOR_VERSION, path)
	state.upgrade_history_snapshot_schema()
	var commands: EntityCommandService = CommandServiceScript.new()
	commands.initialize(state, registry)
	commands.reconstruct_region(Vector2i(-1, -1))
	var first := _first_instance(Vector2i(-1, -1), WORLD_SEED + 3)
	var first_id := String(first.instance_id)
	var other := _first_instance(Vector2i.ZERO, WORLD_SEED + 3)
	commands.reconstruct_region(Vector2i.ZERO)
	var second_id := String(other.instance_id)
	_check(commands.dispatch(_component_command(_uuid(301), first_id, "core.appearance", _appearance("branch A", [600, 700, 800]))).get("ok", false), "negative-region command becomes first history entry")
	var undo := _history_command(commands, "ENTITY_UNDO", _uuid(302), first_id)
	_check(commands.dispatch(undo).get("ok", false), "history entry can be undone before a new branch command")
	var summary := commands.get_history_summary()
	_check(summary.redo.get("entity_id", "") == first_id, "linear cursor exposes exactly one redo candidate")
	var branch_command := _component_command(_uuid(303), second_id, "core.logical", _logical({"branch": true}))
	_check(commands.dispatch(branch_command).get("ok", false), "a new accepted command after Undo creates a new linear branch")
	_check(commands.get_history_summary().redo.is_empty() and state.snapshot.entity_history.size() == 1, "new forward command invalidates and removes the undone Redo branch")
	var stale_world := _history_command(commands, "ENTITY_UNDO", _uuid(304), second_id)
	stale_world.expected_world_revision = state.get_revision() - 1
	var before_reject: Dictionary = state.snapshot.duplicate(true)
	_check(commands.dispatch(stale_world).get("reason") == "stale_world_revision" and state.snapshot == before_reject, "stale global revision is rejected before cursor, receipt, or entity effects")
	var stale_entity := _history_command(commands, "ENTITY_UNDO", _uuid(305), second_id)
	stale_entity.expected_entity_revision = state.get_entity_revision(second_id) - 1
	_check(commands.dispatch(stale_entity).get("reason") == "stale_entity_revision" and state.snapshot == before_reject, "stale entity revision is independently rejected")
	var wrong_target := _history_command(commands, "ENTITY_UNDO", _uuid(306), second_id)
	wrong_target.history_entry_id = _uuid(301)
	_check(commands.dispatch(wrong_target).get("reason") == "entity_history_operation_out_of_order" and state.snapshot == before_reject, "out-of-order or wrong-entity history references fail closed")
	var bad_world := _history_command(commands, "ENTITY_UNDO", _uuid(307), second_id)
	bad_world.world_seed = WORLD_SEED
	_check(CommandContract.validate(bad_world, WORLD_ID, WORLD_SEED + 3, Field.GENERATOR_VERSION).get("reason") == "command_world_mismatch", "history command with another seed/world identity is rejected by the wire contract")
	var legacy_mutation := state.set_component(commands._base_instances[second_id], "core.appearance", _appearance("bypass", [500, 500, 500]))
	_check(legacy_mutation.get("reason") == "schema3_mutation_requires_entity_command_dispatcher" and state.snapshot == before_reject, "legacy direct state-service mutation paths cannot bypass schema-3 history")
	_check(state.delete_instance(commands._base_instances[second_id]).get("reason") == "schema3_mutation_requires_entity_command_dispatcher" and state.restore_instance(commands._base_instances[second_id]).get("reason") == "schema3_mutation_requires_entity_command_dispatcher" and state.snapshot == before_reject, "legacy delete and restore writers are also blocked after history migration")
	var undo_current := _history_command(commands, "ENTITY_UNDO", _uuid(308), second_id)
	var before_pin_failure: Dictionary = state.snapshot.duplicate(true)
	var old_registry := commands.registry
	commands.registry = RegistryScript.new()
	var unavailable_pin := commands.dispatch(undo_current)
	_check(not unavailable_pin.get("ok", false) and state.snapshot == before_pin_failure, "undo fails closed if the history entry's required definition pin is unavailable")
	commands.registry = old_registry
	var undo_good := _history_command(commands, "ENTITY_UNDO", _uuid(309), second_id)
	_check(commands.dispatch(undo_good).get("ok", false), "restoring the required registry allows the unchanged history operation")
	var exact_retry: Dictionary = commands.dispatch(undo_good)
	_check(exact_retry.get("ok", false) and exact_retry.get("duplicate", false), "Undo receipt replay remains idempotent after a subsequent cursor move")
	var conflict := undo_good.duplicate(true)
	conflict.expected_world_revision = state.get_revision()
	_check(commands.dispatch(conflict).get("reason") == "idempotency_key_payload_conflict", "same Undo command ID with different expected revision/payload is rejected")
	var negative_forward := _component_command(_uuid(310), first_id, "core.appearance", _appearance("negative undo", [400, 700, 900]))
	_check(commands.dispatch(negative_forward).get("ok", false), "a fresh operation on a negative-coordinate entity creates a new history entry")
	var negative_undo := _history_command(commands, "ENTITY_UNDO", _uuid(311), first_id)
	_check(commands.dispatch(negative_undo).get("ok", false) and commands.get_entity_region(first_id).region_key == Vector2i(-1, -1), "undo works for a canonical negative-coordinate region")


func _test_schema_two_migration_and_old_receipts() -> void:
	var path := root_path.path_join("schema2")
	var state: ProceduralObjectStateService = StateServiceScript.new()
	active_state = state
	state.initialize(WORLD_ID, WORLD_SEED + 4, Field.GENERATOR_VERSION, path)
	_check(state.upgrade_command_snapshot_schema().get("ok", false), "schema-2 migration precondition uses the P3.0A compatibility upgrader")
	var commands: EntityCommandService = CommandServiceScript.new()
	commands.initialize(state, registry)
	commands.reconstruct_region(Vector2i.ZERO)
	var base := _first_instance(Vector2i.ZERO, WORLD_SEED + 4)
	var entity_id := String(base.instance_id)
	var old_command := _component_command(_uuid(401), entity_id, "core.appearance", _appearance("schema2", [600, 600, 900]))
	var old_result: Dictionary = commands.dispatch(old_command)
	_check(old_result.get("ok", false) and state.snapshot.schema_version == 2, "a P3.0A command is persisted in schema 2 before history migration")
	var undo_before_migration := _history_command(commands, "ENTITY_UNDO", _uuid(402), entity_id)
	_check(commands.dispatch(undo_before_migration).get("reason") == "entity_history_schema_migration_required" and state.get_revision() == int(old_result.world_revision), "Undo is fail-closed until explicit schema-3 history migration")
	var old_receipts: Dictionary = state.snapshot.command_receipts.duplicate(true)
	var preflight := state.preflight_history_snapshot_upgrade()
	_check(preflight.get("ok", false) and preflight.source_schema == 2 and preflight.preserved_receipt_count == old_receipts.size(), "schema-2 preflight accounts for and preserves every legacy command receipt")
	var migration := state.upgrade_history_snapshot_schema()
	_check(migration.get("ok", false) and state.snapshot.schema_version == 3 and state.snapshot.command_receipts == old_receipts and state.snapshot.entity_history.is_empty(), "schema-2 migration retains receipts verbatim and starts a non-retroactive empty history")
	var migrated_commands: EntityCommandService = CommandServiceScript.new()
	migrated_commands.initialize(state, registry)
	migrated_commands.reconstruct_region(Vector2i.ZERO)
	var replay := migrated_commands.dispatch(old_command)
	_check(replay.get("ok", false) and replay.get("duplicate", false) and state.snapshot.entity_history.is_empty(), "pre-migration operation remains idempotent but is not represented as undoable history")
	_check(migrated_commands.dispatch(_history_command(migrated_commands, "ENTITY_UNDO", _uuid(403), entity_id)).get("reason") == "entity_undo_history_empty", "legacy operations do not acquire invented reverse state during migration")


func _test_migration_failures_and_commit_uncertainty() -> void:
	var bad_path := root_path.path_join("bad-migration")
	var bad_state: ProceduralObjectStateService = StateServiceScript.new()
	bad_state.initialize(WORLD_ID, WORLD_SEED + 5, Field.GENERATOR_VERSION, bad_path)
	bad_state.snapshot["unexpected"] = true
	var bad_preflight := bad_state.preflight_history_snapshot_upgrade()
	_check(not bad_preflight.get("ok", false) and bad_state.get_revision() == 0 and bad_state.snapshot.schema_version == 1, "invalid source snapshot fails migration preflight without writing or normalization")
	var incompatible := bad_state.snapshot.duplicate(true)
	incompatible.schema_version = 99
	_check(StateContract.validate_snapshot(incompatible, WORLD_ID, WORLD_SEED + 5, Field.GENERATOR_VERSION).get("reason") == "snapshot_schema_unsupported", "unsupported source schemas fail closed")
	var migration_path := root_path.path_join("interrupted-migration")
	var migration_state: ProceduralObjectStateService = StateServiceScript.new()
	migration_state.initialize(WORLD_ID, WORLD_SEED + 10, Field.GENERATOR_VERSION, migration_path)
	var schema2_migration: Dictionary = migration_state.upgrade_command_snapshot_schema()
	var schema2_before: Dictionary = migration_state.snapshot.duplicate(true)
	var generation_before := migration_state.storage_generation
	_check(schema2_migration.get("ok", false) and migration_state.preflight_history_snapshot_upgrade().get("ok", false), "interrupted-migration fixture has a committed schema-2 source and passing no-write preflight")
	migration_state.store = FailBeforeStore.new()
	var interrupted_migration: Dictionary = migration_state.upgrade_history_snapshot_schema()
	_check(not interrupted_migration.get("ok", false) and not migration_state.initialized and migration_state.snapshot == schema2_before, "schema-3 migration write interruption fails closed without publishing an in-memory candidate")
	var migration_recovery: ProceduralObjectStateService = StateServiceScript.new()
	var migration_readback: Dictionary = migration_recovery.initialize(WORLD_ID, WORLD_SEED + 10, Field.GENERATOR_VERSION, migration_path)
	_check(migration_readback.get("ok", false) and migration_recovery.snapshot.schema_version == 2 and migration_recovery.storage_generation == generation_before, "failed migration leaves the prior committed schema-2 generation available for explicit recovery")

	var path := root_path.path_join("uncertain")
	var state: ProceduralObjectStateService = StateServiceScript.new()
	active_state = state
	state.initialize(WORLD_ID, WORLD_SEED + 6, Field.GENERATOR_VERSION, path)
	state.upgrade_history_snapshot_schema()
	var commands: EntityCommandService = CommandServiceScript.new()
	commands.initialize(state, registry)
	commands.reconstruct_region(Vector2i.ZERO)
	var base := _first_instance(Vector2i.ZERO, WORLD_SEED + 6)
	var entity_id := String(base.instance_id)
	var forward := _component_command(_uuid(601), entity_id, "core.appearance", _appearance("durable-before-uncertainty", [650, 650, 650]))
	_check(commands.dispatch(forward).get("ok", false), "uncertainty fixture commits a source command before injecting the later failure")
	var undo := _history_command(commands, "ENTITY_UNDO", _uuid(602), entity_id)
	var durable_before: Dictionary = state.snapshot.duplicate(true)
	state.store = CommitThenFailStore.new(state.store)
	var uncertain: Dictionary = commands.dispatch(undo)
	_check(not uncertain.get("ok", false) and uncertain.get("reason", "").begins_with("command_commit_uncertain:") and not state.initialized, "failure after durable generation rename is classified as uncertain and poisons the service")
	_check(state.snapshot == durable_before, "uncertain commit does not publish candidate state or move the in-memory cursor before readback/reinitialization")
	var reconciled: ProceduralObjectStateService = StateServiceScript.new()
	var readback: Dictionary = reconciled.initialize(WORLD_ID, WORLD_SEED + 6, Field.GENERATOR_VERSION, path)
	_check(readback.get("ok", false) and reconciled.get_revision() == durable_before.revision + 1 and reconciled.snapshot.history_cursor == 0, "reinitialization resolves commit uncertainty by reading the committed Undo receipt and cursor")
	var resumed: EntityCommandService = CommandServiceScript.new()
	_check(resumed.initialize(reconciled, registry).get("ok", false) and resumed.reconstruct_region(Vector2i.ZERO).get("ok", false), "reconciled history is usable only after service reconstruction")
	var retry: Dictionary = resumed.dispatch(undo)
	_check(retry.get("ok", false) and retry.get("duplicate", false) and reconciled.snapshot.history_cursor == 0, "retry after uncertain durable commit returns the exact receipt without applying Undo twice")

	var fail_path := root_path.path_join("prewrite-failure")
	var fail_state: ProceduralObjectStateService = StateServiceScript.new()
	active_state = fail_state
	fail_state.initialize(WORLD_ID, WORLD_SEED + 7, Field.GENERATOR_VERSION, fail_path)
	fail_state.upgrade_history_snapshot_schema()
	var fail_commands: EntityCommandService = CommandServiceScript.new()
	fail_commands.initialize(fail_state, registry)
	fail_commands.reconstruct_region(Vector2i.ZERO)
	var fail_base := _first_instance(Vector2i.ZERO, WORLD_SEED + 7)
	var fail_entity_id := String(fail_base.instance_id)
	_check(fail_commands.dispatch(_component_command(_uuid(701), fail_entity_id, "core.appearance", _appearance("fail path", [700, 700, 700]))).get("ok", false), "prewrite-failure fixture creates one reversible history entry")
	var fail_undo := _history_command(fail_commands, "ENTITY_UNDO", _uuid(702), fail_entity_id)
	var before_failure: Dictionary = fail_state.snapshot.duplicate(true)
	_remove_tree(fail_path)
	_write_text(fail_path, "blocked")
	var failed_commit: Dictionary = fail_commands.dispatch(fail_undo)
	_check(not failed_commit.get("ok", false) and fail_state.snapshot == before_failure and not fail_state.initialized, "prewrite persistence failure leaves the cursor and entity unchanged and forces reload before retry")


func _test_history_and_receipt_limits() -> void:
	var path := root_path.path_join("history-cap")
	var state: ProceduralObjectStateService = StateServiceScript.new()
	active_state = state
	state.initialize(WORLD_ID, WORLD_SEED + 8, Field.GENERATOR_VERSION, path)
	state.upgrade_history_snapshot_schema()
	var commands: EntityCommandService = CommandServiceScript.new()
	commands.initialize(state, registry)
	commands.reconstruct_region(Vector2i.ZERO)
	# Start from a strictly valid full snapshot so the cap transition is exercised
	# once without hundreds of quadratic history validations and disk generations.
	state.store = MemorySnapshotStore.new()
	var base := _first_instance(Vector2i.ZERO, WORLD_SEED + 8)
	var entity_id := String(base.instance_id)
	var identity: Dictionary = StateContract.identity_for_instance(base)
	var history_snapshot: Dictionary = state.snapshot.duplicate(true)
	var history_entries: Array = []
	var history_receipts: Dictionary = {}
	for index in range(StateContract.MAX_HISTORY_ENTRIES):
		var command_id := _uuid(10000 + index)
		var command := {"schema_version": 1, "command_id": command_id, "operation": "ENTITY_SET_COMPONENT", "origin": {"type": "player", "id": "player.history-test"}, "world_id": WORLD_ID, "world_seed": WORLD_SEED + 8, "generator_version": Field.GENERATOR_VERSION, "expected_world_revision": index, "expected_entity_revision": index, "entity_id": entity_id, "component_id": "core.appearance", "component": _appearance("cap-%d" % index, [index % 1001, 500, 500])}
		var undo_metadata := {"inverse_operation": "ENTITY_SET_COMPONENT", "component_id": "core.appearance", "prior_component_present": false, "prior_component": {}}
		var digest := StateContract.canonical_sha256(command)
		var entry := {"schema_version": 1, "history_entry_id": command_id, "source_command_id": command_id, "original_command": command, "original_command_sha256": digest, "entity_id": entity_id, "operation": "ENTITY_SET_COMPONENT", "world_id": WORLD_ID, "world_seed": WORLD_SEED + 8, "generator_version": Field.GENERATOR_VERSION, "entity_identity": identity, "world_revision_before": index, "world_revision_after": index + 1, "entity_revision_before": index, "entity_revision_after": index + 1, "receipt_command_id": command_id, "inverse_metadata_sha256": StateContract.canonical_sha256(undo_metadata), "application_state": "APPLIED"}
		history_entries.append(entry)
		history_receipts[command_id] = {"command_sha256": digest, "operation": "ENTITY_SET_COMPONENT", "entity_id": entity_id, "world_revision": index + 1, "entity_revision": index + 1, "undo_metadata": undo_metadata}
	history_snapshot.revision = StateContract.MAX_HISTORY_ENTRIES
	history_snapshot.entity_revisions[entity_id] = StateContract.MAX_HISTORY_ENTRIES
	history_snapshot.command_receipts = history_receipts
	history_snapshot.entity_history = history_entries
	history_snapshot.history_cursor = StateContract.MAX_HISTORY_ENTRIES
	history_snapshot.overrides[entity_id] = {"identity": identity, "components": {"core.appearance": _appearance("cap-final", [900, 500, 500])}}
	var full_history_check: Dictionary = StateContract.validate_snapshot(history_snapshot, WORLD_ID, WORLD_SEED + 8, Field.GENERATOR_VERSION)
	_check(full_history_check.get("ok", false), "synthetic full-capacity history snapshot satisfies every schema-3 entry, receipt and cursor invariant (%s)" % full_history_check.get("reason", "ok"))
	state.snapshot = full_history_check.snapshot
	var cap_append: Dictionary = commands.dispatch(_component_command(_uuid(10256), entity_id, "core.logical", _logical({"capacity": true})))
	_check(cap_append.get("ok", false), "forward edit at history capacity boundary commits (%s)" % cap_append.get("reason", "unknown"))
	_check(state.snapshot.entity_history.size() == StateContract.MAX_HISTORY_ENTRIES and state.snapshot.history_cursor == StateContract.MAX_HISTORY_ENTRIES and state.snapshot.command_receipts.size() == StateContract.MAX_HISTORY_ENTRIES + 1, "history cap prunes exactly the oldest applied entry while retaining every idempotency receipt")
	var retained_oldest_id := String(state.snapshot.entity_history[0].history_entry_id)
	var undo_retained := _history_command(commands, "ENTITY_UNDO", _uuid(20000), entity_id)
	_check(commands.dispatch(undo_retained).get("ok", false) and state.snapshot.history_cursor == StateContract.MAX_HISTORY_ENTRIES - 1, "history remains navigable at capacity with the newest retained entry")
	_check(retained_oldest_id == _uuid(10001) and state.snapshot.command_receipts.has(_uuid(10000)), "cap evicts only the oldest undo entry while preserving its idempotency receipt")

	var cap_path := root_path.path_join("receipt-cap")
	var cap_state: ProceduralObjectStateService = StateServiceScript.new()
	active_state = cap_state
	cap_state.initialize(WORLD_ID, WORLD_SEED + 9, Field.GENERATOR_VERSION, cap_path)
	cap_state.upgrade_history_snapshot_schema()
	var cap_commands: EntityCommandService = CommandServiceScript.new()
	cap_commands.initialize(cap_state, registry)
	cap_commands.reconstruct_region(Vector2i.ZERO)
	var cap_base := _first_instance(Vector2i.ZERO, WORLD_SEED + 9)
	var cap_id := String(cap_base.instance_id)
	var synthetic_receipts: Dictionary = {}
	for index in range(StateContract.MAX_COMMAND_RECEIPTS):
		var receipt_id := _uuid(30000 + index)
		synthetic_receipts[receipt_id] = {"command_sha256": "a".repeat(64), "operation": "ENTITY_SET_COMPONENT", "entity_id": cap_id, "world_revision": 1, "entity_revision": 1, "undo_metadata": {"inverse_operation": "ENTITY_SET_COMPONENT", "component_id": "core.appearance", "prior_component_present": false, "prior_component": {}}}
	cap_state.snapshot.revision = 1
	cap_state.snapshot.entity_revisions[cap_id] = 1
	cap_state.snapshot.command_receipts = synthetic_receipts
	_check(StateContract.validate_snapshot(cap_state.snapshot, WORLD_ID, WORLD_SEED + 9, Field.GENERATOR_VERSION).get("ok", false), "full receipt-capacity synthetic snapshot remains contract-valid without changing historic receipt policy")
	var cap_command := _component_command(_uuid(50000), cap_id, "core.logical", _logical({"new": true}))
	var cap_before: Dictionary = cap_state.snapshot.duplicate(true)
	var cap_forward_result: Dictionary = cap_commands.dispatch(cap_command)
	var cap_undo_result: Dictionary = cap_commands.dispatch(_history_command(cap_commands, "ENTITY_UNDO", _uuid(50001), cap_id))
	_check(cap_forward_result.get("reason") == "command_receipt_capacity_reached" and cap_undo_result.get("reason") == "command_receipt_capacity_reached" and cap_state.snapshot == cap_before, "full receipt capacity rejects forward and history-navigation commands without pruning prior receipts")


func _make_registry() -> ContentDefinitionRegistry:
	mod_root_uri = "user://mods/p3_0c_history_%d" % Time.get_ticks_usec()
	var external_root := ProjectSettings.globalize_path(mod_root_uri.path_join("procedural-rock"))
	var mkdir_result := DirAccess.make_dir_recursive_absolute(external_root.path_join("objects"))
	if mkdir_result != OK and mkdir_result != ERR_ALREADY_EXISTS:
		_check(false, "external declarative package fixture creates under disposable history root")
		return null
	DirAccess.make_dir_recursive_absolute(external_root.path_join("populations"))
	var source_root := ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir().path_join("mods/examples/procedural-rock")
	for relative_path in ["manifest.json", "objects/procedural_rock.json", "populations/basalt_legacy.json", "populations/basalt_population.json"]:
		var bytes: PackedByteArray = FileAccess.get_file_as_bytes(source_root.path_join(relative_path))
		if bytes.is_empty() or not _write_bytes(external_root.path_join(relative_path), bytes):
			_check(false, "external package fixture copies repository declarative input: %s" % relative_path)
			return null
	var discovery: Dictionary = Loader.discover_and_validate(["res://mods/first-party", mod_root_uri])
	if not discovery.get("ok", false):
		_check(false, "first-party package discovery succeeds (%s)" % discovery.get("reason", "unknown"))
		return null
	var value: ContentDefinitionRegistry = RegistryScript.new()
	var registered: Dictionary = value.register_discovered(discovery)
	if not registered.get("ok", false):
		_check(false, "first-party registry registration succeeds (%s)" % registered.get("reason", "unknown"))
		return null
	return value


func _first_instance(region: Vector2i, seed_value: int = WORLD_SEED) -> Dictionary:
	var generated: Dictionary = ObjectWorld.build_region_instances(seed_value, WORLD_ID, region, registry)
	if not generated.get("ok", false) or generated.get("instances", []).is_empty():
		_check(false, "test region has a deterministic procedural instance")
		return {}
	return generated.instances[0]


func _component_command(command_id: String, entity_id: String, component_id: String, value: Dictionary) -> Dictionary:
	var base := _base_command(command_id, "ENTITY_SET_COMPONENT", entity_id)
	base["component_id"] = component_id
	base["component"] = value
	return base


func _simple_command(command_id: String, operation: String, entity_id: String) -> Dictionary:
	return _base_command(command_id, operation, entity_id)


func _history_command(commands: EntityCommandService, operation: String, command_id: String, entity_id: String) -> Dictionary:
	var summary: Dictionary = commands.get_history_summary()
	var entry: Dictionary = summary.get("undo" if operation == "ENTITY_UNDO" else "redo", {})
	return {"schema_version": 1, "command_id": command_id, "operation": operation, "origin": {"type": "player", "id": "player.history-test"}, "world_id": WORLD_ID, "world_seed": int(commands.state_service.world_seed), "generator_version": int(commands.state_service.generator_version), "expected_world_revision": commands.state_service.get_revision(), "expected_entity_revision": commands.state_service.get_entity_revision(entity_id), "entity_id": entity_id, "history_entry_id": String(entry.get("history_entry_id", _uuid(999999)))}


func _base_command(command_id: String, operation: String, entity_id: String) -> Dictionary:
	var world_seed := int(active_state.world_seed) if active_state != null else WORLD_SEED
	var world_revision := active_state.get_revision() if active_state != null else 0
	var entity_revision := active_state.get_entity_revision(entity_id) if active_state != null else 0
	return {"schema_version": 1, "command_id": command_id, "operation": operation, "origin": {"type": "player", "id": "player.history-test"}, "world_id": WORLD_ID, "world_seed": world_seed, "generator_version": Field.GENERATOR_VERSION, "expected_world_revision": world_revision, "expected_entity_revision": entity_revision, "entity_id": entity_id}


func _place_command(command_id: String, seed_value: int, position: Array, region: Array) -> Dictionary:
	return {"schema_version": 1, "command_id": command_id, "operation": "ENTITY_PLACE", "origin": {"type": "player", "id": "player.history-test"}, "world_id": WORLD_ID, "world_seed": seed_value, "generator_version": Field.GENERATOR_VERSION, "expected_world_revision": 0, "expected_entity_revision": 0, "definition_id": DEF_ID, "position_mm": position, "region_key": region, "recipe_seed": 4567, "components": {"core.transform": _transform([0, 0, 0], [0, 0, 0], [1000, 1000, 1000]), "core.appearance": _appearance("placed", [1000, 1000, 1000]), "core.logical": _logical({})}}


func _transform(translation: Array, rotation: Array, scale: Array) -> Dictionary:
	return {"schema_version": 1, "properties": {"translation_mm": translation, "rotation_mdeg": rotation, "scale_milli": scale}}


func _appearance(label: String, tint: Array) -> Dictionary:
	return {"schema_version": 1, "properties": {"tint_milli": tint, "label": label}}


func _logical(values: Dictionary) -> Dictionary:
	return {"schema_version": 1, "properties": {"values": values}}


func _uuid(value: int) -> String:
	return "00000000-0000-4000-8000-%012d" % value


func _write_text(path: String, value: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(value)
		file.close()


func _write_bytes(path: String, value: PackedByteArray) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_buffer(value)
	file.close()
	return FileAccess.get_file_as_bytes(path) == value


func _remove_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	var directory := DirAccess.open(path)
	if directory == null:
		return
	directory.list_dir_begin()
	while true:
		var child := directory.get_next()
		if child.is_empty():
			break
		var child_path := path.path_join(child)
		if directory.current_is_dir():
			_remove_tree(child_path)
		else:
			DirAccess.remove_absolute(child_path)
	directory.list_dir_end()
	DirAccess.remove_absolute(path)


func _check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error("ASSERTION FAILED: " + label)
	else:
		print("ASSERTION PASS: " + label)


func _finish() -> void:
	if failures == 0:
		print("ENTITY_HISTORY_PASS: assertions=%d failures=0" % assertions)
	else:
		push_error("ENTITY_HISTORY_FAIL: assertions=%d failures=%d" % [assertions, failures])
	quit(0 if failures == 0 else 1)
