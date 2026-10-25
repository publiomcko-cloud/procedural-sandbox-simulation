class_name EntityCommandService
extends RefCounted

## P3.0A deterministic command dispatcher. It mutates only the existing P2.0B
## state service snapshot and never references a scene node or renderer API.
const Contract := preload("res://scripts/entities/entity_command_contract.gd")
const StateContract := preload("res://scripts/objects/procedural_object_state_contract.gd")
const ObjectWorld := preload("res://scripts/objects/procedural_object_world.gd")
const RockMeshAdapter := preload("res://scripts/objects/procedural_rock_mesh_adapter.gd")
const MAX_COMMAND_RECEIPTS := StateContract.MAX_COMMAND_RECEIPTS

var state_service: ProceduralObjectStateService
var registry: ContentDefinitionRegistry
var initialized := false
var initialization_error := ""
var _base_instances: Dictionary = {}


func initialize(authoritative_state_service: ProceduralObjectStateService, content_registry: ContentDefinitionRegistry) -> Dictionary:
	initialized = false
	_base_instances.clear()
	state_service = authoritative_state_service
	registry = content_registry
	if state_service == null or registry == null or not bool(state_service.get("initialized")):
		initialization_error = "command_dependencies_uninitialized"
		return _failure(initialization_error)
	if int(state_service.snapshot.get("schema_version", 0)) != StateContract.COMMAND_SNAPSHOT_SCHEMA_VERSION:
		initialization_error = "command_snapshot_migration_required"
		return _failure(initialization_error)
	initialized = true
	initialization_error = ""
	return {"ok": true, "reason": "ok", "world_revision": state_service.get_revision(), "entity_snapshot_schema": StateContract.COMMAND_SNAPSHOT_SCHEMA_VERSION}


## Reconstructs one canonical region without creating Godot nodes. Regions are
## explicit command preconditions: absent/unloaded content cannot be mutated.
func reconstruct_region(region_key: Vector2i) -> Dictionary:
	if not initialized:
		return _failure("command_service_not_initialized")
	if not _valid_region(region_key):
		return _failure("command_region_invalid")
	for existing_id in _base_instances.keys():
		var existing: Dictionary = _base_instances[existing_id]
		if Vector2i(existing.region_key) == region_key:
			_base_instances.erase(existing_id)
	var generated: Dictionary = ObjectWorld.build_region_instances(state_service.world_seed, state_service.world_id, region_key, registry)
	if not generated.get("ok", false):
		return _failure(String(generated.get("reason", "command_region_generation_failed")))
	var count := 0
	for base_instance in generated.get("instances", []):
		var registered := _register_reconstructed_instance(base_instance)
		if not registered.get("ok", false):
			return registered
		count += 1
	var placed: Dictionary = state_service.snapshot.get("placed_entities", {})
	for entity_id in placed:
		var record: Dictionary = placed[entity_id]
		var stored_region: Array = record.identity.region_key
		if Vector2i(int(stored_region[0]), int(stored_region[1])) != region_key:
			continue
		var base_instance_result := _build_placed_instance(String(entity_id), record)
		if not base_instance_result.get("ok", false):
			return base_instance_result
		var registered := _register_reconstructed_instance(base_instance_result.instance)
		if not registered.get("ok", false):
			return registered
		count += 1
	return {"ok": true, "region_key": region_key, "entity_count": count}


func release_region(region_key: Vector2i) -> void:
	for entity_id in _base_instances.keys():
		if Vector2i(_base_instances[entity_id].region_key) == region_key:
			_base_instances.erase(entity_id)


func resolve_entity(entity_id: String) -> Dictionary:
	if not initialized:
		return _failure("command_service_not_initialized")
	if not _base_instances.has(entity_id):
		return _failure("entity_not_reconstructed_or_content_missing")
	return state_service.resolve_instance(_base_instances[entity_id])


func dispatch(raw_command: Variant) -> Dictionary:
	if not initialized:
		return _failure("command_service_not_initialized")
	var checked := Contract.validate(raw_command, state_service.world_id, state_service.world_seed, state_service.generator_version)
	if not checked.get("ok", false):
		return checked
	var command: Dictionary = checked.command
	var command_id := String(command.command_id)
	var command_digest := JSON.stringify(command, "", true, true).sha256_text()
	var receipts: Dictionary = state_service.snapshot.get("command_receipts", {})
	if receipts.has(command_id):
		var prior: Dictionary = receipts[command_id]
		if String(prior.command_sha256) != command_digest:
			return _failure("idempotency_key_payload_conflict")
		return {"ok": true, "reason": "duplicate_command_replayed", "duplicate": true, "operation": prior.operation, "entity_id": prior.entity_id, "world_revision": int(prior.world_revision), "entity_revision": int(prior.entity_revision)}
	var origin_result := _validate_origin_registration(command.origin)
	if not origin_result.ok:
		return origin_result
	if int(state_service.snapshot.get("revision", -1)) != int(command.expected_world_revision):
		return _failure("stale_world_revision")
	if receipts.size() >= MAX_COMMAND_RECEIPTS:
		return _failure("command_receipt_capacity_reached")
	var candidate: Dictionary = state_service.snapshot.duplicate(true)
	var operation := String(command.operation)
	var entity_id := ""
	var identity: Dictionary = {}
	var entity_revision := 1
	var prepared: Dictionary = {}
	var undo_metadata: Dictionary = {}
	match operation:
		"ENTITY_PLACE":
			prepared = _prepare_placement(command)
			if not prepared.get("ok", false):
				return prepared
			entity_id = String(prepared.entity_id)
			identity = prepared.identity
			if candidate.placed_entities.has(entity_id) or candidate.overrides.has(entity_id) or candidate.deleted.has(entity_id):
				return _failure("placed_entity_id_collision")
			candidate.placed_entities[entity_id] = prepared.record
			undo_metadata = {"inverse_operation": "ENTITY_DELETE", "identity": identity.duplicate(true)}
			entity_revision = 1
		"ENTITY_SET_COMPONENT", "ENTITY_DELETE", "ENTITY_RESTORE":
			entity_id = String(command.entity_id)
			if not _base_instances.has(entity_id):
				return _failure("entity_not_reconstructed_or_content_missing")
			var base_instance: Dictionary = _base_instances[entity_id]
			identity = StateContract.identity_for_instance(base_instance)
			var identity_check := StateContract.validate_identity(identity, state_service.world_id, state_service.world_seed, state_service.generator_version)
			if not identity_check.get("ok", false):
				return _failure(String(identity_check.get("reason", "entity_identity_invalid")))
			identity = identity_check.identity
			var pin_check := _validate_identity_pin(identity)
			if not pin_check.ok:
				return pin_check
			entity_revision = state_service.get_entity_revision(entity_id)
			if entity_revision != int(command.expected_entity_revision):
				return _failure("stale_entity_revision")
			var deleted: Dictionary = candidate.deleted
			var overrides: Dictionary = candidate.overrides
			if operation == "ENTITY_SET_COMPONENT":
				if deleted.has(entity_id):
					return _failure("deleted_entity_requires_restore")
				var override_record: Dictionary = overrides.get(entity_id, {"identity": identity, "components": {}})
				if not StateContract.identities_equal(override_record.identity, identity):
					return _failure("entity_content_pin_mismatch")
				var prior_components: Dictionary = override_record.components
				undo_metadata = {
					"inverse_operation": "ENTITY_SET_COMPONENT",
					"component_id": String(command.component_id),
					"prior_component_present": prior_components.has(String(command.component_id)),
					"prior_component": prior_components.get(String(command.component_id), {}).duplicate(true) if prior_components.has(String(command.component_id)) else {},
				}
				override_record.components[String(command.component_id)] = command.component.duplicate(true)
				overrides[entity_id] = override_record
				candidate.overrides = overrides
			elif operation == "ENTITY_DELETE":
				if deleted.has(entity_id):
					return _failure("entity_already_deleted")
				undo_metadata = {"inverse_operation": "ENTITY_RESTORE", "identity": identity.duplicate(true), "prior_override": overrides.get(entity_id, {}).duplicate(true)}
				deleted[entity_id] = identity
				overrides.erase(entity_id)
				candidate.deleted = deleted
				candidate.overrides = overrides
			else:
				if not deleted.has(entity_id) or not StateContract.identities_equal(deleted[entity_id], identity):
					return _failure("entity_not_deleted_or_identity_mismatch")
				undo_metadata = {"inverse_operation": "ENTITY_DELETE", "identity": identity.duplicate(true), "prior_override": overrides.get(entity_id, {}).duplicate(true)}
				deleted.erase(entity_id)
				overrides.erase(entity_id)
				candidate.deleted = deleted
				candidate.overrides = overrides
			entity_revision += 1
		_:
			return _failure("command_operation_unsupported")
	candidate.entity_revisions[entity_id] = entity_revision
	var next_world_revision := int(state_service.get_revision()) + 1
	var receipt := {"command_sha256": command_digest, "operation": operation, "entity_id": entity_id, "world_revision": next_world_revision, "entity_revision": entity_revision, "undo_metadata": undo_metadata}
	candidate.command_receipts[command_id] = receipt
	var commit := state_service.commit_command_candidate(candidate, int(command.expected_world_revision))
	if not commit.get("ok", false):
		if not state_service.initialized:
			initialized = false
		initialization_error = String(commit.get("reason", "command_commit_failed"))
		return commit
	if operation == "ENTITY_PLACE":
		_base_instances[entity_id] = prepared.instance
	return {"ok": true, "reason": "committed", "duplicate": false, "operation": operation, "entity_id": entity_id, "world_revision": int(commit.world_revision), "entity_revision": entity_revision, "generation": int(commit.generation)}


func _register_reconstructed_instance(base_instance: Dictionary) -> Dictionary:
	var identity := StateContract.identity_for_instance(base_instance)
	var pin_check := _validate_identity_pin(identity)
	if not pin_check.get("ok", false):
		return pin_check
	var resolved: Dictionary = state_service.resolve_instance(base_instance)
	if not resolved.get("ok", false):
		return _failure(String(resolved.get("reason", "entity_reconstruction_failed")))
	var id := String(identity.instance_id)
	_base_instances[id] = base_instance.duplicate(true)
	return {"ok": true, "entity_id": id, "deleted": bool(resolved.get("deleted", false))}


func _prepare_placement(command: Dictionary) -> Dictionary:
	if not registry.has_method("get_definition") or not registry.has_method("pin_definitions"):
		return _failure("content_registry_unavailable")
	var definition_id := String(command.definition_id)
	var definition: Dictionary = registry.get_definition(definition_id)
	if definition.is_empty():
		return _failure("place_definition_missing")
	var ids: Array[String] = [definition_id]
	var pins_result: Dictionary = registry.pin_definitions(ids)
	if not pins_result.get("ok", false) or pins_result.get("pins", []).size() != 1:
		return _failure("place_definition_pin_unavailable")
	var content_pin: Dictionary = pins_result.pins[0]
	var recipe_result: Dictionary = registry.evaluate_rock_recipe(definition_id, int(command.recipe_seed))
	if not recipe_result.get("ok", false) or String(recipe_result.get("algorithm", "")) != RockMeshAdapter.ALGORITHM or typeof(recipe_result.get("geometry")) != TYPE_DICTIONARY:
		return _failure("place_definition_recipe_unsupported")
	var region := Vector2i(int(command.region_key[0]), int(command.region_key[1]))
	var command_id := String(command.command_id)
	var entity_id := StateContract._placed_id(state_service.world_id, state_service.world_seed, command_id)
	var seed_source := "%s|%s|%d|%s|%s" % [state_service.world_id, state_service.world_seed, state_service.generator_version, entity_id, JSON.stringify(content_pin, "", true, true)]
	var placement_seed := int(seed_source.sha256_text().substr(0, 8).hex_to_int() % 2147483646) + 1
	var identity := {"identity_schema_version": 3, "identity_kind": "placed_explicit_v1", "instance_id": entity_id, "definition_id": definition_id, "content_pin": content_pin, "world_id": state_service.world_id, "world_seed": state_service.world_seed, "generator_version": state_service.generator_version, "region_key": [region.x, region.y], "placement_seed": placement_seed, "recipe_seed": int(command.recipe_seed)}
	var identity_check := StateContract.validate_identity(identity, state_service.world_id, state_service.world_seed, state_service.generator_version)
	if not identity_check.get("ok", false):
		return _failure(String(identity_check.get("reason", "place_identity_invalid")))
	var record := {"identity": identity_check.identity, "position_mm": command.position_mm.duplicate(), "components": command.components.duplicate(true)}
	var base_instance := _build_placed_instance(entity_id, record)
	if not base_instance.get("ok", false):
		return base_instance
	return {"ok": true, "entity_id": entity_id, "identity": identity_check.identity, "record": record, "instance": base_instance.instance}


func _build_placed_instance(entity_id: String, record: Dictionary) -> Dictionary:
	var identity: Dictionary = record.identity
	var pin_check := _validate_identity_pin(identity)
	if not pin_check.get("ok", false):
		return pin_check
	var recipe: Dictionary = registry.evaluate_rock_recipe(String(identity.definition_id), int(identity.recipe_seed))
	if not recipe.get("ok", false) or String(recipe.get("algorithm", "")) != RockMeshAdapter.ALGORITHM:
		return _failure("placed_entity_recipe_unavailable")
	return {"ok": true, "instance": {
		"instance_id": entity_id, "entity_identity": identity.duplicate(true), "definition_id": identity.definition_id,
		"content_pin": identity.content_pin.duplicate(true), "world_id": identity.world_id, "world_seed": identity.world_seed,
		"generator_version": identity.generator_version, "region_key": Vector2i(int(identity.region_key[0]), int(identity.region_key[1])),
		"placement_seed": identity.placement_seed, "recipe_seed": identity.recipe_seed, "recipe_algorithm": recipe.algorithm,
		"geometry_profile": recipe.get("profile", ""), "geometry": recipe.geometry.duplicate(true),
		"geometry_seeds": recipe.geometry_seeds.duplicate(true), "instance_state": {}, "component_contract_version": 1,
		"components": ["core.transform@1", "core.appearance@1", "core.logical@1"],
		"position_mm": Vector3i(int(record.position_mm[0]), int(record.position_mm[1]), int(record.position_mm[2])),
		"default_scale_milli": Vector3i(1000, 1000, 1000), "default_yaw_mdeg": 0, "population_rule_id": "",
		"population_rule_pin": {}, "population_rule_schema_version": 0, "population_candidate_index": -1,
		"population_algorithm": "explicit_place_v1", "population_batched": false,
		"base_components": record.components.duplicate(true),
	}}


func prepared_instance_from_record(entity_id: String, record: Dictionary) -> Dictionary:
	var result := _build_placed_instance(entity_id, record)
	return result.get("instance", {}) if result.get("ok", false) else {}


func _validate_identity_pin(identity: Dictionary) -> Dictionary:
	var definition_id := String(identity.get("definition_id", ""))
	if definition_id.is_empty():
		return _failure("entity_definition_missing")
	if registry == null or not registry.has_method("validate_content_pins"):
		return _failure("content_registry_unavailable")
	var pin: Dictionary = identity.get("content_pin", {})
	var pin_list: Array[Dictionary] = [pin]
	var checked: Dictionary = registry.validate_content_pins(pin_list)
	if not checked.get("ok", false):
		return _failure("entity_content_pin_unavailable")
	var ids: Array[String] = [definition_id]
	var current_pin: Dictionary = registry.pin_definitions(ids)
	if not current_pin.get("ok", false) or current_pin.pins.size() != 1 or not _content_pins_equal(current_pin.pins[0], pin):
		return _failure("entity_content_pin_mismatch")
	return {"ok": true}


func _content_pins_equal(first: Dictionary, second: Dictionary) -> bool:
	# JSON integer tokens may be parsed as integral floats by Godot. Compare the
	# schema field semantically after both pins have passed strict validation.
	return String(first.get("content_id", "")) == String(second.get("content_id", "")) \
		and String(first.get("mod_id", "")) == String(second.get("mod_id", "")) \
		and String(first.get("mod_version", "")) == String(second.get("mod_version", "")) \
		and int(first.get("definition_schema_version", -1)) == int(second.get("definition_schema_version", -2))


func _validate_origin_registration(origin: Dictionary) -> Dictionary:
	if String(origin.type) == "mod" and (registry == null or not registry.has_method("has_mod") or not registry.has_mod(String(origin.id))):
		return _failure("command_origin_mod_missing")
	return {"ok": true}


func _valid_region(region_key: Vector2i) -> bool:
	return region_key.x >= -2147483648 and region_key.x <= 2147483647 and region_key.y >= -2147483648 and region_key.y <= 2147483647


func _failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
