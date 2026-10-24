extends SceneTree

const Registry := preload("res://scripts/modding/content_definition_registry.gd")
const ObjectWorld := preload("res://scripts/objects/procedural_object_world.gd")
const StateService := preload("res://scripts/objects/procedural_object_state_service.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var arguments := OS.get_cmdline_user_args()
	if arguments.size() != 5 or arguments[0] != "read":
		push_error("OBJECT_STATE_PROBE_ARGUMENTS_INVALID")
		quit(2)
		return
	var world_id := arguments[1]
	var world_seed := int(arguments[2])
	var generator_version := int(arguments[3])
	var state_directory: String = arguments[4]
	var registry: ContentDefinitionRegistry = Registry.new()
	var roots: Array[String] = ["res://mods/first-party", "user://mods"]
	var registered: Dictionary = registry.discover_and_register(roots)
	if not registered.get("ok", false):
		push_error("OBJECT_STATE_PROBE_REGISTRY_FAILED: %s" % registered.get("reason", "unknown"))
		quit(4)
		return
	var region := Vector2i(-2, 3)
	var built: Dictionary = ObjectWorld.build_region_instances(world_seed, world_id, region, registry)
	if not built.get("ok", false):
		push_error("OBJECT_STATE_PROBE_REBUILD_FAILED: %s" % built.get("reason", "unknown"))
		quit(5)
		return
	var service: ProceduralObjectStateService = StateService.new()
	var loaded: Dictionary = service.initialize(world_id, world_seed, generator_version, state_directory)
	if not loaded.get("ok", false) or not loaded.get("found", false) or service.get_revision() != 3:
		push_error("OBJECT_STATE_PROBE_LOAD_FAILED: %s" % loaded.get("reason", "revision_mismatch"))
		quit(6)
		return
	var record: Dictionary = built.instances[0]
	var resolved: Dictionary = service.resolve_instance(record)
	if not resolved.get("ok", false) or resolved.instance.get("instance_components", {}).size() != 3:
		push_error("OBJECT_STATE_PROBE_COMPONENT_MISMATCH")
		quit(7)
		return
	print("OBJECT_STATE_PROCESS_RESTART_PASS revision=%d components=%d id=%s" % [service.get_revision(), resolved.instance.instance_components.size(), record.instance_id])
	quit(0)
