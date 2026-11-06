extends SceneTree

const Registry := preload("res://scripts/modding/content_definition_registry.gd")
const StateService := preload("res://scripts/objects/procedural_object_state_service.gd")
const CommandService := preload("res://scripts/entities/entity_command_service.gd")
const ProjectionService := preload("res://scripts/terrain/terrain_object_effect_projection_service.gd")
const Frame := preload("res://scripts/terrain/terrain_object_effect_local_frame.gd")
const Brush := preload("res://scripts/terrain/sdf_brush_edit_state.gd")
const Grid := preload("res://scripts/terrain/terrain_chunk_grid.gd")
const TerrainMeshJob := preload("res://scripts/terrain/terrain_mesh_job.gd")
const SharedAuthority := preload("res://scripts/terrain/shared_surface_boundary_authority.gd")
const Field := preload("res://scripts/terrain/sdf_world.gd")

const WORLD_ID := "issue108-phase-d"
const WORLD_SEED := 424242
const ROOT := "user://issue108-phase-d-tests"

var assertions := 0
var failures := 0
var evidence: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_remove_tree(ProjectSettings.globalize_path(ROOT))
	var registry := Registry.new()
	_check(
		registry.discover_and_register(["res://mods/first-party"]).get("ok", false),
		"first-party registry initializes"
	)
	var state: RefCounted = StateService.new()
	_check(
		state.initialize(
			WORLD_ID, WORLD_SEED, Field.GENERATOR_VERSION, ROOT + "/object-state"
		).get("ok", false),
		"authoritative state initializes"
	)
	_check(
		state.upgrade_history_snapshot_schema().get("ok", false),
		"authoritative state upgrades to history schema"
	)
	var commands: RefCounted = CommandService.new()
	_check(commands.initialize(state, registry).get("ok", false), "command service initializes")
	_check(commands.reconstruct_region(Vector2i.ZERO).get("ok", false), "source region reconstructs")

	var projection: RefCounted = ProjectionService.new()
	_check(
		projection.initialize(
			WORLD_ID,
			WORLD_SEED,
			Field.GENERATOR_VERSION,
			ROOT + "/terrain-object-effects"
		).get("ok", false),
		"terrain effect projection initializes"
	)
	var reconciled: Dictionary = projection.reconcile_command_region(
		Vector2i.ZERO, commands
	)
	_check(reconciled.get("ok", false), "authoritative region reconciles into effect projection")
	_check(
		(reconciled.get("affected_chunk_ids", []) as Array).size() > 0,
		"initial reconciliation exposes deterministic dirty footprint"
	)

	var candidate := _first_effect_chunk(projection)
	_check(candidate.get("ok", false), "at least one chunk has a precision-safe local effect")
	if not candidate.get("ok", false):
		_finish()
		return
	var region_key: Vector2i = candidate["region_key"]
	var coordinate: Vector2i = candidate["coordinate"]
	var effect_snapshot: Dictionary = projection.local_snapshot_for_chunk(
		region_key, coordinate
	)
	_check(
		effect_snapshot.get("ok", false)
			and int(effect_snapshot.get("terrain_object_effect_count", 0)) > 0,
		"chunk effect snapshot is immutable and non-empty"
	)
	var frame: Dictionary = effect_snapshot["terrain_object_local_frames"][0]
	_check(
		Frame.validate_frame(frame).get("ok", false),
		"worker snapshot carries a valid prequalified local frame"
	)

	_test_edit_order(frame)
	_test_chunk_mesh(projection)
	_test_shared_seam(registry)
	_test_delete_restore(commands, state, projection, frame)
	_finish()


func _test_edit_order(frame: Dictionary) -> void:
	var query_region := Vector2i(
		int(frame["frame_region_key"][0]),
		int(frame["frame_region_key"][1])
	)
	var query_local := _v3(frame["interior_point_local"])
	var world_query := Vector3(
		float(query_region.x) * Frame.REGION_SIZE_X_M + query_local.x,
		query_local.y,
		float(query_region.y) * Frame.REGION_SIZE_Z_M + query_local.z
	)
	var without_effect := _snapshot([])
	without_effect["centers"] = PackedVector3Array([world_query])
	without_effect["radii"] = PackedFloat64Array([2.0])
	without_effect["modes"] = PackedByteArray([Brush.Mode.FILL])
	var with_effect := without_effect.duplicate(true)
	with_effect["terrain_object_local_frames"] = [frame.duplicate(true)]
	with_effect["terrain_object_effect_count"] = 1
	with_effect["terrain_object_effect_snapshot_sha256"] = "test"

	var filled := Brush.sample_density_snapshot(
		WORLD_SEED, query_region, query_local, false, without_effect
	)
	var composed := Brush.sample_density_snapshot(
		WORLD_SEED, query_region, query_local, false, with_effect
	)
	var expected := Frame.compose_density_prevalidated(
		filled, frame, query_region, query_local
	)
	_check(filled > 0.0, "fixture FILL produces solid terrain before object imprint")
	_check(
		composed == expected and composed < 0.0,
		"terrain edits compose before object imprint; FILL cannot overwrite active imprint"
	)
	evidence["edit_order_filled_density"] = filled
	evidence["edit_order_composed_density"] = composed


func _test_chunk_mesh(projection: RefCounted) -> void:
	var changed := false
	var selected_region := Vector2i.ZERO
	var selected_coordinate := Vector2i.ZERO
	var selected_base_hash := ""
	var selected_effect_hash := ""
	var candidate_count := 0
	for region_key in [
		Vector2i.ZERO,
		Vector2i.RIGHT,
		Vector2i.LEFT,
		Vector2i(0, 1),
		Vector2i(0, -1),
	]:
		for coordinate in Grid.all_coordinates():
			var effect_snapshot: Dictionary = projection.local_snapshot_for_chunk(
				region_key, coordinate
			)
			if int(effect_snapshot.get("terrain_object_effect_count", 0)) == 0:
				continue
			candidate_count += 1
			var base_snapshot := _snapshot([])
			var effect_job_snapshot := base_snapshot.duplicate(true)
			effect_job_snapshot["terrain_object_local_frames"] = effect_snapshot[
				"terrain_object_local_frames"
			].duplicate(true)
			effect_job_snapshot["terrain_object_sampling_frames"] = effect_snapshot.get(
				"terrain_object_sampling_frames", []
			).duplicate(true)
			effect_job_snapshot["terrain_object_effect_count"] = int(
				effect_snapshot["terrain_object_effect_count"]
			)
			effect_job_snapshot["terrain_object_effect_snapshot_sha256"] = String(
				effect_snapshot["terrain_object_effect_snapshot_sha256"]
			)
			var base_job := TerrainMeshJob.new(
				WORLD_SEED, region_key, coordinate, false, base_snapshot, 0, 0
			)
			var effect_job := TerrainMeshJob.new(
				WORLD_SEED, region_key, coordinate, false, effect_job_snapshot, 0, 0
			)
			base_job.run()
			effect_job.run()
			_check(
				base_job.result.get("valid", false)
					and effect_job.result.get("valid", false),
				"candidate LOD0 jobs complete with and without object effects"
			)
			var base_hash := _cpu_mesh_hash(base_job.result)
			var effect_hash := _cpu_mesh_hash(effect_job.result)
			if base_hash != effect_hash:
				changed = true
				selected_region = region_key
				selected_coordinate = coordinate
				selected_base_hash = base_hash
				selected_effect_hash = effect_hash
				var lod_job := TerrainMeshJob.new(
					WORLD_SEED,
					region_key,
					coordinate,
					false,
					effect_job_snapshot,
					0,
					1
				)
				lod_job.run()
				_check(
					lod_job.result.get("valid", false),
					"LOD1/fallback path consumes the same object effect snapshot"
				)
				break
		if changed:
			break
	_check(candidate_count > 0, "projection exposes at least one mesh candidate chunk")
	_check(
		changed,
		"at least one affected chunk CPU mesh changes when object imprint is active"
	)
	if changed:
		evidence["affected_chunk"] = Grid.stable_id(
			selected_region, selected_coordinate
		)
		evidence["base_mesh_sha256"] = selected_base_hash
		evidence["effect_mesh_sha256"] = selected_effect_hash


func _test_shared_seam(registry: RefCounted) -> void:
	var seam_instance := _fixture_instance(
		registry,
		Vector2i.ZERO,
		Vector3i(15850, 3800, 6000),
		"phase-d-seam"
	)
	var frame_result := Frame.build_from_instance(seam_instance, 1)
	_check(frame_result.get("ok", false), "deterministic seam effect frame builds")
	if not frame_result.get("ok", false):
		return
	var frame: Dictionary = frame_result["frame"]
	var z_chunk := clampi(
		floori(float(frame["interior_point_local"][2]) / 3.0),
		0,
		Grid.CHUNK_COUNT_Z - 1
	)
	var snapshot := _snapshot([frame])
	snapshot["terrain_object_effect_snapshot_sha256"] = JSON.stringify(
		frame, "", true, true
	).sha256_text()
	var built := SharedAuthority.build_x_region_boundary_pair(
		WORLD_SEED, Vector2i.ZERO, z_chunk, snapshot, true
	)
	_check(
		built.get("valid", false),
		"shared X authority builds from one precision-safe seam effect snapshot"
	)
	if built.get("valid", false):
		_check(
			built["left"].get("shared_mesh_signature", "")
				== built["right"].get("shared_mesh_signature", ""),
			"both sides publish the same shared-surface signature with imprint"
		)


func _test_delete_restore(
	commands: RefCounted,
	state: RefCounted,
	projection: RefCounted,
	initial_frame: Dictionary
) -> void:
	var source_id := String(initial_frame["source_instance_id"])
	var source_region_result: Dictionary = commands.get_entity_region(source_id)
	_check(source_region_result.get("ok", false), "effect source entity is reconstructed")
	if not source_region_result.get("ok", false):
		return
	var source_region: Vector2i = source_region_result["region_key"]

	var deleted: Dictionary = commands.dispatch(_simple_command(
		"00000000-0000-4000-8000-00000000d001",
		"ENTITY_DELETE",
		source_id,
		state.get_revision(),
		state.get_entity_revision(source_id)
	))
	_check(deleted.get("ok", false), "authoritative source delete commits")
	var delete_reconcile: Dictionary = projection.reconcile_command_region(
		source_region, commands
	)
	_check(
		delete_reconcile.get("ok", false)
			and (delete_reconcile.get("affected_chunk_ids", []) as Array).size() > 0,
		"delete reconciliation invalidates old imprint footprint"
	)
	var after_delete := _frame_by_source(projection, source_id)
	_check(after_delete.is_empty(), "deleted source has no live local effect frame")

	var restored: Dictionary = commands.dispatch(_simple_command(
		"00000000-0000-4000-8000-00000000d002",
		"ENTITY_RESTORE",
		source_id,
		state.get_revision(),
		state.get_entity_revision(source_id)
	))
	_check(restored.get("ok", false), "authoritative source restore commits")
	var restore_reconcile: Dictionary = projection.reconcile_command_region(
		source_region, commands
	)
	_check(
		restore_reconcile.get("ok", false)
			and (restore_reconcile.get("affected_chunk_ids", []) as Array).size() > 0,
		"restore reconciliation invalidates restored imprint footprint"
	)
	var after_restore := _frame_by_source(projection, source_id)
	_check(
		not after_restore.is_empty()
			and String(after_restore["effect_id"]) == String(initial_frame["effect_id"]),
		"restore recreates the same stable live effect identity"
	)
	_check(
		not bool(after_restore.get("terrain_interaction_applied", false)),
		"live overlay does not create a second applied-state authority"
	)


func _first_effect_chunk(projection: RefCounted) -> Dictionary:
	for z in range(Grid.CHUNK_COUNT_Z):
		for x in range(Grid.CHUNK_COUNT_X):
			var snapshot: Dictionary = projection.local_snapshot_for_chunk(
				Vector2i.ZERO, Vector2i(x, z)
			)
			if int(snapshot.get("terrain_object_effect_count", 0)) > 0:
				return {
					"ok": true,
					"region_key": Vector2i.ZERO,
					"coordinate": Vector2i(x, z),
				}
	for neighbor in [
		Vector2i.RIGHT, Vector2i.LEFT, Vector2i(0, 1), Vector2i(0, -1)
	]:
		for z in range(Grid.CHUNK_COUNT_Z):
			for x in range(Grid.CHUNK_COUNT_X):
				var snapshot: Dictionary = projection.local_snapshot_for_chunk(
					neighbor, Vector2i(x, z)
				)
				if int(snapshot.get("terrain_object_effect_count", 0)) > 0:
					return {
						"ok": true,
						"region_key": neighbor,
						"coordinate": Vector2i(x, z),
					}
	return {"ok": false}


func _first_cross_region_effect_chunk(projection: RefCounted) -> Dictionary:
	for z in range(Grid.CHUNK_COUNT_Z):
		var left: Dictionary = projection.local_snapshot_for_chunk(
			Vector2i.ZERO, Vector2i(Grid.CHUNK_COUNT_X - 1, z)
		)
		var right: Dictionary = projection.local_snapshot_for_chunk(
			Vector2i.RIGHT, Vector2i(0, z)
		)
		if int(left.get("terrain_object_effect_count", 0)) > 0 			and int(right.get("terrain_object_effect_count", 0)) > 0:
			return {
				"ok": true,
				"left_region": Vector2i.ZERO,
				"z_chunk": z,
			}
	return {"ok": false}


func _frame_by_source(projection: RefCounted, source_id: String) -> Dictionary:
	for region in [
		Vector2i.ZERO,
		Vector2i.RIGHT,
		Vector2i.LEFT,
		Vector2i(0, 1),
		Vector2i(0, -1),
	]:
		for coordinate in Grid.all_coordinates():
			for frame in projection.get_local_frames_for_chunk(region, coordinate):
				if String(frame.get("source_instance_id", "")) == source_id:
					return frame.duplicate(true)
	return {}


func _fixture_instance(
	registry: RefCounted,
	region_key: Vector2i,
	position_mm: Vector3i,
	instance_id: String
) -> Dictionary:
	var definition_id := "firstparty.core_rocks:granite"
	var ids: Array[String] = [definition_id]
	var pin_result: Dictionary = registry.pin_definitions(ids)
	var recipe: Dictionary = registry.evaluate_rock_recipe(definition_id, 31337)
	var interaction: Dictionary = registry.resolve_terrain_interaction(definition_id)
	if not pin_result.get("ok", false) \
		or (pin_result.get("pins", []) as Array).is_empty() \
		or not recipe.get("ok", false) \
		or not interaction.get("ok", false):
		return {}
	return {
		"instance_id": instance_id,
		"definition_id": definition_id,
		"content_pin": pin_result["pins"][0].duplicate(true),
		"world_id": WORLD_ID,
		"world_seed": WORLD_SEED,
		"generator_version": Field.GENERATOR_VERSION,
		"region_key": region_key,
		"position_mm": position_mm,
		"default_scale_milli": Vector3i(1000, 1000, 1000),
		"default_yaw_mdeg": 0,
		"geometry": recipe["geometry"].duplicate(true),
		"geometry_seeds": recipe["geometry_seeds"].duplicate(true),
		"terrain_interaction": interaction["rule"].duplicate(true),
		"terrain_interaction_pin": interaction["pin"].duplicate(true),
		"terrain_interaction_applied": false,
		"instance_components": {},
	}


func _snapshot(frames: Array) -> Dictionary:
	var sampling_frames: Array[Dictionary] = []
	for frame_value in frames:
		if typeof(frame_value) != TYPE_DICTIONARY:
			continue
		var compiled: Dictionary = Frame.compile_prevalidated(frame_value)
		if compiled.get("ok", false):
			sampling_frames.append(compiled["sampling_frame"])
	return {
		"valid": true,
		"revision": 0,
		"cache_scope_id": 1,
		"world_seed": WORLD_SEED,
		"generator_version": Field.GENERATOR_VERSION,
		"centers": PackedVector3Array(),
		"radii": PackedFloat64Array(),
		"modes": PackedByteArray(),
		"sequences": PackedInt64Array(),
		"materialized_tiles": [],
		"materialized_tile_index": {},
		"candidate_operation_count": 0,
		"ledger_operation_count": 0,
		"terrain_object_local_frames": frames.duplicate(true),
		"terrain_object_sampling_frames": sampling_frames,
		"terrain_object_effect_count": frames.size(),
		"terrain_object_effect_snapshot_sha256": "test",
	}


func _cpu_mesh_hash(result: Dictionary) -> String:
	var positions: PackedVector3Array = result.get(
		"positions", PackedVector3Array()
	)
	var bytes := PackedByteArray()
	for point in positions:
		bytes.append_array(
			("%0.9f,%0.9f,%0.9f;" % [point.x, point.y, point.z]).to_utf8_buffer()
		)
	return bytes.hex_encode().sha256_text()


func _simple_command(
	command_id: String,
	operation: String,
	entity_id: String,
	world_revision: int,
	entity_revision: int
) -> Dictionary:
	return {
		"schema_version": 1,
		"command_id": command_id,
		"operation": operation,
		"origin": {"type": "player", "id": "phase-d-test"},
		"world_id": WORLD_ID,
		"world_seed": WORLD_SEED,
		"generator_version": Field.GENERATOR_VERSION,
		"expected_world_revision": world_revision,
		"expected_entity_revision": entity_revision,
		"entity_id": entity_id,
	}


func _v3(value: Array) -> Vector3:
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
		"PASS" if failures == 0 else "FAIL",
		assertions,
		failures,
	])
	_remove_tree(ProjectSettings.globalize_path(ROOT))
	quit(0 if failures == 0 else 1)
