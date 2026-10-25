class_name ProceduralObjectStateContract
extends RefCounted

## Versioned, data-only component contracts for mutable procedural instances.
## These values are deliberately independent of Node3D, meshes and mod scripts.
const SCHEMA_VERSION := 1
const Spatial := preload("res://scripts/terrain/terrain_spatial_ownership.gd")
const COMPONENT_TRANSFORM := "core.transform"
const COMPONENT_APPEARANCE := "core.appearance"
const COMPONENT_LOGICAL := "core.logical"
const MAX_LOGICAL_FIELDS := 32
const MAX_LABEL_LENGTH := 64
const MAX_WORLD_SEED := 2147483646
const MIN_REGION_COORD := -2147483648
const MAX_REGION_COORD := 2147483647
const COMMAND_SNAPSHOT_SCHEMA_VERSION := 2
const MAX_COMMAND_RECEIPTS := 4096
const HISTORY_SNAPSHOT_SCHEMA_VERSION := 3
const MAX_HISTORY_ENTRIES := 256
const MAX_DOCUMENT_BYTES := 4 * 1024 * 1024


static func normalize_component(component_id: String, value: Variant) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return _failure("component_state_not_dictionary")
	var component: Dictionary = value
	if component.get("schema_version", null) != SCHEMA_VERSION:
		return _failure("component_schema_unsupported")
	var properties_value: Variant = component.get("properties", null)
	if typeof(properties_value) != TYPE_DICTIONARY:
		return _failure("component_properties_invalid")
	var properties: Dictionary = properties_value
	match component_id:
		COMPONENT_TRANSFORM:
			return _normalize_transform(properties)
		COMPONENT_APPEARANCE:
			return _normalize_appearance(properties)
		COMPONENT_LOGICAL:
			return _normalize_logical(properties)
	return _failure("component_id_unsupported")


static func _normalize_transform(properties: Dictionary) -> Dictionary:
	if not _exact_keys(properties, ["translation_mm", "rotation_mdeg", "scale_milli"]):
		return _failure("transform_fields_invalid")
	var translation := _read_int_vector(properties["translation_mm"], -8000, 8000)
	var rotation := _read_int_vector(properties["rotation_mdeg"], -360000, 360000)
	var scale := _read_int_vector(properties["scale_milli"], 100, 5000)
	if not translation.ok or not rotation.ok or not scale.ok:
		return _failure("transform_values_out_of_range")
	return {"ok": true, "value": {"schema_version": SCHEMA_VERSION, "properties": {"translation_mm": translation.value, "rotation_mdeg": rotation.value, "scale_milli": scale.value}}}


static func _normalize_appearance(properties: Dictionary) -> Dictionary:
	if not _exact_keys(properties, ["tint_milli", "label"]):
		return _failure("appearance_fields_invalid")
	var tint_value: Variant = properties["tint_milli"]
	if typeof(tint_value) != TYPE_ARRAY or tint_value.size() != 3:
		return _failure("appearance_tint_invalid")
	var tint: Array[int] = []
	for channel in tint_value:
		var parsed := _read_integer(channel, 0, 1000)
		if not parsed.ok:
			return _failure("appearance_tint_invalid")
		tint.append(parsed.value)
	var label_value: Variant = properties["label"]
	if typeof(label_value) != TYPE_STRING or String(label_value).length() > MAX_LABEL_LENGTH:
		return _failure("appearance_label_invalid")
	return {"ok": true, "value": {"schema_version": SCHEMA_VERSION, "properties": {"tint_milli": tint, "label": String(label_value)}}}


static func _normalize_logical(properties: Dictionary) -> Dictionary:
	if not _exact_keys(properties, ["values"]):
		return _failure("logical_fields_invalid")
	var values_value: Variant = properties["values"]
	if typeof(values_value) != TYPE_DICTIONARY or values_value.size() > MAX_LOGICAL_FIELDS:
		return _failure("logical_values_invalid")
	var normalized: Dictionary = {}
	for key_value in values_value:
		if typeof(key_value) != TYPE_STRING or not _valid_logical_key(String(key_value)):
			return _failure("logical_key_invalid")
		var item: Variant = values_value[key_value]
		match typeof(item):
			TYPE_BOOL:
				normalized[key_value] = item
			TYPE_INT, TYPE_FLOAT:
				if not is_finite(float(item)) or floor(float(item)) != float(item) or abs(float(item)) > 2147483647.0:
					return _failure("logical_integer_out_of_range")
				normalized[key_value] = int(item)
			TYPE_STRING:
				if String(item).length() > MAX_LABEL_LENGTH:
					return _failure("logical_string_too_long")
				normalized[key_value] = item
			_:
				return _failure("logical_value_type_unsupported")
	return {"ok": true, "value": {"schema_version": SCHEMA_VERSION, "properties": {"values": normalized}}}


static func validate_snapshot(snapshot: Variant, expected_world_id: String, expected_seed: int, expected_generator: int) -> Dictionary:
	if typeof(snapshot) != TYPE_DICTIONARY:
		return _failure("snapshot_not_dictionary")
	var version: Variant = snapshot.get("schema_version", null)
	if not _is_int(version):
		return _failure("snapshot_schema_unsupported")
	if int(version) == SCHEMA_VERSION:
		return _validate_snapshot_v1(snapshot, expected_world_id, expected_seed, expected_generator)
	if int(version) == COMMAND_SNAPSHOT_SCHEMA_VERSION:
		return _validate_snapshot_v2(snapshot, expected_world_id, expected_seed, expected_generator)
	if int(version) == HISTORY_SNAPSHOT_SCHEMA_VERSION:
		return _validate_snapshot_v3(snapshot, expected_world_id, expected_seed, expected_generator)
	return _failure("snapshot_schema_unsupported")


static func _validate_snapshot_v2(snapshot: Variant, expected_world_id: String, expected_seed: int, expected_generator: int, allow_history_commands: bool = false) -> Dictionary:
	if not _exact_keys(snapshot, ["schema_version", "world_id", "world_seed", "generator_version", "revision", "overrides", "deleted", "placed_entities", "entity_revisions", "command_receipts"]):
		return _failure("snapshot_fields_invalid")
	if not _is_int(snapshot.get("schema_version")) or int(snapshot.schema_version) != COMMAND_SNAPSHOT_SCHEMA_VERSION:
		return _failure("snapshot_schema_unsupported")
	var legacy_shape: Dictionary = {}
	for key in ["schema_version", "world_id", "world_seed", "generator_version", "revision", "overrides", "deleted"]:
		legacy_shape[key] = snapshot[key]
	legacy_shape.schema_version = SCHEMA_VERSION
	var legacy_checked := _validate_snapshot_v1(legacy_shape, expected_world_id, expected_seed, expected_generator, true)
	if not legacy_checked.get("ok", false):
		return legacy_checked
	if typeof(snapshot.placed_entities) != TYPE_DICTIONARY or snapshot.placed_entities.size() > 20000 or typeof(snapshot.entity_revisions) != TYPE_DICTIONARY or snapshot.entity_revisions.size() > 40000 or typeof(snapshot.command_receipts) != TYPE_DICTIONARY or snapshot.command_receipts.size() > MAX_COMMAND_RECEIPTS:
		return _failure("command_snapshot_bounds_invalid")
	var normalized: Dictionary = legacy_checked.snapshot
	normalized.schema_version = COMMAND_SNAPSHOT_SCHEMA_VERSION
	var placed: Dictionary = {}
	for id_value in snapshot.placed_entities:
		if typeof(id_value) != TYPE_STRING or not _valid_instance_id(String(id_value), expected_world_id, expected_seed) or not _exact_keys(snapshot.placed_entities[id_value], ["identity", "position_mm", "components"]):
			return _failure("placed_entity_record_invalid")
		var record: Dictionary = snapshot.placed_entities[id_value]
		var identity_result := validate_identity(record.identity, expected_world_id, expected_seed, expected_generator)
		if not identity_result.get("ok", false) or int(record.identity.get("identity_schema_version", -1)) != 3 or String(id_value) != String(identity_result.instance_id):
			return _failure("placed_entity_identity_invalid")
		var position := _read_int_vector(record.position_mm, -2147483647, 2147483647)
		if not position.ok:
			return _failure("placed_entity_transform_invalid")
		var region_key_array: Array = identity_result.identity.region_key
		var region_key := Vector2i(int(region_key_array[0]), int(region_key_array[1]))
		if _region_for_mm(int(position.value[0]), int(position.value[2])) != region_key:
			return _failure("placed_entity_region_mismatch")
		if typeof(record.components) != TYPE_DICTIONARY or not _exact_keys(record.components, [COMPONENT_TRANSFORM, COMPONENT_APPEARANCE, COMPONENT_LOGICAL]):
			return _failure("placed_entity_components_invalid")
		var components: Dictionary = {}
		for component_id in record.components:
			var component_result := normalize_component(String(component_id), record.components[component_id])
			if not component_result.get("ok", false):
				return _failure("placed_entity_component_invalid")
			components[component_id] = component_result.value
		placed[id_value] = {"identity": identity_result.identity, "position_mm": position.value, "components": components}
	var entity_revisions: Dictionary = {}
	for id_value in snapshot.entity_revisions:
		if typeof(id_value) != TYPE_STRING or not _valid_instance_id(String(id_value), expected_world_id, expected_seed) or not _is_int(snapshot.entity_revisions[id_value]):
			return _failure("entity_revision_record_invalid")
		var entity_revision := int(snapshot.entity_revisions[id_value])
		if entity_revision < 1 or entity_revision > int(normalized.revision):
			return _failure("entity_revision_record_invalid")
		entity_revisions[id_value] = entity_revision
	for id_value in placed:
		if not entity_revisions.has(id_value):
			return _failure("placed_entity_revision_missing")
	for id_value in normalized.overrides:
		if int(normalized.overrides[id_value].identity.get("identity_schema_version", 1)) == 3 and not placed.has(id_value):
			return _failure("placed_entity_record_missing")
	for id_value in normalized.deleted:
		if int(normalized.deleted[id_value].get("identity_schema_version", 1)) == 3 and not placed.has(id_value):
			return _failure("placed_entity_record_missing")
	var receipts: Dictionary = {}
	for command_id in snapshot.command_receipts:
		if typeof(command_id) != TYPE_STRING or not _valid_command_id(String(command_id)) or not _exact_keys(snapshot.command_receipts[command_id], ["command_sha256", "operation", "entity_id", "world_revision", "entity_revision", "undo_metadata"]):
			return _failure("command_receipt_invalid")
		var receipt: Dictionary = snapshot.command_receipts[command_id]
		var allowed_operations := ["ENTITY_SET_COMPONENT", "ENTITY_DELETE", "ENTITY_RESTORE", "ENTITY_PLACE"]
		if allow_history_commands:
			allowed_operations.append_array(["ENTITY_UNDO", "ENTITY_REDO"])
		if typeof(receipt.command_sha256) != TYPE_STRING or String(receipt.command_sha256).length() != 64 or not _is_hex(String(receipt.command_sha256)) or not allowed_operations.has(receipt.operation) or not _is_int(receipt.world_revision) or int(receipt.world_revision) < 1 or int(receipt.world_revision) > int(normalized.revision) or not _is_int(receipt.entity_revision) or int(receipt.entity_revision) < 1 or int(receipt.entity_revision) > int(receipt.world_revision):
			return _failure("command_receipt_invalid")
		if receipt.operation == "ENTITY_PLACE":
			if typeof(receipt.entity_id) != TYPE_STRING or not placed.has(receipt.entity_id) or String(receipt.entity_id) != _placed_id(expected_world_id, expected_seed, String(command_id)):
				return _failure("command_receipt_entity_invalid")
		elif typeof(receipt.entity_id) != TYPE_STRING or not _valid_instance_id(String(receipt.entity_id), expected_world_id, expected_seed):
			return _failure("command_receipt_entity_invalid")
		var undo_check := _validate_undo_metadata(String(receipt.operation), String(receipt.entity_id), receipt.undo_metadata, expected_world_id, expected_seed, expected_generator)
		if not undo_check.get("ok", false):
			return undo_check
		receipts[command_id] = {"command_sha256": String(receipt.command_sha256), "operation": String(receipt.operation), "entity_id": String(receipt.entity_id), "world_revision": int(receipt.world_revision), "entity_revision": int(receipt.entity_revision), "undo_metadata": undo_check.value}
	normalized.placed_entities = placed
	normalized.entity_revisions = entity_revisions
	normalized.command_receipts = receipts
	return {"ok": true, "snapshot": normalized}


static func _validate_snapshot_v3(snapshot: Dictionary, expected_world_id: String, expected_seed: int, expected_generator: int) -> Dictionary:
	var validation_started_usec := Time.get_ticks_usec()
	if not _exact_keys(snapshot, ["schema_version", "world_id", "world_seed", "generator_version", "revision", "overrides", "deleted", "placed_entities", "entity_revisions", "command_receipts", "entity_history", "history_cursor"]):
		return _failure("history_snapshot_fields_invalid")
	var schema_two: Dictionary = {}
	for key in ["world_id", "world_seed", "generator_version", "revision", "overrides", "deleted", "placed_entities", "entity_revisions", "command_receipts"]:
		schema_two[key] = snapshot[key]
	schema_two["schema_version"] = COMMAND_SNAPSHOT_SCHEMA_VERSION
	var base_validation_started_usec := Time.get_ticks_usec()
	var base_checked := _validate_snapshot_v2(schema_two, expected_world_id, expected_seed, expected_generator, true)
	var base_validation_usec := Time.get_ticks_usec() - base_validation_started_usec
	if not base_checked.get("ok", false):
		return base_checked
	if typeof(snapshot.entity_history) != TYPE_ARRAY or snapshot.entity_history.size() > MAX_HISTORY_ENTRIES or not _is_int(snapshot.history_cursor):
		return _failure("entity_history_bounds_invalid")
	var history: Array = []
	var seen_ids: Dictionary = {}
	var cursor := int(snapshot.history_cursor)
	if cursor < 0 or cursor > snapshot.entity_history.size():
		return _failure("entity_history_cursor_invalid")
	var previous_world_revision := -1
	var history_validation_started_usec := Time.get_ticks_usec()
	for index in range(snapshot.entity_history.size()):
		var entry_result := _validate_history_entry(snapshot.entity_history[index], base_checked.snapshot, expected_world_id, expected_seed, expected_generator, index < cursor, previous_world_revision)
		if not entry_result.get("ok", false):
			return entry_result
		var entry: Dictionary = entry_result.entry
		if seen_ids.has(entry.history_entry_id):
			return _failure("entity_history_duplicate_entry")
		seen_ids[entry.history_entry_id] = true
		previous_world_revision = int(entry.world_revision_after)
		history.append(entry)
	var history_validation_usec := Time.get_ticks_usec() - history_validation_started_usec
	var normalized: Dictionary = base_checked.snapshot
	normalized.schema_version = HISTORY_SNAPSHOT_SCHEMA_VERSION
	normalized.entity_history = history
	normalized.history_cursor = cursor
	var snapshot_bytes := JSON.stringify(normalized, "", true, true).to_utf8_buffer()
	if snapshot_bytes.size() > MAX_DOCUMENT_BYTES:
		return _failure("entity_history_snapshot_too_large")
	return {"ok": true, "snapshot": normalized, "timings_usec": {"base_snapshot_validation_usec": base_validation_usec, "history_validation_usec": history_validation_usec, "history_snapshot_validation_total_usec": Time.get_ticks_usec() - validation_started_usec}}


static func _validate_history_entry(value: Variant, base_snapshot: Dictionary, expected_world_id: String, expected_seed: int, expected_generator: int, should_be_applied: bool, prior_world_revision: int) -> Dictionary:
	var keys := ["schema_version", "history_entry_id", "source_command_id", "original_command", "original_command_sha256", "entity_id", "operation", "world_id", "world_seed", "generator_version", "entity_identity", "world_revision_before", "world_revision_after", "entity_revision_before", "entity_revision_after", "receipt_command_id", "inverse_metadata_sha256", "application_state"]
	if typeof(value) != TYPE_DICTIONARY or not _exact_keys(value, keys):
		return _failure("entity_history_entry_fields_invalid")
	var entry: Dictionary = value
	if not _is_int(entry.schema_version) or int(entry.schema_version) != 1 or typeof(entry.history_entry_id) != TYPE_STRING or not _valid_command_id(String(entry.history_entry_id)) or entry.source_command_id != entry.history_entry_id or entry.receipt_command_id != entry.history_entry_id or typeof(entry.entity_id) != TYPE_STRING or not _valid_instance_id(String(entry.entity_id), expected_world_id, expected_seed):
		return _failure("entity_history_entry_identity_invalid")
	if typeof(entry.operation) != TYPE_STRING or not ["ENTITY_SET_COMPONENT", "ENTITY_DELETE", "ENTITY_RESTORE", "ENTITY_PLACE"].has(entry.operation) or entry.world_id != expected_world_id or not _is_int(entry.world_seed) or int(entry.world_seed) != expected_seed or not _is_int(entry.generator_version) or int(entry.generator_version) != expected_generator:
		return _failure("entity_history_entry_world_invalid")
	if not _is_int(entry.world_revision_before) or not _is_int(entry.world_revision_after) or int(entry.world_revision_after) != int(entry.world_revision_before) + 1 or int(entry.world_revision_after) <= prior_world_revision or int(entry.world_revision_after) > int(base_snapshot.revision):
		return _failure("entity_history_world_revision_invalid")
	if not _is_int(entry.entity_revision_before) or not _is_int(entry.entity_revision_after) or int(entry.entity_revision_after) != int(entry.entity_revision_before) + 1 or int(entry.entity_revision_before) < 0 or int(entry.entity_revision_after) > int(entry.world_revision_after) or (entry.operation == "ENTITY_PLACE" and (int(entry.entity_revision_before) != 0 or int(entry.entity_revision_after) != 1)):
		return _failure("entity_history_entity_revision_invalid")
	var expected_state := "APPLIED" if should_be_applied else "UNDONE"
	if typeof(entry.application_state) != TYPE_STRING or String(entry.application_state) != expected_state:
		return _failure("entity_history_cursor_state_mismatch")
	var identity_result := validate_identity(entry.entity_identity, expected_world_id, expected_seed, expected_generator)
	if not identity_result.get("ok", false) or String(identity_result.instance_id) != String(entry.entity_id):
		return _failure("entity_history_content_identity_invalid")
	var command_check := _validate_history_source_command(entry.original_command, entry, expected_world_id, expected_seed, expected_generator)
	if not command_check.get("ok", false):
		return command_check
	var canonical_command: Dictionary = command_check.command
	var digest := _sha256_canonical(canonical_command)
	if typeof(entry.original_command_sha256) != TYPE_STRING or String(entry.original_command_sha256) != digest:
		return _failure("entity_history_command_digest_mismatch")
	var receipts: Dictionary = base_snapshot.command_receipts
	if not receipts.has(entry.receipt_command_id):
		return _failure("entity_history_receipt_missing")
	var receipt: Dictionary = receipts[entry.receipt_command_id]
	if String(receipt.command_sha256) != digest or String(receipt.operation) != String(entry.operation) or String(receipt.entity_id) != String(entry.entity_id) or int(receipt.world_revision) != int(entry.world_revision_after) or int(receipt.entity_revision) != int(entry.entity_revision_after) or String(entry.inverse_metadata_sha256) != _sha256_canonical(receipt.undo_metadata):
		return _failure("entity_history_receipt_mismatch")
	var normalized_entry: Dictionary = _canonical_json_numbers(entry)
	normalized_entry.entity_identity = identity_result.identity
	normalized_entry.original_command = canonical_command
	return {"ok": true, "entry": normalized_entry}


static func _validate_history_source_command(value: Variant, entry: Dictionary, world_id: String, world_seed: int, generator_version: int) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return _failure("entity_history_command_invalid")
	var command: Dictionary = value
	var operation := String(entry.operation)
	var keys := ["schema_version", "command_id", "operation", "origin", "world_id", "world_seed", "generator_version", "expected_world_revision", "expected_entity_revision"]
	if operation == "ENTITY_PLACE":
		keys.append_array(["definition_id", "position_mm", "region_key", "recipe_seed", "components"])
	else:
		keys.append("entity_id")
	if operation == "ENTITY_SET_COMPONENT":
		keys.append_array(["component_id", "component"])
	if not _exact_keys(command, keys) or not _is_int(command.schema_version) or int(command.schema_version) != 1 or command.command_id != entry.history_entry_id or command.operation != operation or command.world_id != world_id or not _is_int(command.world_seed) or int(command.world_seed) != world_seed or not _is_int(command.generator_version) or int(command.generator_version) != generator_version or not _is_int(command.expected_world_revision) or int(command.expected_world_revision) != int(entry.world_revision_before) or not _is_int(command.expected_entity_revision) or int(command.expected_entity_revision) != int(entry.entity_revision_before):
		return _failure("entity_history_command_invalid")
	if typeof(command.origin) != TYPE_DICTIONARY or not _exact_keys(command.origin, ["type", "id"]) or not ["player", "editor", "mod"].has(command.origin.get("type")) or typeof(command.origin.get("id")) != TYPE_STRING or String(command.origin.id).is_empty() or String(command.origin.id).length() > 64:
		return _failure("entity_history_origin_invalid")
	if operation == "ENTITY_PLACE":
		if typeof(command.definition_id) != TYPE_STRING or String(command.definition_id).find(":") < 1 or not _is_int(command.recipe_seed) or int(command.recipe_seed) < 1 or int(command.recipe_seed) > 2147483647:
			return _failure("entity_history_place_command_invalid")
		var position := _read_int_vector(command.position_mm, -2147483647, 2147483647)
		if not position.get("ok", false) or typeof(command.region_key) != TYPE_ARRAY or command.region_key.size() != 2 or not _is_int(command.region_key[0]) or not _is_int(command.region_key[1]):
			return _failure("entity_history_place_command_invalid")
		if String(entry.entity_id) != _placed_id(world_id, world_seed, String(entry.history_entry_id)):
			return _failure("entity_history_place_identity_invalid")
		if typeof(command.components) != TYPE_DICTIONARY or not _exact_keys(command.components, [COMPONENT_TRANSFORM, COMPONENT_APPEARANCE, COMPONENT_LOGICAL]):
			return _failure("entity_history_place_components_invalid")
		for component_id in command.components:
			if not normalize_component(String(component_id), command.components[component_id]).get("ok", false):
				return _failure("entity_history_place_components_invalid")
	elif operation == "ENTITY_SET_COMPONENT":
		if typeof(command.entity_id) != TYPE_STRING or command.entity_id != entry.entity_id or typeof(command.component_id) != TYPE_STRING or not normalize_component(String(command.component_id), command.component).get("ok", false):
			return _failure("entity_history_set_command_invalid")
	elif typeof(command.entity_id) != TYPE_STRING or command.entity_id != entry.entity_id:
		return _failure("entity_history_command_entity_invalid")
	return {"ok": true, "command": _canonical_json_numbers(command)}


static func _sha256_canonical(value: Variant) -> String:
	return canonical_sha256(value)


static func canonical_sha256(value: Variant) -> String:
	return JSON.stringify(_canonical_json_numbers(value), "", true, true).sha256_text()


static func _canonical_json_numbers(value: Variant) -> Variant:
	# Godot's JSON parser may materialize integer lexical tokens as integral
	# floats. Normalize exact safe integers before hashing so command and
	# receipt identities remain stable across serialize/readback cycles.
	if typeof(value) == TYPE_FLOAT:
		var numeric := float(value)
		if is_finite(numeric) and numeric == floor(numeric) and abs(numeric) <= 9007199254740991.0:
			return int(numeric)
		return numeric
	if typeof(value) == TYPE_ARRAY:
		var normalized_array: Array = []
		for item in value:
			normalized_array.append(_canonical_json_numbers(item))
		return normalized_array
	if typeof(value) == TYPE_DICTIONARY:
		var normalized_dictionary: Dictionary = {}
		for key in value:
			normalized_dictionary[key] = _canonical_json_numbers(value[key])
		return normalized_dictionary
	return value


static func _validate_snapshot_v1(snapshot: Variant, expected_world_id: String, expected_seed: int, expected_generator: int, allow_explicit_identity: bool = false) -> Dictionary:
	if typeof(snapshot) != TYPE_DICTIONARY:
		return _failure("snapshot_not_dictionary")
	if not _valid_world_identity(expected_world_id, expected_seed, expected_generator):
		return _failure("snapshot_expected_world_identity_invalid")
	var value: Dictionary = snapshot
	if not _exact_keys(value, ["schema_version", "world_id", "world_seed", "generator_version", "revision", "overrides", "deleted"]):
		return _failure("snapshot_fields_invalid")
	if not _is_int(value.schema_version) or int(value.schema_version) != SCHEMA_VERSION:
		return _failure("snapshot_schema_unsupported")
	if value.world_id != expected_world_id or not _is_int(value.world_seed) or int(value.world_seed) != expected_seed:
		return _failure("snapshot_world_identity_mismatch")
	if not _is_int(value.generator_version) or int(value.generator_version) != expected_generator:
		return _failure("snapshot_generator_unsupported")
	if not _is_int(value.revision) or int(value.revision) < 0 or int(value.revision) > 2147483647:
		return _failure("snapshot_revision_invalid")
	if typeof(value.overrides) != TYPE_DICTIONARY or value.overrides.size() > 20000 or typeof(value.deleted) != TYPE_DICTIONARY or value.deleted.size() > 20000:
		return _failure("snapshot_state_bounds_invalid")
	var normalized_snapshot: Dictionary = value.duplicate(true)
	normalized_snapshot.schema_version = SCHEMA_VERSION
	normalized_snapshot.world_seed = expected_seed
	normalized_snapshot.generator_version = expected_generator
	normalized_snapshot.revision = int(value.revision)
	var normalized_overrides: Dictionary = {}
	var normalized_deleted: Dictionary = {}
	var deleted_ids: Dictionary = {}
	for id_value in value.deleted:
		if typeof(id_value) != TYPE_STRING or not _valid_instance_id(String(id_value), expected_world_id, expected_seed):
			return _failure("snapshot_deleted_id_invalid")
		var deleted_identity := validate_identity(value.deleted[id_value], expected_world_id, expected_seed, expected_generator)
		if not deleted_identity.ok or deleted_identity.instance_id != id_value or (not allow_explicit_identity and int(deleted_identity.identity.get("identity_schema_version", 1)) == 3):
			return _failure("snapshot_deleted_identity_invalid")
		deleted_ids[id_value] = true
		normalized_deleted[id_value] = deleted_identity.identity
	for id_value in value.overrides:
		if typeof(id_value) != TYPE_STRING or not _valid_instance_id(String(id_value), expected_world_id, expected_seed) or deleted_ids.has(id_value):
			return _failure("snapshot_override_id_invalid")
		var record: Variant = value.overrides[id_value]
		if typeof(record) != TYPE_DICTIONARY or not _exact_keys(record, ["identity", "components"]):
			return _failure("snapshot_override_record_invalid")
		var identity_result := validate_identity(record.identity, expected_world_id, expected_seed, expected_generator)
		if not identity_result.ok or identity_result.instance_id != id_value or (not allow_explicit_identity and int(identity_result.identity.get("identity_schema_version", 1)) == 3):
			return _failure("snapshot_override_identity_invalid")
		if typeof(record.components) != TYPE_DICTIONARY or record.components.is_empty() or record.components.size() > 3:
			return _failure("snapshot_components_invalid")
		var normalized_components: Dictionary = {}
		for component_id in record.components:
			var normalized := normalize_component(String(component_id), record.components[component_id])
			if not normalized.ok:
				return _failure("snapshot_component_invalid")
			normalized_components[component_id] = normalized.value
		normalized_overrides[id_value] = {"identity": identity_result.identity, "components": normalized_components}
	normalized_snapshot.overrides = normalized_overrides
	normalized_snapshot.deleted = normalized_deleted
	return {"ok": true, "snapshot": normalized_snapshot}


static func validate_identity(identity: Variant, expected_world_id: String, expected_seed: int, expected_generator: int) -> Dictionary:
	if not _valid_world_identity(expected_world_id, expected_seed, expected_generator):
		return _failure("identity_expected_world_invalid")
	if typeof(identity) != TYPE_DICTIONARY:
		return _failure("identity_fields_invalid")
	var identity_version := 1
	if identity.has("identity_schema_version"):
		if not _is_int(identity["identity_schema_version"]) or not [2, 3].has(int(identity["identity_schema_version"])):
			return _failure("identity_schema_unsupported")
		identity_version = int(identity["identity_schema_version"])
	var expected_keys := ["instance_id", "definition_id", "content_pin", "world_id", "world_seed", "generator_version", "region_key", "slot", "placement_seed", "recipe_seed"]
	if identity_version == 2:
		expected_keys = ["identity_schema_version", "instance_id", "definition_id", "content_pin", "world_id", "world_seed", "generator_version", "region_key", "population_rule_id", "population_rule_pin", "candidate_index", "placement_seed", "recipe_seed"]
	elif identity_version == 3:
		expected_keys = ["identity_schema_version", "identity_kind", "instance_id", "definition_id", "content_pin", "world_id", "world_seed", "generator_version", "region_key", "placement_seed", "recipe_seed"]
	if not _exact_keys(identity, expected_keys):
		return _failure("identity_fields_invalid")
	if identity.world_id != expected_world_id or not _is_int(identity.world_seed) or int(identity.world_seed) != expected_seed or not _is_int(identity.generator_version) or int(identity.generator_version) != expected_generator:
		return _failure("identity_world_mismatch")
	if typeof(identity.definition_id) != TYPE_STRING or String(identity.definition_id).find(":") < 1:
		return _failure("identity_definition_invalid")
	if typeof(identity.content_pin) != TYPE_DICTIONARY or not _exact_keys(identity.content_pin, ["content_id", "mod_id", "mod_version", "definition_schema_version"]):
		return _failure("identity_content_pin_invalid")
	if identity.content_pin.content_id != identity.definition_id or typeof(identity.content_pin.mod_id) != TYPE_STRING or not String(identity.definition_id).begins_with(String(identity.content_pin.mod_id) + ":") or typeof(identity.content_pin.mod_version) != TYPE_STRING or not _is_int(identity.content_pin.definition_schema_version) or int(identity.content_pin.definition_schema_version) < 1:
		return _failure("identity_content_pin_invalid")
	if typeof(identity.region_key) != TYPE_ARRAY or identity.region_key.size() != 2 or not _is_int(identity.region_key[0]) or not _is_int(identity.region_key[1]) or int(identity.region_key[0]) < MIN_REGION_COORD or int(identity.region_key[0]) > MAX_REGION_COORD or int(identity.region_key[1]) < MIN_REGION_COORD or int(identity.region_key[1]) > MAX_REGION_COORD:
		return _failure("identity_region_invalid")
	var region := Vector2i(int(identity.region_key[0]), int(identity.region_key[1]))
	var expected_id := ""
	if identity_version == 1:
		if not _is_int(identity.slot) or int(identity.slot) < 0 or int(identity.slot) > 15:
			return _failure("identity_recipe_invalid")
		expected_id = "%s/seed-%d/object/%s/region/%d,%d/slot/%d" % [expected_world_id, expected_seed, identity.definition_id, region.x, region.y, int(identity.slot)]
	elif identity_version == 2:
		var rule_pin: Variant = identity.population_rule_pin
		if typeof(identity.population_rule_id) != TYPE_STRING or String(identity.population_rule_id).find(":") < 1 or typeof(rule_pin) != TYPE_DICTIONARY or not _exact_keys(rule_pin, ["rule_id", "mod_id", "mod_version", "rule_schema_version", "algorithm", "rule_sha256"]):
			return _failure("identity_population_rule_invalid")
		var rule_id := String(identity.population_rule_id)
		var colon_index := rule_id.find(":")
		var local_rule_id := rule_id.substr(colon_index + 1)
		var rule_regex := RegEx.new()
		rule_regex.compile("^[a-z][a-z0-9_]*(\\.[a-z][a-z0-9_]*)*$")
		if rule_pin.rule_id != rule_id or rule_pin.mod_id != rule_id.substr(0, colon_index) or not rule_id.begins_with(String(rule_pin.mod_id) + ":") or rule_regex.search(local_rule_id) == null or typeof(rule_pin.mod_version) != TYPE_STRING or not _is_int(rule_pin.rule_schema_version) or int(rule_pin.rule_schema_version) != 1 or typeof(rule_pin.algorithm) != TYPE_STRING or not ["region_grid_density_v1"].has(rule_pin.algorithm) or typeof(rule_pin.rule_sha256) != TYPE_STRING or String(rule_pin.rule_sha256).length() != 64 or not _is_hex(String(rule_pin.rule_sha256)):
			return _failure("identity_population_rule_pin_invalid")
		if not _is_int(identity.candidate_index) or int(identity.candidate_index) < 0 or int(identity.candidate_index) > 255:
			return _failure("identity_recipe_invalid")
		expected_id = "%s/seed-%d/object/%s/region/%d,%d/population/%s/candidate/%d" % [expected_world_id, expected_seed, identity.definition_id, region.x, region.y, rule_id, int(identity.candidate_index)]
	else:
		if identity.identity_kind != "placed_explicit_v1" or not _valid_command_id(String(identity.instance_id).get_slice("/placed/", 1)):
			return _failure("identity_placed_contract_invalid")
		expected_id = _placed_id(expected_world_id, expected_seed, String(identity.instance_id).get_slice("/placed/", 1))
	if not _is_int(identity.placement_seed) or int(identity.placement_seed) < 1 or int(identity.placement_seed) > 2147483647 or not _is_int(identity.recipe_seed) or int(identity.recipe_seed) < 1 or int(identity.recipe_seed) > 2147483647:
		return _failure("identity_recipe_invalid")
	if identity.instance_id != expected_id:
		return _failure("identity_id_mismatch")
	var normalized_identity: Dictionary = identity.duplicate(true)
	normalized_identity.world_seed = expected_seed
	normalized_identity.generator_version = expected_generator
	normalized_identity.region_key = [int(identity.region_key[0]), int(identity.region_key[1])]
	if identity_version == 1:
		normalized_identity.slot = int(identity.slot)
	elif identity_version == 2:
		normalized_identity.identity_schema_version = 2
		normalized_identity.candidate_index = int(identity.candidate_index)
	else:
		normalized_identity.identity_schema_version = 3
	normalized_identity.placement_seed = int(identity.placement_seed)
	normalized_identity.recipe_seed = int(identity.recipe_seed)
	var normalized_pin: Dictionary = identity.content_pin.duplicate(true)
	normalized_pin.definition_schema_version = int(identity.content_pin.definition_schema_version)
	normalized_identity.content_pin = normalized_pin
	if identity_version == 2:
		var normalized_rule_pin: Dictionary = identity.population_rule_pin.duplicate(true)
		normalized_rule_pin.rule_schema_version = int(identity.population_rule_pin.rule_schema_version)
		normalized_identity.population_rule_pin = normalized_rule_pin
	return {"ok": true, "instance_id": expected_id, "identity": normalized_identity}


static func identity_for_instance(instance: Dictionary) -> Dictionary:
	if instance.has("entity_identity"):
		return (instance.entity_identity as Dictionary).duplicate(true)
	var key: Vector2i = instance.region_key
	if not String(instance.get("population_rule_id", "")).is_empty():
		return {"identity_schema_version": 2, "instance_id": instance.instance_id, "definition_id": instance.definition_id, "content_pin": instance.content_pin.duplicate(true), "world_id": instance.world_id, "world_seed": instance.world_seed, "generator_version": instance.generator_version, "region_key": [key.x, key.y], "population_rule_id": instance.population_rule_id, "population_rule_pin": instance.population_rule_pin.duplicate(true), "candidate_index": instance.population_candidate_index, "placement_seed": instance.placement_seed, "recipe_seed": instance.recipe_seed}
	return {"instance_id": instance.instance_id, "definition_id": instance.definition_id, "content_pin": instance.content_pin.duplicate(true), "world_id": instance.world_id, "world_seed": instance.world_seed, "generator_version": instance.generator_version, "region_key": [key.x, key.y], "slot": instance.slot, "placement_seed": instance.placement_seed, "recipe_seed": instance.recipe_seed}


static func identities_equal(first: Dictionary, second: Dictionary) -> bool:
	return canonical_sha256(first) == canonical_sha256(second)


static func _read_int_vector(value: Variant, minimum: int, maximum: int) -> Dictionary:
	if typeof(value) != TYPE_ARRAY or value.size() != 3:
		return {"ok": false}
	var output: Array[int] = []
	for item in value:
		var parsed := _read_integer(item, minimum, maximum)
		if not parsed.ok:
			return {"ok": false}
		output.append(parsed.value)
	return {"ok": true, "value": output}


static func _read_integer(value: Variant, minimum: int, maximum: int) -> Dictionary:
	if not _is_int(value) or int(value) < minimum or int(value) > maximum:
		return {"ok": false}
	return {"ok": true, "value": int(value)}


static func _is_int(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or (typeof(value) == TYPE_FLOAT and is_finite(value) and floor(value) == value and abs(value) <= 9007199254740991.0)


static func _exact_keys(value: Dictionary, keys: Array) -> bool:
	if value.size() != keys.size():
		return false
	for key in keys:
		if not value.has(key):
			return false
	return true


static func _valid_instance_id(value: String, world_id: String, world_seed: int) -> bool:
	if value.length() > 256:
		return false
	var regex := RegEx.new()
	regex.compile("^" + world_id + "/seed-" + str(world_seed) + "/object/[a-z][a-z0-9_.]*:[a-z][a-z0-9_.]*/region/-?[0-9]+,-?[0-9]+/slot/[0-9]+$")
	if regex.search(value) != null:
		return true
	regex.compile("^" + world_id + "/seed-" + str(world_seed) + "/object/[a-z][a-z0-9_.]*:[a-z][a-z0-9_.]*/region/-?[0-9]+,-?[0-9]+/population/[a-z][a-z0-9_.]*:[a-z][a-z0-9_.]*/candidate/[0-9]+$")
	if regex.search(value) != null:
		return true
	regex.compile("^" + world_id + "/seed-" + str(world_seed) + "/placed/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")
	return regex.search(value) != null


static func _valid_command_id(value: String) -> bool:
	var regex := RegEx.new()
	regex.compile("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")
	return regex.search(value) != null


static func _placed_id(world_id: String, world_seed: int, command_id: String) -> String:
	return "%s/seed-%d/placed/%s" % [world_id, world_seed, command_id]


static func _validate_undo_metadata(operation: String, entity_id: String, value: Variant, world_id: String, world_seed: int, generator: int) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return _failure("command_undo_metadata_invalid")
	var metadata: Dictionary = value
	if operation == "ENTITY_UNDO" or operation == "ENTITY_REDO":
		var expected_inverse_operation := "ENTITY_REDO" if operation == "ENTITY_UNDO" else "ENTITY_UNDO"
		if not _exact_keys(metadata, ["inverse_operation", "history_entry_id"]) or metadata.get("inverse_operation") != expected_inverse_operation or typeof(metadata.get("history_entry_id")) != TYPE_STRING or not _valid_command_id(String(metadata.history_entry_id)):
			return _failure("command_undo_metadata_invalid")
		return {"ok": true, "value": {"inverse_operation": expected_inverse_operation, "history_entry_id": String(metadata.history_entry_id)}}
	if operation == "ENTITY_SET_COMPONENT":
		if not _exact_keys(metadata, ["inverse_operation", "component_id", "prior_component_present", "prior_component"]) or metadata.inverse_operation != "ENTITY_SET_COMPONENT" or typeof(metadata.component_id) != TYPE_STRING or typeof(metadata.prior_component_present) != TYPE_BOOL or typeof(metadata.prior_component) != TYPE_DICTIONARY:
			return _failure("command_undo_metadata_invalid")
		if bool(metadata.prior_component_present):
			var prior := normalize_component(String(metadata.component_id), metadata.prior_component)
			if not prior.get("ok", false):
				return _failure("command_undo_metadata_invalid")
			return {"ok": true, "value": {"inverse_operation": "ENTITY_SET_COMPONENT", "component_id": String(metadata.component_id), "prior_component_present": true, "prior_component": prior.value}}
		if not metadata.prior_component.is_empty():
			return _failure("command_undo_metadata_invalid")
		return {"ok": true, "value": {"inverse_operation": "ENTITY_SET_COMPONENT", "component_id": String(metadata.component_id), "prior_component_present": false, "prior_component": {}}}
	var expected_inverse := "ENTITY_DELETE" if operation == "ENTITY_RESTORE" else "ENTITY_RESTORE" if operation == "ENTITY_DELETE" else ""
	if operation == "ENTITY_PLACE":
		if not _exact_keys(metadata, ["inverse_operation", "identity"]) or metadata.inverse_operation != "ENTITY_DELETE":
			return _failure("command_undo_metadata_invalid")
	else:
		var legacy_keys := ["inverse_operation", "identity", "prior_override"]
		var current_restore_keys := ["inverse_operation", "identity", "prior_deleted", "prior_override"]
		var keys_valid := _exact_keys(metadata, legacy_keys)
		if operation == "ENTITY_RESTORE" and _exact_keys(metadata, current_restore_keys):
			keys_valid = typeof(metadata.prior_deleted) == TYPE_BOOL
		if expected_inverse.is_empty() or not keys_valid or metadata.inverse_operation != expected_inverse or typeof(metadata.prior_override) != TYPE_DICTIONARY:
			return _failure("command_undo_metadata_invalid")
	var identity_result := validate_identity(metadata.identity, world_id, world_seed, generator)
	if not identity_result.get("ok", false) or String(identity_result.instance_id) != entity_id:
		return _failure("command_undo_metadata_invalid")
	var normalized: Dictionary = {"inverse_operation": String(metadata.inverse_operation), "identity": identity_result.identity}
	if operation != "ENTITY_PLACE":
		var prior_override := _normalize_undo_override(metadata.prior_override, identity_result.identity)
		if not prior_override.get("ok", false):
			return _failure("command_undo_metadata_invalid")
		normalized.prior_override = prior_override.value
		if operation == "ENTITY_RESTORE" and metadata.has("prior_deleted"):
			normalized.prior_deleted = bool(metadata.prior_deleted)
	return {"ok": true, "value": normalized}


static func _normalize_undo_override(value: Variant, identity: Dictionary) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {"ok": false}
	if value.is_empty():
		return {"ok": true, "value": {}}
	if not _exact_keys(value, ["identity", "components"]) or typeof(value.identity) != TYPE_DICTIONARY or typeof(value.components) != TYPE_DICTIONARY or value.components.is_empty() or value.components.size() > 3:
		return {"ok": false}
	var prior_identity := validate_identity(value.identity, String(identity.world_id), int(identity.world_seed), int(identity.generator_version))
	if not prior_identity.get("ok", false) or not identities_equal(prior_identity.identity, identity):
		return {"ok": false}
	var components: Dictionary = {}
	for component_id in value.components:
		var checked := normalize_component(String(component_id), value.components[component_id])
		if not checked.get("ok", false):
			return {"ok": false}
		components[String(component_id)] = checked.value
	return {"ok": true, "value": {"identity": prior_identity.identity, "components": components}}


static func _region_for_mm(x_mm: int, z_mm: int) -> Vector2i:
	var result: Dictionary = Spatial.world_to_region_local(Vector3(float(x_mm) / 1000.0, 0.0, float(z_mm) / 1000.0))
	return result.region_key


static func _is_hex(value: String) -> bool:
	for character in value:
		if not "0123456789abcdef".contains(character):
			return false
	return true


static func _valid_world_identity(world_id: String, world_seed: int, generator_version: int) -> bool:
	if world_id.is_empty() or world_id.length() > 64 or world_seed < 0 or world_seed > MAX_WORLD_SEED or generator_version < 1 or generator_version > 2147483647:
		return false
	var regex := RegEx.new()
	regex.compile("^[a-z][a-z0-9_-]*$")
	return regex.search(world_id) != null


static func _valid_logical_key(value: String) -> bool:
	if value.is_empty() or value.length() > 48:
		return false
	var regex := RegEx.new()
	regex.compile("^[a-z][a-z0-9_]*$")
	return regex.search(value) != null


static func _failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
