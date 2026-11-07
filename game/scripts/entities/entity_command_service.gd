class_name EntityCommandService
extends RefCounted

## P3.0A deterministic command dispatcher. It mutates only the existing P2.0B
## state service snapshot and never references a scene node or renderer API.
const Contract := preload("res://scripts/entities/entity_command_contract.gd")
const StateContract := preload("res://scripts/objects/procedural_object_state_contract.gd")
const ObjectWorld := preload("res://scripts/objects/procedural_object_world.gd")
const RockMeshAdapter := preload("res://scripts/objects/procedural_rock_mesh_adapter.gd")
const Spatial := preload("res://scripts/terrain/terrain_spatial_ownership.gd")
const MAX_COMMAND_RECEIPTS := StateContract.MAX_COMMAND_RECEIPTS
const MAX_HISTORY_ENTRIES := StateContract.MAX_HISTORY_ENTRIES
const HISTORY_SCHEMA_VERSION := StateContract.HISTORY_SNAPSHOT_SCHEMA_VERSION

var state_service: ProceduralObjectStateService
var registry: ContentDefinitionRegistry
var initialized := false
var initialization_error := ""
var _base_instances: Dictionary = {}
var last_reconstruction_usec := 0
var last_dispatch_metrics: Dictionary = {}


func initialize(authoritative_state_service: ProceduralObjectStateService, content_registry: ContentDefinitionRegistry) -> Dictionary:
	initialized = false
	_base_instances.clear()
	state_service = authoritative_state_service
	registry = content_registry
	if state_service == null or registry == null or not bool(state_service.get("initialized")):
		initialization_error = "command_dependencies_uninitialized"
		return _failure(initialization_error)
	if not [StateContract.COMMAND_SNAPSHOT_SCHEMA_VERSION, HISTORY_SCHEMA_VERSION].has(int(state_service.snapshot.get("schema_version", 0))):
		initialization_error = "command_snapshot_migration_required"
		return _failure(initialization_error)
	initialized = true
	initialization_error = ""
	return {"ok": true, "reason": "ok", "world_revision": state_service.get_revision(), "entity_snapshot_schema": int(state_service.snapshot.get("schema_version", 0))}


## Reconstructs one canonical region without creating Godot nodes. Regions are
## explicit command preconditions: absent/unloaded content cannot be mutated.
func reconstruct_region(region_key: Vector2i) -> Dictionary:
	if not initialized:
		return _failure("command_service_not_initialized")
	if not _valid_region(region_key):
		return _failure("command_region_invalid")
	var generated: Dictionary = ObjectWorld.build_region_instances(
		state_service.world_seed, state_service.world_id, region_key, registry
	)
	if not generated.get("ok", false):
		return _failure(String(generated.get("reason", "command_region_generation_failed")))
	return reconstruct_region_from_generated(region_key, generated)


## Completes reconstruction from an immutable procedural-generation result.
## This split lets the expensive terrain/surface scan run on a worker while
## authoritative state registration remains serialized on the main thread.
func reconstruct_region_from_generated(region_key: Vector2i, generated: Dictionary) -> Dictionary:
	var reconstruction_started_usec := Time.get_ticks_usec()
	if not initialized:
		return _failure("command_service_not_initialized")
	if not _valid_region(region_key):
		return _failure("command_region_invalid")
	if not generated.get("ok", false) or Vector2i(generated.get("region_key", region_key)) != region_key:
		return _failure(String(generated.get("reason", "command_region_generation_invalid")))
	for existing_id in _base_instances.keys().duplicate():
		var existing: Dictionary = _base_instances[existing_id]
		if Vector2i(existing.region_key) == region_key:
			_base_instances.erase(existing_id)
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
	var main_thread_usec := Time.get_ticks_usec() - reconstruction_started_usec
	var generation_usec := int(generated.get("timings_usec", {}).get("total", 0))
	last_reconstruction_usec = generation_usec + main_thread_usec
	return {
		"ok": true,
		"region_key": region_key,
		"entity_count": count,
		"candidate_cell_count": int(generated.get("candidate_cell_count", 0)),
		"surface_anchor_count": int(generated.get("surface_anchor_count", 0)),
		"generation_usec": generation_usec,
		"main_thread_reconstruction_usec": main_thread_usec,
		"reconstruction_usec": last_reconstruction_usec,
	}


func release_region(region_key: Vector2i) -> void:
	for entity_id in _base_instances.keys().duplicate():
		if Vector2i(_base_instances[entity_id].region_key) == region_key:
			_base_instances.erase(entity_id)


## Builds the authoritative base list for a derived projection without
## registering the region as command-resident. Procedural generation may be
## completed on a worker before this method is called; placed records are
## reconstructed here against the current registry/pins.
func build_projection_region_base_instances(
	region_key: Vector2i,
	generated: Dictionary
) -> Dictionary:
	if not initialized:
		return _failure("command_service_not_initialized")
	if not _valid_region(region_key):
		return _failure("command_region_invalid")
	if not generated.get("ok", false) 		or Vector2i(generated.get("region_key", region_key)) != region_key:
		return _failure(String(
			generated.get("reason", "command_region_generation_invalid")
		))
	var by_id: Dictionary = {}
	for base_value in generated.get("instances", []):
		if typeof(base_value) != TYPE_DICTIONARY:
			return _failure("command_region_generated_instance_invalid")
		var base: Dictionary = base_value
		var instance_id := String(base.get("instance_id", ""))
		if instance_id.is_empty() or by_id.has(instance_id):
			return _failure("command_region_generated_identity_invalid")
		by_id[instance_id] = base.duplicate(true)

	var placed: Dictionary = state_service.snapshot.get("placed_entities", {})
	for entity_id_value in placed:
		var entity_id := String(entity_id_value)
		var record: Dictionary = placed[entity_id]
		var identity: Dictionary = record.get("identity", {})
		var stored_region: Array = identity.get("region_key", [])
		if stored_region.size() != 2:
			return _failure("placed_entity_identity_invalid")
		if Vector2i(int(stored_region[0]), int(stored_region[1])) != region_key:
			continue
		var built := _build_placed_instance(entity_id, record)
		if not built.get("ok", false):
			return built
		if by_id.has(entity_id):
			return _failure("placed_entity_id_collision")
		by_id[entity_id] = (built["instance"] as Dictionary).duplicate(true)

	var ids: Array[String] = []
	for entity_id in by_id:
		ids.append(String(entity_id))
	ids.sort()
	var result: Array[Dictionary] = []
	for entity_id in ids:
		result.append((by_id[entity_id] as Dictionary).duplicate(true))
	return {
		"ok": true,
		"region_key": region_key,
		"instances": result,
		"entity_count": result.size(),
		"generation_usec": int(
			generated.get("timings_usec", {}).get(
				"total", generated.get("worker_usec", 0)
			)
		),
	}


## Adopts a base list that was produced earlier by
## build_projection_region_base_instances() on this same service. The state
## revision gate makes the prepared view invalid as soon as any authoritative
## entity command commits. Registry/content authority is unchanged; this only
## avoids revalidating and re-resolving the same immutable bases during visual
## publication.
func adopt_prepared_projection_region_base_instances(
	region_key: Vector2i,
	prepared_instances: Array,
	prepared_state_revision: int
) -> Dictionary:
	var started_usec := Time.get_ticks_usec()
	if not initialized:
		return _failure("command_service_not_initialized")
	if not _valid_region(region_key):
		return _failure("command_region_invalid")
	if prepared_state_revision < 0 or prepared_state_revision != int(
		state_service.get_revision()
	):
		return _failure("prepared_projection_state_revision_stale")

	var candidates: Array[Dictionary] = []
	var seen_ids: Dictionary = {}
	for value in prepared_instances:
		if typeof(value) != TYPE_DICTIONARY:
			return _failure("prepared_projection_instance_invalid")
		var base: Dictionary = value
		if Vector2i(
			base.get(
				"region_key",
				Vector2i(2147483647, 2147483647)
			)
		) != region_key:
			return _failure("prepared_projection_region_mismatch")
		var instance_id := String(base.get("instance_id", ""))
		if instance_id.is_empty() or seen_ids.has(instance_id):
			return _failure("prepared_projection_identity_invalid")
		seen_ids[instance_id] = true
		candidates.append(base)

	for existing_id in _base_instances.keys().duplicate():
		var existing: Dictionary = _base_instances[existing_id]
		if Vector2i(existing.get("region_key", Vector2i.ZERO)) == region_key:
			_base_instances.erase(existing_id)
	for base in candidates:
		# The prepared dictionaries are immutable reconstruction products. A
		# shallow dictionary copy isolates top-level map mutation without
		# duplicating large immutable geometry/pin payloads.
		_base_instances[String(base["instance_id"])] = base.duplicate(false)

	var main_thread_usec := Time.get_ticks_usec() - started_usec
	last_reconstruction_usec = main_thread_usec
	return {
		"ok": true,
		"region_key": region_key,
		"entity_count": candidates.size(),
		"generation_usec": 0,
		"main_thread_reconstruction_usec": main_thread_usec,
		"reconstruction_usec": main_thread_usec,
		"prepared_adoption": true,
	}


func get_region_base_instances(region_key: Vector2i) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var ids: Array[String] = []
	for entity_id in _base_instances:
		if Vector2i(_base_instances[entity_id].get("region_key", Vector2i(2147483647, 2147483647))) == region_key:
			ids.append(String(entity_id))
	ids.sort()
	for entity_id in ids:
		result.append(_base_instances[entity_id].duplicate(true))
	return result


func get_entity_region(entity_id: String) -> Dictionary:
	if not _base_instances.has(entity_id):
		return _failure("entity_not_reconstructed_or_content_missing")
	return {"ok": true, "region_key": Vector2i(_base_instances[entity_id].region_key)}


func resolve_entity(entity_id: String) -> Dictionary:
	if not initialized:
		return _failure("command_service_not_initialized")
	if not _base_instances.has(entity_id):
		return _failure("entity_not_reconstructed_or_content_missing")
	return state_service.resolve_instance(_base_instances[entity_id])


func dispatch(raw_command: Variant) -> Dictionary:
	var dispatch_started_usec := Time.get_ticks_usec()
	if not initialized:
		return _failure("command_service_not_initialized")
	var validation_started_usec := Time.get_ticks_usec()
	var checked := Contract.validate(raw_command, state_service.world_id, state_service.world_seed, state_service.generator_version)
	if not checked.get("ok", false):
		return checked
	var command_validation_usec := Time.get_ticks_usec() - validation_started_usec
	var command: Dictionary = checked.command
	var command_id := String(command.command_id)
	var command_digest := StateContract.canonical_sha256(command)
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
	var operation := String(command.operation)
	if operation == "ENTITY_UNDO" or operation == "ENTITY_REDO":
		return _dispatch_history_navigation(command, command_digest, dispatch_started_usec, command_validation_usec)
	var candidate: Dictionary = state_service.snapshot.duplicate(true)
	var command_preparation_started_usec := Time.get_ticks_usec()
	var entity_id := ""
	var identity: Dictionary = {}
	var entity_revision := 1
	var entity_revision_before := 0
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
			if operation == "ENTITY_SET_COMPONENT" and String(command.component_id) == StateContract.COMPONENT_TRANSFORM:
				var ownership_check := _validate_transform_region_ownership(base_instance, command.component)
				if not ownership_check.get("ok", false):
					return ownership_check
			entity_revision = state_service.get_entity_revision(entity_id)
			entity_revision_before = entity_revision
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
				var was_deleted := deleted.has(entity_id)
				if was_deleted and not StateContract.identities_equal(deleted[entity_id], identity):
					return _failure("entity_identity_mismatch")
				var prior_override: Dictionary = overrides.get(entity_id, {}).duplicate(true)
				if not was_deleted and prior_override.is_empty():
					return _failure("entity_already_at_procedural_baseline")
				undo_metadata = {"inverse_operation": "ENTITY_DELETE", "identity": identity.duplicate(true), "prior_deleted": was_deleted, "prior_override": prior_override}
				deleted.erase(entity_id)
				overrides.erase(entity_id)
				candidate.deleted = deleted
				candidate.overrides = overrides
				candidate.deleted = deleted
				candidate.overrides = overrides
			entity_revision += 1
		_:
			return _failure("command_operation_unsupported")
	candidate.entity_revisions[entity_id] = entity_revision
	var next_world_revision := int(state_service.get_revision()) + 1
	var receipt := {"command_sha256": command_digest, "operation": operation, "entity_id": entity_id, "world_revision": next_world_revision, "entity_revision": entity_revision, "undo_metadata": undo_metadata}
	candidate.command_receipts[command_id] = receipt
	if int(state_service.snapshot.get("schema_version", 0)) == HISTORY_SCHEMA_VERSION:
		var history_result := _append_history_entry(candidate, command, command_digest, entity_id, identity, receipt, int(state_service.get_revision()), entity_revision_before, entity_revision)
		if not history_result.get("ok", false):
			return history_result
	var command_preparation_usec := Time.get_ticks_usec() - command_preparation_started_usec
	var commit := state_service.commit_command_candidate(candidate, int(command.expected_world_revision))
	if not commit.get("ok", false):
		if not state_service.initialized:
			initialized = false
		initialization_error = String(commit.get("reason", "command_commit_failed"))
		return commit
	if operation == "ENTITY_PLACE":
		_base_instances[entity_id] = prepared.instance
	last_dispatch_metrics = {
		"command_validation_usec": command_validation_usec,
		"command_preparation_usec": command_preparation_usec,
		"candidate_validation_usec": int(state_service.last_candidate_validation_usec),
		"history_validation_usec": int(state_service.last_history_validation_usec),
		"persistence_usec": int(state_service.last_persist_duration_usec),
		"dispatch_total_usec": Time.get_ticks_usec() - dispatch_started_usec,
	}
	return {"ok": true, "reason": "committed", "duplicate": false, "operation": operation, "entity_id": entity_id, "world_revision": int(commit.world_revision), "entity_revision": entity_revision, "generation": int(commit.generation), "history_depth": int(candidate.get("entity_history", []).size()), "history_cursor": int(candidate.get("history_cursor", 0)), "timings_usec": last_dispatch_metrics.duplicate(true)}


func get_history_summary() -> Dictionary:
	if not initialized or int(state_service.snapshot.get("schema_version", 0)) != HISTORY_SCHEMA_VERSION:
		return {"enabled": false, "depth": 0, "cursor": 0, "undo": {}, "redo": {}}
	var history: Array = state_service.snapshot.get("entity_history", [])
	var cursor := int(state_service.snapshot.get("history_cursor", 0))
	var undo_entry: Dictionary = history[cursor - 1] if cursor > 0 else {}
	var redo_entry: Dictionary = history[cursor] if cursor < history.size() else {}
	return {"enabled": true, "depth": history.size(), "cursor": cursor, "undo": _history_entry_summary(undo_entry), "redo": _history_entry_summary(redo_entry)}


func _history_entry_summary(entry: Dictionary) -> Dictionary:
	if entry.is_empty():
		return {}
	return {"history_entry_id": String(entry.get("history_entry_id", "")), "operation": String(entry.get("operation", "")), "entity_id": String(entry.get("entity_id", "")), "application_state": String(entry.get("application_state", ""))}


func _append_history_entry(candidate: Dictionary, command: Dictionary, digest: String, entity_id: String, identity: Dictionary, receipt: Dictionary, world_revision_before: int, entity_revision_before: int, entity_revision_after: int) -> Dictionary:
	var history: Array = candidate.get("entity_history", []).duplicate(true)
	var cursor := int(candidate.get("history_cursor", 0))
	if cursor < 0 or cursor > history.size():
		return _failure("history_cursor_invalid_before_append")
	for index in range(history.size() - 1, cursor - 1, -1):
		history.remove_at(index)
	if history.size() >= MAX_HISTORY_ENTRIES:
		if cursor <= 0:
			return _failure("history_capacity_cannot_prune_redoable_entry")
		history.remove_at(0)
		cursor -= 1
	var history_id := String(command.command_id)
	var entry := {
		"schema_version": 1,
		"history_entry_id": history_id,
		"source_command_id": history_id,
		"original_command": command.duplicate(true),
		"original_command_sha256": digest,
		"entity_id": entity_id,
		"operation": String(command.operation),
		"world_id": state_service.world_id,
		"world_seed": state_service.world_seed,
		"generator_version": state_service.generator_version,
		"entity_identity": identity.duplicate(true),
		"world_revision_before": world_revision_before,
		"world_revision_after": int(receipt.world_revision),
		"entity_revision_before": entity_revision_before,
		"entity_revision_after": entity_revision_after,
		"receipt_command_id": history_id,
		"inverse_metadata_sha256": StateContract.canonical_sha256(receipt.undo_metadata),
		"application_state": "APPLIED",
	}
	history.append(entry)
	candidate.entity_history = history
	candidate.history_cursor = history.size()
	return {"ok": true}


func _dispatch_history_navigation(command: Dictionary, command_digest: String, dispatch_started_usec: int, command_validation_usec: int) -> Dictionary:
	if int(state_service.snapshot.get("schema_version", 0)) != HISTORY_SCHEMA_VERSION:
		return _failure("entity_history_schema_migration_required")
	var operation := String(command.operation)
	var history: Array = state_service.snapshot.get("entity_history", [])
	var cursor := int(state_service.snapshot.get("history_cursor", 0))
	var entry_index := cursor - 1 if operation == "ENTITY_UNDO" else cursor
	if entry_index < 0 or entry_index >= history.size():
		return _failure("entity_undo_history_empty" if operation == "ENTITY_UNDO" else "entity_redo_history_empty")
	var entry: Dictionary = history[entry_index]
	if String(entry.get("history_entry_id", "")) != String(command.history_entry_id) or String(entry.get("entity_id", "")) != String(command.entity_id):
		return _failure("entity_history_operation_out_of_order")
	var expected_state := "APPLIED" if operation == "ENTITY_UNDO" else "UNDONE"
	if String(entry.get("application_state", "")) != expected_state:
		return _failure("entity_history_state_conflict")
	if not _base_instances.has(String(command.entity_id)):
		return _failure("entity_not_reconstructed_or_content_missing")
	var base_instance: Dictionary = _base_instances[String(command.entity_id)]
	var identity: Dictionary = StateContract.identity_for_instance(base_instance)
	if not StateContract.identities_equal(identity, entry.get("entity_identity", {})):
		return _failure("entity_history_identity_mismatch")
	var pin_check := _validate_identity_pin(identity)
	if not pin_check.get("ok", false):
		return pin_check
	var current_entity_revision := state_service.get_entity_revision(String(command.entity_id))
	if current_entity_revision != int(command.expected_entity_revision):
		return _failure("stale_entity_revision")
	var original_receipt: Dictionary = state_service.snapshot.get("command_receipts", {}).get(String(entry.receipt_command_id), {})
	if original_receipt.is_empty() or String(original_receipt.command_sha256) != String(entry.original_command_sha256):
		return _failure("entity_history_source_receipt_unavailable")
	var candidate: Dictionary = state_service.snapshot.duplicate(true)
	var inverse_started_usec := Time.get_ticks_usec()
	var apply_result := _apply_history_operation(candidate, entry, original_receipt, operation == "ENTITY_REDO")
	if not apply_result.get("ok", false):
		return apply_result
	var next_cursor := cursor - 1 if operation == "ENTITY_UNDO" else cursor + 1
	var updated_history: Array = candidate.entity_history
	updated_history[entry_index]["application_state"] = "APPLIED" if operation == "ENTITY_REDO" else "UNDONE"
	candidate.entity_history = updated_history
	candidate.history_cursor = next_cursor
	var next_entity_revision := current_entity_revision + 1
	if next_entity_revision >= 2147483647:
		return _failure("entity_revision_limit_reached")
	candidate.entity_revisions[String(command.entity_id)] = next_entity_revision
	var next_world_revision := state_service.get_revision() + 1
	var inverse_prepare_usec := Time.get_ticks_usec() - inverse_started_usec
	var command_preparation_usec := maxi(0, inverse_started_usec - dispatch_started_usec - command_validation_usec)
	var receipt := {
		"command_sha256": command_digest,
		"operation": operation,
		"entity_id": String(command.entity_id),
		"world_revision": next_world_revision,
		"entity_revision": next_entity_revision,
		"undo_metadata": {"inverse_operation": "ENTITY_REDO" if operation == "ENTITY_UNDO" else "ENTITY_UNDO", "history_entry_id": String(command.history_entry_id)},
	}
	candidate.command_receipts[String(command.command_id)] = receipt
	var commit: Dictionary = state_service.commit_command_candidate(candidate, int(command.expected_world_revision))
	if not commit.get("ok", false):
		if not state_service.initialized:
			initialized = false
		initialization_error = String(commit.get("reason", "history_command_commit_failed"))
		return commit
	last_dispatch_metrics = {
		"command_validation_usec": command_validation_usec,
		"command_preparation_usec": command_preparation_usec,
		"inverse_preparation_usec": inverse_prepare_usec,
		"candidate_validation_usec": int(state_service.last_candidate_validation_usec),
		"history_validation_usec": int(state_service.last_history_validation_usec),
		"persistence_usec": int(state_service.last_persist_duration_usec),
		"dispatch_total_usec": Time.get_ticks_usec() - dispatch_started_usec,
	}
	return {"ok": true, "reason": "committed", "duplicate": false, "operation": operation, "history_entry_id": String(entry.history_entry_id), "entity_id": String(command.entity_id), "world_revision": int(commit.world_revision), "entity_revision": next_entity_revision, "generation": int(commit.generation), "history_depth": history.size(), "history_cursor": next_cursor, "timings_usec": last_dispatch_metrics.duplicate(true)}


func _apply_history_operation(candidate: Dictionary, entry: Dictionary, original_receipt: Dictionary, redo: bool) -> Dictionary:
	var entity_id := String(entry.entity_id)
	var identity: Dictionary = entry.entity_identity
	var operation := String(entry.operation)
	var overrides: Dictionary = candidate.overrides.duplicate(true)
	var deleted: Dictionary = candidate.deleted.duplicate(true)
	var placed: Dictionary = candidate.placed_entities.duplicate(true)
	var override_record: Dictionary = overrides.get(entity_id, {}).duplicate(true)
	var prior_override: Dictionary = original_receipt.undo_metadata.get("prior_override", {}).duplicate(true)
	match operation:
		"ENTITY_SET_COMPONENT":
			if deleted.has(entity_id):
				return _failure("entity_history_set_target_deleted")
			var source_command: Dictionary = entry.original_command
			var component_id := String(source_command.component_id)
			var metadata: Dictionary = original_receipt.undo_metadata
			var components_before: Dictionary = override_record.get("components", {})
			var component_value: Dictionary
			if redo:
				var prior_present := bool(metadata.prior_component_present)
				if prior_present != components_before.has(component_id) or (prior_present and not _same_history_value(components_before[component_id], metadata.prior_component)):
					return _failure("entity_history_redo_component_precondition_mismatch")
				component_value = source_command.component.duplicate(true)
			else:
				if not components_before.has(component_id) or not _same_history_value(components_before[component_id], source_command.component):
					return _failure("entity_history_undo_component_precondition_mismatch")
				if bool(metadata.prior_component_present):
					component_value = metadata.prior_component.duplicate(true)
			if override_record.is_empty():
				override_record = {"identity": identity.duplicate(true), "components": {}}
			if not StateContract.identities_equal(override_record.get("identity", {}), identity):
				return _failure("entity_history_override_identity_mismatch")
			var components: Dictionary = override_record.get("components", {}).duplicate(true)
			if redo or bool(original_receipt.undo_metadata.prior_component_present):
				components[component_id] = component_value
			else:
				components.erase(component_id)
			if components.is_empty():
				overrides.erase(entity_id)
			else:
				override_record.components = components
				overrides[entity_id] = override_record
		"ENTITY_DELETE":
			if redo:
				if deleted.has(entity_id):
					return _failure("entity_history_delete_target_already_deleted")
				if not _same_history_value(overrides.get(entity_id, {}), prior_override):
					return _failure("entity_history_redo_delete_override_mismatch")
				deleted[entity_id] = identity.duplicate(true)
				overrides.erase(entity_id)
			else:
				if not deleted.has(entity_id) or not StateContract.identities_equal(deleted[entity_id], identity):
					return _failure("entity_history_delete_tombstone_missing")
				deleted.erase(entity_id)
				if prior_override.is_empty():
					overrides.erase(entity_id)
				else:
					overrides[entity_id] = prior_override
		"ENTITY_RESTORE":
			var prior_deleted := bool(original_receipt.undo_metadata.get("prior_deleted", true))
			if redo:
				if deleted.has(entity_id) != prior_deleted or (prior_deleted and not StateContract.identities_equal(deleted.get(entity_id, {}), identity)):
					return _failure("entity_history_redo_restore_deletion_state_mismatch")
				if not _same_history_value(overrides.get(entity_id, {}), prior_override):
					return _failure("entity_history_redo_restore_override_mismatch")
				deleted.erase(entity_id)
				overrides.erase(entity_id)
			else:
				if deleted.has(entity_id) or overrides.has(entity_id):
					return _failure("entity_history_undo_restore_target_not_baseline")
				if prior_deleted:
					deleted[entity_id] = identity.duplicate(true)
				else:
					deleted.erase(entity_id)
				if prior_override.is_empty():
					overrides.erase(entity_id)
				else:
					overrides[entity_id] = prior_override
		"ENTITY_PLACE":
			if not placed.has(entity_id) or not StateContract.identities_equal(placed[entity_id].get("identity", {}), identity):
				return _failure("entity_history_placed_record_missing")
			if redo:
				if not deleted.has(entity_id) or not StateContract.identities_equal(deleted[entity_id], identity):
					return _failure("entity_history_place_tombstone_missing")
				if overrides.has(entity_id):
					return _failure("entity_history_redo_place_override_mismatch")
				deleted.erase(entity_id)
			else:
				if deleted.has(entity_id):
					return _failure("entity_history_place_target_already_deleted")
				if overrides.has(entity_id):
					return _failure("entity_history_undo_place_override_mismatch")
				# Keep the explicit record and tombstone it so redo reserves the same ID.
				deleted[entity_id] = identity.duplicate(true)
			overrides.erase(entity_id)
		_:
			return _failure("entity_history_operation_unsupported")
	candidate.overrides = overrides
	candidate.deleted = deleted
	candidate.placed_entities = placed
	return {"ok": true}


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
	var terrain_interaction_result: Dictionary = registry.resolve_terrain_interaction(String(identity.definition_id))
	if not terrain_interaction_result.get("ok", false):
		return _failure("placed_entity_terrain_interaction_unavailable")
	var terrain_interaction: Dictionary = terrain_interaction_result.get("rule", {})
	var terrain_interaction_pin: Dictionary = terrain_interaction_result.get("pin", {})
	var region_key := Vector2i(int(identity.region_key[0]), int(identity.region_key[1]))
	var world_position_mm := Vector3i(int(record.position_mm[0]), int(record.position_mm[1]), int(record.position_mm[2]))
	var region_origin_mm := Vector3i(roundi(Spatial.region_origin_world(region_key).x * 1000.0), 0, roundi(Spatial.region_origin_world(region_key).z * 1000.0))
	var region_local_position_mm: Vector3i = world_position_mm - region_origin_mm
	return {"ok": true, "instance": {
		"instance_id": entity_id, "entity_identity": identity.duplicate(true), "definition_id": identity.definition_id,
		"content_pin": identity.content_pin.duplicate(true), "world_id": identity.world_id, "world_seed": identity.world_seed,
		"generator_version": identity.generator_version, "region_key": region_key,
		"placement_seed": identity.placement_seed, "recipe_seed": identity.recipe_seed, "recipe_algorithm": recipe.algorithm,
		"geometry_profile": recipe.get("profile", ""), "geometry": recipe.geometry.duplicate(true),
		"geometry_seeds": recipe.geometry_seeds.duplicate(true), "instance_state": {}, "component_contract_version": 1,
		"components": ["core.transform@1", "core.appearance@1", "core.logical@1"],
		# Persistent records store world-space anchors; streamed region roots use local coordinates.
		"position_mm": region_local_position_mm, "world_position_mm": world_position_mm,
		"default_scale_milli": Vector3i(1000, 1000, 1000), "default_yaw_mdeg": 0, "population_rule_id": "",
		"population_rule_pin": {}, "population_rule_schema_version": 0, "population_candidate_index": -1,
		"population_algorithm": "explicit_place_v1", "population_batched": false,
		"terrain_interaction": terrain_interaction.duplicate(true),
		"terrain_interaction_pin": terrain_interaction_pin.duplicate(true),
		"terrain_interaction_applied": false,
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


func _same_history_value(first: Variant, second: Variant) -> bool:
	return StateContract.canonical_sha256(first) == StateContract.canonical_sha256(second)


func _validate_origin_registration(origin: Dictionary) -> Dictionary:
	if String(origin.type) == "mod" and (registry == null or not registry.has_method("has_mod") or not registry.has_mod(String(origin.id))):
		return _failure("command_origin_mod_missing")
	return {"ok": true}


func _validate_transform_region_ownership(base_instance: Dictionary, component: Dictionary) -> Dictionary:
	var properties: Dictionary = component.get("properties", {})
	var translation: Array = properties.get("translation_mm", [0, 0, 0])
	if translation.size() != 3:
		return _failure("component_transform_invalid")
	var base_region: Vector2i = Vector2i(base_instance.get("region_key", Vector2i.ZERO))
	var local_position_mm: Vector3i = Vector3i(base_instance.get("position_mm", Vector3i.ZERO))
	var effective_position := Spatial.region_origin_world(base_region) + Vector3(local_position_mm) / 1000.0 + Vector3(int(translation[0]), int(translation[1]), int(translation[2])) / 1000.0
	var mapped: Dictionary = Spatial.world_to_region_local(effective_position)
	if not mapped.get("valid", false) or Vector2i(mapped.get("region_key", Vector2i.ZERO)) != base_region:
		return _failure("component_transform_region_transfer_not_supported")
	return {"ok": true}


func _valid_region(region_key: Vector2i) -> bool:
	return region_key.x >= -2147483648 and region_key.x <= 2147483647 and region_key.y >= -2147483648 and region_key.y <= 2147483647


func _failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
