class_name TerrainObjectEffectProjectionService
extends RefCounted

## Derived projection service. Entity/object state is the sole authority.
##
## Reconciliation is serialized and durable: a fully validated candidate and its
## derived spatial index are prepared first, then the candidate snapshot is
## committed, and only then does it become visible in memory. A crash between an
## entity-state commit and projection reconciliation is repaired by comparing
## source_world_revision on the next scope reconciliation.
const Contract := preload("res://scripts/terrain/terrain_object_effect_projection_contract.gd")
const StoreScript := preload("res://scripts/terrain/terrain_object_effect_projection_store.gd")
const Effect := preload("res://scripts/terrain/terrain_object_effect.gd")
const EffectIndex := preload("res://scripts/terrain/terrain_object_effect_index.gd")

var world_id := ""
var world_seed := -1
var generator_version := -1
var snapshot: Dictionary = {}
var store: RefCounted
var index: RefCounted
var initialized := false
var initialization_error := ""
var storage_generation := 0
var last_reconcile_metrics: Dictionary = {}


func initialize(
	world_identifier: String,
	seed_value: int,
	generator: int,
	directory_override: String = ""
) -> Dictionary:
	initialized = false
	initialization_error = ""
	world_id = world_identifier
	world_seed = seed_value
	generator_version = generator
	store = StoreScript.new(directory_override)
	var loaded: Dictionary = store.load_snapshot(world_id, world_seed, generator_version)
	if not loaded.get("ok", false):
		initialization_error = String(loaded.get("reason", "effect_projection_load_failed"))
		return _failure(initialization_error)
	var checked := Contract.validate_snapshot(
		loaded.get("snapshot"), world_id, world_seed, generator_version
	)
	if not checked.get("ok", false):
		initialization_error = String(checked.get("reason", "effect_projection_snapshot_invalid"))
		return _failure(initialization_error)
	var index_result := _build_index(checked["snapshot"])
	if not index_result.get("ok", false):
		initialization_error = String(index_result.get("reason", "effect_projection_index_rebuild_failed"))
		return _failure(initialization_error)
	snapshot = checked["snapshot"]
	index = index_result["index"]
	storage_generation = int(loaded.get("generation", 0))
	initialized = true
	return {
		"ok": true,
		"found": bool(loaded.get("found", false)),
		"generation": storage_generation,
		"projection_revision": int(snapshot["projection_revision"]),
		"source_world_revision": int(snapshot["source_world_revision"]),
		"recovered_temporary": bool(loaded.get("recovered_temporary", false)),
		"ignored_incomplete_generations": int(loaded.get("ignored_incomplete_generations", 0)),
		"effect_count": (snapshot["effects"] as Dictionary).size(),
		"scope_count": (snapshot["scopes"] as Dictionary).size(),
	}


func reconcile_scope(
	region_key: Vector2i,
	source_world_revision: int,
	authoritative_instances: Array[Dictionary],
	source_revisions: Dictionary
) -> Dictionary:
	var started_usec := Time.get_ticks_usec()
	if not initialized:
		return _failure("effect_projection_service_not_initialized")
	if source_world_revision < 0 or source_world_revision > Contract.MAX_REVISION:
		return _failure("effect_projection_source_world_revision_invalid")
	var current_global_revision := int(snapshot["source_world_revision"])
	if source_world_revision < current_global_revision:
		return _failure("effect_projection_stale_source_world_revision")
	var scope_id := Contract.scope_id_for_region(region_key)
	var scopes: Dictionary = snapshot["scopes"]
	var prior_scope: Dictionary = scopes.get(scope_id, {})
	if not prior_scope.is_empty() 		and source_world_revision < int(prior_scope.get("source_world_revision", 0)):
		return _failure("effect_projection_stale_scope_revision")

	var ordered_instances := authoritative_instances.duplicate(true)
	ordered_instances.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.get("instance_id", "")) < String(b.get("instance_id", ""))
	)
	var incoming_effects: Dictionary = {}
	var source_instance_ids: Array[String] = []
	var source_digest_entries: Array[Dictionary] = []
	var seen_sources: Dictionary = {}
	for instance in ordered_instances:
		var instance_id := String(instance.get("instance_id", ""))
		if instance_id.is_empty() or seen_sources.has(instance_id):
			return _failure("effect_projection_source_identity_invalid")
		seen_sources[instance_id] = true
		if instance.get("region_key", Vector2i(2147483647, 2147483647)) != region_key:
			return _failure("effect_projection_source_region_mismatch")
		var source_revision_result := _source_revision(source_revisions, instance_id)
		if not source_revision_result.get("ok", false):
			return source_revision_result
		var source_revision := int(source_revision_result["revision"])
		source_instance_ids.append(instance_id)
		var interaction: Dictionary = instance.get("terrain_interaction", {})
		if interaction.is_empty():
			source_digest_entries.append({
				"instance_id": instance_id,
				"source_revision": source_revision,
				"content_pin_sha256": Contract.canonical_sha256(instance.get("content_pin", {})),
				"terrain_interaction": "none",
			})
			continue
		var built := Effect.build_from_instance(instance, source_revision)
		if not built.get("ok", false):
			return _failure(
				"effect_projection_effect_build_failed:%s" % built.get("reason", "unknown")
			)
		var effect: Dictionary = built["effect"]
		var effect_id := String(effect["effect_id"])
		if incoming_effects.has(effect_id):
			return _failure("effect_projection_effect_identity_collision")
		var existing: Dictionary = (snapshot["effects"] as Dictionary).get(effect_id, {})
		if not existing.is_empty():
			var existing_revision := int(existing["source_revision"])
			if source_revision < existing_revision:
				return _failure("effect_projection_stale_source_revision")
			if source_revision == existing_revision 				and String(effect["source_fingerprint_sha256"]) 					!= String(existing["source_fingerprint_sha256"]):
				return _failure("effect_projection_same_revision_fingerprint_conflict")
		incoming_effects[effect_id] = effect
		source_digest_entries.append({
			"instance_id": instance_id,
			"source_revision": source_revision,
			"effect_id": effect_id,
			"source_fingerprint_sha256": String(effect["source_fingerprint_sha256"]),
		})

	source_instance_ids.sort()
	var effect_ids: Array[String] = []
	for effect_id_value in incoming_effects:
		effect_ids.append(String(effect_id_value))
	effect_ids.sort()
	source_digest_entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.get("instance_id", "")) < String(b.get("instance_id", ""))
	)
	var source_digest := Contract.canonical_sha256({
		"scope_id": scope_id,
		"region_key": [region_key.x, region_key.y],
		"source_world_revision": source_world_revision,
		"sources": source_digest_entries,
	})
	var next_scope := {
		"scope_id": scope_id,
		"region_key": [region_key.x, region_key.y],
		"source_world_revision": source_world_revision,
		"source_digest_sha256": source_digest,
		"source_instance_ids": source_instance_ids,
		"effect_ids": effect_ids,
	}
	var scope_checked := Contract.validate_scope(next_scope, scope_id)
	if not scope_checked.get("ok", false):
		return scope_checked
	next_scope = scope_checked["scope"]

	if not prior_scope.is_empty() 		and int(prior_scope["source_world_revision"]) == source_world_revision 		and String(prior_scope["source_digest_sha256"]) == source_digest 		and prior_scope["source_instance_ids"] == source_instance_ids 		and prior_scope["effect_ids"] == effect_ids:
		last_reconcile_metrics = {
			"scope_id": scope_id,
			"changed": false,
			"source_count": source_instance_ids.size(),
			"effect_count": effect_ids.size(),
			"removed_effect_count": 0,
			"duration_usec": Time.get_ticks_usec() - started_usec,
		}
		return {
			"ok": true,
			"changed": false,
			"reason": "already_current",
			"scope_id": scope_id,
			"generation": storage_generation,
			"projection_revision": int(snapshot["projection_revision"]),
			"source_world_revision": source_world_revision,
			"effect_count": effect_ids.size(),
			"removed_effect_count": 0,
		}

	var candidate: Dictionary = snapshot.duplicate(true)
	var candidate_scopes: Dictionary = candidate["scopes"]
	var candidate_effects: Dictionary = candidate["effects"]
	var prior_effect_ids: Array = prior_scope.get("effect_ids", [])
	var removed_effect_count := 0
	for prior_effect_id_value in prior_effect_ids:
		var prior_effect_id := String(prior_effect_id_value)
		if effect_ids.has(prior_effect_id):
			continue
		candidate_effects.erase(prior_effect_id)
		removed_effect_count += 1
	for effect_id in effect_ids:
		candidate_effects[effect_id] = incoming_effects[effect_id].duplicate(true)
	candidate_scopes[scope_id] = next_scope
	candidate["effects"] = candidate_effects
	candidate["scopes"] = candidate_scopes
	candidate["projection_revision"] = int(snapshot["projection_revision"]) + 1
	candidate["source_world_revision"] = source_world_revision

	var checked := Contract.validate_snapshot(
		candidate, world_id, world_seed, generator_version
	)
	if not checked.get("ok", false):
		return checked
	var index_result := _build_index(checked["snapshot"])
	if not index_result.get("ok", false):
		return index_result
	var persisted: Dictionary = store.save_validated_snapshot(checked["snapshot"])
	if not persisted.get("ok", false):
		# A store failure may occur after bytes were flushed or a rename became
		# durable. Do not permit another mutation until load/recovery establishes
		# the actual committed generation.
		initialized = false
		initialization_error = String(
			persisted.get("reason", "effect_projection_persist_failed")
		)
		return _failure(
			"effect_projection_commit_uncertain:%s" % initialization_error
		)

	snapshot = checked["snapshot"]
	index = index_result["index"]
	storage_generation = int(persisted["generation"])
	last_reconcile_metrics = {
		"scope_id": scope_id,
		"changed": true,
		"source_count": source_instance_ids.size(),
		"effect_count": effect_ids.size(),
		"removed_effect_count": removed_effect_count,
		"duration_usec": Time.get_ticks_usec() - started_usec,
	}
	return {
		"ok": true,
		"changed": true,
		"reason": "committed",
		"scope_id": scope_id,
		"generation": storage_generation,
		"projection_revision": int(snapshot["projection_revision"]),
		"source_world_revision": source_world_revision,
		"effect_count": effect_ids.size(),
		"removed_effect_count": removed_effect_count,
	}


## Read-only adapter over the authoritative command service. It never dispatches
## commands or mutates entity state.
func reconcile_command_region(region_key: Vector2i, command_service: RefCounted) -> Dictionary:
	if not initialized:
		return _failure("effect_projection_service_not_initialized")
	if command_service == null 		or not command_service.has_method("get_region_base_instances") 		or not command_service.has_method("resolve_entity"):
		return _failure("effect_projection_command_service_invalid")
	var authoritative_state_service: Variant = command_service.get("state_service")
	if authoritative_state_service == null 		or not authoritative_state_service.has_method("get_revision") 		or not authoritative_state_service.has_method("get_entity_revision"):
		return _failure("effect_projection_state_service_invalid")
	var source_world_revision := int(authoritative_state_service.call("get_revision"))
	var base_instances_value: Variant = command_service.call("get_region_base_instances", region_key)
	if typeof(base_instances_value) != TYPE_ARRAY:
		return _failure("effect_projection_region_sources_invalid")
	var active_instances: Array[Dictionary] = []
	var source_revisions: Dictionary = {}
	for base_value in base_instances_value:
		if typeof(base_value) != TYPE_DICTIONARY:
			return _failure("effect_projection_region_source_invalid")
		var base: Dictionary = base_value
		var instance_id := String(base.get("instance_id", ""))
		if instance_id.is_empty():
			return _failure("effect_projection_region_source_identity_invalid")
		var resolved_value: Variant = command_service.call("resolve_entity", instance_id)
		if typeof(resolved_value) != TYPE_DICTIONARY:
			return _failure("effect_projection_region_resolution_invalid")
		var resolved: Dictionary = resolved_value
		if not resolved.get("ok", false):
			return _failure(
				"effect_projection_region_resolution_failed:%s" 					% resolved.get("reason", "unknown")
			)
		if bool(resolved.get("deleted", false)):
			continue
		if typeof(resolved.get("instance")) != TYPE_DICTIONARY:
			return _failure("effect_projection_region_effective_instance_invalid")
		active_instances.append((resolved["instance"] as Dictionary).duplicate(true))
		source_revisions[instance_id] = int(
			authoritative_state_service.call("get_entity_revision", instance_id)
		)
	return reconcile_scope(
		region_key, source_world_revision, active_instances, source_revisions
	)


func get_scope_status(region_key: Vector2i, authoritative_world_revision: int) -> Dictionary:
	if not initialized:
		return _failure("effect_projection_service_not_initialized")
	var scope_id := Contract.scope_id_for_region(region_key)
	var scope: Dictionary = (snapshot["scopes"] as Dictionary).get(scope_id, {})
	if scope.is_empty():
		return {
			"ok": true,
			"status": "missing",
			"scope_id": scope_id,
			"authoritative_world_revision": authoritative_world_revision,
		}
	var projected := int(scope["source_world_revision"])
	var status := "current" if projected == authoritative_world_revision 		else "stale" if projected < authoritative_world_revision 		else "ahead"
	return {
		"ok": true,
		"status": status,
		"scope_id": scope_id,
		"projected_source_world_revision": projected,
		"authoritative_world_revision": authoritative_world_revision,
		"effect_count": (scope["effect_ids"] as Array).size(),
	}


func get_effects_for_chunk(
	region_key: Vector2i,
	chunk_coordinate: Vector2i
) -> Array[Dictionary]:
	if not initialized:
		return []
	return index.get_effects_for_chunk(region_key, chunk_coordinate)


func snapshot_for_chunk(
	region_key: Vector2i,
	chunk_coordinate: Vector2i
) -> Dictionary:
	if not initialized:
		return _failure("effect_projection_service_not_initialized")
	return index.snapshot_for_chunk(region_key, chunk_coordinate)


func get_snapshot() -> Dictionary:
	return snapshot.duplicate(true)


func get_effect_count() -> int:
	return (snapshot.get("effects", {}) as Dictionary).size() if initialized else 0


func get_scope_count() -> int:
	return (snapshot.get("scopes", {}) as Dictionary).size() if initialized else 0


func _source_revision(source_revisions: Dictionary, instance_id: String) -> Dictionary:
	if not source_revisions.has(instance_id):
		return _failure("effect_projection_source_revision_missing")
	var value: Variant = source_revisions[instance_id]
	if not _is_integer(value) or int(value) < 0 or int(value) > Contract.MAX_REVISION:
		return _failure("effect_projection_source_revision_invalid")
	return {"ok": true, "revision": int(value)}


func _build_index(candidate_snapshot: Dictionary) -> Dictionary:
	var candidate_index := EffectIndex.new()
	var effect_ids: Array[String] = []
	for effect_id_value in (candidate_snapshot["effects"] as Dictionary):
		effect_ids.append(String(effect_id_value))
	effect_ids.sort()
	for effect_id in effect_ids:
		var indexed: Dictionary = candidate_index.replace_effect(
			candidate_snapshot["effects"][effect_id]
		)
		if not indexed.get("ok", false):
			return _failure(
				"effect_projection_index_rebuild_failed:%s" 					% indexed.get("reason", "unknown")
			)
	return {"ok": true, "index": candidate_index}


func _is_integer(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or (
		typeof(value) == TYPE_FLOAT
		and is_finite(float(value))
		and floor(float(value)) == float(value)
		and abs(float(value)) <= 9007199254740991.0
	)


func _failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
