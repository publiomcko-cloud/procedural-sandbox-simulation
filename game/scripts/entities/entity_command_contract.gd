class_name EntityCommandContract
extends RefCounted

## Strict, renderer-independent P3.0A command wire contract.
const StateContract := preload("res://scripts/objects/procedural_object_state_contract.gd")
const Spatial := preload("res://scripts/terrain/terrain_spatial_ownership.gd")
const VERSION := 1
const OPERATIONS := ["ENTITY_SET_COMPONENT", "ENTITY_DELETE", "ENTITY_RESTORE", "ENTITY_PLACE", "ENTITY_UNDO", "ENTITY_REDO"]
const MAX_WORLD_COORD_MM := 2147483647
const COMMAND_ID_PATTERN := "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"


static func validate(command: Variant, world_id: String, world_seed: int, generator_version: int) -> Dictionary:
	if typeof(command) != TYPE_DICTIONARY:
		return _failure("command_not_dictionary")
	var operation: Variant = command.get("operation", null)
	if typeof(operation) != TYPE_STRING or not OPERATIONS.has(operation):
		return _failure("command_operation_unsupported")
	var common := ["schema_version", "command_id", "operation", "origin", "world_id", "world_seed", "generator_version", "expected_world_revision", "expected_entity_revision"]
	var expected := common.duplicate()
	if operation == "ENTITY_PLACE":
		expected.append_array(["definition_id", "position_mm", "region_key", "recipe_seed", "components"])
	else:
		expected.append("entity_id")
	if operation == "ENTITY_SET_COMPONENT":
		expected.append_array(["component_id", "component"])
	elif operation == "ENTITY_UNDO" or operation == "ENTITY_REDO":
		expected.append("history_entry_id")
	if not _exact_keys(command, expected):
		return _failure("command_fields_invalid")
	if not _is_int(command.schema_version) or int(command.schema_version) != VERSION:
		return _failure("command_schema_unsupported")
	if typeof(command.command_id) != TYPE_STRING or not _matches(String(command.command_id), COMMAND_ID_PATTERN):
		return _failure("command_id_invalid")
	if typeof(command.world_id) != TYPE_STRING or command.world_id != world_id or not _is_int(command.world_seed) or int(command.world_seed) != world_seed or not _is_int(command.generator_version) or int(command.generator_version) != generator_version:
		return _failure("command_world_mismatch")
	if not _is_int(command.expected_world_revision) or int(command.expected_world_revision) < 0 or int(command.expected_world_revision) >= 2147483647:
		return _failure("command_world_revision_invalid")
	if not _is_int(command.expected_entity_revision) or int(command.expected_entity_revision) < 0 or int(command.expected_entity_revision) >= 2147483647:
		return _failure("command_entity_revision_invalid")
	var origin_result := _validate_origin(command.origin)
	if not origin_result.ok:
		return origin_result
	var normalized: Dictionary = command.duplicate(true)
	normalized.schema_version = VERSION
	normalized.world_seed = world_seed
	normalized.generator_version = generator_version
	normalized.expected_world_revision = int(command.expected_world_revision)
	normalized.expected_entity_revision = int(command.expected_entity_revision)
	if operation == "ENTITY_PLACE":
		if int(command.expected_entity_revision) != 0:
			return _failure("place_expected_entity_revision_must_be_zero")
		if typeof(command.definition_id) != TYPE_STRING or String(command.definition_id).find(":") < 1:
			return _failure("place_definition_invalid")
		var position := _int_vector(command.position_mm, -MAX_WORLD_COORD_MM, MAX_WORLD_COORD_MM)
		if not position.ok or not _is_int(command.recipe_seed) or int(command.recipe_seed) < 1 or int(command.recipe_seed) > 2147483647:
			return _failure("place_parameters_invalid")
		var region := _region_key_for_mm(int(position.value[0]), int(position.value[2]))
		if typeof(command.region_key) != TYPE_ARRAY or command.region_key.size() != 2 or not _is_int(command.region_key[0]) or not _is_int(command.region_key[1]) or int(command.region_key[0]) < -2147483648 or int(command.region_key[0]) > 2147483647 or int(command.region_key[1]) < -2147483648 or int(command.region_key[1]) > 2147483647 or Vector2i(int(command.region_key[0]), int(command.region_key[1])) != region:
			return _failure("place_region_ownership_mismatch")
		var components := _normalize_components(command.components)
		if not components.ok:
			return components
		normalized.position_mm = position.value
		normalized.region_key = [region.x, region.y]
		normalized.recipe_seed = int(command.recipe_seed)
		normalized.components = components.value
	else:
		if typeof(command.entity_id) != TYPE_STRING or not StateContract._valid_instance_id(String(command.entity_id), world_id, world_seed):
			return _failure("command_entity_id_invalid")
		normalized.entity_id = String(command.entity_id)
		if operation == "ENTITY_UNDO" or operation == "ENTITY_REDO":
			if typeof(command.history_entry_id) != TYPE_STRING or not _matches(String(command.history_entry_id), COMMAND_ID_PATTERN):
				return _failure("command_history_reference_invalid")
			normalized.history_entry_id = String(command.history_entry_id)
		if operation == "ENTITY_SET_COMPONENT":
			if typeof(command.component_id) != TYPE_STRING:
				return _failure("command_component_id_invalid")
			var component_result := StateContract.normalize_component(String(command.component_id), command.component)
			if not component_result.ok:
				return _failure(String(component_result.get("reason", "command_component_invalid")))
			normalized.component = component_result.value
	return {"ok": true, "command": normalized}


static func _validate_origin(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY or not _exact_keys(value, ["type", "id"]):
		return _failure("command_origin_invalid")
	if typeof(value.type) != TYPE_STRING or not ["player", "editor", "mod"].has(value.type) or typeof(value.id) != TYPE_STRING or String(value.id).is_empty() or String(value.id).length() > 64:
		return _failure("command_origin_invalid")
	var pattern := "^[a-z][a-z0-9_.:-]*$"
	if not _matches(String(value.id), pattern):
		return _failure("command_origin_id_invalid")
	if value.type == "mod" and String(value.id).find(":") >= 0:
		return _failure("command_mod_origin_id_invalid")
	return {"ok": true}


static func _normalize_components(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY or not _exact_keys(value, [StateContract.COMPONENT_TRANSFORM, StateContract.COMPONENT_APPEARANCE, StateContract.COMPONENT_LOGICAL]):
		return _failure("place_components_invalid")
	var result: Dictionary = {}
	for component_id in value:
		var normalized := StateContract.normalize_component(String(component_id), value[component_id])
		if not normalized.ok:
			return _failure("place_component_invalid:%s" % normalized.get("reason", "invalid"))
		result[component_id] = normalized.value
	return {"ok": true, "value": result}


static func _region_key_for_mm(x_mm: int, z_mm: int) -> Vector2i:
	var result: Dictionary = Spatial.world_to_region_local(Vector3(float(x_mm) / 1000.0, 0.0, float(z_mm) / 1000.0))
	return result.region_key


static func _int_vector(value: Variant, minimum: int, maximum: int) -> Dictionary:
	if typeof(value) != TYPE_ARRAY or value.size() != 3:
		return {"ok": false}
	var result: Array[int] = []
	for item in value:
		if not _is_int(item) or int(item) < minimum or int(item) > maximum:
			return {"ok": false}
		result.append(int(item))
	return {"ok": true, "value": result}


static func _is_int(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or (typeof(value) == TYPE_FLOAT and is_finite(value) and floor(value) == value and abs(value) <= 9007199254740991.0)


static func _exact_keys(value: Dictionary, keys: Array) -> bool:
	if value.size() != keys.size():
		return false
	for key in keys:
		if not value.has(key):
			return false
	return true


static func _matches(value: String, pattern: String) -> bool:
	var regex := RegEx.new()
	regex.compile(pattern)
	return regex.search(value) != null


static func _failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
