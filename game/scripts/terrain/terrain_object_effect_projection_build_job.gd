class_name TerrainObjectEffectProjectionBuildJob
extends RefCounted

## Worker-only construction of the pure terrain-object projection payload.
## No service state, persistence, scene nodes, or entity authority are mutated.
const Effect := preload("res://scripts/terrain/terrain_object_effect.gd")
const LocalFrame := preload("res://scripts/terrain/terrain_object_effect_local_frame.gd")
const Contract := preload("res://scripts/terrain/terrain_object_effect_projection_contract.gd")

var world_id := ""
var world_seed := -1
var generator_version := -1
var region_key := Vector2i.ZERO
var source: Dictionary = {}
var result: Dictionary = {}
var worker_started_usec := 0
var worker_finished_usec := 0
var worker_thread_id := 0


func _init(
	world_identifier: String,
	seed_value: int,
	generator: int,
	key: Vector2i,
	source_value: Dictionary
) -> void:
	world_id = world_identifier
	world_seed = seed_value
	generator_version = generator
	region_key = key
	source = source_value.duplicate(true)


func run() -> void:
	worker_started_usec = Time.get_ticks_usec()
	worker_thread_id = OS.get_thread_caller_id()
	result = _build()
	worker_finished_usec = Time.get_ticks_usec()
	result["worker_usec"] = worker_finished_usec - worker_started_usec
	result["worker_thread_id"] = worker_thread_id


func _build() -> Dictionary:
	var build_started_usec := Time.get_ticks_usec()
	var source_world_revision := int(source.get("world_revision", -1))
	if source_world_revision < 0 		or source_world_revision > Contract.MAX_REVISION:
		return _failure("effect_projection_source_world_revision_invalid")
	var instances_value: Variant = source.get("instances", [])
	var revisions_value: Variant = source.get("source_revisions", {})
	if typeof(instances_value) != TYPE_ARRAY 		or typeof(revisions_value) != TYPE_DICTIONARY:
		return _failure("effect_projection_source_payload_invalid")
	var prepare_started_usec := Time.get_ticks_usec()
	var ordered_instances: Array = (instances_value as Array).duplicate(true)
	ordered_instances.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.get("instance_id", "")) 			< String(b.get("instance_id", ""))
	)
	var prepare_usec := Time.get_ticks_usec() - prepare_started_usec
	var source_revisions: Dictionary = revisions_value
	var incoming_effects: Dictionary = {}
	var incoming_frames: Dictionary = {}
	var source_instance_ids: Array[String] = []
	var source_digest_entries: Array[Dictionary] = []
	var seen_sources: Dictionary = {}
	var interaction_instance_count := 0
	var non_interaction_instance_count := 0
	var effect_frame_started_usec := Time.get_ticks_usec()

	for instance_value in ordered_instances:
		if typeof(instance_value) != TYPE_DICTIONARY:
			return _failure("effect_projection_source_not_dictionary")
		var instance: Dictionary = instance_value
		var instance_id := String(instance.get("instance_id", ""))
		if instance_id.is_empty() or seen_sources.has(instance_id):
			return _failure("effect_projection_source_identity_invalid")
		seen_sources[instance_id] = true
		if instance.get(
			"region_key", Vector2i(2147483647, 2147483647)
		) != region_key:
			return _failure("effect_projection_source_region_mismatch")
		if not source_revisions.has(instance_id):
			return _failure("effect_projection_source_revision_missing")
		var source_revision := int(source_revisions[instance_id])
		if source_revision < 0 			or source_revision > source_world_revision 			or source_revision > Contract.MAX_REVISION:
			return _failure("effect_projection_source_revision_invalid")
		source_instance_ids.append(instance_id)
		var interaction: Dictionary = instance.get("terrain_interaction", {})
		if interaction.is_empty():
			non_interaction_instance_count += 1
			source_digest_entries.append({
				"instance_id": instance_id,
				"source_revision": source_revision,
				"content_pin_sha256": Contract.canonical_sha256(
					instance.get("content_pin", {})
				),
				"terrain_interaction": "none",
			})
			continue

		interaction_instance_count += 1
		var built := Effect.build_from_instance(instance, source_revision)
		if not built.get("ok", false):
			return _failure(
				"effect_projection_effect_build_failed:%s" 					% built.get("reason", "unknown")
			)
		var effect: Dictionary = built["effect"]
		var effect_id := String(effect["effect_id"])
		if incoming_effects.has(effect_id):
			return _failure("effect_projection_effect_identity_collision")
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
		incoming_effects[effect_id] = effect
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

	var effect_frame_usec := Time.get_ticks_usec() - effect_frame_started_usec
	var digest_started_usec := Time.get_ticks_usec()
	source_instance_ids.sort()
	source_digest_entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.get("instance_id", "")) 			< String(b.get("instance_id", ""))
	)
	var scope_id := Contract.scope_id_for_region(region_key)
	var source_digest_sha256 := Contract.source_digest(
		scope_id,
		region_key,
		source_world_revision,
		source_digest_entries
	)
	var digest_usec := Time.get_ticks_usec() - digest_started_usec
	var validate_started_usec := Time.get_ticks_usec()
	var candidate := {
		"schema_version": Contract.SCHEMA_VERSION,
		"world_id": world_id,
		"world_seed": world_seed,
		"generator_version": generator_version,
		"scope_id": scope_id,
		"region_key": [region_key.x, region_key.y],
		"projection_revision": 0,
		"source_world_revision": source_world_revision,
		"source_digest_sha256": source_digest_sha256,
		"source_instance_ids": source_instance_ids,
		"effects": incoming_effects,
		"local_frames": incoming_frames,
	}
	var checked := Contract.validate_snapshot(
		candidate,
		world_id,
		world_seed,
		generator_version,
		region_key
	)
	var validate_usec := Time.get_ticks_usec() - validate_started_usec
	if not checked.get("ok", false):
		return _failure(
			"effect_projection_worker_validation_failed:%s"
				% checked.get("reason", "unknown")
		)
	var normalized_snapshot: Dictionary = checked["snapshot"]
	var total_usec := Time.get_ticks_usec() - build_started_usec
	return {
		"ok": true,
		"region_key": region_key,
		"source_world_revision": source_world_revision,
		"source_instance_ids": normalized_snapshot["source_instance_ids"],
		"source_digest_sha256": source_digest_sha256,
		"source_digest_entries": source_digest_entries,
		"effects": normalized_snapshot["effects"],
		"local_frames": normalized_snapshot["local_frames"],
		"worker_prevalidated": true,
		"prevalidated_snapshot": normalized_snapshot,
		"timings_usec": {
			"prepare_sort": prepare_usec,
			"effect_frame_build": effect_frame_usec,
			"digest": digest_usec,
			"validate_snapshot": validate_usec,
			"total": total_usec,
		},
		"work_counts": {
			"source_instance_count": ordered_instances.size(),
			"interaction_instance_count": interaction_instance_count,
			"non_interaction_instance_count": non_interaction_instance_count,
			"effect_count": incoming_effects.size(),
		},
	}


func _failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
