extends Node3D

## Isolated P3.0A demonstration scene. It writes only to a unique harness folder
## under Godot user data and removes that folder when the scene closes.
const Loader := preload("res://scripts/modding/declarative_mod_loader.gd")
const RegistryScript := preload("res://scripts/modding/content_definition_registry.gd")
const StateServiceScript := preload("res://scripts/objects/procedural_object_state_service.gd")
const StateContract := preload("res://scripts/objects/procedural_object_state_contract.gd")
const CommandServiceScript := preload("res://scripts/entities/entity_command_service.gd")
const RockMeshAdapter := preload("res://scripts/objects/procedural_rock_mesh_adapter.gd")
const Field := preload("res://scripts/terrain/sdf_world.gd")
const WORLD_ID := "p3-command-demo"
const WORLD_SEED := 734921

var state_service: ProceduralObjectStateService
var command_service: EntityCommandService
var registry: ContentDefinitionRegistry
var selected_id := ""
var selected_root: Node3D
var _session_uuid := ""
var _storage_root := ""
var _sequence := 0
var _operation_label: Label
var _object_nodes: Dictionary = {}
var _definition_id := ""


func _ready() -> void:
	_session_uuid = _make_uuid()
	_storage_root = OS.get_user_data_dir().path_join("p3-0a-command-demo-" + _session_uuid)
	_build_stage()
	_build_hud()
	var discovered: Dictionary = Loader.discover_and_validate(["res://mods/first-party"])
	if not discovered.get("ok", false):
		_set_status("Package registry failed: %s" % discovered.get("reason", "unknown"))
		return
	registry = RegistryScript.new()
	var registered: Dictionary = registry.register_discovered(discovered)
	if not registered.get("ok", false):
		_set_status("Package registration failed: %s" % registered.get("reason", "unknown"))
		return
	_definition_id = _first_placeable_definition_id()
	if _definition_id.is_empty():
		_set_status("Package registration failed: no placeable definition")
		return
	state_service = StateServiceScript.new()
	var initialized: Dictionary = state_service.initialize(WORLD_ID, WORLD_SEED, Field.GENERATOR_VERSION, _storage_root)
	if not initialized.get("ok", false):
		_set_status("Isolated state failed: %s" % initialized.get("reason", "unknown"))
		return
	var migrated: Dictionary = state_service.upgrade_command_snapshot_schema()
	if not migrated.get("ok", false):
		_set_status("Explicit isolated schema setup failed: %s" % migrated.get("reason", "unknown"))
		return
	command_service = CommandServiceScript.new()
	if not command_service.initialize(state_service, registry).get("ok", false):
		_set_status("Command service initialization failed")
		return
	_set_status("Ready. Focus this window, then use P to place, E to edit, Delete to hide, and R to restore.")


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	var key_event: InputEventKey = event
	if _matches_key(key_event, KEY_P):
		_place_new_entity()
	elif _matches_key(key_event, KEY_E):
		_edit_selected()
	elif _matches_key(key_event, KEY_DELETE):
		_delete_selected()
	elif _matches_key(key_event, KEY_R):
		_restore_selected()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		_remove_tree(_storage_root)


func _build_stage() -> void:
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.42, 0.46, 0.52)
	env.ambient_light_energy = 0.8
	environment.environment = env
	add_child(environment)
	var camera := Camera3D.new()
	camera.current = true
	camera.position = Vector3(7.0, 5.0, 9.0)
	add_child(camera)
	camera.look_at(Vector3(0.0, 1.0, 0.0))
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-48.0, -28.0, 0.0)
	light.light_energy = 1.2
	add_child(light)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(36.0, 28.0)
	floor_mesh.mesh = plane
	floor_mesh.position = Vector3(0.0, -0.03, 0.0)
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.16, 0.19, 0.17)
	floor_material.roughness = 1.0
	floor_mesh.material_override = floor_material
	add_child(floor_mesh)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(18.0, 18.0)
	panel.custom_minimum_size = Vector2(480.0, 126.0)
	layer.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	margin.add_child(column)
	var heading := Label.new()
	heading.text = "P3.0A Transactional Entity Command Harness"
	column.add_child(heading)
	_operation_label = Label.new()
	_operation_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_operation_label.custom_minimum_size = Vector2(620.0, 56.0)
	column.add_child(_operation_label)
	var controls := Label.new()
	controls.text = "Focus window: P place  |  E alter  |  Delete hide  |  R restore"
	column.add_child(controls)


func _first_placeable_definition_id() -> String:
	if registry == null:
		return ""
	for definition_id in registry.get_definition_ids():
		var recipe: Dictionary = registry.evaluate_rock_recipe(definition_id, 1)
		if recipe.get("ok", false) and String(recipe.get("algorithm", "")) == RockMeshAdapter.ALGORITHM:
			return definition_id
	return ""


func _place_new_entity() -> void:
	if command_service == null:
		return
	var position := [(_sequence % 5) * 2500, 0, 0]
	var region := [floori(float(position[0]) / 16000.0), 0]
	var command_id := _next_uuid()
	var command := {
		"schema_version": 1, "command_id": command_id, "operation": "ENTITY_PLACE",
		"origin": {"type": "player", "id": "demo-player"}, "world_id": WORLD_ID,
		"world_seed": WORLD_SEED, "generator_version": Field.GENERATOR_VERSION,
		"expected_world_revision": state_service.get_revision(), "expected_entity_revision": 0,
		"definition_id": _definition_id, "position_mm": position, "region_key": region,
		"recipe_seed": 4000 + _sequence,
		"components": {
			StateContract.COMPONENT_TRANSFORM: _transform([0, 0, 0], [0, 0, 0], [1000, 1000, 1000]),
			StateContract.COMPONENT_APPEARANCE: _appearance("placed content"),
			StateContract.COMPONENT_LOGICAL: _logical({"placed": true}),
		},
	}
	_sequence += 1
	var result: Dictionary = command_service.dispatch(command)
	if not result.get("ok", false):
		_set_status("ENTITY_PLACE rejected: %s" % result.get("reason", "unknown"))
		return
	selected_id = String(result.entity_id)
	if not _apply_authoritative_entity_view(selected_id, "ENTITY_PLACE"):
		return
	_set_status("Placed %s\nworld revision %d / entity revision %d" % [selected_id, result.world_revision, result.entity_revision])


func _edit_selected() -> void:
	if selected_id.is_empty():
		return
	var revision := state_service.get_entity_revision(selected_id)
	var command := _entity_command("ENTITY_SET_COMPONENT", _next_uuid(), revision)
	command["component_id"] = StateContract.COMPONENT_TRANSFORM
	command["component"] = _transform([400, 0, 0], [0, 35000, 0], [1250, 1100, 1250])
	var result: Dictionary = command_service.dispatch(command)
	if not result.get("ok", false):
		_set_status("ENTITY_SET_COMPONENT rejected: %s" % result.get("reason", "unknown"))
		return
	if not _apply_authoritative_entity_view(selected_id, "ENTITY_SET_COMPONENT"):
		return
	_set_status("Altered %s\nworld revision %d / entity revision %d" % [selected_id, result.world_revision, result.entity_revision])


func _delete_selected() -> void:
	if selected_id.is_empty():
		return
	var command := _entity_command("ENTITY_DELETE", _next_uuid(), state_service.get_entity_revision(selected_id))
	var result: Dictionary = command_service.dispatch(command)
	if not result.get("ok", false):
		_set_status("ENTITY_DELETE rejected: %s" % result.get("reason", "unknown"))
		return
	if not _apply_authoritative_entity_view(selected_id, "ENTITY_DELETE"):
		return
	_set_status("Logically deleted %s\nworld revision %d / entity revision %d" % [selected_id, result.world_revision, result.entity_revision])


func _restore_selected() -> void:
	if selected_id.is_empty():
		return
	var command := _entity_command("ENTITY_RESTORE", _next_uuid(), state_service.get_entity_revision(selected_id))
	var result: Dictionary = command_service.dispatch(command)
	if not result.get("ok", false):
		_set_status("ENTITY_RESTORE rejected: %s" % result.get("reason", "unknown"))
		return
	if not _apply_authoritative_entity_view(selected_id, "ENTITY_RESTORE"):
		return
	_set_status("Restored %s\nworld revision %d / entity revision %d" % [selected_id, result.world_revision, result.entity_revision])


func _entity_command(operation: String, command_id: String, entity_revision: int) -> Dictionary:
	return {
		"schema_version": 1, "command_id": command_id, "operation": operation,
		"origin": {"type": "editor", "id": "demo-editor"}, "world_id": WORLD_ID,
		"world_seed": WORLD_SEED, "generator_version": Field.GENERATOR_VERSION,
		"expected_world_revision": state_service.get_revision(), "expected_entity_revision": entity_revision,
		"entity_id": selected_id,
	}


func _apply_authoritative_entity_view(entity_id: String, operation: String) -> bool:
	var resolved: Dictionary = command_service.resolve_entity(entity_id)
	if not resolved.get("ok", false):
		_set_status("%s committed but visual synchronization failed: %s" % [operation, resolved.get("reason", "unknown")])
		return false
	var node: Node3D = _object_nodes.get(entity_id)
	if bool(resolved.get("deleted", false)):
		if node == null:
			_set_status("%s committed but the entity node is missing" % operation)
			return false
		node.visible = false
		return true
	if not _show_entity(resolved.instance):
		_set_status("%s committed but mesh/view synchronization failed" % operation)
		return false
	return true


func _matches_key(event: InputEventKey, expected: int) -> bool:
	return int(event.keycode) == expected or int(event.physical_keycode) == expected


func _show_entity(instance: Dictionary) -> bool:
	var entity_id := String(instance.instance_id)
	var node: Node3D = _object_nodes.get(entity_id)
	if node == null:
		var built: Dictionary = RockMeshAdapter.build_mesh(instance.geometry, instance.geometry_seeds)
		if not built.get("ok", false):
			_set_status("Mesh build failed: %s" % built.get("reason", "unknown"))
			return false
		node = Node3D.new()
		node.name = "ExplicitEntity_%s" % entity_id.sha256_text().substr(0, 10)
		var mesh_node := MeshInstance3D.new()
		mesh_node.mesh = built.mesh
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.28, 0.37, 0.27)
		material.roughness = 0.9
		mesh_node.material_override = material
		node.add_child(mesh_node)
		add_child(node)
		_object_nodes[entity_id] = node
	node.visible = true
	selected_root = node
	var position: Vector3i = instance.position_mm
	node.position = Vector3(position) / 1000.0
	var components: Dictionary = instance.get("instance_components", {})
	var transform: Dictionary = components.get(StateContract.COMPONENT_TRANSFORM, _transform([0, 0, 0], [0, 0, 0], [1000, 1000, 1000]))
	var properties: Dictionary = transform.properties
	var delta: Array = properties.translation_mm
	var rotation: Array = properties.rotation_mdeg
	var scale: Array = properties.scale_milli
	node.position += Vector3(float(delta[0]), float(delta[1]), float(delta[2])) / 1000.0
	node.rotation = Vector3(float(rotation[0]), float(rotation[1]), float(rotation[2])) * PI / 180000.0
	node.scale = Vector3(float(scale[0]), float(scale[1]), float(scale[2])) / 1000.0
	return true


func _transform(translation: Array, rotation: Array, scale: Array) -> Dictionary:
	return {"schema_version": 1, "properties": {"translation_mm": translation, "rotation_mdeg": rotation, "scale_milli": scale}}


func _appearance(label: String) -> Dictionary:
	return {"schema_version": 1, "properties": {"tint_milli": [500, 700, 400], "label": label}}


func _logical(values: Dictionary) -> Dictionary:
	return {"schema_version": 1, "properties": {"values": values}}


func _set_status(value: String) -> void:
	if _operation_label != null:
		_operation_label.text = value


func _next_uuid() -> String:
	return _make_uuid()


func _make_uuid() -> String:
	var hex := Crypto.new().generate_random_bytes(16).hex_encode()
	return "%s-%s-4%s-8%s-%s" % [hex.substr(0, 8), hex.substr(8, 4), hex.substr(13, 3), hex.substr(17, 3), hex.substr(20, 12)]


func _remove_tree(path: String) -> void:
	if path.is_empty() or not DirAccess.dir_exists_absolute(path):
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
