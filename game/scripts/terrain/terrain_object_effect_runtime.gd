class_name TerrainObjectEffectRuntime
extends RefCounted

## Main-thread bridge from authoritative entity/object state to immutable
## terrain-worker effect snapshots. It owns an independent read-only command
## reconstruction service so terrain projection residency cannot disturb object
## streaming reconstruction state.
const ProjectionService := preload("res://scripts/terrain/terrain_object_effect_projection_service.gd")
const CommandService := preload("res://scripts/entities/entity_command_service.gd")
const ObjectWorld := preload("res://scripts/objects/procedural_object_world.gd")
const EffectIndex := preload("res://scripts/terrain/terrain_object_effect_index.gd")
const Grid := preload("res://scripts/terrain/terrain_chunk_grid.gd")
const ProjectionContract := preload("res://scripts/terrain/terrain_object_effect_projection_contract.gd")

const SOURCE_REGION_REACH := 1
const RESIDENT_TRIM_RADIUS := 3

var initialized := false
var initialization_error := ""
var authoritative_state_service: RefCounted
var registry: RefCounted
var command_service: RefCounted
var projection: RefCounted
var last_snapshot_metrics: Dictionary = {}


func initialize(
	world_id: String,
	world_seed: int,
	generator_version: int,
	state_service: RefCounted,
	content_registry: RefCounted,
	directory_override: String = ""
) -> Dictionary:
	initialized = false
	initialization_error = ""
	if state_service == null or content_registry == null:
		return _fail_initialize("terrain_effect_runtime_dependencies_missing")
	authoritative_state_service = state_service
	registry = content_registry
	command_service = null
	var command_candidate := CommandService.new()
	var command_init: Dictionary = command_candidate.initialize(
		authoritative_state_service, registry
	)
	if command_init.get("ok", false):
		command_service = command_candidate
	elif command_init.get("reason") != "command_snapshot_migration_required":
		return _fail_initialize(
			"terrain_effect_runtime_command_service_failed:%s" 				% command_init.get("reason", "unknown")
		)
	# Schema-1 worlds still have procedural/override authority. Until the
	# explicit command-schema migration occurs, projection reconstruction uses
	# ObjectWorld + state_service.resolve_instance and contains no placed
	# entities. The command service is retried lazily after migration.
	projection = ProjectionService.new()
	var projection_init: Dictionary = projection.initialize(
		world_id, world_seed, generator_version, directory_override
	)
	if not projection_init.get("ok", false):
		return _fail_initialize(
			"terrain_effect_runtime_projection_failed:%s" 				% projection_init.get("reason", "unknown")
		)
	initialized = true
	return {
		"ok": true,
		"source_region_reach": SOURCE_REGION_REACH,
		"resident_trim_radius": RESIDENT_TRIM_RADIUS,
	}


func snapshot_for_chunk(
	region_key: Vector2i,
	chunk_coordinate: Vector2i
) -> Dictionary:
	return snapshot_for_requests([
		{"region_key": region_key, "coordinate": chunk_coordinate},
	])


func snapshot_for_requests(requests: Array) -> Dictionary:
	var started_usec := Time.get_ticks_usec()
	if not initialized:
		return _failure("terrain_effect_runtime_not_initialized")
	if requests.is_empty():
		return _empty_snapshot([])
	var normalized_requests: Array[Dictionary] = []
	var target_regions: Dictionary = {}
	for request_value in requests:
		if typeof(request_value) != TYPE_DICTIONARY:
			return _failure("terrain_effect_runtime_request_invalid")
		var request: Dictionary = request_value
		if not request.get("region_key") is Vector2i 			or not request.get("coordinate") is Vector2i:
			return _failure("terrain_effect_runtime_request_invalid")
		var region_key: Vector2i = request["region_key"]
		var coordinate: Vector2i = request["coordinate"]
		if not Grid.is_valid_coordinate(coordinate):
			return _failure("terrain_effect_runtime_chunk_invalid")
		normalized_requests.append({
			"region_key": region_key,
			"coordinate": coordinate,
		})
		target_regions[_region_id(region_key)] = region_key
	normalized_requests.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ar: Vector2i = a["region_key"]
		var br: Vector2i = b["region_key"]
		if ar.y != br.y:
			return ar.y < br.y
		if ar.x != br.x:
			return ar.x < br.x
		var ac: Vector2i = a["coordinate"]
		var bc: Vector2i = b["coordinate"]
		return ac.y < bc.y if ac.y != bc.y else ac.x < bc.x
	)

	# Requests in one shared-surface snapshot are adjacent. Trim against their
	# bounding region set before loading the 1-region source halo.
	_trim_resident_scopes(target_regions.values())
	var needed_sources: Dictionary = {}
	for region_value in target_regions.values():
		var target: Vector2i = region_value
		for dz in range(-SOURCE_REGION_REACH, SOURCE_REGION_REACH + 1):
			for dx in range(-SOURCE_REGION_REACH, SOURCE_REGION_REACH + 1):
				var source := target + Vector2i(dx, dz)
				needed_sources[_region_id(source)] = source
	var source_ids: Array[String] = []
	for source_id_value in needed_sources:
		source_ids.append(String(source_id_value))
	source_ids.sort()
	for source_id in source_ids:
		var ensured := _ensure_source_scope(needed_sources[source_id])
		if not ensured.get("ok", false):
			return ensured

	var by_id: Dictionary = {}
	var request_rows: Array[Dictionary] = []
	for request in normalized_requests:
		var region_key: Vector2i = request["region_key"]
		var coordinate: Vector2i = request["coordinate"]
		var chunk_snapshot: Dictionary = projection.snapshot_for_chunk(
			region_key, coordinate
		)
		if not chunk_snapshot.get("ok", false):
			return chunk_snapshot
		request_rows.append({
			"region_key": [region_key.x, region_key.y],
			"coordinate": [coordinate.x, coordinate.y],
			"snapshot_sha256": String(chunk_snapshot["snapshot_sha256"]),
		})
		for effect_value in chunk_snapshot["effects"]:
			var effect: Dictionary = effect_value
			by_id[String(effect["effect_id"])] = effect
	var effect_ids: Array[String] = []
	for effect_id_value in by_id:
		effect_ids.append(String(effect_id_value))
	effect_ids.sort()
	var effects: Array[Dictionary] = []
	var fingerprints: Array[String] = []
	for effect_id in effect_ids:
		var effect: Dictionary = by_id[effect_id]
		effects.append(effect.duplicate(true))
		fingerprints.append(String(effect["source_fingerprint_sha256"]))
	var source_world_revision := int(authoritative_state_service.call("get_revision"))
	var snapshot_sha := ProjectionContract.canonical_sha256({
		"schema_version": 1,
		"source_world_revision": source_world_revision,
		"requests": request_rows,
		"effect_ids": effect_ids,
		"fingerprints": fingerprints,
	})
	last_snapshot_metrics = {
		"request_count": normalized_requests.size(),
		"source_scope_count": source_ids.size(),
		"effect_count": effects.size(),
		"source_world_revision": source_world_revision,
		"duration_usec": Time.get_ticks_usec() - started_usec,
	}
	return {
		"ok": true,
		"source_world_revision": source_world_revision,
		"effects": effects,
		"effect_count": effects.size(),
		"snapshot_sha256": snapshot_sha,
		"requests": normalized_requests,
	}


func attach_to_terrain_snapshot(
	terrain_snapshot: Dictionary,
	requests: Array
) -> Dictionary:
	if not bool(terrain_snapshot.get("valid", true)):
		return terrain_snapshot
	var effect_snapshot := snapshot_for_requests(requests)
	if not effect_snapshot.get("ok", false):
		var invalid := terrain_snapshot.duplicate(true)
		invalid["valid"] = false
		invalid["storage_error"] = String(
			effect_snapshot.get("reason", "terrain_object_effect_snapshot_failed")
		)
		return invalid
	var result := terrain_snapshot.duplicate(true)
	result["terrain_object_effects"] = (
		effect_snapshot["effects"] as Array
	).duplicate(true)
	result["terrain_object_effect_snapshot_sha256"] = String(
		effect_snapshot["snapshot_sha256"]
	)
	result["terrain_object_effect_source_world_revision"] = int(
		effect_snapshot["source_world_revision"]
	)
	result["terrain_object_effect_count"] = int(
		effect_snapshot["effect_count"]
	)
	return result


func is_snapshot_current(snapshot: Dictionary) -> bool:
	if not initialized:
		return false
	return int(
		snapshot.get("terrain_object_effect_source_world_revision", -1)
	) == int(authoritative_state_service.call("get_revision"))


func reconcile_source_region(region_key: Vector2i) -> Dictionary:
	if not initialized:
		return _failure("terrain_effect_runtime_not_initialized")
	var loaded: Dictionary = projection.load_scope(region_key)
	if not loaded.get("ok", false):
		return loaded
	var before: Dictionary = projection.get_scope_snapshot(region_key)
	var before_chunks := _indexed_chunks_for_scope(before)
	var reconciled: Dictionary = _reconcile_region_from_authority(region_key)
	if not reconciled.get("ok", false):
		return reconciled
	var after: Dictionary = projection.get_scope_snapshot(region_key)
	var after_chunks := _indexed_chunks_for_scope(after)
	var affected: Dictionary = {}
	for descriptor in before_chunks:
		affected[_chunk_id(descriptor)] = descriptor
	for descriptor in after_chunks:
		affected[_chunk_id(descriptor)] = descriptor
	var ids: Array[String] = []
	for id_value in affected:
		ids.append(String(id_value))
	ids.sort()
	var affected_chunks: Array[Dictionary] = []
	for id in ids:
		affected_chunks.append((affected[id] as Dictionary).duplicate(true))
	return {
		"ok": true,
		"changed": bool(reconciled.get("changed", false)),
		"region_key": region_key,
		"source_world_revision": int(
			authoritative_state_service.call("get_revision")
		),
		"projection_revision": int(
			after.get("projection_revision", 0)
		),
		"affected_chunks": affected_chunks,
		"affected_chunk_count": affected_chunks.size(),
		"effect_count": (after.get("effects", {}) as Dictionary).size(),
	}


func release_far_scopes(focus_region: Vector2i) -> void:
	if not initialized:
		return
	var retained_targets: Array = [focus_region]
	_trim_resident_scopes(retained_targets)


func get_resident_effects_for_chunk(
	region_key: Vector2i,
	chunk_coordinate: Vector2i
) -> Array[Dictionary]:
	if not initialized or not Grid.is_valid_coordinate(chunk_coordinate):
		return []
	return projection.get_effects_for_chunk(region_key, chunk_coordinate)


func get_resident_effects_for_point(
	region_key: Vector2i,
	local_position: Vector3
) -> Array[Dictionary]:
	if not initialized or not local_position.is_finite():
		return []
	var chunk_width := float(Grid.CELLS_PER_CHUNK_X) * Grid.SAMPLE_STEP
	var chunk_depth := float(Grid.CELLS_PER_CHUNK_Z) * Grid.SAMPLE_STEP
	var coordinate := Vector2i(
		clampi(floori(local_position.x / chunk_width), 0, Grid.CHUNK_COUNT_X - 1),
		clampi(floori(local_position.z / chunk_depth), 0, Grid.CHUNK_COUNT_Z - 1)
	)
	return projection.get_effects_for_chunk(region_key, coordinate)


func get_loaded_scope_count() -> int:
	return int(projection.get_loaded_scope_count()) if initialized else 0


func get_effect_count() -> int:
	return int(projection.get_effect_count()) if initialized else 0


func _reconcile_region_from_authority(region_key: Vector2i) -> Dictionary:
	if _ensure_command_service():
		var reconstructed: Dictionary = command_service.reconstruct_region(region_key)
		if not reconstructed.get("ok", false):
			return _failure(
				"terrain_effect_runtime_reconstruct_failed:%s" 					% reconstructed.get("reason", "unknown")
			)
		var reconciled: Dictionary = projection.reconcile_command_region(
			region_key, command_service
		)
		command_service.release_region(region_key)
		return reconciled

	var generated: Dictionary = ObjectWorld.build_region_instances(
		int(authoritative_state_service.get("world_seed")),
		String(authoritative_state_service.get("world_id")),
		region_key,
		registry
	)
	if not generated.get("ok", false):
		return _failure(
			"terrain_effect_runtime_generation_failed:%s" 				% generated.get("reason", "unknown")
		)
	var active_instances: Array[Dictionary] = []
	var source_revisions: Dictionary = {}
	for base_value in generated.get("instances", []):
		if typeof(base_value) != TYPE_DICTIONARY:
			return _failure("terrain_effect_runtime_generated_instance_invalid")
		var base: Dictionary = base_value
		var resolved: Dictionary = authoritative_state_service.call(
			"resolve_instance", base
		)
		if not resolved.get("ok", false):
			return _failure(
				"terrain_effect_runtime_resolution_failed:%s" 					% resolved.get("reason", "unknown")
			)
		if bool(resolved.get("deleted", false)):
			continue
		var instance: Dictionary = resolved.get("instance", {})
		var instance_id := String(instance.get("instance_id", ""))
		if instance_id.is_empty():
			return _failure("terrain_effect_runtime_instance_identity_invalid")
		active_instances.append(instance.duplicate(true))
		source_revisions[instance_id] = int(
			authoritative_state_service.call(
				"get_entity_revision", instance_id
			)
		)
	return projection.reconcile_scope(
		region_key,
		int(authoritative_state_service.call("get_revision")),
		active_instances,
		source_revisions
	)


func _ensure_command_service() -> bool:
	if command_service != null and bool(command_service.get("initialized")):
		return true
	var candidate := CommandService.new()
	var initialized_result: Dictionary = candidate.initialize(
		authoritative_state_service, registry
	)
	if not initialized_result.get("ok", false):
		return false
	command_service = candidate
	return true


func _ensure_source_scope(region_key: Vector2i) -> Dictionary:
	var authoritative_revision := int(
		authoritative_state_service.call("get_revision")
	)
	var loaded: Dictionary = projection.load_scope(region_key)
	if not loaded.get("ok", false):
		return loaded
	var status: Dictionary = projection.get_scope_status(
		region_key, authoritative_revision
	)
	# A missing shard is an empty derived cache, not proof that the region has
	# no authoritative interacting sources. Revision zero is therefore not
	# sufficient to classify it as current.
	if bool(loaded.get("found", false)) 		and status.get("status") == "current":
		return {"ok": true, "changed": false, "status": "current"}
	if status.get("status") == "ahead":
		return _failure("terrain_effect_projection_ahead_of_authority")
	return _reconcile_region_from_authority(region_key)


func _trim_resident_scopes(target_regions: Array) -> void:
	if projection == null or target_regions.is_empty():
		return
	for scope_id in projection.get_loaded_scope_ids():
		var region_result := _region_from_scope_id(scope_id)
		if not region_result.get("ok", false):
			continue
		var region: Vector2i = region_result["region_key"]
		var retain := false
		for target_value in target_regions:
			var target: Vector2i = target_value
			if maxi(
				absi(region.x - target.x),
				absi(region.y - target.y)
			) <= RESIDENT_TRIM_RADIUS:
				retain = true
				break
		if not retain:
			projection.release_scope(region)


func _indexed_chunks_for_scope(scope_snapshot: Dictionary) -> Array[Dictionary]:
	if scope_snapshot.is_empty():
		return []
	var index := EffectIndex.new()
	var effects: Dictionary = scope_snapshot.get("effects", {})
	var effect_ids: Array[String] = []
	for effect_id_value in effects:
		effect_ids.append(String(effect_id_value))
	effect_ids.sort()
	for effect_id in effect_ids:
		var indexed: Dictionary = index.replace_effect(effects[effect_id])
		if not indexed.get("ok", false):
			return []
	var by_id: Dictionary = {}
	for effect_id in effect_ids:
		for chunk_id in index.get_indexed_chunk_ids(effect_id):
			var parsed := _parse_chunk_id(chunk_id)
			if parsed.get("ok", false):
				by_id[chunk_id] = {
					"region_key": parsed["region_key"],
					"coordinate": parsed["coordinate"],
				}
	var ids: Array[String] = []
	for id_value in by_id:
		ids.append(String(id_value))
	ids.sort()
	var result: Array[Dictionary] = []
	for id in ids:
		result.append(by_id[id])
	return result


func _parse_chunk_id(value: String) -> Dictionary:
	var split := value.split("/chunk:")
	if split.size() != 2 or not split[0].begins_with("region:"):
		return {"ok": false}
	var region_parts := split[0].trim_prefix("region:").split(",")
	var chunk_parts := split[1].split(",")
	if region_parts.size() != 2 or chunk_parts.size() != 2:
		return {"ok": false}
	var region_key := Vector2i(
		int(region_parts[0]), int(region_parts[1])
	)
	var coordinate := Vector2i(
		int(chunk_parts[0]), int(chunk_parts[1])
	)
	if not Grid.is_valid_coordinate(coordinate):
		return {"ok": false}
	return {
		"ok": true,
		"region_key": region_key,
		"coordinate": coordinate,
	}


func _region_from_scope_id(value: String) -> Dictionary:
	if not value.begins_with("region:"):
		return {"ok": false}
	var parts := value.trim_prefix("region:").split(",")
	if parts.size() != 2:
		return {"ok": false}
	return {
		"ok": true,
		"region_key": Vector2i(int(parts[0]), int(parts[1])),
	}


func _region_id(region_key: Vector2i) -> String:
	return "%d,%d" % [region_key.x, region_key.y]


func _chunk_id(descriptor: Dictionary) -> String:
	return Grid.stable_id(
		descriptor["region_key"], descriptor["coordinate"]
	)


func _empty_snapshot(requests: Array) -> Dictionary:
	var revision := int(authoritative_state_service.call("get_revision")) 		if authoritative_state_service != null else 0
	return {
		"ok": true,
		"source_world_revision": revision,
		"effects": [],
		"effect_count": 0,
		"snapshot_sha256": ProjectionContract.canonical_sha256({
			"schema_version": 1,
			"source_world_revision": revision,
			"requests": requests,
			"effect_ids": [],
			"fingerprints": [],
		}),
		"requests": requests,
	}


func _fail_initialize(reason: String) -> Dictionary:
	initialization_error = reason
	initialized = false
	return _failure(reason)


func _failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
