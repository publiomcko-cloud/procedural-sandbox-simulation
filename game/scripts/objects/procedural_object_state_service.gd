class_name ProceduralObjectStateService
extends RefCounted

## Node-independent authoritative override/tombstone service. A mutation becomes
## visible to the model only after its new immutable snapshot is committed.
const Contract := preload("res://scripts/objects/procedural_object_state_contract.gd")
const StoreScript := preload("res://scripts/objects/procedural_object_state_store.gd")

var world_id := ""
var world_seed := -1
var generator_version := -1
var snapshot: Dictionary = {}
var store: RefCounted
var initialized := false
var initialization_error := ""
var storage_generation := 0
var last_persist_duration_usec := 0
var _known_instances: Dictionary = {}


func initialize(world_identifier: String, seed_value: int, generator: int, directory_override: String = "") -> Dictionary:
	initialized = false
	world_id = world_identifier
	world_seed = seed_value
	generator_version = generator
	_known_instances.clear()
	store = StoreScript.new(directory_override)
	var loaded: Dictionary = store.load_snapshot(world_id, world_seed, generator_version)
	if not loaded.get("ok", false):
		initialization_error = String(loaded.get("reason", "object_state_load_failed"))
		return _failure(initialization_error)
	var checked := Contract.validate_snapshot(loaded.get("snapshot"), world_id, world_seed, generator_version)
	if not checked.get("ok", false):
		initialization_error = String(checked.get("reason", "object_state_snapshot_invalid"))
		return _failure(initialization_error)
	snapshot = checked.snapshot
	storage_generation = int(loaded.get("generation", 0))
	initialized = true
	initialization_error = ""
	return {"ok": true, "reason": "ok", "generation": storage_generation, "revision": int(snapshot.revision), "found": bool(loaded.get("found", false)), "recovered_temporary": bool(loaded.get("recovered_temporary", false))}


func resolve_instance(base_instance: Dictionary) -> Dictionary:
	if not initialized:
		return _failure("object_state_service_not_initialized")
	var identity := Contract.identity_for_instance(base_instance)
	var checked_identity := Contract.validate_identity(identity, world_id, world_seed, generator_version)
	if not checked_identity.get("ok", false):
		return _failure(String(checked_identity.get("reason", "object_identity_invalid")))
	identity = checked_identity.identity
	var instance_id := String(identity.instance_id)
	_known_instances[instance_id] = identity.duplicate(true)
	if (snapshot.deleted as Dictionary).has(instance_id):
		if not Contract.identities_equal(snapshot.deleted[instance_id], identity):
			return _failure("object_state_identity_pin_mismatch")
		return {"ok": true, "deleted": true, "instance": {}}
	var effective := base_instance.duplicate(true)
	var stored: Dictionary = (snapshot.overrides as Dictionary).get(instance_id, {})
	var effective_components: Dictionary = base_instance.get("base_components", {}).duplicate(true)
	if not stored.is_empty():
		if not Contract.identities_equal(stored.identity, identity):
			return _failure("object_state_identity_pin_mismatch")
		for component_id in stored.components:
			effective_components[component_id] = stored.components[component_id].duplicate(true)
	effective["instance_components"] = effective_components
	return {"ok": true, "deleted": false, "instance": effective}


func set_component(base_instance: Dictionary, component_id: String, component_value: Dictionary) -> Dictionary:
	var identity_result := _validate_mutation_identity(base_instance)
	if not identity_result.get("ok", false):
		return identity_result
	var normalized := Contract.normalize_component(component_id, component_value)
	if not normalized.get("ok", false):
		return _failure(String(normalized.get("reason", "component_invalid")))
	var candidate := snapshot.duplicate(true)
	var instance_id := String(identity_result.instance_id)
	var deleted: Dictionary = candidate.deleted
	if deleted.has(instance_id):
		return _failure("deleted_instance_requires_restore")
	var overrides: Dictionary = candidate.overrides
	var record: Dictionary = overrides.get(instance_id, {"identity": identity_result.identity, "components": {}})
	if record.identity != identity_result.identity:
		return _failure("object_state_identity_pin_mismatch")
	record.components[component_id] = normalized.value
	overrides[instance_id] = record
	candidate.overrides = overrides
	return _commit_candidate(candidate, instance_id)


func delete_instance(base_instance: Dictionary) -> Dictionary:
	var identity_result := _validate_mutation_identity(base_instance)
	if not identity_result.get("ok", false):
		return identity_result
	var candidate := snapshot.duplicate(true)
	var instance_id := String(identity_result.instance_id)
	var deleted: Dictionary = candidate.deleted
	deleted[instance_id] = identity_result.identity
	var overrides: Dictionary = candidate.overrides
	overrides.erase(instance_id)
	candidate.deleted = deleted
	candidate.overrides = overrides
	return _commit_candidate(candidate, instance_id)


func restore_instance(base_instance: Dictionary) -> Dictionary:
	var identity_result := _validate_mutation_identity(base_instance)
	if not identity_result.get("ok", false):
		return identity_result
	var candidate := snapshot.duplicate(true)
	var instance_id := String(identity_result.instance_id)
	var deleted: Dictionary = candidate.deleted
	deleted.erase(instance_id)
	var overrides: Dictionary = candidate.overrides
	overrides.erase(instance_id)
	candidate.deleted = deleted
	candidate.overrides = overrides
	return _commit_candidate(candidate, instance_id)


func get_revision() -> int:
	return int(snapshot.get("revision", 0))


func get_persisted_override_count() -> int:
	return (snapshot.get("overrides", {}) as Dictionary).size()


func get_deleted_count() -> int:
	return (snapshot.get("deleted", {}) as Dictionary).size()


func get_deleted_identity(instance_id: String) -> Dictionary:
	return (snapshot.get("deleted", {}) as Dictionary).get(instance_id, {}).duplicate(true)


func get_entity_revision(instance_id: String) -> int:
	return int(snapshot.get("entity_revisions", {}).get(instance_id, 0))


## Explicit schema upgrade. Loading schema 1 never rewrites a user's save.
func upgrade_command_snapshot_schema() -> Dictionary:
	if not initialized:
		return _failure("object_state_service_not_initialized")
	if int(snapshot.get("schema_version", 0)) == Contract.COMMAND_SNAPSHOT_SCHEMA_VERSION:
		return {"ok": true, "reason": "already_upgraded", "revision": get_revision()}
	if int(snapshot.get("schema_version", 0)) != Contract.SCHEMA_VERSION:
		return _failure("object_state_schema_upgrade_unsupported")
	var candidate: Dictionary = snapshot.duplicate(true)
	candidate.schema_version = Contract.COMMAND_SNAPSHOT_SCHEMA_VERSION
	candidate["placed_entities"] = {}
	candidate["entity_revisions"] = {}
	candidate["command_receipts"] = {}
	var checked := Contract.validate_snapshot(candidate, world_id, world_seed, generator_version)
	if not checked.get("ok", false):
		return _failure(String(checked.get("reason", "object_state_upgrade_invalid")))
	var persist_started := Time.get_ticks_usec()
	var saved: Dictionary = store.save_snapshot(checked.snapshot)
	last_persist_duration_usec = Time.get_ticks_usec() - persist_started
	if not saved.get("ok", false):
		return _failure(String(saved.get("reason", "object_state_upgrade_write_failed")))
	snapshot = checked.snapshot
	storage_generation = int(saved.get("generation", storage_generation))
	return {"ok": true, "reason": "schema_upgraded_explicitly", "revision": get_revision(), "generation": storage_generation}


func commit_command_candidate(candidate: Dictionary, expected_world_revision: int) -> Dictionary:
	if not initialized:
		return _failure("object_state_service_not_initialized")
	if int(snapshot.get("schema_version", 0)) != Contract.COMMAND_SNAPSHOT_SCHEMA_VERSION:
		return _failure("command_snapshot_migration_required")
	if get_revision() != expected_world_revision:
		return _failure("stale_world_revision")
	var normalized_candidate: Dictionary = candidate.duplicate(true)
	normalized_candidate.revision = expected_world_revision + 1
	var checked := Contract.validate_snapshot(normalized_candidate, world_id, world_seed, generator_version)
	if not checked.get("ok", false):
		return _failure(String(checked.get("reason", "command_candidate_invalid")))
	var persist_started := Time.get_ticks_usec()
	var saved: Dictionary = store.save_snapshot(checked.snapshot)
	last_persist_duration_usec = Time.get_ticks_usec() - persist_started
	if not saved.get("ok", false):
		# A rename may have committed before readback failed. Require reinitialization
		# before another command so a retry cannot overwrite a durable receipt.
		initialized = false
		initialization_error = String(saved.get("reason", "command_store_outcome_uncertain"))
		return _failure("command_commit_uncertain:%s" % initialization_error)
	snapshot = checked.snapshot
	storage_generation = int(saved.get("generation", storage_generation))
	return {"ok": true, "world_revision": get_revision(), "generation": storage_generation}


func _validate_mutation_identity(base_instance: Dictionary) -> Dictionary:
	if not initialized:
		return _failure("object_state_service_not_initialized")
	var identity := Contract.identity_for_instance(base_instance)
	var checked := Contract.validate_identity(identity, world_id, world_seed, generator_version)
	if not checked.get("ok", false):
		return _failure(String(checked.get("reason", "object_identity_invalid")))
	identity = checked.identity
	if not _known_instances.has(String(identity.instance_id)) or not Contract.identities_equal(_known_instances[String(identity.instance_id)], identity):
		return _failure("object_identity_not_reconstructed")
	return {"ok": true, "identity": identity, "instance_id": checked.instance_id}


func _commit_candidate(candidate: Dictionary, changed_instance_id: String = "") -> Dictionary:
	candidate.revision = int(snapshot.revision) + 1
	if int(candidate.get("schema_version", 0)) == Contract.COMMAND_SNAPSHOT_SCHEMA_VERSION and not changed_instance_id.is_empty():
		var entity_revisions: Dictionary = candidate.get("entity_revisions", {}).duplicate(true)
		entity_revisions[changed_instance_id] = int(entity_revisions.get(changed_instance_id, 0)) + 1
		candidate.entity_revisions = entity_revisions
	var checked := Contract.validate_snapshot(candidate, world_id, world_seed, generator_version)
	if not checked.get("ok", false):
		return _failure(String(checked.get("reason", "object_state_candidate_invalid")))
	var persist_started := Time.get_ticks_usec()
	var saved: Dictionary = store.save_snapshot(checked.snapshot)
	last_persist_duration_usec = Time.get_ticks_usec() - persist_started
	if not saved.get("ok", false):
		return _failure(String(saved.get("reason", "object_state_save_failed")))
	snapshot = checked.snapshot
	storage_generation = int(saved.generation)
	return {"ok": true, "revision": int(snapshot.revision), "generation": storage_generation, "entity_revision": get_entity_revision(changed_instance_id) if not changed_instance_id.is_empty() else 0}


func _failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
