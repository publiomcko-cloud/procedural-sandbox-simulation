extends SceneTree

const Registry := preload("res://scripts/modding/content_definition_registry.gd")
const StateService := preload("res://scripts/objects/procedural_object_state_service.gd")
const CommandService := preload("res://scripts/entities/entity_command_service.gd")
const StateContract := preload("res://scripts/objects/procedural_object_state_contract.gd")
const EffectRuntime := preload("res://scripts/terrain/terrain_object_effect_runtime.gd")
const ProjectionStore := preload("res://scripts/terrain/terrain_object_effect_projection_store.gd")
const ProjectionContract := preload("res://scripts/terrain/terrain_object_effect_projection_contract.gd")
const Effect := preload("res://scripts/terrain/terrain_object_effect.gd")
const Brush := preload("res://scripts/terrain/sdf_brush_edit_state.gd")
const Grid := preload("res://scripts/terrain/terrain_chunk_grid.gd")
const Spatial := preload("res://scripts/terrain/terrain_spatial_ownership.gd")
const Mesher := preload("res://scripts/terrain/marching_tetrahedra.gd")
const Lod01Mesher := preload("res://scripts/terrain/lod01_chunk_mesher.gd")
const Shared := preload("res://scripts/terrain/shared_surface_boundary_authority.gd")
const Field := preload("res://scripts/terrain/sdf_world.gd")

const WORLD_ID := "issue108-phase-d"
const WORLD_SEED := 424242
const ROOT := "user://issue108-phase-d-tests"
const DEFINITION_ID := "firstparty.core_rocks:granite"

var assertions := 0
var failures := 0
var evidence: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_remove_tree(ProjectSettings.globalize_path(ROOT))
	var registry := Registry.new()
	var registered: Dictionary = registry.discover_and_register(
		["res://mods/first-party"]
	)
	_check(registered.get("ok", false), "first-party registry initializes")
	if not registered.get("ok", false):
		_finish()
		return

	var state: RefCounted = StateService.new()
	_check(
		state.initialize(
			WORLD_ID,
			WORLD_SEED,
			Field.GENERATOR_VERSION,
			ROOT + "/object-state"
		).get("ok", false),
		"authoritative object state initializes"
	)

	var runtime := EffectRuntime.new()
	var runtime_init: Dictionary = runtime.initialize(
		WORLD_ID,
		WORLD_SEED,
		Field.GENERATOR_VERSION,
		state,
		registry,
		ROOT + "/effect-projection"
	)
	_check(
		runtime_init.get("ok", false),
		"live effect runtime initializes on pre-command schema"
	)
	if not runtime_init.get("ok", false):
		_finish()
		return

	var initial_reconcile: Dictionary = runtime.reconcile_source_region(
		Vector2i.ZERO
	)
	_check(
		initial_reconcile.get("ok", false)
			and int(initial_reconcile.get("effect_count", 0)) > 0,
		"schema-1 procedural authority projects live terrain effects"
	)
	var scope: Dictionary = runtime.projection.get_scope_snapshot(Vector2i.ZERO)
	var source_effect := _first_effect(scope)
	_check(
		not source_effect.is_empty(),
		"live fixture selects one projected source effect"
	)
	if source_effect.is_empty():
		_finish()
		return

	var source_region := _effect_region(source_effect)
	_check(
		source_region == Vector2i.ZERO,
		"selected projected effect belongs to canonical source region"
	)
	var interior := _vector3(source_effect["interior_point_local"])
	var coordinate := _chunk_for_local(interior)
	var terrain := Brush.new(WORLD_SEED, Field.GENERATOR_VERSION)
	var base_snapshot: Dictionary = terrain.get_meshing_snapshot_for_chunk(
		source_region, coordinate
	)
	var live_snapshot: Dictionary = runtime.attach_to_terrain_snapshot(
		base_snapshot,
		[{"region_key": source_region, "coordinate": coordinate}]
	)
	_check(
		live_snapshot.get("valid", false)
			and int(live_snapshot.get("terrain_object_effect_count", 0)) > 0
			and not String(
				live_snapshot.get(
					"terrain_object_effect_snapshot_sha256", ""
				)
			).is_empty(),
		"worker snapshot carries immutable indexed terrain-object effects"
	)

	var base_density := Brush.sample_density_snapshot(
		WORLD_SEED, source_region, interior, false, base_snapshot
	)
	var live_density := Brush.sample_density_snapshot(
		WORLD_SEED, source_region, interior, false, live_snapshot
	)
	_check(
		live_density <= base_density
			and live_density < 0.0,
		"live sampler applies object imprint after base terrain"
	)

	# Player FILL is evaluated before the anchored imprint. The object therefore
	# retains its reserved contact volume at the same point.
	var interior_world := Spatial.region_local_to_world(
		source_region, interior
	)
	_check(
		terrain.add_sphere(
			Brush.Mode.FILL,
			interior_world,
			2.0
		),
		"player FILL fixture commits before object-effect sampling"
	)
	var fill_snapshot: Dictionary = terrain.get_meshing_snapshot_for_chunk(
		source_region, coordinate
	)
	var fill_only_density := Brush.sample_density_snapshot(
		WORLD_SEED, source_region, interior, false, fill_snapshot
	)
	var fill_live_snapshot: Dictionary = runtime.attach_to_terrain_snapshot(
		fill_snapshot,
		[{"region_key": source_region, "coordinate": coordinate}]
	)
	var fill_then_imprint_density := Brush.sample_density_snapshot(
		WORLD_SEED,
		source_region,
		interior,
		false,
		fill_live_snapshot
	)
	_check(
		fill_then_imprint_density <= fill_only_density
			and fill_then_imprint_density < 0.0,
		"composition order is player edits then anchored imprint"
	)

	# The immutable effect snapshot must materially change terrain geometry, not
	# only a scalar helper outside the meshing pipeline.
	var base_mesh: Dictionary = Mesher.build_chunk_cpu_data(
		WORLD_SEED,
		source_region,
		coordinate,
		false,
		base_snapshot
	)
	var live_mesh: Dictionary = Mesher.build_chunk_cpu_data(
		WORLD_SEED,
		source_region,
		coordinate,
		false,
		live_snapshot
	)
	_check(
		base_mesh.get("valid", false) and live_mesh.get("valid", false),
		"LOD0 mesher accepts base and effect snapshots"
	)
	var mesh_changed := int(base_mesh.get("triangle_count", -1)) 		!= int(live_mesh.get("triangle_count", -1)) 		or _points_sha(base_mesh.get("positions", PackedVector3Array())) 			!= _points_sha(live_mesh.get("positions", PackedVector3Array()))
	_check(
		mesh_changed,
		"terrain-object effect changes the authoritative terrain mesh output"
	)

	var lod1_base: Dictionary = Lod01Mesher.build_chunk_cpu_data(
		WORLD_SEED,
		source_region,
		coordinate,
		base_snapshot
	)
	var lod1_live: Dictionary = Lod01Mesher.build_chunk_cpu_data(
		WORLD_SEED,
		source_region,
		coordinate,
		live_snapshot
	)
	_check(
		lod1_base.get("valid", false)
			and lod1_live.get("valid", false),
		"LOD1 mesher accepts the same immutable effect snapshot as LOD0"
	)
	var lod1_changed := int(lod1_base.get("triangle_count", -1)) 		!= int(lod1_live.get("triangle_count", -1)) 		or _points_sha(lod1_base.get("positions", PackedVector3Array())) 			!= _points_sha(lod1_live.get("positions", PackedVector3Array()))
	_check(
		lod1_changed,
		"terrain-object effect changes LOD1 geometry through the shared sampler"
	)

	# Shared X seam: build one deterministic edge imprint and require the shared
	# surface authority to see it as part of the same snapshot on both sides.
	var seam_effect_result := Effect.build_from_instance(
		_fixture_instance(
			registry,
			Vector2i.ZERO,
			Vector3i(15850, 3800, 6000),
			"phase-d-seam-source"
		),
		0
	)
	_check(
		seam_effect_result.get("ok", false),
		"seam fixture builds a valid region-local effect"
	)
	if seam_effect_result.get("ok", false):
		var seam_effect: Dictionary = seam_effect_result["effect"]
		var seam_terrain := Brush.new(
			WORLD_SEED, Field.GENERATOR_VERSION
		)
		var seam_base: Dictionary = Shared.make_x_pair_snapshot(
			seam_terrain, Vector2i.ZERO, 1
		)
		var seam_live := seam_base.duplicate(true)
		seam_live["terrain_object_effects"] = [seam_effect]
		seam_live["terrain_object_effect_snapshot_sha256"] = (
			JSON.stringify(seam_effect, "", true, true).sha256_text()
		)
		seam_live["terrain_object_effect_source_world_revision"] = 0
		seam_live["terrain_object_effect_count"] = 1
		var shared_base: Dictionary = Shared.build_x_region_boundary_pair(
			WORLD_SEED,
			Vector2i.ZERO,
			1,
			seam_base,
			true
		)
		var shared_live: Dictionary = Shared.build_x_region_boundary_pair(
			WORLD_SEED,
			Vector2i.ZERO,
			1,
			seam_live,
			true
		)
		_check(
			shared_base.get("valid", false)
				and shared_live.get("valid", false),
			"shared-surface authority accepts effect-bearing pair snapshot"
		)
		_check(
			String(shared_live.get("mesh_signature", ""))
				!= String(shared_base.get("mesh_signature", "")),
			"seam effect changes one shared authority surface, not independent side meshes"
		)
		_check(
			String(
				shared_live["left"].get(
					"shared_mesh_signature", ""
				)
			) == String(
				shared_live["right"].get(
					"shared_mesh_signature", ""
				)
			),
			"both seam publications carry the identical shared effect signature"
		)

	# Upgrade entity command schema and mutate the projected source. Runtime
	# reconciliation returns the exact union of old/new chunk dependencies so the
	# scene can remesh only touched visible chunks.
	_check(
		state.upgrade_history_snapshot_schema().get("ok", false),
		"entity state upgrades for lifecycle integration probe"
	)
	var commands := CommandService.new()
	_check(
		commands.initialize(state, registry).get("ok", false)
			and commands.reconstruct_region(source_region).get("ok", false),
		"authoritative command service reconstructs effect source region"
	)
	var source_id := String(source_effect["source_instance_id"])
	var transformed: Dictionary = commands.dispatch(
		_set_component_command(
			"00000000-0000-4000-8000-00000000d001",
			source_id,
			state.get_revision(),
			state.get_entity_revision(source_id),
			{"schema_version": 1, "properties": {
				"translation_mm": [0, 250, 0],
				"rotation_mdeg": [0, 12000, 0],
				"scale_milli": [1100, 1000, 900],
			}}
		)
	)
	_check(
		transformed.get("ok", false),
		"authoritative transform commits before effect remesh reconciliation"
	)
	var transformed_reconcile: Dictionary = runtime.reconcile_source_region(
		source_region
	)
	_check(
		transformed_reconcile.get("ok", false)
			and transformed_reconcile.get("changed", false)
			and int(
				transformed_reconcile.get(
					"affected_chunk_count", 0
				)
			) > 0,
		"transform reconciliation returns bounded old/new chunk dependencies"
	)
	var transformed_effect := _effect_for_source(
		runtime.projection.get_scope_snapshot(source_region),
		source_id
	)
	_check(
		not transformed_effect.is_empty()
			and String(
				transformed_effect["source_fingerprint_sha256"]
			) != String(
				source_effect["source_fingerprint_sha256"]
			),
		"live projection advances transformed source fingerprint"
	)

	var deleted: Dictionary = commands.dispatch(
		_simple_command(
			"00000000-0000-4000-8000-00000000d002",
			"ENTITY_DELETE",
			source_id,
			state.get_revision(),
			state.get_entity_revision(source_id)
		)
	)
	_check(deleted.get("ok", false), "authoritative delete commits")
	var deleted_reconcile: Dictionary = runtime.reconcile_source_region(
		source_region
	)
	_check(
		deleted_reconcile.get("ok", false)
			and int(
				deleted_reconcile.get(
					"affected_chunk_count", 0
				)
			) > 0
			and _effect_for_source(
				runtime.projection.get_scope_snapshot(source_region),
				source_id
			).is_empty(),
		"delete removes live imprint and returns chunks that must be restored"
	)

	var restored: Dictionary = commands.dispatch(
		_simple_command(
			"00000000-0000-4000-8000-00000000d003",
			"ENTITY_RESTORE",
			source_id,
			state.get_revision(),
			state.get_entity_revision(source_id)
		)
	)
	_check(restored.get("ok", false), "authoritative restore commits")
	var restored_reconcile: Dictionary = runtime.reconcile_source_region(
		source_region
	)
	var restored_effect := _effect_for_source(
		runtime.projection.get_scope_snapshot(source_region),
		source_id
	)
	_check(
		restored_reconcile.get("ok", false)
			and not restored_effect.is_empty()
			and String(restored_effect["effect_id"])
				== String(source_effect["effect_id"]),
		"restore reintroduces the same stable live imprint identity"
	)

	# Phase-C projection files are derived caches. A known older schema is
	# preserved and ignored, then the next current-schema save advances the
	# generation rather than treating the old cache as corruption.
	var obsolete_root := ProjectSettings.globalize_path(
		ROOT + "/obsolete-projection"
	)
	var obsolete_scope := obsolete_root.path_join("regions/r_0_0")
	DirAccess.make_dir_recursive_absolute(obsolete_scope)
	var obsolete_payload := "{}"
	var obsolete_envelope := {
		"format": ProjectionStore.FORMAT_ID,
		"schema_version": 1,
		"generation": 1,
		"payload_json": obsolete_payload,
		"payload_sha256": obsolete_payload.sha256_text(),
	}
	var obsolete_path := obsolete_scope.path_join(
		"projection-00000001.json"
	)
	var obsolete_file := FileAccess.open(obsolete_path, FileAccess.WRITE)
	if obsolete_file != null:
		obsolete_file.store_string(
			JSON.stringify(obsolete_envelope, "", true, true)
		)
		obsolete_file.flush()
		obsolete_file.close()
	var projection_store := ProjectionStore.new(obsolete_root)
	projection_store.configure(
		WORLD_ID, WORLD_SEED, Field.GENERATOR_VERSION
	)
	var obsolete_load: Dictionary = projection_store.load_scope(
		Vector2i.ZERO
	)
	_check(
		obsolete_load.get("ok", false)
			and not obsolete_load.get("found", true)
			and int(
				obsolete_load.get(
					"ignored_incomplete_generations", 0
				)
			) == 1
			and FileAccess.file_exists(obsolete_path),
		"obsolete derived projection schema is preserved and scheduled for rebuild"
	)
	var rebuilt_empty := ProjectionContract.empty_snapshot(
		WORLD_ID,
		WORLD_SEED,
		Field.GENERATOR_VERSION,
		Vector2i.ZERO
	)
	var rebuilt_save: Dictionary = projection_store.save_snapshot(
		rebuilt_empty
	)
	_check(
		rebuilt_save.get("ok", false)
			and int(rebuilt_save.get("generation", -1)) == 2,
		"current projection rebuild advances past preserved obsolete generation"
	)

	evidence = {
		"initial_effect_count": int(
			initial_reconcile.get("effect_count", 0)
		),
		"worker_effect_count": int(
			live_snapshot.get("terrain_object_effect_count", 0)
		),
		"base_density_at_interior": base_density,
		"live_density_at_interior": live_density,
		"fill_only_density": fill_only_density,
		"fill_then_imprint_density": fill_then_imprint_density,
		"base_triangles": int(base_mesh.get("triangle_count", 0)),
		"live_triangles": int(live_mesh.get("triangle_count", 0)),
		"lod1_base_triangles": int(lod1_base.get("triangle_count", 0)),
		"lod1_live_triangles": int(lod1_live.get("triangle_count", 0)),
		"transform_affected_chunks": int(
			transformed_reconcile.get("affected_chunk_count", 0)
		),
		"delete_affected_chunks": int(
			deleted_reconcile.get("affected_chunk_count", 0)
		),
	}
	_finish()


func _fixture_instance(
	registry: RefCounted,
	region_key: Vector2i,
	position_mm: Vector3i,
	instance_id: String
) -> Dictionary:
	var ids: Array[String] = [DEFINITION_ID]
	var pins: Dictionary = registry.pin_definitions(ids)
	var recipe: Dictionary = registry.evaluate_rock_recipe(
		DEFINITION_ID, 31337
	)
	var interaction: Dictionary = registry.resolve_terrain_interaction(
		DEFINITION_ID
	)
	if not pins.get("ok", false) 		or pins.get("pins", []).is_empty() 		or not recipe.get("ok", false) 		or not interaction.get("ok", false):
		return {}
	return {
		"instance_id": instance_id,
		"definition_id": DEFINITION_ID,
		"content_pin": pins["pins"][0].duplicate(true),
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


func _first_effect(scope: Dictionary) -> Dictionary:
	var effects: Dictionary = scope.get("effects", {})
	var ids: Array[String] = []
	for effect_id in effects:
		ids.append(String(effect_id))
	ids.sort()
	return (
		(effects[ids[0]] as Dictionary).duplicate(true)
		if not ids.is_empty()
		else {}
	)


func _effect_for_source(scope: Dictionary, source_id: String) -> Dictionary:
	for value in (scope.get("effects", {}) as Dictionary).values():
		var effect: Dictionary = value
		if String(effect.get("source_instance_id", "")) == source_id:
			return effect.duplicate(true)
	return {}


func _effect_region(effect: Dictionary) -> Vector2i:
	var values: Array = effect["source_region_key"]
	return Vector2i(int(values[0]), int(values[1]))


func _chunk_for_local(point: Vector3) -> Vector2i:
	var width := float(Grid.CELLS_PER_CHUNK_X) * Grid.SAMPLE_STEP
	var depth := float(Grid.CELLS_PER_CHUNK_Z) * Grid.SAMPLE_STEP
	return Vector2i(
		clampi(floori(point.x / width), 0, Grid.CHUNK_COUNT_X - 1),
		clampi(floori(point.z / depth), 0, Grid.CHUNK_COUNT_Z - 1)
	)


func _set_component_command(
	command_id: String,
	entity_id: String,
	world_revision: int,
	entity_revision: int,
	component: Dictionary
) -> Dictionary:
	return {
		"schema_version": 1,
		"command_id": command_id,
		"operation": "ENTITY_SET_COMPONENT",
		"origin": {"type": "player", "id": "phase-d-test"},
		"world_id": WORLD_ID,
		"world_seed": WORLD_SEED,
		"generator_version": Field.GENERATOR_VERSION,
		"expected_world_revision": world_revision,
		"expected_entity_revision": entity_revision,
		"entity_id": entity_id,
		"component_id": StateContract.COMPONENT_TRANSFORM,
		"component": component,
	}


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


func _vector3(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))


func _points_sha(points: PackedVector3Array) -> String:
	var rows: Array[String] = []
	for point in points:
		rows.append("%.9f,%.9f,%.9f" % [point.x, point.y, point.z])
	return "\n".join(rows).sha256_text()


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
		if name == "." or name == "..":
			continue
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
