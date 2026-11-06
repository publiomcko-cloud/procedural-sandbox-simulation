class_name TerrainObjectEffectRuntime
extends RefCounted

## Live Phase-D coordinator. It owns no terrain or entity authority.
## It derives immutable per-job local-frame snapshots from the authoritative
## object stream and the region-sharded projection.
const ProjectionService := preload("res://scripts/terrain/terrain_object_effect_projection_service.gd")
const Contract := preload("res://scripts/terrain/terrain_object_effect_projection_contract.gd")
const Grid := preload("res://scripts/terrain/terrain_chunk_grid.gd")
const LocalFrameIndex := preload("res://scripts/terrain/terrain_object_effect_local_frame_index.gd")

# Public v1 contracts bound horizontal reach:
# translation <= 8 m, half extent <= 1.8 m, scale <= 5x, roughness <= 0.1 m.
# With 16x12 m regions, +/-2 source regions conservatively covers any effect
# that can touch a target chunk, including the chunk-normal halo.
const SOURCE_REGION_RADIUS := 2

var world_id := ""
var world_seed := -1
var generator_version := -1
var object_stream: Node
var projection: RefCounted
var initialized := false
var initialization_error := ""
var last_prepare_metrics: Dictionary = {}
var _invalidated_scope_ids: Dictionary = {}
var _pre_invalidation_frames: Dictionary = {}


func initialize(
	world_identifier: String,
	seed_value: int,
	generator: int,
	object_stream_value: Node,
	directory_override: String = ""
) -> Dictionary:
	initialized = false
	initialization_error = ""
	if object_stream_value == null 		or not object_stream_value.has_method("get_authoritative_region_projection_source") 		or not object_stream_value.has_method("get_command_world_revision"):
		initialization_error = "terrain_effect_runtime_object_stream_invalid"
		return _failure(initialization_error)
	world_id = world_identifier
	world_seed = seed_value
	generator_version = generator
	object_stream = object_stream_value
	_invalidated_scope_ids.clear()
	_pre_invalidation_frames.clear()
	projection = ProjectionService.new()
	var init: Dictionary = projection.initialize(
		world_id, world_seed, generator_version, directory_override
	)
	if not init.get("ok", false):
		initialization_error = String(
			init.get("reason", "terrain_effect_projection_initialize_failed")
		)
		return _failure(initialization_error)
	initialized = true
	return {"ok": true, "reason": "ok"}


func prepare_chunk_snapshot(
	base_snapshot: Dictionary,
	region_key: Vector2i,
	chunk_coordinate: Vector2i
) -> Dictionary:
	return prepare_targets_snapshot(base_snapshot, [{
		"region_key": region_key,
		"chunk_coordinate": chunk_coordinate,
	}])


func prepare_targets_snapshot(
	base_snapshot: Dictionary,
	targets_value: Array
) -> Dictionary:
	var started_usec := Time.get_ticks_usec()
	if not initialized:
		return _failure("terrain_effect_runtime_not_initialized")
	if base_snapshot.has("valid") and not bool(base_snapshot["valid"]):
		return _failure("terrain_effect_runtime_base_snapshot_invalid")
	var targets_check := _normalize_targets(targets_value)
	if not targets_check.get("ok", false):
		return targets_check
	var targets: Array[Dictionary] = targets_check["targets"]
	var required_source_regions := _required_source_regions(targets)
	if required_source_regions.size() > ProjectionService.MAX_RESIDENT_SCOPES:
		return _failure("terrain_effect_runtime_required_scope_budget_exceeded")

	var capacity := _make_projection_capacity(required_source_regions)
	if not capacity.get("ok", false):
		return capacity
	var authority_revision := int(object_stream.call("get_command_world_revision"))
	var reconciled_count := 0
	var loaded_count := 0
	for source_region in required_source_regions:
		var scope_id := Contract.scope_id_for_region(source_region)
		var status: Dictionary = projection.get_scope_status(
			source_region, authority_revision
		)
		var status_name := String(status.get("status", "unloaded"))
		var must_reconcile := status_name in ["unloaded", "missing", "ahead"] 			or _invalidated_scope_ids.has(scope_id)
		# A global entity world revision does not make unrelated source regions
		# stale. Region-local invalidation is driven by the command/lifecycle path.
		if not must_reconcile:
			continue
		var source: Dictionary = object_stream.call(
			"get_authoritative_region_projection_source", source_region
		)
		if not source.get("ok", false):
			return _failure(
				"terrain_effect_runtime_source_failed:%s" 					% source.get("reason", "unknown")
			)
		var source_revision := int(source.get("world_revision", -1))
		var reconciled: Dictionary = projection.reconcile_scope(
			source_region,
			source_revision,
			source.get("instances", []),
			source.get("source_revisions", {}),
			true
		)
		if not reconciled.get("ok", false):
			return _failure(
				"terrain_effect_runtime_reconcile_failed:%s" 					% reconciled.get("reason", "unknown")
			)
		reconciled_count += 1
		_invalidated_scope_ids.erase(scope_id)
		_pre_invalidation_frames.erase(scope_id)
		if bool(reconciled.get("changed", false)):
			loaded_count += 1

	var by_effect_id: Dictionary = {}
	var target_rows: Array[Dictionary] = []
	for target in targets:
		var effect_snapshot: Dictionary = projection.snapshot_for_chunk(
			target["region_key"], target["chunk_coordinate"]
		)
		if not effect_snapshot.get("ok", false):
			return _failure(
				"terrain_effect_runtime_chunk_snapshot_failed:%s" 					% effect_snapshot.get("reason", "unknown")
			)
		var effect_ids: Array[String] = []
		for frame_value in effect_snapshot.get("local_frames", []):
			if typeof(frame_value) != TYPE_DICTIONARY:
				return _failure("terrain_effect_runtime_frame_invalid")
			var frame: Dictionary = frame_value
			var effect_id := String(frame.get("effect_id", ""))
			if effect_id.is_empty():
				return _failure("terrain_effect_runtime_frame_identity_invalid")
			by_effect_id[effect_id] = frame.duplicate(true)
			effect_ids.append(effect_id)
		effect_ids.sort()
		target_rows.append({
			"region_key": [
				(target["region_key"] as Vector2i).x,
				(target["region_key"] as Vector2i).y,
			],
			"chunk_coordinate": [
				(target["chunk_coordinate"] as Vector2i).x,
				(target["chunk_coordinate"] as Vector2i).y,
			],
			"effect_ids": effect_ids,
			"source_snapshot_sha256": String(
				effect_snapshot.get("snapshot_sha256", "")
			),
		})
	target_rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return JSON.stringify(a, "", true, true) < JSON.stringify(b, "", true, true)
	)
	var effect_ids: Array[String] = []
	for effect_id_value in by_effect_id:
		effect_ids.append(String(effect_id_value))
	effect_ids.sort()
	var frames: Array[Dictionary] = []
	var frame_hashes: Array[String] = []
	for effect_id in effect_ids:
		var frame: Dictionary = by_effect_id[effect_id]
		frames.append(frame)
		frame_hashes.append(String(frame["frame_sha256"]))

	var prepared := base_snapshot.duplicate(true)
	prepared["terrain_object_effect_frames"] = frames
	prepared["terrain_effect_snapshot_sha256"] = Contract.canonical_sha256({
		"schema_version": 1,
		"world_id": world_id,
		"world_seed": world_seed,
		"generator_version": generator_version,
		"authority_revision": authority_revision,
		"targets": target_rows,
		"effect_ids": effect_ids,
		"frame_hashes": frame_hashes,
	})
	prepared["terrain_effect_authority_revision"] = authority_revision
	prepared["terrain_effect_frame_count"] = frames.size()
	last_prepare_metrics = {
		"target_count": targets.size(),
		"required_source_scope_count": required_source_regions.size(),
		"reconciled_scope_count": reconciled_count,
		"changed_scope_count": loaded_count,
		"frame_count": frames.size(),
		"duration_usec": Time.get_ticks_usec() - started_usec,
	}
	return {
		"ok": true,
		"snapshot": prepared,
		"effect_count": frames.size(),
		"snapshot_sha256": prepared["terrain_effect_snapshot_sha256"],
		"authority_revision": authority_revision,
		"metrics": last_prepare_metrics.duplicate(true),
	}


func invalidate_source_region(source_region: Vector2i) -> void:
	if not initialized or projection == null:
		return
	var scope_id := Contract.scope_id_for_region(source_region)
	if not _pre_invalidation_frames.has(scope_id):
		var scope: Dictionary = projection.get_scope_snapshot(source_region)
		_pre_invalidation_frames[scope_id] = (
			scope.get("local_frames", {}) as Dictionary
		).duplicate(true) if not scope.is_empty() else {}
	_invalidated_scope_ids[scope_id] = true


func refresh_invalidated_source_region(
	source_region: Vector2i
) -> Dictionary:
	if not initialized:
		return _failure("terrain_effect_runtime_not_initialized")
	var scope_id := Contract.scope_id_for_region(source_region)
	var old_frames: Dictionary = (
		_pre_invalidation_frames.get(scope_id, {}) as Dictionary
	).duplicate(true)
	var source: Dictionary = object_stream.call(
		"get_authoritative_region_projection_source", source_region
	)
	if not source.get("ok", false):
		return _failure(
			"terrain_effect_runtime_source_failed:%s" 				% source.get("reason", "unknown")
		)
	var reconciled: Dictionary = projection.reconcile_scope(
		source_region,
		int(source.get("world_revision", -1)),
		source.get("instances", []),
		source.get("source_revisions", {}),
		true
	)
	if not reconciled.get("ok", false):
		return _failure(
			"terrain_effect_runtime_reconcile_failed:%s" 				% reconciled.get("reason", "unknown")
		)
	var new_scope: Dictionary = projection.get_scope_snapshot(source_region)
	var new_frames: Dictionary = (
		new_scope.get("local_frames", {}) as Dictionary
	).duplicate(true)
	var targets := _changed_frame_targets(old_frames, new_frames)
	_invalidated_scope_ids.erase(scope_id)
	_pre_invalidation_frames.erase(scope_id)
	return {
		"ok": true,
		"targets": targets,
		"changed_target_count": targets.size(),
		"projection_changed": bool(reconciled.get("changed", false)),
	}


func _changed_frame_targets(
	old_frames: Dictionary,
	new_frames: Dictionary
) -> Array[Dictionary]:
	var changed_ids: Dictionary = {}
	for effect_id_value in old_frames:
		var effect_id := String(effect_id_value)
		if not new_frames.has(effect_id) 			or String((old_frames[effect_id] as Dictionary).get("frame_sha256", "")) 				!= String((new_frames[effect_id] as Dictionary).get("frame_sha256", "")):
			changed_ids[effect_id] = true
	for effect_id_value in new_frames:
		var effect_id := String(effect_id_value)
		if not old_frames.has(effect_id) 			or String((old_frames[effect_id] as Dictionary).get("frame_sha256", "")) 				!= String((new_frames[effect_id] as Dictionary).get("frame_sha256", "")):
			changed_ids[effect_id] = true

	var chunk_ids: Dictionary = {}
	for frames in [old_frames, new_frames]:
		var index := LocalFrameIndex.new()
		for effect_id in changed_ids:
			if not frames.has(effect_id):
				continue
			var indexed: Dictionary = index.replace_frame(frames[effect_id])
			if not indexed.get("ok", false):
				continue
		for chunk_id in index.get_all_indexed_chunk_ids():
			chunk_ids[String(chunk_id)] = true

	var ids: Array[String] = []
	for chunk_id in chunk_ids:
		ids.append(String(chunk_id))
	ids.sort()
	var targets: Array[Dictionary] = []
	for chunk_id in ids:
		var parsed := _target_from_chunk_id(chunk_id)
		if parsed.get("ok", false):
			targets.append({
				"region_key": parsed["region_key"],
				"chunk_coordinate": parsed["chunk_coordinate"],
			})
	return targets


func _target_from_chunk_id(chunk_id: String) -> Dictionary:
	if not chunk_id.begins_with("region:") or not chunk_id.contains("/chunk:"):
		return {"ok": false}
	var sides := chunk_id.split("/chunk:")
	if sides.size() != 2:
		return {"ok": false}
	var region_parts := sides[0].trim_prefix("region:").split(",")
	var chunk_parts := sides[1].split(",")
	if region_parts.size() != 2 or chunk_parts.size() != 2 		or not region_parts[0].is_valid_int() 		or not region_parts[1].is_valid_int() 		or not chunk_parts[0].is_valid_int() 		or not chunk_parts[1].is_valid_int():
		return {"ok": false}
	var coordinate := Vector2i(int(chunk_parts[0]), int(chunk_parts[1]))
	if not Grid.is_valid_coordinate(coordinate):
		return {"ok": false}
	return {
		"ok": true,
		"region_key": Vector2i(
			int(region_parts[0]), int(region_parts[1])
		),
		"chunk_coordinate": coordinate,
	}


func release_all_scopes() -> void:
	if projection == null:
		return
	for scope_id in projection.get_loaded_scope_ids():
		var parsed := _region_from_scope_id(scope_id)
		if parsed.get("ok", false):
			projection.release_scope(parsed["region_key"])


func get_loaded_scope_count() -> int:
	return projection.get_loaded_scope_count() 		if projection != null and initialized else 0


func _make_projection_capacity(
	required_regions: Array[Vector2i]
) -> Dictionary:
	var required_ids: Dictionary = {}
	for region in required_regions:
		required_ids[Contract.scope_id_for_region(region)] = true
	var loaded_ids: Array[String] = projection.get_loaded_scope_ids()
	var missing_count := 0
	for region in required_regions:
		if not loaded_ids.has(Contract.scope_id_for_region(region)):
			missing_count += 1
	var needed := loaded_ids.size() + missing_count 		- ProjectionService.MAX_RESIDENT_SCOPES
	if needed <= 0:
		return {"ok": true, "released": 0}
	var released := 0
	for scope_id in loaded_ids:
		if required_ids.has(scope_id):
			continue
		var parsed := _region_from_scope_id(scope_id)
		if not parsed.get("ok", false):
			continue
		projection.release_scope(parsed["region_key"])
		released += 1
		if released >= needed:
			break
	if projection.get_loaded_scope_count() + missing_count 		> ProjectionService.MAX_RESIDENT_SCOPES:
		return _failure("terrain_effect_runtime_scope_eviction_failed")
	return {"ok": true, "released": released}


func _required_source_regions(
	targets: Array[Dictionary]
) -> Array[Vector2i]:
	var by_id: Dictionary = {}
	for target in targets:
		var center: Vector2i = target["region_key"]
		for z in range(
			center.y - SOURCE_REGION_RADIUS,
			center.y + SOURCE_REGION_RADIUS + 1
		):
			for x in range(
				center.x - SOURCE_REGION_RADIUS,
				center.x + SOURCE_REGION_RADIUS + 1
			):
				var region := Vector2i(x, z)
				by_id[Contract.scope_id_for_region(region)] = region
	var result: Array[Vector2i] = []
	var ids: Array[String] = []
	for scope_id in by_id:
		ids.append(String(scope_id))
	ids.sort()
	for scope_id in ids:
		result.append(by_id[scope_id])
	return result


func _normalize_targets(value: Array) -> Dictionary:
	if value.is_empty() or value.size() > 64:
		return _failure("terrain_effect_runtime_targets_invalid")
	var by_id: Dictionary = {}
	for target_value in value:
		if typeof(target_value) != TYPE_DICTIONARY:
			return _failure("terrain_effect_runtime_target_invalid")
		var target: Dictionary = target_value
		if not target.get("region_key") is Vector2i 			or not target.get("chunk_coordinate") is Vector2i:
			return _failure("terrain_effect_runtime_target_fields_invalid")
		var region: Vector2i = target["region_key"]
		var coordinate: Vector2i = target["chunk_coordinate"]
		if not Grid.is_valid_coordinate(coordinate):
			return _failure("terrain_effect_runtime_target_chunk_invalid")
		var id := Grid.stable_id(region, coordinate)
		by_id[id] = {
			"region_key": region,
			"chunk_coordinate": coordinate,
		}
	var ids: Array[String] = []
	for id in by_id:
		ids.append(String(id))
	ids.sort()
	var targets: Array[Dictionary] = []
	for id in ids:
		targets.append(by_id[id])
	return {"ok": true, "targets": targets}


func _region_from_scope_id(scope_id: String) -> Dictionary:
	if not scope_id.begins_with("region:"):
		return {"ok": false}
	var parts := scope_id.trim_prefix("region:").split(",")
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return {"ok": false}
	return {
		"ok": true,
		"region_key": Vector2i(int(parts[0]), int(parts[1])),
	}


func _failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
