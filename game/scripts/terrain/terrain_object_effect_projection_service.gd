class_name TerrainObjectEffectProjectionService
extends RefCounted

## Region-sharded derived projection service.
##
## Entity/object state is the only authority. Regional effect scopes are loaded
## and released independently so an unbounded world never accumulates a global
## resident projection. A scope becomes visible only after its validated
## generation has been durably committed.
const Contract := preload("res://scripts/terrain/terrain_object_effect_projection_contract.gd")
const StoreScript := preload("res://scripts/terrain/terrain_object_effect_projection_store.gd")
const Effect := preload("res://scripts/terrain/terrain_object_effect.gd")
const LocalFrame := preload("res://scripts/terrain/terrain_object_effect_local_frame.gd")
const LocalFrameIndex := preload("res://scripts/terrain/terrain_object_effect_local_frame_index.gd")
const Grid := preload("res://scripts/terrain/terrain_chunk_grid.gd")
const PerformanceTrace := preload("res://scripts/diagnostics/performance_trace.gd")

# The demo retains terrain within radius 2 and a terrain-object effect can reach
# source regions within radius 2. The normal bounded working set is therefore
# radius 4: (2 * 4 + 1)^2 = 81 source scopes. This is a derived contract, not
# an arbitrary cache size.
const TERRAIN_RESIDENCY_RADIUS := 2
const EFFECT_SOURCE_RADIUS := 2
const NORMAL_WORKING_SET_RADIUS := TERRAIN_RESIDENCY_RADIUS + EFFECT_SOURCE_RADIUS
const MAX_RESIDENT_SCOPES := (NORMAL_WORKING_SET_RADIUS * 2 + 1) * (NORMAL_WORKING_SET_RADIUS * 2 + 1)

var world_id := ""
var world_seed := -1
var generator_version := -1
var store: RefCounted
var initialized := false
var initialization_error := ""
var last_reconcile_metrics: Dictionary = {}
var _perf_trace_enabled := false

var _scopes: Dictionary = {}
var _scope_indexes: Dictionary = {}
var _storage_generations: Dictionary = {}
# Reverse routing: stable target chunk id -> sorted source scope ids whose
# indexed effect footprints can touch that chunk. This removes the former
# O(resident scopes) scan from every chunk snapshot.
var _scope_ids_by_chunk: Dictionary = {}
var _performance := {
	"scope_load_count": 0,
	"scope_release_count": 0,
	"scope_route_install_count": 0,
	"snapshot_call_count": 0,
	"lookup_scope_index_examined_count": 0,
	"lookup_frame_count": 0,
	"peak_resident_scope_count": 0,
}


func initialize(
	world_identifier: String,
	seed_value: int,
	generator: int,
	directory_override: String = ""
) -> Dictionary:
	initialized = false
	initialization_error = ""
	_perf_trace_enabled = PerformanceTrace.is_enabled()
	world_id = world_identifier
	world_seed = seed_value
	generator_version = generator
	_scopes.clear()
	_scope_indexes.clear()
	_storage_generations.clear()
	_scope_ids_by_chunk.clear()
	_reset_performance_metrics()
	store = StoreScript.new(directory_override)
	store.configure(world_id, world_seed, generator_version)
	initialized = true
	return {
		"ok": true,
		"resident_scope_count": 0,
		"effect_count": 0,
	}


func load_scope(region_key: Vector2i) -> Dictionary:
	var load_started_usec := Time.get_ticks_usec()
	if not initialized:
		return _failure("effect_projection_service_not_initialized")
	var scope_id := Contract.scope_id_for_region(region_key)
	if _scopes.has(scope_id):
		var existing: Dictionary = _scopes[scope_id]
		return {
			"ok": true,
			"found": int(_storage_generations.get(scope_id, 0)) > 0,
			"already_loaded": true,
			"generation": int(_storage_generations.get(scope_id, 0)),
			"projection_revision": int(existing["projection_revision"]),
			"source_world_revision": int(existing["source_world_revision"]),
			"effect_count": (existing["effects"] as Dictionary).size(),
			"recovered_temporary": false,
		}
	if _scopes.size() >= MAX_RESIDENT_SCOPES:
		return _failure("effect_projection_resident_scope_capacity_exceeded")
	var loaded: Dictionary = store.load_scope(region_key)
	if not loaded.get("ok", false):
		return loaded
	var checked := Contract.validate_snapshot(
		loaded.get("snapshot"),
		world_id,
		world_seed,
		generator_version,
		region_key
	)
	if not checked.get("ok", false):
		return checked
	var index_result := _build_scope_index(checked["snapshot"])
	if not index_result.get("ok", false):
		return index_result
	_scopes[scope_id] = checked["snapshot"]
	_install_scope_index(scope_id, index_result["index"])
	_storage_generations[scope_id] = int(loaded.get("generation", 0))
	_performance["scope_load_count"] = int(_performance["scope_load_count"]) + 1
	_performance["peak_resident_scope_count"] = maxi(
		int(_performance["peak_resident_scope_count"]), _scopes.size()
	)
	var load_duration_usec := Time.get_ticks_usec() - load_started_usec
	if _perf_trace_enabled and load_duration_usec >= PerformanceTrace.min_usec():
		PerformanceTrace.emit("effect_scope_load", {
			"duration_usec": load_duration_usec,
			"scope_id": scope_id,
			"region": [region_key.x, region_key.y],
			"found": bool(loaded.get("found", false)),
			"generation": int(loaded.get("generation", 0)),
			"effect_count": (checked["snapshot"]["effects"] as Dictionary).size(),
			"resident_scope_count": _scopes.size(),
		})
	return {
		"ok": true,
		"found": bool(loaded.get("found", false)),
		"already_loaded": false,
		"generation": int(loaded.get("generation", 0)),
		"projection_revision": int(checked["snapshot"]["projection_revision"]),
		"source_world_revision": int(checked["snapshot"]["source_world_revision"]),
		"effect_count": (checked["snapshot"]["effects"] as Dictionary).size(),
		"recovered_temporary": bool(loaded.get("recovered_temporary", false)),
		"ignored_incomplete_generations": int(
			loaded.get("ignored_incomplete_generations", 0)
		),
		"legacy_rebuild_required": bool(
			loaded.get("legacy_rebuild_required", false)
		),
	}


func release_scope(region_key: Vector2i) -> void:
	var scope_id := Contract.scope_id_for_region(region_key)
	if not _scopes.has(scope_id):
		return
	_remove_scope_routes(scope_id)
	_scopes.erase(scope_id)
	_scope_indexes.erase(scope_id)
	_storage_generations.erase(scope_id)
	_performance["scope_release_count"] = int(_performance["scope_release_count"]) + 1


func reconcile_scope(
	region_key: Vector2i,
	source_world_revision: int,
	authoritative_instances: Array,
	source_revisions: Dictionary,
	allow_authoritative_rewind: bool = false,
	persist_projection: bool = true
) -> Dictionary:
	var started_usec := Time.get_ticks_usec()
	if not initialized:
		return _failure("effect_projection_service_not_initialized")
	if source_world_revision < 0 or source_world_revision > Contract.MAX_REVISION:
		return _failure("effect_projection_source_world_revision_invalid")
	var loaded := load_scope(region_key)
	if not loaded.get("ok", false):
		return loaded
	var scope_id := Contract.scope_id_for_region(region_key)
	var prior: Dictionary = _scopes[scope_id]
	var prior_source_world_revision := int(prior["source_world_revision"])
	if source_world_revision < prior_source_world_revision:
		if not allow_authoritative_rewind:
			return _failure("effect_projection_stale_scope_revision")
		# The projection is derived. When the caller explicitly identifies its
		# source snapshot as the current authority (e.g. loading/rolling back an
		# older authoritative save), discard the ahead derived contents and
		# commit a new projection generation from that authority. Keep the
		# projection revision monotonic for diagnostics.
		var prior_projection_revision := int(prior["projection_revision"])
		prior = Contract.empty_snapshot(
			world_id, world_seed, generator_version, region_key
		)
		prior["projection_revision"] = prior_projection_revision

	var ordered_instances := authoritative_instances.duplicate(true)
	ordered_instances.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.get("instance_id", "")) < String(b.get("instance_id", ""))
	)
	var incoming_effects: Dictionary = {}
	var incoming_frames: Dictionary = {}
	var source_instance_ids: Array[String] = []
	var source_digest_entries: Array[Dictionary] = []
	var seen_sources: Dictionary = {}
	for instance_value in ordered_instances:
		if typeof(instance_value) != TYPE_DICTIONARY:
			return _failure("effect_projection_source_not_dictionary")
		var instance: Dictionary = instance_value
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
		if source_revision > source_world_revision:
			return _failure("effect_projection_source_revision_ahead")
		source_instance_ids.append(instance_id)
		var interaction: Dictionary = instance.get("terrain_interaction", {})
		if interaction.is_empty():
			source_digest_entries.append({
				"instance_id": instance_id,
				"source_revision": source_revision,
				"content_pin_sha256": Contract.canonical_sha256(
					instance.get("content_pin", {})
				),
				"terrain_interaction": "none",
			})
			continue
		var built := Effect.build_from_instance(instance, source_revision)
		if not built.get("ok", false):
			return _failure(
				"effect_projection_effect_build_failed:%s" 					% built.get("reason", "unknown")
			)
		var effect: Dictionary = built["effect"]
		var effect_id := String(effect["effect_id"])
		if incoming_effects.has(effect_id):
			return _failure("effect_projection_effect_identity_collision")
		var existing: Dictionary = (prior["effects"] as Dictionary).get(effect_id, {})
		if not existing.is_empty():
			var existing_revision := int(existing["source_revision"])
			if source_revision < existing_revision:
				return _failure("effect_projection_stale_source_revision")
			if source_revision == existing_revision 				and String(effect["source_fingerprint_sha256"]) 					!= String(existing["source_fingerprint_sha256"]):
				return _failure(
					"effect_projection_same_revision_fingerprint_conflict"
				)
		incoming_effects[effect_id] = effect
		var built_frame := LocalFrame.build_from_instance(
			instance,
			effect,
			source_revision,
			built.get("shape_descriptor", {})
		)
		if not built_frame.get("ok", false):
			return _failure(
				"effect_projection_frame_build_failed:%s" 					% built_frame.get("reason", "unknown")
			)
		var frame: Dictionary = built_frame["frame"]
		incoming_frames[effect_id] = frame
		source_digest_entries.append({
			"instance_id": instance_id,
			"source_revision": source_revision,
			"effect_id": effect_id,
			"source_fingerprint_sha256": String(
				effect["source_fingerprint_sha256"]
			),
			"sampling_frame_sha256": String(frame["frame_sha256"]),
		})

	source_instance_ids.sort()
	source_digest_entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.get("instance_id", "")) < String(b.get("instance_id", ""))
	)
	var source_digest := Contract.source_digest(
		scope_id,
		region_key,
		source_world_revision,
		source_digest_entries
	)
	copy_conflict_usec = Time.get_ticks_usec() - copy_conflict_started_usec
	if int(prior["source_world_revision"]) == source_world_revision 		and String(prior["source_digest_sha256"]) == source_digest 		and prior["source_instance_ids"] == source_instance_ids:
		last_reconcile_metrics = {
			"scope_id": scope_id,
			"changed": false,
			"source_count": source_instance_ids.size(),
			"effect_count": incoming_effects.size(),
			"removed_effect_count": 0,
			"duration_usec": Time.get_ticks_usec() - started_usec,
		}
		return {
			"ok": true,
			"changed": false,
			"reason": "already_current",
			"scope_id": scope_id,
			"generation": int(_storage_generations.get(scope_id, 0)),
			"projection_revision": int(prior["projection_revision"]),
			"source_world_revision": source_world_revision,
			"effect_count": incoming_effects.size(),
			"removed_effect_count": 0,
		}

	var removed_effect_count := 0
	for prior_effect_id in (prior["effects"] as Dictionary):
		if not incoming_effects.has(String(prior_effect_id)):
			removed_effect_count += 1
	var candidate := {
		"schema_version": Contract.SCHEMA_VERSION,
		"world_id": world_id,
		"world_seed": world_seed,
		"generator_version": generator_version,
		"scope_id": scope_id,
		"region_key": [region_key.x, region_key.y],
		"projection_revision": int(prior["projection_revision"]) + 1,
		"source_world_revision": source_world_revision,
		"source_digest_sha256": source_digest,
		"source_instance_ids": source_instance_ids,
		"effects": incoming_effects,
		"local_frames": incoming_frames,
	}
	var checked := Contract.validate_snapshot(
		candidate, world_id, world_seed, generator_version, region_key
	)
	if not checked.get("ok", false):
		return checked
	var index_result := _build_scope_index(checked["snapshot"])
	if not index_result.get("ok", false):
		return index_result
	var generation := int(_storage_generations.get(scope_id, 0))
	if persist_projection:
		var persisted: Dictionary = store.save_validated_snapshot(checked["snapshot"])
		if not persisted.get("ok", false):
			# The write may have become durable before failure was observable. Force
			# a full service reinitialize so no second mutation can build on an
			# uncertain generation.
			initialized = false
			initialization_error = String(
				persisted.get("reason", "effect_projection_persist_failed")
			)
			return _failure(
				"effect_projection_commit_uncertain:%s" % initialization_error
			)
		generation = int(persisted["generation"])

	# A transient publication is safe because projection state is derived. The
	# authoritative entity/object state remains durable; after a crash or release
	# this scope can be rebuilt exactly. Lifecycle mutations still use the
	# crash-consistent persisted path.
	var publish_routes_started_usec := Time.get_ticks_usec()
	_scopes[scope_id] = checked["snapshot"]
	_install_scope_index(scope_id, index_result["index"])
	_storage_generations[scope_id] = generation
	publish_routes_usec = Time.get_ticks_usec() - publish_routes_started_usec
	last_reconcile_metrics = {
		"scope_id": scope_id,
		"changed": true,
		"persisted": persist_projection,
		"source_count": source_instance_ids.size(),
		"effect_count": incoming_effects.size(),
		"removed_effect_count": removed_effect_count,
		"duration_usec": Time.get_ticks_usec() - started_usec,
		"load_usec": load_usec,
		"copy_conflict_usec": copy_conflict_usec,
		"validate_usec": validate_usec,
		"index_usec": index_usec,
		"persist_usec": persist_usec,
		"publish_routes_usec": publish_routes_usec,
	}
	if _perf_trace_enabled and (
		int(last_reconcile_metrics["duration_usec"]) >= PerformanceTrace.min_usec()
		or persist_projection
	):
		var trace_payload := last_reconcile_metrics.duplicate(true)
		trace_payload["region"] = [region_key.x, region_key.y]
		trace_payload["resident_scope_count"] = _scopes.size()
		PerformanceTrace.emit("effect_projection_reconcile", trace_payload)
	return {
		"ok": true,
		"changed": true,
		"persisted": persist_projection,
		"reason": "committed" if persist_projection else "transient_current",
		"scope_id": scope_id,
		"generation": generation,
		"projection_revision": int(checked["snapshot"]["projection_revision"]),
		"source_world_revision": source_world_revision,
		"effect_count": incoming_effects.size(),
		"removed_effect_count": removed_effect_count,
	}


func reconcile_prebuilt_scope(
	region_key: Vector2i,
	prebuilt: Dictionary,
	allow_authoritative_rewind: bool = false,
	persist_projection: bool = true
) -> Dictionary:
	var started_usec := Time.get_ticks_usec()
	var load_usec := 0
	var copy_conflict_usec := 0
	var validate_usec := 0
	var index_usec := 0
	var persist_usec := 0
	var publish_routes_usec := 0
	if not initialized:
		return _failure("effect_projection_service_not_initialized")
	if not prebuilt.get("ok", false) 		or prebuilt.get("region_key", Vector2i(2147483647, 2147483647)) 			!= region_key:
		return _failure("effect_projection_prebuilt_invalid")
	var source_world_revision := int(
		prebuilt.get("source_world_revision", -1)
	)
	if source_world_revision < 0 		or source_world_revision > Contract.MAX_REVISION:
		return _failure("effect_projection_source_world_revision_invalid")
	if typeof(prebuilt.get("effects")) != TYPE_DICTIONARY 		or typeof(prebuilt.get("local_frames")) != TYPE_DICTIONARY 		or typeof(prebuilt.get("source_instance_ids")) != TYPE_ARRAY 		or typeof(prebuilt.get("source_digest_sha256")) != TYPE_STRING:
		return _failure("effect_projection_prebuilt_fields_invalid")

	var load_started_usec := Time.get_ticks_usec()
	var loaded := load_scope(region_key)
	load_usec = Time.get_ticks_usec() - load_started_usec
	if not loaded.get("ok", false):
		return loaded
	var scope_id := Contract.scope_id_for_region(region_key)
	var prior: Dictionary = _scopes[scope_id]
	var prior_source_world_revision := int(prior["source_world_revision"])
	if source_world_revision < prior_source_world_revision:
		if not allow_authoritative_rewind:
			return _failure("effect_projection_stale_scope_revision")
		var prior_projection_revision := int(prior["projection_revision"])
		prior = Contract.empty_snapshot(
			world_id, world_seed, generator_version, region_key
		)
		prior["projection_revision"] = prior_projection_revision

	var copy_conflict_started_usec := Time.get_ticks_usec()
	var incoming_effects: Dictionary = (
		prebuilt["effects"] as Dictionary
	).duplicate(true)
	var incoming_frames: Dictionary = (
		prebuilt["local_frames"] as Dictionary
	).duplicate(true)
	var source_instance_ids: Array = (
		prebuilt["source_instance_ids"] as Array
	).duplicate()
	var source_digest := String(prebuilt["source_digest_sha256"])

	for effect_id_value in incoming_effects:
		var effect_id := String(effect_id_value)
		if not incoming_frames.has(effect_id):
			return _failure("effect_projection_prebuilt_frame_missing")
		var effect: Dictionary = incoming_effects[effect_id]
		var existing: Dictionary = (
			prior["effects"] as Dictionary
		).get(effect_id, {})
		if existing.is_empty():
			continue
		var source_revision := int(effect.get("source_revision", -1))
		var existing_revision := int(existing["source_revision"])
		if source_revision < existing_revision:
			return _failure("effect_projection_stale_source_revision")
		if source_revision == existing_revision 			and String(effect.get("source_fingerprint_sha256", "")) 				!= String(existing["source_fingerprint_sha256"]):
			return _failure(
				"effect_projection_same_revision_fingerprint_conflict"
			)

	if int(prior["source_world_revision"]) == source_world_revision 		and String(prior["source_digest_sha256"]) == source_digest 		and prior["source_instance_ids"] == source_instance_ids:
		last_reconcile_metrics = {
			"scope_id": scope_id,
			"changed": false,
			"prebuilt": true,
			"source_count": source_instance_ids.size(),
			"effect_count": incoming_effects.size(),
			"removed_effect_count": 0,
			"duration_usec": Time.get_ticks_usec() - started_usec,
		}
		return {
			"ok": true,
			"changed": false,
			"reason": "already_current",
			"scope_id": scope_id,
			"generation": int(_storage_generations.get(scope_id, 0)),
			"projection_revision": int(prior["projection_revision"]),
			"source_world_revision": source_world_revision,
			"effect_count": incoming_effects.size(),
			"removed_effect_count": 0,
		}

	var removed_effect_count := 0
	for prior_effect_id in (prior["effects"] as Dictionary):
		if not incoming_effects.has(String(prior_effect_id)):
			removed_effect_count += 1
	var candidate := {
		"schema_version": Contract.SCHEMA_VERSION,
		"world_id": world_id,
		"world_seed": world_seed,
		"generator_version": generator_version,
		"scope_id": scope_id,
		"region_key": [region_key.x, region_key.y],
		"projection_revision": int(prior["projection_revision"]) + 1,
		"source_world_revision": source_world_revision,
		"source_digest_sha256": source_digest,
		"source_instance_ids": source_instance_ids,
		"effects": incoming_effects,
		"local_frames": incoming_frames,
	}
	var validate_started_usec := Time.get_ticks_usec()
	var checked := Contract.validate_snapshot(
		candidate, world_id, world_seed, generator_version, region_key
	)
	validate_usec = Time.get_ticks_usec() - validate_started_usec
	if not checked.get("ok", false):
		return checked
	var index_started_usec := Time.get_ticks_usec()
	var index_result := _build_scope_index(checked["snapshot"])
	index_usec = Time.get_ticks_usec() - index_started_usec
	if not index_result.get("ok", false):
		return index_result

	var generation := int(_storage_generations.get(scope_id, 0))
	if persist_projection:
		var persist_started_usec := Time.get_ticks_usec()
		var persisted: Dictionary = store.save_validated_snapshot(
			checked["snapshot"]
		)
		persist_usec = Time.get_ticks_usec() - persist_started_usec
		if not persisted.get("ok", false):
			initialized = false
			initialization_error = String(
				persisted.get("reason", "effect_projection_persist_failed")
			)
			return _failure(
				"effect_projection_commit_uncertain:%s" 					% initialization_error
			)
		generation = int(persisted["generation"])

	_scopes[scope_id] = checked["snapshot"]
	_install_scope_index(scope_id, index_result["index"])
	_storage_generations[scope_id] = generation
	last_reconcile_metrics = {
		"scope_id": scope_id,
		"changed": true,
		"prebuilt": true,
		"persisted": persist_projection,
		"source_count": source_instance_ids.size(),
		"effect_count": incoming_effects.size(),
		"removed_effect_count": removed_effect_count,
		"duration_usec": Time.get_ticks_usec() - started_usec,
	}
	return {
		"ok": true,
		"changed": true,
		"persisted": persist_projection,
		"reason": "committed" if persist_projection else "transient_current",
		"scope_id": scope_id,
		"generation": generation,
		"projection_revision": int(checked["snapshot"]["projection_revision"]),
		"source_world_revision": source_world_revision,
		"effect_count": incoming_effects.size(),
		"removed_effect_count": removed_effect_count,
	}


## Read-only adapter over authoritative entity/object state.
func reconcile_command_region(
	region_key: Vector2i,
	command_service: RefCounted
) -> Dictionary:
	if not initialized:
		return _failure("effect_projection_service_not_initialized")
	if command_service == null 		or not command_service.has_method("get_region_base_instances") 		or not command_service.has_method("resolve_entity"):
		return _failure("effect_projection_command_service_invalid")
	var authoritative_state_service: Variant = command_service.get("state_service")
	if authoritative_state_service == null 		or not authoritative_state_service.has_method("get_revision") 		or not authoritative_state_service.has_method("get_entity_revision"):
		return _failure("effect_projection_state_service_invalid")
	var source_world_revision := int(
		authoritative_state_service.call("get_revision")
	)
	var base_instances_value: Variant = command_service.call(
		"get_region_base_instances", region_key
	)
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
		var resolved_value: Variant = command_service.call(
			"resolve_entity", instance_id
		)
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
			return _failure(
				"effect_projection_region_effective_instance_invalid"
			)
		active_instances.append(
			(resolved["instance"] as Dictionary).duplicate(true)
		)
		source_revisions[instance_id] = int(
			authoritative_state_service.call(
				"get_entity_revision", instance_id
			)
		)
	return reconcile_scope(
		region_key,
		source_world_revision,
		active_instances,
		source_revisions
	)


func get_scope_status(
	region_key: Vector2i,
	authoritative_world_revision: int
) -> Dictionary:
	if not initialized:
		return _failure("effect_projection_service_not_initialized")
	var scope_id := Contract.scope_id_for_region(region_key)
	if not _scopes.has(scope_id):
		return {
			"ok": true,
			"status": "unloaded",
			"scope_id": scope_id,
			"authoritative_world_revision": authoritative_world_revision,
		}
	var scope: Dictionary = _scopes[scope_id]
	var projected := int(scope["source_world_revision"])
	var status := "current" if projected == authoritative_world_revision 		else "stale" if projected < authoritative_world_revision 		else "ahead"
	return {
		"ok": true,
		"status": status,
		"scope_id": scope_id,
		"projected_source_world_revision": projected,
		"authoritative_world_revision": authoritative_world_revision,
		"effect_count": (scope["effects"] as Dictionary).size(),
	}


func get_scope_snapshot(region_key: Vector2i) -> Dictionary:
	var scope_id := Contract.scope_id_for_region(region_key)
	return (_scopes.get(scope_id, {}) as Dictionary).duplicate(true)


func storage_generation_for_scope(region_key: Vector2i) -> int:
	return int(_storage_generations.get(
		Contract.scope_id_for_region(region_key), 0
	))


func get_scope_indexed_chunk_ids(region_key: Vector2i) -> Array[String]:
	var scope_id := Contract.scope_id_for_region(region_key)
	if not _scope_indexes.has(scope_id):
		return []
	return _scope_indexes[scope_id].get_all_indexed_chunk_ids()


func get_loaded_scope_ids() -> Array[String]:
	var ids: Array[String] = []
	for scope_id in _scopes:
		ids.append(String(scope_id))
	ids.sort()
	return ids


func get_loaded_scope_count() -> int:
	return _scopes.size()


func get_effect_count() -> int:
	var count := 0
	for scope in _scopes.values():
		count += ((scope as Dictionary)["effects"] as Dictionary).size()
	return count


## Returns precision-safe local sampling frames from every resident source scope
## whose conservative local bounds touch the requested chunk.
func get_frames_for_chunk(
	region_key: Vector2i,
	chunk_coordinate: Vector2i
) -> Array[Dictionary]:
	if not initialized or not Grid.is_valid_coordinate(chunk_coordinate):
		return []
	var chunk_id := Grid.stable_id(region_key, chunk_coordinate)
	var scope_ids: Array = _scope_ids_by_chunk.get(chunk_id, [])
	_performance["snapshot_call_count"] = int(_performance["snapshot_call_count"]) + 1
	_performance["lookup_scope_index_examined_count"] = int(
		_performance["lookup_scope_index_examined_count"]
	) + scope_ids.size()
	var by_id: Dictionary = {}
	for scope_id_value in scope_ids:
		var scope_id := String(scope_id_value)
		if not _scope_indexes.has(scope_id):
			continue
		var scope_index: RefCounted = _scope_indexes[scope_id]
		for frame in scope_index.get_frames_for_chunk(
			region_key, chunk_coordinate
		):
			by_id[String(frame["effect_id"])] = frame
	var ids: Array[String] = []
	for effect_id in by_id:
		ids.append(String(effect_id))
	ids.sort()
	var result: Array[Dictionary] = []
	for effect_id in ids:
		result.append((by_id[effect_id] as Dictionary).duplicate(true))
	_performance["lookup_frame_count"] = int(_performance["lookup_frame_count"]) + result.size()
	return result


func snapshot_for_chunk(
	region_key: Vector2i,
	chunk_coordinate: Vector2i
) -> Dictionary:
	if not initialized:
		return _failure("effect_projection_service_not_initialized")
	var frames := get_frames_for_chunk(region_key, chunk_coordinate)
	var effect_ids: Array[String] = []
	var frame_hashes: Array[String] = []
	for frame in frames:
		effect_ids.append(String(frame["effect_id"]))
		frame_hashes.append(String(frame["frame_sha256"]))
	return {
		"ok": true,
		"region_key": region_key,
		"chunk_coordinate": chunk_coordinate,
		"local_frames": frames,
		"effect_count": frames.size(),
		"routed_scope_count": (
			_scope_ids_by_chunk.get(
				Grid.stable_id(region_key, chunk_coordinate), []
			) as Array
		).size(),
		"snapshot_sha256": Contract.canonical_sha256({
			"region_key": [region_key.x, region_key.y],
			"chunk_coordinate": [chunk_coordinate.x, chunk_coordinate.y],
			"effect_ids": effect_ids,
			"frame_hashes": frame_hashes,
		}),
	}


func has_scope(region_key: Vector2i) -> bool:
	return _scopes.has(Contract.scope_id_for_region(region_key))


func get_performance_snapshot() -> Dictionary:
	var result := _performance.duplicate(true)
	result["resident_scope_count"] = _scopes.size()
	result["reverse_route_chunk_count"] = _scope_ids_by_chunk.size()
	result["max_resident_scope_count"] = MAX_RESIDENT_SCOPES
	return result


func reset_performance_metrics() -> void:
	_reset_performance_metrics()


func _reset_performance_metrics() -> void:
	_performance = {
		"scope_load_count": 0,
		"scope_release_count": 0,
		"scope_route_install_count": 0,
		"snapshot_call_count": 0,
		"lookup_scope_index_examined_count": 0,
		"lookup_frame_count": 0,
		"peak_resident_scope_count": _scopes.size(),
	}


func _install_scope_index(scope_id: String, index: RefCounted) -> void:
	_remove_scope_routes(scope_id)
	_scope_indexes[scope_id] = index
	for chunk_id_value in index.get_all_indexed_chunk_ids():
		var chunk_id := String(chunk_id_value)
		var ids: Array = _scope_ids_by_chunk.get(chunk_id, [])
		if not ids.has(scope_id):
			ids.append(scope_id)
			ids.sort()
			_scope_ids_by_chunk[chunk_id] = ids
	_performance["scope_route_install_count"] = int(
		_performance["scope_route_install_count"]
	) + 1


func _remove_scope_routes(scope_id: String) -> void:
	if not _scope_indexes.has(scope_id):
		return
	var index: RefCounted = _scope_indexes[scope_id]
	for chunk_id_value in index.get_all_indexed_chunk_ids():
		var chunk_id := String(chunk_id_value)
		var ids: Array = _scope_ids_by_chunk.get(chunk_id, [])
		ids.erase(scope_id)
		if ids.is_empty():
			_scope_ids_by_chunk.erase(chunk_id)
		else:
			_scope_ids_by_chunk[chunk_id] = ids


func _source_revision(
	source_revisions: Dictionary,
	instance_id: String
) -> Dictionary:
	if not source_revisions.has(instance_id):
		return _failure("effect_projection_source_revision_missing")
	var value: Variant = source_revisions[instance_id]
	if not _is_integer(value) 		or int(value) < 0 		or int(value) > Contract.MAX_REVISION:
		return _failure("effect_projection_source_revision_invalid")
	return {"ok": true, "revision": int(value)}


func _build_scope_index(scope_snapshot: Dictionary) -> Dictionary:
	var candidate_index := LocalFrameIndex.new()
	var effect_ids: Array[String] = []
	for effect_id_value in (scope_snapshot["local_frames"] as Dictionary):
		effect_ids.append(String(effect_id_value))
	effect_ids.sort()
	for effect_id in effect_ids:
		var indexed: Dictionary = candidate_index.replace_frame_prevalidated(
			scope_snapshot["local_frames"][effect_id]
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
