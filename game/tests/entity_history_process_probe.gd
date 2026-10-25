extends SceneTree

const Loader := preload("res://scripts/modding/declarative_mod_loader.gd")
const RegistryScript := preload("res://scripts/modding/content_definition_registry.gd")
const StateServiceScript := preload("res://scripts/objects/procedural_object_state_service.gd")
const CommandServiceScript := preload("res://scripts/entities/entity_command_service.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 11 or args[0] != "read":
		push_error("ENTITY_HISTORY_PROBE_ARGUMENTS_INVALID")
		quit(2)
		return
	var world_id := args[1]
	var world_seed := int(args[2])
	var generator_version := int(args[3])
	var state_directory := args[4]
	var mod_root := args[5]
	var entity_id := args[6]
	var expected_depth := int(args[7])
	var expected_cursor := int(args[8])
	var region_key := Vector2i(int(args[9]), int(args[10]))
	var registry: ContentDefinitionRegistry = RegistryScript.new()
	var discovery: Dictionary = Loader.discover_and_validate(["res://mods/first-party", mod_root])
	if not discovery.get("ok", false) or not registry.register_discovered(discovery).get("ok", false):
		push_error("ENTITY_HISTORY_PROBE_REGISTRY_FAILED")
		quit(3)
		return
	var state: ProceduralObjectStateService = StateServiceScript.new()
	var loaded: Dictionary = state.initialize(world_id, world_seed, generator_version, state_directory)
	if not loaded.get("ok", false) or not loaded.get("found", false) or int(state.snapshot.get("schema_version", 0)) != 3:
		push_error("ENTITY_HISTORY_PROBE_LOAD_FAILED: %s" % loaded.get("reason", "snapshot_missing"))
		quit(4)
		return
	var commands: EntityCommandService = CommandServiceScript.new()
	if not commands.initialize(state, registry).get("ok", false) or not commands.reconstruct_region(region_key).get("ok", false):
		push_error("ENTITY_HISTORY_PROBE_RECONSTRUCTION_FAILED")
		quit(5)
		return
	var summary: Dictionary = commands.get_history_summary()
	var resolved: Dictionary = commands.resolve_entity(entity_id)
	var redo_entry: Dictionary = summary.get("redo", {})
	if int(summary.get("depth", -1)) != expected_depth or int(summary.get("cursor", -1)) != expected_cursor or String(redo_entry.get("operation", "")) != "ENTITY_DELETE" or not resolved.get("ok", false) or bool(resolved.get("deleted", true)) or not state.snapshot.get("overrides", {}).has(entity_id):
		push_error("ENTITY_HISTORY_PROBE_STATE_MISMATCH")
		quit(6)
		return
	print("ENTITY_HISTORY_PROCESS_RESTART_PASS depth=%d cursor=%d revision=%d" % [summary.depth, summary.cursor, state.get_revision()])
	quit(0)
