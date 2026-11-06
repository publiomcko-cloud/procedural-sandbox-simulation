extends SceneTree

const Registry := preload("res://scripts/modding/content_definition_registry.gd")
const ObjectWorld := preload("res://scripts/objects/procedural_object_world.gd")
const BrushState := preload("res://scripts/terrain/sdf_brush_edit_state.gd")
const Runtime := preload("res://scripts/terrain/terrain_object_effect_runtime.gd")
const ProjectionService := preload("res://scripts/terrain/terrain_object_effect_projection_service.gd")
const Frame := preload("res://scripts/terrain/terrain_object_effect_local_frame.gd")
const Grid := preload("res://scripts/terrain/terrain_chunk_grid.gd")
const Spatial := preload("res://scripts/terrain/terrain_spatial_ownership.gd")
const TerrainMeshJob := preload("res://scripts/terrain/terrain_mesh_job.gd")
const SharedAuthority := preload("res://scripts/terrain/shared_surface_boundary_authority.gd")
const SharedXJob := preload("res://scripts/terrain/shared_surface_boundary_mesh_job.gd")
const Field := preload("res://scripts/terrain/sdf_world.gd")

const WORLD_ID := "issue108-phase-d"
const WORLD_SEED := 424242
const ROOT := "user://issue108-phase-d-tests"

var assertions := 0
var failures := 0
var evidence: Dictionary = {}


class FakeObjectStream:
	extends Node

	var source_region := Vector2i.ZERO
	var instance: Dictionary = {}
	var active := true
	var world_revision := 0
	var entity_revision := 0

	func get_command_world_revision() -> int:
		return world_revision

	func get_authoritative_region_projection_source(region_key: Vector2i) -> Dictionary:
		var instances: Array[Dictionary] = []
		var revisions: Dictionary = {}
		if active and region_key == source_region and not instance.is_empty():
			instances.append(instance.duplicate(true))
			revisions[String(instance["instance_id"])] = entity_revision
		return {
			"ok": true,
			"region_key": region_key,
			"world_revision": world_revision,
			"instances": instances,
			"source_revisions": revisions,
		}

	func transform_translation(value: Vector3i) -> void:
		if instance.is_empty():
			return
		var components: Dictionary = instance.get("instance_components", {}).duplicate(true)
		var default_scale: Vector3i = instance.get(
			"default_scale_milli", Vector3i(1000, 1000, 1000)
		)
		components["core.transform"] = {
			"schema_version": 1,
			"properties": {
				"translation_mm": [value.x, value.y, value.z],
				"rotation_mdeg": [0, int(instance.get("default_yaw_mdeg", 0)), 0],
				"scale_milli": [
					default_scale.x, default_scale.y, default_scale.z
				],
			},
		}
		instance["instance_components"] = components
		entity_revision += 1
		world_revision += 1

	func set_active(value: bool) -> void:
		active = value
		entity_revision += 1
		world_revision += 1


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_remove_tree(ProjectSettings.globalize_path(ROOT))
	var registry := Registry.new()
	var registered: Dictionary = registry.discover_and_register(["res://mods/first-party"])
	_check(registered.get("ok", false), "first-party registry initializes")
	if not registered.get("ok", false):
		_finish()
		return
	var generated: Dictionary = ObjectWorld.build_region_instances(
		WORLD_SEED, WORLD_ID, Vector2i.ZERO, registry
	)
	_check(generated.get("ok", false), "reference procedural region generates")
	var source := _first_interacting(generated.get("instances", []))
	_check(not source.is_empty(), "reference interacting source exists")
	if source.is_empty():
		_finish()
		return

	var edge := _relocate_to_edge(source)
	var fake := FakeObjectStream.new()
	fake.source_region = Vector2i.ZERO
	fake.instance = edge
	var runtime := Runtime.new()
	var runtime_init: Dictionary = runtime.initialize(
		WORLD_ID,
		WORLD_SEED,
		Field.GENERATOR_VERSION,
		fake,
		ROOT + "/projection"
	)
	_check(runtime_init.get("ok", false), "live terrain-effect runtime initializes")

	var ledger := BrushState.new(WORLD_SEED, Field.GENERATOR_VERSION)
	var z_local := float((edge["position_mm"] as Vector3i).z) / 1000.0
	var z_chunk := clampi(floori(z_local / (
		float(Grid.CELLS_PER_CHUNK_Z) * Grid.SAMPLE_STEP
	)), 0, Grid.CHUNK_COUNT_Z - 1)
	var left_coordinate := Vector2i(Grid.CHUNK_COUNT_X - 1, z_chunk)
	var right_coordinate := Vector2i(0, z_chunk)
	var left_snapshot: Dictionary = ledger.get_meshing_snapshot_for_chunk(
		Vector2i.ZERO, left_coordinate
	)
	var prepared_left: Dictionary = runtime.prepare_chunk_snapshot(
		left_snapshot, Vector2i.ZERO, left_coordinate
	)
	_check(prepared_left.get("ok", false), "left edge chunk receives immutable effect snapshot")
	var left_live: Dictionary = prepared_left.get("snapshot", {})
	_check(
		int(left_live.get("terrain_effect_frame_count", -1)) > 0,
		"left edge chunk contains at least one terrain effect frame"
	)

	var right_snapshot: Dictionary = ledger.get_meshing_snapshot_for_chunk(
		Vector2i.RIGHT, right_coordinate
	)
	var prepared_right: Dictionary = runtime.prepare_chunk_snapshot(
		right_snapshot, Vector2i.RIGHT, right_coordinate
	)
	_check(prepared_right.get("ok", false), "right neighbor chunk receives cross-region effect snapshot")
	var right_live: Dictionary = prepared_right.get("snapshot", {})
	_check(
		int(right_live.get("terrain_effect_frame_count", -1)) > 0,
		"effect crosses the signed region boundary through the live index"
	)

	var frame: Dictionary = (left_live["terrain_object_effect_frames"] as Array)[0]
	var source_region_values: Array = frame["source_region_key"]
	var source_region := Vector2i(
		int(source_region_values[0]), int(source_region_values[1])
	)
	var interior := _array_to_vector3(frame["interior_point_local"])
	var cutter := Frame.sample_cutter_prevalidated(frame, source_region, interior)
	_check(is_finite(cutter) and cutter < 0.0, "live frame has negative cutter interior")

	var baseline_snapshot: Dictionary = left_live.duplicate(true)
	baseline_snapshot["terrain_object_effect_frames"] = []
	var density_without := BrushState.sample_density_snapshot(
		WORLD_SEED, source_region, interior, false, baseline_snapshot
	)
	var density_with := BrushState.sample_density_snapshot(
		WORLD_SEED, source_region, interior, false, left_live
	)
	_check(
		density_with <= density_without
			and absf(density_with - minf(density_without, cutter)) < 0.000001,
		"live sampler composes subtract-solid imprint after canonical terrain"
	)

	# FILL is evaluated first; the anchored imprint is then re-applied according
	# to terrain_edits_then_imprint_v1.
	var world_point := Spatial.region_origin_world(source_region) + interior
	_check(
		ledger.add_sphere(BrushState.Mode.FILL, world_point, 1.25),
		"player FILL edit is accepted at imprint interior"
	)
	var fill_snapshot: Dictionary = ledger.get_meshing_snapshot_for_chunk(
		Vector2i.ZERO, left_coordinate
	)
	var prepared_fill: Dictionary = runtime.prepare_chunk_snapshot(
		fill_snapshot, Vector2i.ZERO, left_coordinate
	)
	_check(prepared_fill.get("ok", false), "edited chunk receives current effect snapshot")
	var fill_live: Dictionary = prepared_fill["snapshot"]
	var fill_no_effect := fill_live.duplicate(true)
	fill_no_effect["terrain_object_effect_frames"] = []
	var fill_density_without := BrushState.sample_density_snapshot(
		WORLD_SEED, source_region, interior, false, fill_no_effect
	)
	var fill_density_with := BrushState.sample_density_snapshot(
		WORLD_SEED, source_region, interior, false, fill_live
	)
	_check(
		fill_density_without > fill_density_with and fill_density_with < 0.0,
		"terrain_edits_then_imprint_v1 re-applies anchored imprint after FILL"
	)

	# LOD1 is deliberately rejected for effect-bearing chunks until its callback
	# can consume the same region-local frame without world-float conversion.
	var lod_job := TerrainMeshJob.new(
		WORLD_SEED,
		Vector2i.ZERO,
		left_coordinate,
		false,
		fill_live,
		Time.get_ticks_usec(),
		1
	)
	lod_job.run()
	_check(
		lod_job.result.get("valid", false)
			and int(lod_job.result.get("lod_level", -1)) == 0
			and lod_job.result.get("lod_fallback_reason")
				== "terrain_effect_precision_frame_requires_lod0",
		"effect-bearing LOD1 request fails over deterministically to precision-safe LOD0"
	)

	# Shared X seam receives one merged immutable effect snapshot for both sides.
	var pair_snapshot: Dictionary = SharedAuthority.make_x_pair_snapshot(
		ledger, Vector2i.ZERO, z_chunk
	)
	var prepared_pair: Dictionary = runtime.prepare_targets_snapshot(
		pair_snapshot,
		[
			{"region_key": Vector2i.ZERO, "chunk_coordinate": left_coordinate},
			{"region_key": Vector2i.RIGHT, "chunk_coordinate": right_coordinate},
		]
	)
	_check(prepared_pair.get("ok", false), "shared X pair receives merged effect snapshot")
	var shared_job := SharedXJob.new(
		WORLD_SEED,
		Vector2i.ZERO,
		z_chunk,
		prepared_pair["snapshot"],
		Time.get_ticks_usec(),
		true
	)
	shared_job.run()
	_check(
		shared_job.result.get("valid", false)
			and shared_job.result.get("left", {}).get("valid", false)
			and shared_job.result.get("right", {}).get("valid", false),
		"shared X seam meshes successfully with live object imprint"
	)

	var first_hash := String(prepared_left.get("snapshot_sha256", ""))
	runtime.invalidate_source_region(Vector2i.ZERO)
	fake.transform_translation(Vector3i(-350, 100, 0))
	var transformed: Dictionary = runtime.prepare_chunk_snapshot(
		ledger.get_meshing_snapshot_for_chunk(Vector2i.ZERO, left_coordinate),
		Vector2i.ZERO,
		left_coordinate
	)
	_check(
		transformed.get("ok", false)
			and String(transformed.get("snapshot_sha256", "")) != first_hash,
		"source transform revision invalidates and rebuilds live effect snapshot"
	)

	runtime.invalidate_source_region(Vector2i.ZERO)
	fake.set_active(false)
	var deleted: Dictionary = runtime.prepare_chunk_snapshot(
		ledger.get_meshing_snapshot_for_chunk(Vector2i.ZERO, left_coordinate),
		Vector2i.ZERO,
		left_coordinate
	)
	_check(
		deleted.get("ok", false)
			and int(deleted.get("effect_count", -1)) == 0,
		"source delete removes live terrain effect from the next snapshot"
	)
	runtime.invalidate_source_region(Vector2i.ZERO)
	fake.set_active(true)
	var restored: Dictionary = runtime.prepare_chunk_snapshot(
		ledger.get_meshing_snapshot_for_chunk(Vector2i.ZERO, left_coordinate),
		Vector2i.ZERO,
		left_coordinate
	)
	_check(
		restored.get("ok", false)
			and int(restored.get("effect_count", 0)) > 0,
		"source restore replays terrain effect into the next snapshot"
	)

	# A derived projection may be ahead after loading/rolling back an older
	# authoritative save. The live coordinator must rebuild from that authority,
	# while direct stale reconcile calls remain fail-closed.
	var rewind_before_revision := int(fake.world_revision)
	var rewind_before_entity_revision := int(fake.entity_revision)
	fake.world_revision = 1
	fake.entity_revision = 1
	var rewound: Dictionary = runtime.prepare_chunk_snapshot(
		ledger.get_meshing_snapshot_for_chunk(Vector2i.ZERO, left_coordinate),
		Vector2i.ZERO,
		left_coordinate
	)
	_check(
		rewound.get("ok", false)
			and int(rewound.get("authority_revision", -1)) == 1,
		"ahead derived projection rebuilds from explicitly current older authority"
	)
	fake.world_revision = rewind_before_revision + 1
	fake.entity_revision = rewind_before_entity_revision + 1
	var forward_again: Dictionary = runtime.prepare_chunk_snapshot(
		ledger.get_meshing_snapshot_for_chunk(Vector2i.ZERO, left_coordinate),
		Vector2i.ZERO,
		left_coordinate
	)
	_check(
		forward_again.get("ok", false),
		"projection advances normally after authoritative rewind rebuild"
	)

	# Old Phase-C projection shards are derived data and must upgrade by rebuild,
	# not be treated as authoritative corruption.
	var legacy_upgrade := _exercise_legacy_projection_rebuild(
		runtime, fake
	)
	_check(
		legacy_upgrade.get("ok", false),
		"legacy Phase-C projection schema is rebuildable without entity-state migration (%s)" 			% legacy_upgrade.get("reason", "ok")
	)

	evidence = {
		"left_effect_count": int(prepared_left.get("effect_count", 0)),
		"right_effect_count": int(prepared_right.get("effect_count", 0)),
		"cutter_interior": cutter,
		"fill_density_without_effect": fill_density_without,
		"fill_density_with_effect": fill_density_with,
		"shared_left_triangles": int(
			(shared_job.result.get("left", {}) as Dictionary).get(
				"triangle_count", 0
			)
		),
		"shared_right_triangles": int(
			(shared_job.result.get("right", {}) as Dictionary).get(
				"triangle_count", 0
			)
		),
		"runtime_loaded_scopes": runtime.get_loaded_scope_count(),
	}
	_finish()


func _exercise_legacy_projection_rebuild(
	runtime: RefCounted,
	fake: Node
) -> Dictionary:
	var current_scope: Dictionary = runtime.projection.get_scope_snapshot(
		Vector2i.ZERO
	)
	if current_scope.is_empty():
		return {"ok": false, "reason": "current_scope_missing"}
	var legacy_scope := current_scope.duplicate(true)
	legacy_scope["schema_version"] = 1
	legacy_scope.erase("local_frames")
	var payload_json := JSON.stringify(legacy_scope, "", true, true)
	var payload_bytes := payload_json.to_utf8_buffer()
	var hashing := HashingContext.new()
	if hashing.start(HashingContext.HASH_SHA256) != OK 		or hashing.update(payload_bytes) != OK:
		return {"ok": false, "reason": "hash_context_failed"}
	var payload_sha := hashing.finish().hex_encode()
	var envelope := {
		"format": "procedural-sandbox-terrain-object-effect-projection",
		"schema_version": 1,
		"generation": 1,
		"payload_json": payload_json,
		"payload_sha256": payload_sha,
	}
	var root := ProjectSettings.globalize_path(ROOT + "/legacy-projection")
	var scope_dir := root.path_join("regions/r_0_0")
	if DirAccess.make_dir_recursive_absolute(scope_dir) != OK:
		return {"ok": false, "reason": "legacy_scope_directory_failed"}
	var file := FileAccess.open(
		scope_dir.path_join("projection-00000001.json"), FileAccess.WRITE
	)
	if file == null:
		return {"ok": false, "reason": "legacy_projection_open_failed"}
	file.store_string(JSON.stringify(envelope, "", true, true))
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		return {"ok": false, "reason": "legacy_projection_write_failed"}

	var upgraded := ProjectionService.new()
	var initialized: Dictionary = upgraded.initialize(
		WORLD_ID, WORLD_SEED, Field.GENERATOR_VERSION, root
	)
	if not initialized.get("ok", false):
		return initialized
	var loaded: Dictionary = upgraded.load_scope(Vector2i.ZERO)
	if not loaded.get("ok", false) 		or loaded.get("found", true) 		or not loaded.get("legacy_rebuild_required", false):
		return {
			"ok": false,
			"reason": "legacy_projection_not_classified_for_rebuild",
			"loaded": loaded,
		}
	var source_id := String(fake.instance.get("instance_id", ""))
	var reconciled: Dictionary = upgraded.reconcile_scope(
		Vector2i.ZERO,
		int(fake.world_revision),
		[fake.instance.duplicate(true)] if bool(fake.active) else [],
		{source_id: int(fake.entity_revision)} if bool(fake.active) else {}
	)
	if not reconciled.get("ok", false):
		return reconciled
	if int(reconciled.get("generation", -1)) != 2 		or not FileAccess.file_exists(
			scope_dir.path_join("projection-00000002.json")
		):
		return {
			"ok": false,
			"reason": "legacy_projection_rebuild_generation_invalid",
			"reconciled": reconciled,
		}
	return {
		"ok": true,
		"generation": int(reconciled["generation"]),
		"effect_count": int(reconciled.get("effect_count", 0)),
	}


func _relocate_to_edge(source: Dictionary) -> Dictionary:
	var instance := source.duplicate(true)
	instance["instance_id"] = "%s/seed-%d/phase-d-edge" % [WORLD_ID, WORLD_SEED]
	instance["world_id"] = WORLD_ID
	instance["world_seed"] = WORLD_SEED
	instance["generator_version"] = Field.GENERATOR_VERSION
	instance["region_key"] = Vector2i.ZERO
	var original: Vector3i = source["position_mm"]
	var position := Vector3i(
		roundi(Spatial.REGION_SIZE_X * 1000.0) - 1,
		original.y,
		clampi(original.z, 1500, roundi(Spatial.REGION_SIZE_Z * 1000.0) - 1500)
	)
	instance["position_mm"] = position
	instance["world_position_mm"] = position
	return instance


func _first_interacting(instances_value: Variant) -> Dictionary:
	if typeof(instances_value) != TYPE_ARRAY:
		return {}
	for value in instances_value:
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var instance: Dictionary = value
		if not (instance.get("terrain_interaction", {}) as Dictionary).is_empty():
			return instance.duplicate(true)
	return {}


func _array_to_vector3(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))


func _remove_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	var directory := DirAccess.open(path)
	if directory == null:
		return
	directory.list_dir_begin()
	while true:
		var name := directory.get_next()
		if name.is_empty():
			break
		var child := path.path_join(name)
		if directory.current_is_dir():
			_remove_tree(child)
		else:
			DirAccess.remove_absolute(child)
	directory.list_dir_end()
	DirAccess.remove_absolute(path)


func _check(condition: bool, message: String) -> void:
	assertions += 1
	if condition:
		print("PASS: " + message)
	else:
		failures += 1
		push_error("FAIL: " + message)


func _finish() -> void:
	print("ISSUE108_PHASE_D_EVIDENCE=" + JSON.stringify(evidence))
	print("ISSUE108_PHASE_D_%s: assertions=%d failures=%d" % [
		"PASS" if failures == 0 else "FAIL", assertions, failures
	])
	_remove_tree(ProjectSettings.globalize_path(ROOT))
	quit(0 if failures == 0 else 1)
