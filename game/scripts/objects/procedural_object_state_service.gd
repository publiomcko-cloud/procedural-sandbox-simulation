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
	if not stored.is_empty():
		if not Contract.identities_equal(stored.identity, identity):
			return _failure("object_state_identity_pin_mismatch")
		effective["instance_components"] = stored.components.duplicate(true)
	else:
		effective["instance_components"] = {}
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
	return _commit_candidate(candidate)


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
	return _commit_candidate(candidate)


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
	return _commit_candidate(candidate)


func get_revision() -> int:
	return int(snapshot.get("revision", 0))


func get_persisted_override_count() -> int:
	return (snapshot.get("overrides", {}) as Dictionary).size()


func get_deleted_count() -> int:
	return (snapshot.get("deleted", {}) as Dictionary).size()


func get_deleted_identity(instance_id: String) -> Dictionary:
	return (snapshot.get("deleted", {}) as Dictionary).get(instance_id, {}).duplicate(true)


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


func _commit_candidate(candidate: Dictionary) -> Dictionary:
	candidate.revision = int(snapshot.revision) + 1
	var checked := Contract.validate_snapshot(candidate, world_id, world_seed, generator_version)
	if not checked.get("ok", false):
		return _failure(String(checked.get("reason", "object_state_candidate_invalid")))
	var saved: Dictionary = store.save_snapshot(checked.snapshot)
	if not saved.get("ok", false):
		return _failure(String(saved.get("reason", "object_state_save_failed")))
	snapshot = checked.snapshot
	storage_generation = int(saved.generation)
	return {"ok": true, "revision": int(snapshot.revision), "generation": storage_generation}


func _failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
