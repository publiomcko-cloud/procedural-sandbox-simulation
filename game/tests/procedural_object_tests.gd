extends SceneTree

const Loader := preload("res://scripts/modding/declarative_mod_loader.gd")
const Registry := preload("res://scripts/modding/content_definition_registry.gd")
const ObjectWorld := preload("res://scripts/objects/procedural_object_world.gd")
const ObjectStream := preload("res://scripts/objects/procedural_object_stream.gd")
const RockMeshAdapter := preload("res://scripts/objects/procedural_rock_mesh_adapter.gd")
const WorldState := preload("res://scripts/terrain/terrain_world_state.gd")
const BrushState := preload("res://scripts/terrain/sdf_brush_edit_state.gd")
const SaveStore := preload("res://scripts/terrain/terrain_world_save_store.gd")
const Field := preload("res://scripts/terrain/sdf_world.gd")
const ObjectStateService := preload("res://scripts/objects/procedural_object_state_service.gd")
const ObjectStateContract := preload("res://scripts/objects/procedural_object_state_contract.gd")
const StaticBatch := preload("res://scripts/objects/procedural_object_static_batch.gd")
const Spatial := preload("res://scripts/terrain/terrain_spatial_ownership.gd")

const SEED := 424242
const WORLD_ID := "procedural-object-test-world"

var assertions := 0
var failures := 0
var _mod_root := ""
var _issue118_stray_root := ""


func _initialize() -> void:
	await _run()
	if failures == 0:
		print("PROCEDURAL_OBJECT_PASS: assertions=%d failures=0" % assertions)
	else:
		push_error("PROCEDURAL_OBJECT_FAIL: assertions=%d failures=%d" % [assertions, failures])
	quit(0 if failures == 0 else 1)


func _run() -> void:
	_cleanup_stale_p2b_fixtures()
	_mod_root = "user://mods/p2_0a_test_%d" % Time.get_ticks_usec()
	var external_copy: String = _create_external_package(_mod_root)
	var roots: Array[String] = _test_roots()
	_test_same_registry_pipeline(roots)
	_test_versioned_recipe_compatibility()
	_test_mesh_conversion()
	_test_seed_family_variation()
	_test_order_independent_records(roots)
	_test_population_contracts_and_distribution(roots)
	_test_population_identity_persistence(roots)
	_test_static_population_batch(roots)
	_test_population_publication_queue(roots)
	_test_population_density_benchmarks(roots)
	_test_persistent_instance_state(roots)
	_test_runtime_streaming_and_unload_reload(roots)
	_test_seed_partition_isolation(roots)
	_test_missing_and_incompatible_content(roots)
	_test_terrain_and_save_authority_isolation()
	_check(not external_copy.is_empty(), "external example was copied only into the disposable isolated user-data test fixture")
	await _test_playable_scene_publication()
	_remove_tree(ProjectSettings.globalize_path(_issue118_stray_root))
	_remove_tree(ProjectSettings.globalize_path(_mod_root))


func _test_same_registry_pipeline(roots: Array[String]) -> void:
	var registry := Registry.new()
	var result: Dictionary = registry.discover_and_register(roots)
	_check(result.get("ok", false), "first-party and user:// external packages register through the P0.3 entrypoint")
	_check(registry.has_mod("firstparty.core_rocks") and registry.has_mod("official.example.procedural_rock"), "both required packages are registered")
	var builtin: Dictionary = registry.get_definition("firstparty.core_rocks:granite")
	var external: Dictionary = registry.get_definition("official.example.procedural_rock:basalt_stack")
	_check(not builtin.is_empty() and not external.is_empty(), "both namespaces resolve through the shared definition API")
	var builtin_recipe: Dictionary = registry.evaluate_rock_recipe(String(builtin.get("id", "")), 654321)
	var external_recipe: Dictionary = registry.evaluate_rock_recipe(String(external.get("id", "")), 654321)
	_check(builtin_recipe.get("ok", false) and external_recipe.get("ok", false), "first-party and external recipes use the same evaluator")
	_check(builtin.get("schema_version") == 2 and builtin_recipe.get("algorithm") == RockMeshAdapter.ALGORITHM and builtin_recipe.get("profile") == "granite_massive_weathered_v1", "first-party granite uses the explicit geological schema/profile")
	_check(external.get("schema_version") == 2 and external_recipe.get("algorithm") == RockMeshAdapter.ALGORITHM and external_recipe.get("profile") == "basalt_fractured_anisotropic_v1", "external basalt uses the same registry contract with its distinct versioned profile")
	_check(builtin_recipe.get("geometry", {}).get("fracture_plane_count", 0) < external_recipe.get("geometry", {}).get("fracture_plane_count", 0), "the basalt profile declares a denser fracture system")
	_check(builtin_recipe.get("geometry_seeds", {}).size() == 4 and external_recipe.get("geometry_seeds", {}).size() == 4, "the registry derives independent structure, fracture, wear and detail seeds")
	_check(registry.pin_definitions([builtin["id"], external["id"]]).get("ok", false), "runtime object definitions carry P0.3 content version pins")
	var runtime: ProceduralObjectStream = ObjectStream.new()
	var runtime_state_path := _unique_state_path("registry")
	var ignored_before_result: Dictionary = Loader.discover_and_validate(roots, ["user://mods"])
	var ignored_before := int(ignored_before_result.get("optional_directory_ignored_count", 0))
	_issue118_stray_root = "user://mods/issue118_runtime_residual_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_issue118_stray_root))
	var default_roots: Dictionary = runtime.initialize(SEED, WORLD_ID, [], runtime_state_path)
	_check(default_roots.get("ok", false), "runtime discovers valid first-party and installed external packages despite an unmanifested user mod directory")
	_check(int(default_roots.get("optional_directory_ignored_count", 0)) == ignored_before + 1 and runtime.get_package_discovery_summary().contains("undeclared folder"), "runtime reports the newly ignored residual folder alongside any pre-existing optional directories")
	_check(not runtime.get_package_discovery_summary().contains(ProjectSettings.globalize_path("user://mods")), "runtime discovery warning does not expose a private absolute path")
	_check(runtime._configured_package_roots().size() == 2, "installed example takes precedence over its repository copy to avoid duplicate package IDs")
	runtime.free()
	_remove_tree(runtime_state_path)


func _test_versioned_recipe_compatibility() -> void:
	var registry := Registry.new()
	var legacy_recipe := {
		"algorithm": "stacked_spheres_v1", "lobe_count": 2, "radius_min_mm": 400, "radius_max_mm": 500,
		"vertical_step_mm": 300, "spread_mm": 150, "jitter_mm": 20,
	}
	var legacy_definition := {
		"schema_version": 1, "type": "procedural_rock", "id": "test.legacy_rocks:granite",
		"display_name": "Legacy granite fixture", "tags": ["rock", "legacy"], "recipe": legacy_recipe,
	}
	var manifest := {
		"id": "test.legacy_rocks", "version": "1.0.0", "schema_version": 1,
		"requires_engine": "4.7.2", "dependencies": [], "content_roots": ["objects/"], "script_policy": "data_only",
	}
	var discovery := {"ok": true, "packages": [{"manifest": manifest, "definitions": [legacy_definition]}]}
	var registration: Dictionary = registry.register_discovered(discovery)
	var evaluated: Dictionary = registry.evaluate_rock_recipe("test.legacy_rocks:granite", 99)
	_check(registration.get("ok", false) and evaluated.get("ok", false) and evaluated.get("algorithm") == "stacked_spheres_v1" and evaluated.get("lobes", []).size() == 2, "schema-1 stacked_spheres_v1 retains its original declarative meaning")
	var invalid_legacy := legacy_definition.duplicate(true)
	invalid_legacy["recipe"]["algorithm"] = "geological_halfspace_v1"
	var rejected_legacy := Registry.new().register_discovered({"ok": true, "packages": [{"manifest": manifest, "definitions": [invalid_legacy]}]})
	_check(not rejected_legacy.get("ok", false), "schema-1 cannot silently reinterpret legacy fields as the geological algorithm")
	var isolated_seeds := {"structure": 11, "fracture": 22, "wear": 33, "detail": 44}
	_check(not RockMeshAdapter.build_mesh(legacy_recipe, isolated_seeds).get("ok", false), "legacy stacked-spheres data is not passed into the new geological adapter")
	var geological_bytes: PackedByteArray = FileAccess.get_file_as_bytes("res://mods/first-party/core-rocks/objects/granite.json")
	var geological: Dictionary = JSON.parse_string(geological_bytes.get_string_from_utf8())
	geological["schema_version"] = 1
	geological["id"] = "test.legacy_rocks:granite"
	var rejected_new := Registry.new().register_discovered({"ok": true, "packages": [{"manifest": manifest, "definitions": [geological]}]})
	_check(not rejected_new.get("ok", false), "schema-2 geological parameters cannot be loaded under schema-1")
	var unknown_profile := JSON.parse_string(geological_bytes.get_string_from_utf8()) as Dictionary
	unknown_profile["id"] = "test.legacy_rocks:granite"
	unknown_profile["recipe"]["profile"] = "granite_magic_v1"
	var rejected_profile := Registry.new().register_discovered({"ok": true, "packages": [{"manifest": manifest, "definitions": [unknown_profile]}]})
	_check(not rejected_profile.get("ok", false), "unregistered geological profiles fail schema validation")


func _test_mesh_conversion() -> void:
	var registry := Registry.new()
	var registration: Dictionary = registry.discover_and_register(_test_roots())
	_check(registration.get("ok", false), "mesh conversion fixture can load both package definitions")
	if not registration.get("ok", false):
		return
	for definition_id in ObjectWorld.SLOT_DEFINITIONS:
		var recipe: Dictionary = registry.evaluate_rock_recipe(definition_id, 91234)
		var geometry: Dictionary = recipe.get("geometry", {})
		var seeds: Dictionary = recipe.get("geometry_seeds", {})
		var first: Dictionary = RockMeshAdapter.build_mesh(geometry, seeds)
		var second: Dictionary = RockMeshAdapter.build_mesh(geometry, seeds)
		var alternate_recipe: Dictionary = registry.evaluate_rock_recipe(definition_id, 91235)
		var alternate_seed: Dictionary = RockMeshAdapter.build_mesh(alternate_recipe.get("geometry", {}), alternate_recipe.get("geometry_seeds", {}))
		_check(first.get("ok", false) and second.get("ok", false), "%s recipe converts to visible mesh data" % definition_id)
		if not first.get("ok", false) or not second.get("ok", false):
			continue
		var first_arrays: Array = first["mesh"].surface_get_arrays(0)
		var second_arrays: Array = second["mesh"].surface_get_arrays(0)
		var alternate_arrays: Array = alternate_seed["mesh"].surface_get_arrays(0) if alternate_seed.get("ok", false) else []
		var vertices: PackedVector3Array = first_arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = first_arrays[Mesh.ARRAY_NORMAL]
		_check(not vertices.is_empty() and vertices.size() == normals.size(), "%s mesh has matched vertex and normal arrays" % definition_id)
		_check(vertices == second_arrays[Mesh.ARRAY_VERTEX] and normals == second_arrays[Mesh.ARRAY_NORMAL], "%s geometry conversion is deterministic" % definition_id)
		_check(alternate_seed.get("ok", false) and vertices != alternate_arrays[Mesh.ARRAY_VERTEX], "%s seed changes the irregular silhouette deterministically" % definition_id)
		_check(int(first.get("triangle_count", 0)) >= 100 and int(first.get("triangle_count", 0)) <= 500 and vertices.size() == int(first.get("triangle_count", 0)) * 3, "%s stays within the exploratory 100-500 triangle closed-shell budget" % definition_id)
		_check(first["mesh"].get_surface_count() == 1 and int(first.get("geometry_version", -1)) == RockMeshAdapter.GEOMETRY_VERSION, "%s has one registered geometry-adapter versioned surface" % definition_id)
		_check(first.get("algorithm") == "geological_halfspace_v1" and first.get("profile") == recipe.get("profile"), "%s reports its explicit geometry algorithm and profile" % definition_id)
		_check(float(first.get("volume_m3", 0.0)) > 0.0 and float(first.get("surface_area_m2", 0.0)) > 0.0, "%s reports finite positive volume and surface area" % definition_id)
		var finite := true
		for index in range(vertices.size()):
			if not vertices[index].is_finite() or not normals[index].is_finite() or normals[index].length_squared() < 0.9:
				finite = false
				break
		_check(finite, "%s mesh positions and normals are finite and normalized" % definition_id)
		var bounds_min: Vector3 = first["bounds_min"]
		var bounds_max: Vector3 = first["bounds_max"]
		_check(absf(bounds_min.y) <= 1.0e-5, "%s keeps its deterministic contact base at region-local y=0" % definition_id)
		var integrity: Dictionary = _inspect_low_poly_mesh(vertices, normals, (bounds_min + bounds_max) * 0.5, (bounds_max - bounds_min) * 0.5)
		_check(integrity.get("ok", false), "%s has outward flat normals, nondegenerate faces, one connected shell and closed two-face edges (%s)" % [definition_id, integrity.get("reason", "ok")])
		var box_volume := (bounds_max.x - bounds_min.x) * (bounds_max.y - bounds_min.y) * (bounds_max.z - bounds_min.z)
		_check(float(first["volume_m3"]) < box_volume * 0.97 and float(first["volume_m3"]) > box_volume * 0.18, "%s is clipped into a non-spherical asymmetric solid within its bounds" % definition_id)
		var angular_faces := false
		for normal_index in range(3, normals.size(), 3):
			if normals[0].dot(normals[normal_index]) < 0.97:
				angular_faces = true
				break
		_check(angular_faces, "%s retains distinct flat facet normals rather than a smooth sphere surface" % definition_id)
		for seed_key in ["structure", "fracture", "wear", "detail"]:
			var changed_seeds: Dictionary = seeds.duplicate(true)
			changed_seeds[seed_key] = int(changed_seeds[seed_key]) + 1
			var stage_variant: Dictionary = RockMeshAdapter.build_mesh(geometry, changed_seeds)
			_check(stage_variant.get("ok", false) and _mesh_arrays(stage_variant)[Mesh.ARRAY_VERTEX] != vertices, "%s %s seed independently affects geometry" % [definition_id, seed_key])
		_check(vertices == _mesh_arrays(RockMeshAdapter.build_mesh(geometry, seeds))[Mesh.ARRAY_VERTEX], "%s repeated recipe conversion preserves deterministic geometry" % definition_id)
		_check(not RockMeshAdapter.build_mesh(geometry, {"structure": -1, "fracture": 2, "wear": 3, "detail": 4}).get("ok", false), "%s invalid geometry seeds are rejected" % definition_id)
		var malformed_geometry := geometry.duplicate(true)
		malformed_geometry["half_extent_x_mm"] = 9007199254740992
		_check(not RockMeshAdapter.build_mesh(malformed_geometry, seeds).get("ok", false), "%s rejects unsafe integer dimensions" % definition_id)
	_check(not RockMeshAdapter.build_mesh({}, {} ).get("ok", false), "empty geological geometry recipe is rejected")


func _inspect_low_poly_mesh(vertices: PackedVector3Array, normals: PackedVector3Array, center: Vector3, half_extents: Vector3) -> Dictionary:
	if vertices.size() < 300 or vertices.size() > 1500 or vertices.size() != normals.size() or vertices.size() % 3 != 0:
		return {"ok": false, "reason": "invalid_triangle_arrays"}
	var edge_counts: Dictionary = {}
	var graph: Dictionary = {}
	var radial_min := INF
	var radial_max := -INF
	for index in range(0, vertices.size(), 3):
		var a := vertices[index]
		var b := vertices[index + 1]
		var c := vertices[index + 2]
		var area_normal := (b - a).cross(c - a)
		if area_normal.length_squared() <= 1.0e-12:
			return {"ok": false, "reason": "degenerate_triangle"}
		var face_center := (a + b + c) / 3.0
		if area_normal.dot(face_center - center) <= 0.0:
			return {"ok": false, "reason": "inward_or_ambiguous_winding"}
		var expected_normal := area_normal.normalized()
		for offset in range(3):
			if normals[index + offset].dot(expected_normal) < 0.9999:
				return {"ok": false, "reason": "face_normal_mismatch"}
		var keys := [_vertex_key(a), _vertex_key(b), _vertex_key(c)]
		for key in keys:
			if not graph.has(key):
				graph[key] = []
		for edge_index in range(3):
			var first_key: String = keys[edge_index]
			var second_key: String = keys[(edge_index + 1) % 3]
			var edge_key := _edge_key(first_key, second_key)
			edge_counts[edge_key] = int(edge_counts.get(edge_key, 0)) + 1
			(graph[first_key] as Array).append(second_key)
			(graph[second_key] as Array).append(first_key)
		for vertex_index in range(index, index + 3):
			var normalized_vertex := vertices[vertex_index] - center
			var normalized_radius := Vector3(normalized_vertex.x / half_extents.x, normalized_vertex.y / half_extents.y, normalized_vertex.z / half_extents.z).length()
			radial_min = minf(radial_min, normalized_radius)
			radial_max = maxf(radial_max, normalized_radius)
	for edge_key in edge_counts:
		if int(edge_counts[edge_key]) != 2:
			return {"ok": false, "reason": "open_or_nonmanifold_edge:%d:%s" % [int(edge_counts[edge_key]), String(edge_key)]}
	var start_key: String = graph.keys()[0]
	var visited: Dictionary = {start_key: true}
	var pending: Array[String] = [start_key]
	while not pending.is_empty():
		var key: String = pending.pop_back()
		for neighbor in graph[key]:
			if not visited.has(neighbor):
				visited[neighbor] = true
				pending.append(neighbor)
	if visited.size() != graph.size():
		return {"ok": false, "reason": "disconnected_shells"}
	return {"ok": true, "reason": "ok", "radial_spread": radial_max - radial_min}


func _test_seed_family_variation() -> void:
	var registry := Registry.new()
	var repository_example_root := ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir().path_join("mods/examples")
	var setup: Dictionary = registry.discover_and_register(["res://mods/first-party", repository_example_root])
	_check(setup.get("ok", false), "seed gallery can register bundled granite and example basalt profiles")
	if not setup.get("ok", false):
		return
	for definition_id in ObjectWorld.SLOT_DEFINITIONS:
		var signatures: Dictionary = {}
		var triangle_total := 0
		for sample_index in range(12):
			var recipe: Dictionary = registry.evaluate_rock_recipe(definition_id, 700100 + sample_index)
			var built: Dictionary = RockMeshAdapter.build_mesh(recipe.get("geometry", {}), recipe.get("geometry_seeds", {}))
			_check(built.get("ok", false), "%s seed-gallery sample %02d builds (%s)" % [definition_id, sample_index + 1, built.get("reason", "ok")])
			if not built.get("ok", false):
				continue
			var vertices: PackedVector3Array = _mesh_arrays(built)[Mesh.ARRAY_VERTEX]
			var signature := "%s:%d" % [str(vertices[0]), vertices.size()]
			for vertex_index in range(0, vertices.size(), 3):
				signature += ";" + _vertex_key(vertices[vertex_index])
			_check(not signatures.has(signature), "%s gallery seed %02d has a distinct deterministic silhouette" % [definition_id, sample_index + 1])
			signatures[signature] = true
			triangle_total += int(built["triangle_count"])
		_check(signatures.size() == 12, "%s produces all twelve requested independent gallery silhouettes" % definition_id)
		print("ROCK_GALLERY_TEST_METRICS: family=%s count=%d mean_triangles=%.2f" % [definition_id, signatures.size(), float(triangle_total) / 12.0])


func _mesh_arrays(result: Dictionary) -> Array:
	if not result.get("ok", false):
		return []
	return result["mesh"].surface_get_arrays(0)


func _vertex_key(vertex: Vector3) -> String:
	return "%d,%d,%d" % [roundi(vertex.x * 1000000.0), roundi(vertex.y * 1000000.0), roundi(vertex.z * 1000000.0)]


func _edge_key(first: String, second: String) -> String:
	return first + "|" + second if first < second else second + "|" + first


func _test_order_independent_records(roots: Array[String]) -> void:
	var registry := Registry.new()
	var setup: Dictionary = registry.discover_and_register(roots)
	_check(setup.get("ok", false), "placement fixture registers common content")
	if not setup.get("ok", false):
		return
	var visitation: Array[Vector2i] = [Vector2i(-2, -1), Vector2i(0, 0), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(2, 1)]
	var forward: Dictionary = {}
	for key in visitation:
		var generated: Dictionary = ObjectWorld.build_region_instances(SEED, WORLD_ID, key, registry)
		_check(generated.get("ok", false), "signed region %s creates deterministic placements (%s)" % [key, generated.get("reason", "ok")])
		forward[key] = generated.get("instances", [])
	var reverse: Dictionary = {}
	visitation.reverse()
	for key in visitation:
		reverse[key] = ObjectWorld.build_region_instances(SEED, WORLD_ID, key, registry).get("instances", [])
	var all_ids: Dictionary = {}
	for key in forward:
		_check(forward[key] == reverse[key], "region %s placement is independent of region discovery order" % key)
		_check(forward[key].size() >= 2, "region %s retains both legacy objects and adds bounded declarative population" % key)
		_check(String(forward[key][0].get("population_algorithm", "")) == ObjectWorld.LEGACY_ALGORITHM and String(forward[key][1].get("population_algorithm", "")) == ObjectWorld.LEGACY_ALGORITHM, "region %s preserves the two exact P2.0B compatibility identities before additive population" % key)
		for instance in forward[key]:
			var instance_id: String = instance["instance_id"]
			_check(not all_ids.has(instance_id), "stable instance ID is unique across signed regions")
			all_ids[instance_id] = true
			_check(instance["position_mm"] is Vector3i and instance["region_key"] == key, "placement uses integer local millimeters and its canonical signed region")
			_check(instance["content_pin"].get("mod_version", "").is_empty() == false and instance["recipe_algorithm"] == "geological_halfspace_v1" and instance["geometry_profile"] != "" and instance["geometry_seeds"].size() == 4, "instance pins its definition, recipe version, profile and independent stage seeds")
			_check(instance.get("instance_state", null) is Dictionary and instance["instance_state"].is_empty(), "unmodified procedural instance starts with no mutable override; persisted deltas stay in the separate sparse state snapshot")
			var local_position := Vector3(instance["position_mm"]) / 1000.0
			var below: float = Field.sample_density(SEED, key, local_position + Vector3.DOWN * 0.05)
			var above: float = Field.sample_density(SEED, key, local_position + Vector3.UP * 0.05)
			_check(below > 0.0 and above < 0.0, "surface placement is derived from canonical solid-to-empty density crossing")


func _test_population_contracts_and_distribution(roots: Array[String]) -> void:
	var registry := Registry.new()
	var setup: Dictionary = registry.discover_and_register(roots)
	_check(setup.get("ok", false) and int(setup.get("population_rule_count", 0)) == 4, "P0.3 registers two versioned compatibility rules and two generic package population rules")
	if not setup.get("ok", false):
		return
	var rule_ids := registry.get_population_rule_ids()
	var sorted_ids := rule_ids.duplicate()
	sorted_ids.sort()
	_check(rule_ids == sorted_ids and rule_ids.size() == 4, "population rule enumeration is stable and independent of package discovery order")
	var all_ids: Dictionary = {}
	var generic_counts: Array[int] = []
	var region_keys: Array[Vector2i] = [Vector2i(-3, -2), Vector2i(-2, -1), Vector2i(-1, 0), Vector2i(0, 0), Vector2i(1, -1), Vector2i(2, 1), Vector2i(3, -2), Vector2i(-4, 3), Vector2i(4, 2), Vector2i(0, -3), Vector2i(-1, -1), Vector2i(2, -3)]
	var forward: Dictionary = {}
	for key in region_keys:
		var generated: Dictionary = ObjectWorld.build_region_instances(SEED, WORLD_ID, key, registry)
		_check(generated.get("ok", false), "population generation succeeds for signed region %s (%s)" % [key, generated.get("reason", "ok")])
		if not generated.get("ok", false):
			return
		var instances: Array[Dictionary] = generated["instances"]
		_check(instances.size() <= ObjectWorld.MAX_OBJECTS_PER_REGION and int(generated.get("candidate_cell_count", 0)) <= ObjectWorld.MAX_CANDIDATE_CELLS_PER_REGION and int(generated.get("surface_anchor_count", 0)) <= ObjectWorld.MAX_SURFACE_ANCHORS_PER_REGION, "region %s output, lattice and surface sampling stay within explicit resource budgets" % key)
		forward[key] = instances
		var generic_count := 0
		var same_region_separation_valid := true
		for instance_index in range(instances.size()):
			var instance: Dictionary = instances[instance_index]
			var instance_id := String(instance["instance_id"])
			_check(not all_ids.has(instance_id), "population identity is collision-free across signed regions")
			all_ids[instance_id] = true
			var world_position: Vector3 = Spatial.region_origin_world(key) + Vector3(instance["position_mm"]) / 1000.0
			var owner: Vector2i = Spatial.world_to_region_local(world_position).get("region_key", Vector2i.ZERO)
			_check(owner == key, "half-open ownership places each instance in its canonical positive or negative region")
			if not String(instance.get("population_rule_id", "")).is_empty():
				generic_count += 1
				var identity: Dictionary = ObjectStateContract.identity_for_instance(instance)
				var validated := ObjectStateContract.validate_identity(identity, WORLD_ID, SEED, Field.GENERATOR_VERSION)
				_check(validated.get("ok", false) and int(identity.get("identity_schema_version", -1)) == 2, "generic population identity pins its namespaced rule and candidate index")
				var rule_pin: Dictionary = instance.get("population_rule_pin", {})
				_check(rule_pin.get("rule_id", "") == instance.get("population_rule_id", "") and String(rule_pin.get("rule_sha256", "")).length() == 64, "persistent population identity pins the exact declarative rule content")
			_check(int(instance.get("default_scale_milli", Vector3i.ZERO).x) >= 500 and int(instance.get("default_scale_milli", Vector3i.ZERO).x) <= 2000 and int(instance.get("default_yaw_mdeg", 0)) >= 0, "declared scale and orientation constraints are represented in deterministic records")
			if instance_index < 2:
				var expected_legacy_id := "%s/seed-%d/object/%s/region/%d,%d/slot/%d" % [WORLD_ID, SEED, instance["definition_id"], key.x, key.y, instance_index]
				var expected_placement_seed := ObjectWorld._mix_seed(SEED, key, instance_index)
				var expected_recipe_seed := ObjectWorld._mix_seed(expected_placement_seed, key, 97 + instance_index)
				_check(instance["instance_id"] == expected_legacy_id and int(instance["placement_seed"]) == expected_placement_seed and int(instance["recipe_seed"]) == expected_recipe_seed, "P2.0B slot %d ID and seeds remain byte-for-byte derivable in region %s" % [instance_index, key])
			for prior_index in range(instance_index):
				var prior: Dictionary = instances[prior_index]
				var distance_mm := Vector2(float(prior["position_mm"].x - instance["position_mm"].x), float(prior["position_mm"].z - instance["position_mm"].z)).length()
				var required_mm := maxf(float(prior.get("minimum_separation_mm", 0)), maxf(float(instance.get("minimum_separation_mm", 0)), float(prior.get("clearance_radius_mm", 0)) + float(instance.get("clearance_radius_mm", 0)) + 100.0))
				same_region_separation_valid = same_region_separation_valid and distance_mm >= required_mm
		_check(same_region_separation_valid, "generated footprints respect minimum spacing and conservative rock clearance in region %s" % key)
		generic_counts.append(generic_count)
	var boundary_clear := true
	for first_key in region_keys:
		for second_key in region_keys:
			if abs(first_key.x - second_key.x) + abs(first_key.y - second_key.y) != 1:
				continue
			for first_instance in forward[first_key]:
				for second_instance in forward[second_key]:
					var first_world := Spatial.region_origin_world(first_key) + Vector3(first_instance["position_mm"]) / 1000.0
					var second_world := Spatial.region_origin_world(second_key) + Vector3(second_instance["position_mm"]) / 1000.0
					var footprint_distance_mm := Vector2(first_world.x - second_world.x, first_world.z - second_world.z).length() * 1000.0
					var footprint_required := float(first_instance.get("clearance_radius_mm", 0)) + float(second_instance.get("clearance_radius_mm", 0)) + 100.0
					boundary_clear = boundary_clear and footprint_distance_mm >= footprint_required
	_check(boundary_clear, "adjacent positive and negative regions keep deterministic static footprints separated across their shared boundaries")
	var reverse_keys := region_keys.duplicate()
	reverse_keys.reverse()
	var reverse_equal := true
	for key in reverse_keys:
		reverse_equal = reverse_equal and forward[key] == ObjectWorld.build_region_instances(SEED, WORLD_ID, key, registry).get("instances", [])
	_check(reverse_equal, "region visitation order does not change candidate selection, identities, transforms or records")
	var reversed_roots: Array[String] = roots.duplicate()
	reversed_roots.reverse()
	var reversed_registry := Registry.new()
	var reversed_registration: Dictionary = reversed_registry.discover_and_register(reversed_roots)
	var package_order_equal: bool = reversed_registration.get("ok", false)
	if package_order_equal:
		for key in region_keys:
			package_order_equal = package_order_equal and forward[key] == ObjectWorld.build_region_instances(SEED, WORLD_ID, key, reversed_registry).get("instances", [])
	_check(package_order_equal, "reversing package search roots does not change any generated content or stable identity")
	var minimum_count := 2147483647
	var maximum_count := 0
	for count in generic_counts:
		minimum_count = mini(minimum_count, count)
		maximum_count = maxi(maximum_count, count)
	_check(maximum_count > minimum_count, "seeded density tickets produce reproducible regional population variation rather than a fixed object count")
	var next_seed_region: Dictionary = ObjectWorld.build_region_instances(SEED + 1, WORLD_ID, Vector2i.ZERO, registry)
	var seed_domain_separated: bool = next_seed_region.get("ok", false)
	if seed_domain_separated:
		for new_instance in next_seed_region["instances"]:
			seed_domain_separated = seed_domain_separated and String(new_instance["instance_id"]).contains("/seed-%d/" % (SEED + 1))
	_check(seed_domain_separated, "world seed participates in generated population instance identities")
	var discovery: Dictionary = Loader.discover_and_validate(roots)
	var malformed: Dictionary = discovery.duplicate(true)
	var packages: Array = malformed["packages"]
	var rules: Array = packages[0]["population_rules"]
	rules[0]["algorithm"] = "arbitrary_script_callback_v1"
	packages[0]["population_rules"] = rules
	malformed["packages"] = packages
	var rejected_registry := Registry.new()
	var rejected := rejected_registry.register_discovered(malformed)
	_check(not rejected.get("ok", false) and rejected_registry.get_population_rule_ids().is_empty() and rejected_registry.get_definition("firstparty.core_rocks:granite").is_empty(), "unsupported package algorithm rejects transactionally without partial registration or script execution")
	var bad_density_discovery: Dictionary = discovery.duplicate(true)
	var density_packages: Array = bad_density_discovery["packages"]
	var first_rules: Array = density_packages[0]["population_rules"]
	for rule in first_rules:
		if String(rule.get("algorithm", "")) == Registry.POPULATION_ALGORITHM:
			rule["density_milli_per_region"] = 15001
	density_packages[0]["population_rules"] = first_rules
	bad_density_discovery["packages"] = density_packages
	_check(not Registry.new().register_discovered(bad_density_discovery).get("ok", false), "out-of-contract density is rejected at the package boundary")
	var changed_legacy_discovery: Dictionary = discovery.duplicate(true)
	var legacy_packages: Array = changed_legacy_discovery["packages"]
	for package_index in range(legacy_packages.size()):
		var package: Dictionary = legacy_packages[package_index]
		var package_rules: Array = package.get("population_rules", [])
		for rule_value in package_rules:
			var rule: Dictionary = rule_value
			if String(rule.get("algorithm", "")) == Registry.LEGACY_POPULATION_ALGORITHM:
				rule["surface"]["maximum_slope_mdeg"] = 45000
		package["population_rules"] = package_rules
		legacy_packages[package_index] = package
	changed_legacy_discovery["packages"] = legacy_packages
	var legacy_registry := Registry.new()
	var changed_legacy_result: Dictionary = legacy_registry.register_discovered(changed_legacy_discovery)
	_check(not changed_legacy_result.get("ok", false) and changed_legacy_result.get("reason") == "population_rule_legacy_contract_invalid" and legacy_registry.get_population_rule_ids().is_empty(), "compatibility rules reject changed fields that the identity-preserving legacy generator does not consume")


func _test_population_identity_persistence(roots: Array[String]) -> void:
	var registry := Registry.new()
	if not registry.discover_and_register(roots).get("ok", false):
		_check(false, "population persistence fixture registers package rules")
		return
	var population: Dictionary = {}
	for key in [Vector2i.ZERO, Vector2i(-1, 0), Vector2i(1, -2), Vector2i(-3, 2)]:
		var generated := ObjectWorld.build_region_instances(SEED, WORLD_ID, key, registry)
		if generated.get("ok", false):
			for instance in generated["instances"]:
				if not String(instance.get("population_rule_id", "")).is_empty():
					population = instance
					break
		if not population.is_empty():
			break
	_check(not population.is_empty(), "bounded fixture finds at least one declaratively populated object for persistence testing")
	if population.is_empty():
		return
	var directory := _unique_state_path("population_identity")
	var writer: ProceduralObjectStateService = ObjectStateService.new()
	_check(writer.initialize(WORLD_ID, SEED, Field.GENERATOR_VERSION, directory).get("ok", false), "population state service starts without per-object baseline records")
	_check(writer.resolve_instance(population).get("ok", false), "population instance resolves from its deterministic rule and recipe seeds")
	var appearance := {"schema_version": 1, "properties": {"tint_milli": [750, 800, 900], "label": "mod-population-instance"}}
	var mutation := writer.set_component(population, ObjectStateContract.COMPONENT_APPEARANCE, appearance)
	_check(mutation.get("ok", false) and writer.get_revision() == 1, "schema-2 population identity accepts a sparse P2.0B component override (%s)" % mutation.get("reason", "ok"))
	var reader: ProceduralObjectStateService = ObjectStateService.new()
	var reload := reader.initialize(WORLD_ID, SEED, Field.GENERATOR_VERSION, directory)
	var resolved := reader.resolve_instance(population)
	_check(reload.get("ok", false) and resolved.get("ok", false) and resolved.get("instance", {}).get("instance_components", {}).has(ObjectStateContract.COMPONENT_APPEARANCE), "population override survives service restart using the exact pinned rule identity (%s)" % resolved.get("reason", "ok"))
	var deleted_result: Dictionary = reader.delete_instance(population)
	_check(deleted_result.get("ok", false) and reader.resolve_instance(population).get("deleted", false), "population candidate can be logically excluded without changing its procedural identity (%s)" % deleted_result.get("reason", "ok"))
	var restored := ProceduralObjectStateService.new()
	var restored_init: Dictionary = restored.initialize(WORLD_ID, SEED, Field.GENERATOR_VERSION, directory)
	var restored_baseline: Dictionary = restored.resolve_instance(population)
	var restored_result: Dictionary = restored.restore_instance(population)
	_check(restored_init.get("ok", false) and restored_baseline.get("ok", false) and restored_result.get("ok", false), "population candidate restoration accepts its previously pinned identity (%s / %s)" % [restored_init.get("reason", "ok"), restored_result.get("reason", "ok")])
	_check(restored.resolve_instance(population).get("ok", false) and restored.resolve_instance(population).instance.instance_components.is_empty(), "restored population candidate returns to derived state with no per-object record")
	_remove_tree(directory)


func _test_static_population_batch(roots: Array[String]) -> void:
	var registry := Registry.new()
	if not registry.discover_and_register(roots).get("ok", false):
		_check(false, "static batch fixture registers declarative package content")
		return
	var items: Array[Dictionary] = []
	for key in [Vector2i(-1, -1), Vector2i.ZERO, Vector2i(1, 1), Vector2i(-2, 1), Vector2i(3, -2)]:
		var generated := ObjectWorld.build_region_instances(SEED, WORLD_ID, key, registry)
		if not generated.get("ok", false):
			continue
		for instance in generated["instances"]:
			if String(instance.get("population_rule_id", "")).is_empty():
				continue
			var mesh_data := RockMeshAdapter.build_mesh(instance["geometry"], instance["geometry_seeds"])
			if mesh_data.get("ok", false):
				items.append({"instance_id": instance["instance_id"], "mesh": mesh_data["mesh"], "position": Vector3(instance["position_mm"]) / 1000.0, "scale_milli": instance["default_scale_milli"], "yaw_mdeg": instance["default_yaw_mdeg"]})
		if items.size() >= 2:
			break
	_check(not items.is_empty(), "generic population produces meshable static instances")
	if items.is_empty():
		return
	var first := StaticBatch.build(items)
	var second := StaticBatch.build(items)
	_check(first.get("ok", false) and second.get("ok", false), "bounded static batch publishes declarative instances in one deterministic mesh")
	if first.get("ok", false) and second.get("ok", false):
		_check(first["instance_ids"] == second["instance_ids"] and first["vertex_count"] == second["vertex_count"], "batch ordering and geometry counts are deterministic across input order")
		_check(first["mesh"].surface_get_arrays(0)[Mesh.ARRAY_VERTEX] == second["mesh"].surface_get_arrays(0)[Mesh.ARRAY_VERTEX], "batched transformed vertices are bitwise stable")
		_check(int(first["vertex_count"]) <= StaticBatch.MAX_BATCH_VERTICES and int(first["triangle_count"]) == int(first["vertex_count"]) / 3, "batch output respects explicit vertex and triangle budgets")
	var invalid: Array[Dictionary] = [{"instance_id": "bad", "mesh": null}]
	_check(not StaticBatch.build(invalid).get("ok", false), "invalid package mesh cannot produce a partial static batch")


func _test_population_publication_queue(roots: Array[String]) -> void:
	var manager: ProceduralObjectStream = ObjectStream.new()
	var state_path := _unique_state_path("population_queue")
	_check(manager.initialize(SEED, WORLD_ID, roots, state_path).get("ok", false), "bounded population publication queue initializes through the declarative package loader")
	if not manager.initialized:
		manager.free()
		_remove_tree(state_path)
		return
	var key := Vector2i(-2, 3)
	var state_a: RefCounted = WorldState.new(SEED, key, BrushState.new(SEED))
	var state_b: RefCounted = WorldState.new(SEED, key, BrushState.new(SEED))
	manager.expect_region_publication(key, 10)
	var first := manager.enqueue_region_publication(key, state_a, 10)
	var replacement := manager.enqueue_region_publication(key, state_b, 10)
	_check(first.get("ok", false) and replacement.get("reason", "") == "queued_replaced" and manager.get_performance_snapshot().get("pending_region_publication_count", 0) == 1, "same-region queued work is replaced without duplicate queue entries")
	manager.expect_region_publication(key, 11)
	_check(manager.get_performance_snapshot().get("pending_region_publication_count", 0) == 0 and not manager.enqueue_region_publication(key, state_a, 10).get("ok", false), "a superseding token cancels pending work and rejects stale enqueue attempts")
	_check(manager.enqueue_region_publication(key, state_b, 11).get("ok", false), "current publication token is admitted after cancellation")
	_check(manager.process_queued_publications() == 1 and manager.get_active_region_count() == 1 and manager.get_performance_snapshot().get("publications_last_process_tick", 0) == 1, "one explicit queue tick publishes at most one complete region batch")
	var metrics: Dictionary = manager.get_performance_snapshot().get("last_region", {})
	_check(metrics.get("batched_instance_count", 0) > 0 and metrics.get("individual_node_count", 0) == 2 and metrics.get("batch_vertex_count", 0) <= StaticBatch.MAX_BATCH_VERTICES, "unmodified population is batched while P2.0B compatibility objects remain individual and bounded")
	var records := manager.get_region_instance_records(key)
	var generic_id := ""
	for instance in records:
		if not String(instance.get("population_rule_id", "")).is_empty():
			generic_id = String(instance["instance_id"])
			break
	if not generic_id.is_empty():
		var promoted := manager.set_instance_component(generic_id, ObjectStateContract.COMPONENT_APPEARANCE, {"schema_version": 1, "properties": {"tint_milli": [700, 800, 900], "label": "promoted"}})
		_check(promoted.get("ok", false), "mutable generic instance persists through the existing P2.0B state service")
		var region_root: Node3D = manager.get_node("Objects_%d_%d" % [key.x, key.y])
		var individual_found := false
		for child in region_root.get_children():
			if String(child.get_meta("stable_instance_id", "")) == generic_id:
				individual_found = true
		_check(individual_found, "mutated batched population candidate is republished as an individual stateful representative")
	var canceled_key := Vector2i(4, -2)
	var canceled_state: RefCounted = WorldState.new(SEED, canceled_key, BrushState.new(SEED))
	manager.enqueue_region_publication(canceled_key, canceled_state, 4)
	manager.unload_region(canceled_key)
	_check(manager.get_performance_snapshot().get("pending_region_publication_count", 0) == 0, "unloading an unpublished region releases its queued state and prevents later publication")
	manager.free()
	_remove_tree(state_path)


func _test_population_density_benchmarks(roots: Array[String]) -> void:
	var density_values: Array[int] = [0, 1000, 5000, 10000]
	var sample_keys: Array[Vector2i] = [Vector2i(-3, -2), Vector2i(-2, 1), Vector2i(-1, -3), Vector2i.ZERO, Vector2i(1, 2), Vector2i(2, -1), Vector2i(3, 1), Vector2i(-4, 3)]
	for density in density_values:
		var discovery: Dictionary = Loader.discover_and_validate(roots)
		if not discovery.get("ok", false):
			_check(false, "density benchmark source packages remain valid (%s)" % discovery.get("reason", "unknown"))
			return
		var packages: Array = discovery["packages"]
		for package_index in range(packages.size()):
			var package: Dictionary = packages[package_index]
			var rules: Array = package.get("population_rules", [])
			for rule_value in rules:
				var rule: Dictionary = rule_value
				if String(rule.get("algorithm", "")) == Registry.POPULATION_ALGORITHM:
					rule["density_milli_per_region"] = density
			package["population_rules"] = rules
			packages[package_index] = package
		discovery["packages"] = packages
		var candidate_registry := Registry.new()
		var registration: Dictionary = candidate_registry.register_discovered(discovery)
		_check(registration.get("ok", false), "exploratory density %d registry remains schema-valid" % density)
		if not registration.get("ok", false):
			continue
		var generation_samples: Array[int] = []
		var total_instances := 0
		var maximum_instances := 0
		var anchors := 0
		var memory_before := OS.get_static_memory_usage()
		for repeat_index in range(2):
			for key in sample_keys:
				var generated: Dictionary = ObjectWorld.build_region_instances(SEED, WORLD_ID, key, candidate_registry)
				if not generated.get("ok", false):
					_check(false, "density %d region %s remains inside bounded generation (%s)" % [density, key, generated.get("reason", "unknown")])
					continue
				generation_samples.append(int(generated.get("timings_usec", {}).get("total", 0)))
				var count := (generated.get("instances", []) as Array).size()
				total_instances += count
				maximum_instances = maxi(maximum_instances, count)
				anchors += int(generated.get("surface_anchor_count", 0))
		var memory_after := OS.get_static_memory_usage()
		generation_samples.sort()
		var p50 := generation_samples[int(floor(float(generation_samples.size() - 1) * 0.50))] if not generation_samples.is_empty() else 0
		var p95 := generation_samples[ceili(float(generation_samples.size()) * 0.95) - 1] if not generation_samples.is_empty() else 0
		var stream: ProceduralObjectStream = ObjectStream.new()
		var state_path := _unique_state_path("population_benchmark_%d" % density)
		var init_result: Dictionary = stream.initialize(SEED, WORLD_ID, roots, state_path)
		var publication_samples: Array[int] = []
		var geometry_samples: Array[int] = []
		var batch_samples: Array[int] = []
		var batch_vertex_peak := 0
		if init_result.get("ok", false):
			stream.registry = candidate_registry
			for index in range(3):
				var key: Vector2i = sample_keys[index]
				var state: RefCounted = WorldState.new(SEED, key, BrushState.new(SEED))
				var publish_result: Dictionary = stream.publish_region(key, state)
				_check(publish_result.get("ok", false), "density %d publication sample %d succeeds (%s)" % [density, index, publish_result.get("reason", "ok")])
				if publish_result.get("ok", false):
					var region_metrics: Dictionary = stream.get_performance_snapshot().get("last_region", {})
					publication_samples.append(int(region_metrics.get("publication_usec", 0)))
					geometry_samples.append(int(region_metrics.get("mesh_build_usec", 0)))
					batch_samples.append(int(region_metrics.get("batch_build_usec", 0)))
					batch_vertex_peak = maxi(batch_vertex_peak, int(region_metrics.get("batch_vertex_count", 0)))
		else:
			_check(false, "density %d publication stream initializes" % density)
		publication_samples.sort()
		geometry_samples.sort()
		batch_samples.sort()
		var publication_p50 := _sample_percentile(publication_samples, 0.50)
		var publication_p95 := _sample_percentile(publication_samples, 0.95)
		print("P2C_POPULATION_UNSCORED: density_milli=%d generation_samples=%d generation_p50_usec=%d generation_p95_usec=%d mean_objects=%.2f max_objects=%d mean_surface_anchors=%.2f publication_samples=%d publication_p50_usec=%d publication_p95_usec=%d mesh_build_p50_usec=%d batch_build_p50_usec=%d batch_vertex_peak=%d static_memory_before_bytes=%d static_memory_after_bytes=%d" % [density, generation_samples.size(), p50, p95, float(total_instances) / float(maxi(1, generation_samples.size())), maximum_instances, float(anchors) / float(maxi(1, generation_samples.size())), publication_samples.size(), publication_p50, publication_p95, _sample_percentile(geometry_samples, 0.50), _sample_percentile(batch_samples, 0.50), batch_vertex_peak, memory_before, memory_after])
		stream.free()
		_remove_tree(state_path)


func _test_runtime_streaming_and_unload_reload(roots: Array[String]) -> void:
	var stale_manager: ProceduralObjectStream = ObjectStream.new()
	var stale_path := _unique_state_path("stale_publication")
	var stale_init := stale_manager.initialize(SEED, WORLD_ID, roots, stale_path)
	_check(stale_init.get("ok", false), "stale publication guard fixture initializes independently")
	var stale_key := Vector2i(-4, -2)
	var stale_state: RefCounted = WorldState.new(SEED, stale_key, BrushState.new(SEED))
	stale_manager.expect_region_publication(stale_key, 12)
	var rejected_stale := stale_manager.publish_region(stale_key, stale_state, false, 11)
	_check(not rejected_stale.get("ok", false) and rejected_stale.get("reason") == "stale_object_region_publication" and stale_manager.get_active_region_count() == 0, "superseded region token cannot publish an object root")
	var current_publication := stale_manager.publish_region(stale_key, stale_state, false, 12)
	var stale_after_current := stale_manager.publish_region(stale_key, stale_state, true, 11)
	_check(current_publication.get("ok", false) and not stale_after_current.get("ok", false) and stale_manager.get_region_instance_records(stale_key).size() >= 2, "late stale completion cannot replace the current published region")
	stale_manager.free()
	_remove_tree(stale_path)
	var manager: ProceduralObjectStream = ObjectStream.new()
	var state_path := _unique_state_path("stream")
	var initialization: Dictionary = manager.initialize(SEED, WORLD_ID, roots, state_path)
	_check(initialization.get("ok", false), "runtime adapter initializes from the common registry")
	_check(manager.get_error_summary().is_empty(), "successful initialization has no hidden package or region errors")
	if not initialization.get("ok", false):
		return
	root.add_child(manager)
	var key := Vector2i(-3, 2)
	var state: RefCounted = WorldState.new(SEED, key, BrushState.new(SEED))
	var before_revision: int = state.get("brush_edits").revision
	var first: Dictionary = manager.publish_region(key, state)
	_check(first.get("ok", false) and first.get("instance_count", 0) >= 2, "published negative region receives the two compatibility objects and any deterministic population")
	if not first.get("ok", false):
		manager.free()
		return
	var records_before: Array[Dictionary] = manager.get_region_instance_records(key)
	var geometry_before: Array = _mesh_snapshots(manager, key)
	var baseline_instance_count := manager.get_region_instance_records(key).size()
	_check(manager.get_active_region_count() == 1 and manager.get_visible_instance_count() == baseline_instance_count, "visual object residency is bounded to explicitly published regions")
	var edited_id := String(records_before[0]["instance_id"])
	var component_edit: Dictionary = manager.set_instance_component(edited_id, ObjectStateContract.COMPONENT_TRANSFORM, {"schema_version": 1, "properties": {"translation_mm": [250, 125, -75], "rotation_mdeg": [0, 0, 9000], "scale_milli": [1100, 1000, 900]}})
	_check(component_edit.get("ok", false) and manager.get_instance_state_revision() == 1, "component override commits transactionally before visual publication")
	var stateful_records: Array[Dictionary] = manager.get_region_instance_records(key)
	var changed_record: Dictionary = {}
	for value in stateful_records:
		if value["instance_id"] == edited_id:
			changed_record = value
	_check(changed_record.get("instance_components", {}).has(ObjectStateContract.COMPONENT_TRANSFORM), "published object carries only its sparse mutable component override")
	_check(changed_record.get("geometry_seeds") == records_before[0].get("geometry_seeds") and changed_record.get("content_pin") == records_before[0].get("content_pin"), "mutable transform leaves recipe seeds and P2.0A content pins unchanged")
	var deleted_id := String(records_before[1]["instance_id"])
	var deleted_result: Dictionary = manager.delete_instance(deleted_id)
	_check(deleted_result.get("ok", false) and manager.get_visible_instance_count() == baseline_instance_count - 1 and manager.state_service.get_deleted_count() == 1, "logical deletion is persisted and removes only its active representation")
	var restored: Dictionary = manager.restore_instance(deleted_id)
	_check(restored.get("ok", false) and manager.get_visible_instance_count() == baseline_instance_count and manager.state_service.get_deleted_count() == 0, "restore removes tombstone and reconstructs the deterministic procedural baseline")
	var generic_id := ""
	for record in manager.get_region_instance_records(key):
		if not String(record.get("population_rule_id", "")).is_empty():
			generic_id = String(record["instance_id"])
			break
	if not generic_id.is_empty():
		var generic_override := manager.set_instance_component(generic_id, ObjectStateContract.COMPONENT_APPEARANCE, {"schema_version": 1, "properties": {"tint_milli": [800, 850, 900], "label": "reloaded-population"}})
		_check(generic_override.get("ok", false) and int(manager.get_performance_snapshot().get("batched_instance_count", 0)) < baseline_instance_count - 2, "mutating one population instance promotes it out of the immutable static batch")
	stateful_records = manager.get_region_instance_records(key)
	var duplicate: Dictionary = manager.publish_region(key, state)
	_check(duplicate.get("ok", false) and duplicate.get("reason") == "already_published" and manager.get_child_count() == 1, "repeated publication does not create duplicate region or object nodes")
	manager.set_object_visibility(false)
	_check(manager.get_visible_instance_count() == 0 and manager.get_child_count() == 1, "visibility toggle hides representations without changing domain records")
	_check(manager.delete_instance(deleted_id).get("ok", false), "logical exclusion remains durable before region eviction")
	manager.unload_region(key)
	_check(manager.get_active_region_count() == 0 and manager.get_child_count() == 0, "region unload releases all object rendering nodes")
	_check(manager.restore_instance(deleted_id).get("ok", false), "deleted object can be restored from its pinned deterministic identity while its region is unloaded")
	var second: Dictionary = manager.publish_region(key, state)
	_check(second.get("ok", false), "region reload succeeds while object visualization is hidden")
	if not second.get("ok", false):
		manager.free()
		return
	_check(not manager.get_child(0).visible and manager.get_visible_instance_count() == 0, "streamed-in regions preserve the user's hidden-object setting")
	manager.set_object_visibility(true)
	_check(manager.get_region_instance_records(key) == stateful_records, "reload recreates persistent overrides with identical IDs, pins, seeds and placements")
	_check(_flatten_snapshot_ids(_mesh_snapshots(manager, key)) == _flatten_snapshot_ids(geometry_before), "reloaded individual and batched mesh representations cover the exact original stable instance identities")
	_check(state.get("brush_edits").revision == before_revision and state.get("brush_edits").get_edit_count() == 0, "object publication does not mutate the canonical terrain ledger")
	manager.free()
	_remove_tree(state_path)


func _test_seed_partition_isolation(roots: Array[String]) -> void:
	var manager: ProceduralObjectStream = ObjectStream.new()
	var state_root := _unique_state_path("seed_partition")
	var initialized := manager.initialize(SEED, WORLD_ID, roots, state_root)
	_check(initialized.get("ok", false), "seed-partition fixture initializes the shared object stream")
	if not initialized.get("ok", false):
		manager.free()
		return
	var first_key := Vector2i(-1, 0)
	var second_key := Vector2i(0, 0)
	var first_state: RefCounted = WorldState.new(SEED, first_key, BrushState.new(SEED))
	var second_state: RefCounted = WorldState.new(SEED, second_key, BrushState.new(SEED))
	var first_publish := manager.publish_region(first_key, first_state)
	var second_publish := manager.publish_region(second_key, second_state)
	_check(first_publish.get("ok", false) and second_publish.get("ok", false) and manager.get_active_region_count() == 2, "same-seed neighboring region publications share one visual seed domain")
	if first_publish.get("ok", false) and not manager.get_region_instance_records(first_key).is_empty():
		var original_id := String(manager.get_region_instance_records(first_key)[0].get("instance_id", ""))
		var changed := manager.set_instance_component(original_id, ObjectStateContract.COMPONENT_APPEARANCE, {"schema_version": 1, "properties": {"tint_milli": [850, 900, 1000], "label": "seed-a"}})
		var old_partition := state_root.path_join("seed-%d-generator-%d" % [SEED, Field.GENERATOR_VERSION])
		_check(changed.get("ok", false) and manager.get_instance_state_revision() == 1 and FileAccess.file_exists(old_partition.path_join("objects-00000001.json")), "first seed override is stored only in its versioned seed partition")
	var new_key := Vector2i(1, -1)
	var new_state: RefCounted = WorldState.new(SEED + 1, new_key, BrushState.new(SEED + 1))
	var switched := manager.publish_region(new_key, new_state)
	_check(switched.get("ok", false) and manager.get_active_region_count() == 1, "changing world seed discards visual representatives from the prior seed domain")
	_check(manager.get_instance_state_revision() == 0 and manager.get_region_instance_records(new_key).size() >= 2, "new seed reconstructs a clean derived baseline without inheriting old overrides")
	var old_partition_after_switch := state_root.path_join("seed-%d-generator-%d" % [SEED, Field.GENERATOR_VERSION])
	var new_partition := state_root.path_join("seed-%d-generator-%d" % [SEED + 1, Field.GENERATOR_VERSION])
	_check(FileAccess.file_exists(old_partition_after_switch.path_join("objects-00000001.json")) and not DirAccess.dir_exists_absolute(new_partition), "switching seeds preserves the previous save and derives the new seed without creating an unnecessary object-state file")
	manager.free()
	_remove_tree(state_root)


func _test_missing_and_incompatible_content(_roots: Array[String]) -> void:
	var missing: ProceduralObjectStream = ObjectStream.new()
	var missing_result: Dictionary = missing.initialize(SEED, WORLD_ID, ["res://mods/first-party"])
	_check(not missing_result.get("ok", false) and missing_result.get("reason") == "required_mod_missing:official.example.procedural_rock", "missing required external package fails with a meaningful identity")
	_check(missing.get_error_summary() == "required_mod_missing:official.example.procedural_rock", "required package failure remains visible to the HUD status adapter")
	_check(not missing.initialized, "missing required content cannot produce a partially initialized object stream")
	missing.free()
	var definition_path := _mod_root.path_join("objects/procedural_rock.json")
	var current_definition_bytes: PackedByteArray = FileAccess.get_file_as_bytes(definition_path)
	var legacy_definition := {
		"schema_version": 1,
		"type": "procedural_rock",
		"id": "official.example.procedural_rock:basalt_stack",
		"display_name": "Legacy Basalt Stack",
		"tags": ["rock", "basalt", "example"],
		"recipe": {"algorithm": "stacked_spheres_v1", "lobe_count": 5, "radius_min_mm": 320, "radius_max_mm": 620, "vertical_step_mm": 360, "spread_mm": 180, "jitter_mm": 90},
	}
	_write_text(definition_path, JSON.stringify(legacy_definition, "\t"))
	var legacy_stream: ProceduralObjectStream = ObjectStream.new()
	var legacy_stream_result: Dictionary = legacy_stream.initialize(SEED, WORLD_ID, _test_roots())
	_check(not legacy_stream_result.get("ok", false) and String(legacy_stream_result.get("reason", "")).begins_with("package_registration_failed:population_rule_definition_unsupported"), "schema-1 external recipe cannot satisfy a schema-2 population rule and fails explicitly without silent reinterpretation")
	legacy_stream.free()
	_write_bytes(definition_path, current_definition_bytes)
	var manifest_path := ProjectSettings.globalize_path(_mod_root.path_join("manifest.json"))
	var manifest_bytes: PackedByteArray = FileAccess.get_file_as_bytes(manifest_path)
	var parsed := JSON.parse_string(manifest_bytes.get_string_from_utf8()) as Dictionary
	parsed["requires_engine"] = "9.9.9"
	_write_text(_mod_root.path_join("manifest.json"), JSON.stringify(parsed))
	var incompatible: ProceduralObjectStream = ObjectStream.new()
	var bad_result: Dictionary = incompatible.initialize(SEED, WORLD_ID, _test_roots())
	_check(not bad_result.get("ok", false) and bad_result.get("reason") == "package_discovery_failed:incompatible_engine_version", "incompatible external package is rejected through the existing loader")
	_check(not incompatible.initialized, "incompatible content cannot be replaced by a fallback definition")
	incompatible.free()
	_write_text(_mod_root.path_join("manifest.json"), manifest_bytes.get_string_from_utf8())


func _test_persistent_instance_state(roots: Array[String]) -> void:
	var registry := Registry.new()
	var registered: Dictionary = registry.discover_and_register(roots)
	_check(registered.get("ok", false), "state round-trip fixture uses shared first-party and external data-only registry")
	if not registered.get("ok", false):
		return
	var generated: Dictionary = ObjectWorld.build_region_instances(SEED, WORLD_ID, Vector2i(-2, 3), registry)
	_check(generated.get("ok", false) and generated.get("instances", []).size() >= 2, "state fixture deterministically builds both legacy and additive instances in a negative region")
	if not generated.get("ok", false):
		return
	var baseline: Dictionary = generated["instances"][0]
	var directory := _unique_state_path("roundtrip")
	var service: ProceduralObjectStateService = ObjectStateService.new()
	var initialized: Dictionary = service.initialize(WORLD_ID, SEED, Field.GENERATOR_VERSION, directory)
	_check(initialized.get("ok", false) and not initialized.get("found", true), "new world starts from derived procedural state without per-object disk records")
	var original := service.resolve_instance(baseline)
	_check(original.get("ok", false) and original.get("instance", {}).get("instance_id") == baseline.instance_id and original.instance.get("instance_components", {}).is_empty(), "unmodified object reconstructs from recipe and seed with sparse empty state")
	var bad_component := service.set_component(baseline, ObjectStateContract.COMPONENT_TRANSFORM, {"schema_version": 2, "properties": {}})
	_check(not bad_component.get("ok", false) and service.get_revision() == 0, "unsupported component schema is rejected without advancing revision")
	var transform := {"schema_version": 1, "properties": {"translation_mm": [100, 200, -300], "rotation_mdeg": [0, 0, 45000], "scale_milli": [1000, 1250, 900]}}
	var changed: Dictionary = service.set_component(baseline, ObjectStateContract.COMPONENT_TRANSFORM, transform)
	_check(changed.get("ok", false) and service.get_revision() == 1 and service.get_persisted_override_count() == 1, "bounded transform override persists as one sparse instance record")
	var appearance := {"schema_version": 1, "properties": {"tint_milli": [1000, 600, 350], "label": "granite-test"}}
	var appearance_result := service.set_component(baseline, ObjectStateContract.COMPONENT_APPEARANCE, appearance)
	_check(appearance_result.get("ok", false), "appearance property override accepts bounded declarative values (%s)" % appearance_result.get("reason", "ok"))
	var logical := {"schema_version": 1, "properties": {"values": {"opened": true, "condition": 900, "note": "checked"}}}
	var logical_result := service.set_component(baseline, ObjectStateContract.COMPONENT_LOGICAL, logical)
	_check(logical_result.get("ok", false), "extensible logical state accepts bounded primitive fields (%s)" % logical_result.get("reason", "ok"))
	_check(not service.set_component(baseline, ObjectStateContract.COMPONENT_LOGICAL, {"schema_version": 1, "properties": {"values": {"callback": Callable()}}}).get("ok", false), "logical state rejects executable/object values")
	_check(not service.set_component(baseline, ObjectStateContract.COMPONENT_TRANSFORM, {"schema_version": 1, "properties": {"translation_mm": [8001, 0, 0], "rotation_mdeg": [0, 0, 0], "scale_milli": [1000, 1000, 1000]}}).get("ok", false), "transform range overflow is rejected before persistence")
	_check(not service.set_component(baseline, ObjectStateContract.COMPONENT_APPEARANCE, {"schema_version": 1, "properties": {"tint_milli": [1000, 1000], "label": "bad"}}).get("ok", false), "malformed appearance array is rejected")
	var reconstructed: ProceduralObjectStateService = ObjectStateService.new()
	var restarted := reconstructed.initialize(WORLD_ID, SEED, Field.GENERATOR_VERSION, directory)
	_check(restarted.get("ok", false) and restarted.get("found", false) and reconstructed.get_revision() == 3, "fresh service instance reloads the committed snapshot and revision")
	var resolved := reconstructed.resolve_instance(baseline)
	_check(resolved.get("ok", false) and resolved.instance.instance_components.size() == 3, "save/reload reconstructs all declared components")
	_check(resolved.instance.geometry == baseline.geometry and resolved.instance.geometry_seeds == baseline.geometry_seeds and resolved.instance.position_mm == baseline.position_mm, "overrides do not rewrite deterministic recipe, seeds or placement")
	var child_output: Array = []
	var project_root := ProjectSettings.globalize_path("res://")
	var child_args: PackedStringArray = ["--headless", "--path", project_root, "--script", "res://tests/procedural_object_state_process_probe.gd", "--", "read", WORLD_ID, str(SEED), str(Field.GENERATOR_VERSION), directory]
	var child_exit := OS.execute(OS.get_executable_path(), child_args, child_output, true, false)
	var child_text := "\n".join(PackedStringArray(child_output))
	_check(child_exit == 0 and child_text.contains("OBJECT_STATE_PROCESS_RESTART_PASS"), "separate Godot process reconstructs persisted instance overrides (%s)" % child_text.strip_edges())
	var stale := baseline.duplicate(true)
	stale["content_pin"] = {"content_id": baseline.definition_id, "mod_id": "wrong.mod", "mod_version": "1.0.0", "definition_schema_version": 2}
	_check(not reconstructed.resolve_instance(stale).get("ok", false), "same ID with changed content pin is rejected rather than substituted")
	var incomplete_path: String = directory.path_join("objects-00000099.tmp")
	_check(_write_bytes(incomplete_path, "incomplete".to_utf8_buffer()), "interrupted transaction fixture leaves an incomplete temporary generation")
	var after_interrupt: ProceduralObjectStateService = ObjectStateService.new()
	var recovered := after_interrupt.initialize(WORLD_ID, SEED, Field.GENERATOR_VERSION, directory)
	_check(recovered.get("ok", false) and recovered.get("revision") == 3, "incomplete temporary write preserves the prior complete generation")
	after_interrupt.resolve_instance(baseline)
	var deleted := after_interrupt.delete_instance(baseline)
	_check(deleted.get("ok", false) and after_interrupt.get_deleted_count() == 1 and after_interrupt.get_persisted_override_count() == 0, "logical exclusion replaces overrides in one committed snapshot")
	var after_delete: ProceduralObjectStateService = ObjectStateService.new()
	_check(after_delete.initialize(WORLD_ID, SEED, Field.GENERATOR_VERSION, directory).get("ok", false) and after_delete.resolve_instance(baseline).get("deleted", false), "logical exclusion survives service restart")
	_check(after_delete.restore_instance(baseline).get("ok", false), "explicit restore commits removal of exclusion and prior mutable overrides")
	var final_service: ProceduralObjectStateService = ObjectStateService.new()
	_check(final_service.initialize(WORLD_ID, SEED, Field.GENERATOR_VERSION, directory).get("ok", false), "restored state reloads successfully")
	var restored := final_service.resolve_instance(baseline)
	_check(not restored.get("deleted", true) and restored.instance.instance_components.is_empty(), "restoration returns exact derived baseline without a per-object record")
	var recovered_temp_dir := _unique_state_path("complete_temp_recovery")
	var recovery_writer: ProceduralObjectStateService = ObjectStateService.new()
	_check(recovery_writer.initialize(WORLD_ID, SEED, Field.GENERATOR_VERSION, recovered_temp_dir).get("ok", false), "complete temporary recovery fixture initializes in an isolated root")
	recovery_writer.resolve_instance(baseline)
	_check(recovery_writer.set_component(baseline, ObjectStateContract.COMPONENT_APPEARANCE, appearance).get("ok", false), "complete temporary recovery fixture commits a baseline generation")
	var finalized_path: String = recovered_temp_dir.path_join("objects-%08d.json" % recovery_writer.storage_generation)
	var temporary_path: String = recovered_temp_dir.path_join("objects-%08d.tmp" % recovery_writer.storage_generation)
	_check(DirAccess.rename_absolute(finalized_path, temporary_path) == OK, "simulated interruption occurs after flush but before generation rename")
	var direct_temp_validation: Dictionary = recovery_writer.store._decode_document(FileAccess.get_file_as_bytes(temporary_path))
	_check(direct_temp_validation.get("ok", false), "complete temporary generation independently validates before recovery (%s)" % direct_temp_validation.get("reason", "ok"))
	var recovery_reader: ProceduralObjectStateService = ObjectStateService.new()
	var temp_recovery := recovery_reader.initialize(WORLD_ID, SEED, Field.GENERATOR_VERSION, recovered_temp_dir)
	_check(temp_recovery.get("ok", false) and temp_recovery.get("recovered_temporary", false) and recovery_reader.get_revision() == 1, "complete temporary generation is recovered and finalized without losing accepted state (reason=%s gen=%d recovered=%s revision=%d)" % [temp_recovery.get("reason", ""), temp_recovery.get("generation", -1), temp_recovery.get("recovered_temporary", false), recovery_reader.get_revision()])
	_check(FileAccess.file_exists(finalized_path), "recovered generation becomes an immutable finalized object-state record")
	var wrong_world: ProceduralObjectStateService = ObjectStateService.new()
	_check(not wrong_world.initialize(WORLD_ID, SEED + 1, Field.GENERATOR_VERSION, directory).get("ok", false), "save for a different world seed is rejected rather than merged")
	var blocked_directory := _unique_state_path("blocked_storage")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(blocked_directory.get_base_dir()))
	_check(_write_bytes(blocked_directory, "not-a-directory".to_utf8_buffer()), "failed-write fixture reserves its state directory path as a regular file")
	var blocked_service: ProceduralObjectStateService = ObjectStateService.new()
	var blocked_init := blocked_service.initialize(WORLD_ID, SEED, Field.GENERATOR_VERSION, blocked_directory)
	_check(blocked_init.get("ok", false), "failed-write service starts from derived state without touching the blocking file")
	blocked_service.resolve_instance(baseline)
	var blocked_mutation := blocked_service.set_component(baseline, ObjectStateContract.COMPONENT_APPEARANCE, appearance)
	_check(not blocked_mutation.get("ok", false) and blocked_service.get_revision() == 0 and blocked_service.get_persisted_override_count() == 0, "storage failure rejects the mutation without advancing authoritative in-memory state")
	DirAccess.remove_absolute(blocked_directory)
	var corrupted_dir := _unique_state_path("corrupt")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(corrupted_dir))
	var source_generation_path: String = directory.path_join("objects-%08d.json" % final_service.storage_generation)
	var corrupt_document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(source_generation_path))
	corrupt_document["generation"] = 1
	corrupt_document["payload_json"] = " " + String(corrupt_document["payload_json"])
	_check(_write_bytes(corrupted_dir.path_join("objects-00000001.json"), JSON.stringify(corrupt_document, "", true, true).to_utf8_buffer()), "corruption fixture changes payload bytes while retaining its original digest")
	var corrupt_service: ProceduralObjectStateService = ObjectStateService.new()
	var corrupt_load := corrupt_service.initialize(WORLD_ID, SEED, Field.GENERATOR_VERSION, corrupted_dir)
	_check(not corrupt_load.get("ok", false) and String(corrupt_load.get("reason", "")).contains("corrupt"), "corrupt finalized generation blocks object-state startup fail-closed")
	var incompatible := final_service.snapshot.duplicate(true)
	incompatible["schema_version"] = 3
	_check(not ObjectStateContract.validate_snapshot(incompatible, WORLD_ID, SEED, Field.GENERATOR_VERSION).get("ok", false), "unsupported object-state schema is rejected without migration or reinterpretation")
	var malformed := final_service.snapshot.duplicate(true)
	malformed["revision"] = -1
	_check(not ObjectStateContract.validate_snapshot(malformed, WORLD_ID, SEED, Field.GENERATOR_VERSION).get("ok", false), "malformed revision metadata is rejected before serialization")
	_check(not ObjectStateContract.validate_snapshot(final_service.snapshot, "../outside", SEED, Field.GENERATOR_VERSION).get("ok", false), "world identifiers cannot redirect the default object-state storage path")
	var overflow_identity := ObjectStateContract.identity_for_instance(baseline)
	overflow_identity.region_key[0] = 2147483648
	overflow_identity.instance_id = String(overflow_identity.instance_id).replace("/region/-2,3/slot/0", "/region/-2147483648,3/slot/0")
	_check(not ObjectStateContract.validate_identity(overflow_identity, WORLD_ID, SEED, Field.GENERATOR_VERSION).get("ok", false), "signed region coordinates outside Vector2i range are rejected before identity normalization")
	var changed_baseline := baseline.duplicate(true)
	changed_baseline["instance_id"] = String(baseline.instance_id) + "/stale"
	_check(not final_service.resolve_instance(changed_baseline).get("ok", false), "stable instance identity mismatch is rejected")
	_remove_tree(directory)
	_remove_tree(corrupted_dir)
	_remove_tree(recovered_temp_dir)


func _test_terrain_and_save_authority_isolation() -> void:
	var registry := Registry.new()
	var registration: Dictionary = registry.discover_and_register(_test_roots())
	_check(registration.get("ok", false), "authority isolation fixture registers content")
	if not registration.get("ok", false):
		return
	var edits: RefCounted = BrushState.new(SEED)
	var save_directory := ProjectSettings.globalize_path(_mod_root.path_join("save_probe"))
	var store: RefCounted = SaveStore.new(save_directory)
	_check(edits.add_sphere(BrushState.Mode.CARVE, Vector3(2.0, 2.0, 2.0), 0.58), "disposable baseline terrain save command is accepted")
	var save_result: Dictionary = store.save_ledger(SaveStore.WORLD_ID, edits)
	_check(save_result.get("ok", false), "schema-1 preservation fixture is saved outside the user's world directory")
	if not save_result.get("ok", false):
		return
	var save_path := save_directory.path_join("save-%08d.json" % int(save_result["generation"]))
	var saved_bytes_before: PackedByteArray = FileAccess.get_file_as_bytes(save_path)
	var revision_before: int = edits.revision
	var count_before: int = edits.get_edit_count()
	var generated: Dictionary = ObjectWorld.build_region_instances(SEED, WORLD_ID, Vector2i(-1, -1), registry)
	_check(generated.get("ok", false), "instance generation succeeds without requiring save access")
	_check(edits.revision == revision_before and edits.get_edit_count() == count_before, "instance generation has no authority over terrain edits")
	_check(FileAccess.get_file_as_bytes(save_path) == saved_bytes_before, "procedural object generation leaves existing schema-1 save bytes unchanged")


func _test_playable_scene_publication() -> void:
	var packed: PackedScene = load("res://scenes/terrain_demo.tscn")
	_check(packed != null, "playable scene includes the procedural-object stream adapter")
	if packed == null:
		return
	var demo: Node = packed.instantiate()
	var isolated_store: RefCounted = SaveStore.new("user://p2_0a_scene_test_%d" % Time.get_ticks_usec())
	demo.set("world_save_store", isolated_store)
	var isolated_object_state := _unique_state_path("playable_scene")
	demo.set("object_state_directory_override", isolated_object_state)
	var package_roots_override: Array[String] = []
	demo.set("object_package_roots_override", package_roots_override)
	root.add_child(demo)
	var center_ready := false
	for _frame in range(4000):
		await process_frame
		if demo.get("active_regions").has("0,0"):
			center_ready = true
			break
	var stream: ProceduralObjectStream = demo.get_node("ProceduralObjects")
	_check(center_ready, "playable terrain scene publishes its focused region during streaming")
	_check(stream.initialized and int(stream.get_package_discovery_diagnostics().size()) >= 1 and stream.get_package_discovery_summary().contains("undeclared folder"), "main scene initializes packages and displays the nonfatal optional-folder diagnostic")
	if center_ready:
		for _frame in range(1200):
			await process_frame
			if stream.get_active_region_count() == demo.get("active_regions").size() and not stream.get_region_instance_records(Vector2i.ZERO).is_empty():
				break
		_check(stream.get_active_region_count() == demo.get("active_regions").size(), "object visibility follows actually published active regions (objects=%d terrain=%d init=%s status=%s)" % [stream.get_active_region_count(), demo.get("active_regions").size(), stream.initialized, demo.get("_procedural_object_status")])
		var runtime_object_metrics: Dictionary = stream.get_performance_snapshot().get("last_region", {})
		_check(int(runtime_object_metrics.get("generation_worker_usec", 0)) > 0, "playable region population generation executes through the worker path")
		_check(int(runtime_object_metrics.get("geometry_cpu_worker_usec", 0)) > 0, "playable procedural geometry CPU construction executes through the worker path")
		var center_records: Array[Dictionary] = stream.get_region_instance_records(Vector2i.ZERO)
		_check(center_records.size() >= 2, "scene publication creates both compatibility objects and declarative population from registered packages (instances=%d init=%s error=%s)" % [center_records.size(), stream.initialized, stream.initialization_error])
		if center_records.size() < 2:
			demo.queue_free()
			_remove_tree(isolated_object_state)
			return
		var selected_id := String(center_records[0]["instance_id"])
		var visual_override := stream.set_instance_component(selected_id, ObjectStateContract.COMPONENT_TRANSFORM, {"schema_version": 1, "properties": {"translation_mm": [400, 250, 0], "rotation_mdeg": [0, 0, 15000], "scale_milli": [1200, 1000, 900]}})
		_check(visual_override.get("ok", false), "playable GUI path accepts and persists a transform override through the stream")
		var visual_appearance := stream.set_instance_component(selected_id, ObjectStateContract.COMPONENT_APPEARANCE, {"schema_version": 1, "properties": {"tint_milli": [900, 600, 350], "label": "visual-state"}})
		_check(visual_appearance.get("ok", false), "playable GUI path accepts a per-instance declarative appearance property")
		var stateful_records: Array[Dictionary] = stream.get_region_instance_records(Vector2i.ZERO)
		var object_root: Node3D = stream.get_node("Objects_0_0")
		var transformed_node: Node3D
		for candidate_node in object_root.get_children():
			if candidate_node.get_meta("stable_instance_id", "") == selected_id:
				transformed_node = candidate_node
		_check(transformed_node != null and transformed_node.position.x > Vector3(center_records[0]["position_mm"]).x / 1000.0, "published Node3D reflects the saved transform delta while remaining derived presentation")
		var deleted_id := String(center_records[1]["instance_id"])
		_check(stream.delete_instance(deleted_id).get("ok", false) and stream.get_visible_instance_count() == center_records.size() - 1, "playable stream commits a logical deletion and removes the representative")
		_check(stream.restore_instance(deleted_id).get("ok", false) and stream.get_visible_instance_count() == center_records.size(), "playable stream restores the procedural baseline for a deleted object")
		# Exercise the P3B main-scene controls through real Viewport input routing.
		_push_demo_key(demo, KEY_M)
		_check(String(demo.get("_object_state_action_status")).contains("History migration preflight passed") and not stream.is_entity_command_ready(), "main-scene M input preflights without implicitly upgrading the legacy object save")
		_push_demo_key(demo, KEY_M)
		var migration_sync_completed := false
		for _frame in range(240):
			await process_frame
			if stream.is_entity_command_ready():
				migration_sync_completed = true
				break
		_check(migration_sync_completed and int(stream.state_service.snapshot.get("schema_version", 0)) == 3, "second main-scene M input explicitly commits the entity-history schema and waits for active regions to synchronize")
		demo.set("orbit_target", Vector3(8.0, 10.0, 6.0))
		demo.set("orbit_offset", Vector3(0.0, 20.0, 0.0))
		demo.call("_update_camera")
		var command_revision_before_b := stream.get_command_world_revision()
		var viewport_center: Vector2 = demo.get_viewport().get_visible_rect().size * 0.5
		_push_demo_pointer(demo, viewport_center)
		_push_demo_key(demo, KEY_B)
		var viewport_placed_id := String(demo.get("_selected_object_id"))
		await _wait_for_entity_presence(stream, viewport_placed_id, true)
		_check(not viewport_placed_id.is_empty() and viewport_placed_id.contains("/placed/") and stream.get_command_world_revision() == command_revision_before_b + 1, "B viewport input places a persistent explicit entity at the visible-pointer target")
		var viewport_placed_node := _find_stable_object_node(stream, viewport_placed_id)
		if viewport_placed_node != null:
			var click_point: Vector2 = demo.get("camera").unproject_position(viewport_placed_node.global_position + Vector3.UP * 0.5)
			_push_demo_ctrl_click(demo, click_point)
			_check(String(demo.get("_selected_object_id")) == viewport_placed_id, "Ctrl+left viewport event selects the placed entity through terrain-occlusion-aware picking")
		_push_demo_key(demo, KEY_F6)
		var input_selected_id := String(demo.get("_selected_object_id"))
		_check(not input_selected_id.is_empty(), "F6 viewport input selects an entity for transactional commands")
		var command_revision_before_f7 := stream.get_command_world_revision()
		_push_demo_key(demo, KEY_F7)
		_check(stream.get_command_world_revision() == command_revision_before_f7 + 2 and int(stream.state_service.get_entity_revision(input_selected_id)) == 2, "F7 routes transform and appearance changes through two revision-checked entity commands (status=%s world=%d->%d entity=%d)" % [String(demo.get("_object_state_action_status")), command_revision_before_f7, stream.get_command_world_revision(), int(stream.state_service.get_entity_revision(input_selected_id))])
		var command_revision_before_delete := stream.get_command_world_revision()
		var selected_override_before_delete: Dictionary = stream.state_service.snapshot.get("overrides", {}).get(input_selected_id, {}).duplicate(true)
		_push_demo_key(demo, KEY_F8)
		await _wait_for_entity_presence(stream, input_selected_id, false)
		var visual_after_delete := stream.get_instance_ids()
		_check(stream.get_command_world_revision() == command_revision_before_delete + 1 and stream.state_service.snapshot.get("deleted", {}).has(input_selected_id) and not visual_after_delete.has(input_selected_id), "F8 viewport input commits ENTITY_DELETE and removes only the selected visual identity (status=%s)" % String(demo.get("_object_state_action_status")))
		var command_revision_after_delete := stream.get_command_world_revision()
		_push_demo_key(demo, KEY_F8)
		_check(stream.get_command_world_revision() == command_revision_after_delete and not stream.get_instance_ids().has(input_selected_id) and String(demo.get("_object_state_action_status")).contains("rejected"), "rejected repeated F8 command leaves the visual representation unchanged and reports its reason")
		var command_revision_before_undo_delete := stream.get_command_world_revision()
		_push_demo_key(demo, KEY_Z, true)
		await _wait_for_entity_presence(stream, input_selected_id, true)
		_check(stream.get_command_world_revision() == command_revision_before_undo_delete + 1 and stream.state_service.snapshot.get("overrides", {}).get(input_selected_id, {}) == selected_override_before_delete and not stream.state_service.snapshot.get("deleted", {}).has(input_selected_id), "Ctrl+Z transactionally undoes ENTITY_DELETE and restores the exact transform and appearance overrides")
		var command_revision_before_redo_delete := stream.get_command_world_revision()
		_push_demo_key(demo, KEY_Y, true)
		await _wait_for_entity_presence(stream, input_selected_id, false)
		_check(stream.get_command_world_revision() == command_revision_before_redo_delete + 1 and stream.state_service.snapshot.get("deleted", {}).has(input_selected_id), "Ctrl+Y transactionally redoes the deletion without losing its inverse data")
		var command_revision_before_second_undo := stream.get_command_world_revision()
		_push_demo_key(demo, KEY_Z, true)
		await _wait_for_entity_presence(stream, input_selected_id, true)
		_check(stream.get_command_world_revision() == command_revision_before_second_undo + 1 and stream.state_service.snapshot.get("overrides", {}).get(input_selected_id, {}) == selected_override_before_delete, "a second Ctrl+Z restores the same full pre-delete state")
		stream.debug_fail_next_visual_publication = true
		var command_revision_before_visual_failure := stream.get_command_world_revision()
		_push_demo_key(demo, KEY_Y, true)
		var visual_failure_reported := false
		for _frame in range(120):
			await process_frame
			if String(demo.get("_object_state_action_status")).contains("visual publication failed"):
				visual_failure_reported = true
				break
		_check(stream.get_command_world_revision() == command_revision_before_visual_failure + 1 and stream.state_service.snapshot.get("deleted", {}).has(input_selected_id) and visual_failure_reported, "committed Redo remains authoritative when mesh publication fails, and the HUD reports the visual failure separately")
		var command_revision_before_visual_recovery := stream.get_command_world_revision()
		_push_demo_key(demo, KEY_Z, true)
		await _wait_for_entity_presence(stream, input_selected_id, true)
		_check(stream.get_command_world_revision() == command_revision_before_visual_recovery + 1 and not stream.state_service.snapshot.get("deleted", {}).has(input_selected_id), "a later Undo can publish and visually reconcile after the explicit failed publication")
		var command_revision_before_restore := stream.get_command_world_revision()
		_push_demo_key(demo, KEY_F9)
		for _frame in range(120):
			await process_frame
			if stream.get_command_world_revision() > command_revision_before_restore:
				break
		await _wait_for_entity_presence(stream, input_selected_id, true)
		_check(stream.get_command_world_revision() == command_revision_before_restore + 1 and not stream.state_service.snapshot.get("deleted", {}).has(input_selected_id) and not stream.state_service.snapshot.get("overrides", {}).has(input_selected_id) and stream.get_instance_ids().count(input_selected_id) == 1 and String(demo.get("_object_state_action_status")).contains("ENTITY_RESTORE committed"), "F9 remains distinct from Undo Delete and restores the procedural baseline without overrides or duplication (status=%s)" % String(demo.get("_object_state_action_status")))
		# Region generation is asynchronous in the playable stream. Presence alone
		# is not a publication-completion fence when the entity already existed
		# before the command, so wait for the queued visual rebuild to drain before
		# taking the persisted visual-state snapshot used by the unload/reload check.
		var restore_visual_quiescent := false
		for _frame in range(240):
			await process_frame
			if int(stream.get_performance_snapshot().get("pending_region_publication_count", 0)) == 0:
				restore_visual_quiescent = true
				break
		_check(restore_visual_quiescent, "F9 visual rebuild drains before the unload/reload reference snapshot")
		stateful_records = stream.get_region_instance_records(Vector2i.ZERO)
		var region_root_count := 0
		for child in stream.get_children():
			if child.name == "Objects_0_0":
				region_root_count += 1
		_check(region_root_count == 1, "terrain publication creates one object root for the focused region")
		demo.set("orbit_target", Vector3(72.0, 3.1, 6.0))
		demo.call("_update_camera")
		var center_unloaded := false
		for _frame in range(1200):
			await process_frame
			if not demo.get("active_regions").has("0,0"):
				center_unloaded = true
				break
		_check(center_unloaded and stream.get_region_instance_records(Vector2i.ZERO).is_empty(), "camera-driven region eviction releases its procedural object representations")
		demo.set("orbit_target", Vector3(8.0, 3.1, 6.0))
		demo.call("_update_camera")
		var center_reloaded := false
		for _frame in range(2400):
			await process_frame
			if demo.get("active_regions").has("0,0"):
				center_reloaded = true
				break
		_check(center_reloaded, "camera-driven revisit republishes the original region")
		if center_reloaded:
			var object_center_reloaded := false
			for _frame in range(240):
				await process_frame
				if stream.has_published_region(Vector2i.ZERO) \
					and int(stream.get_performance_snapshot().get("pending_region_publication_count", 0)) == 0:
					object_center_reloaded = true
					break
			_check(object_center_reloaded, "object stream catches up after asynchronous terrain revisit")
			if object_center_reloaded:
				_check(stream.get_region_instance_records(Vector2i.ZERO) == stateful_records, "playable stream revisit rebuilds the persisted override independent of visit order")
	demo.queue_free()
	for _frame in range(2):
		await process_frame
	_remove_tree(isolated_object_state)


func _push_demo_key(demo: Node, key_code: int, ctrl_pressed: bool = false, shift_pressed: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = key_code
	event.physical_keycode = key_code
	event.pressed = true
	event.ctrl_pressed = ctrl_pressed
	event.shift_pressed = shift_pressed
	demo.get_viewport().push_input(event)
	await process_frame


func _push_demo_pointer(demo: Node, position: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = position
	demo.get_viewport().push_input(event)
	await process_frame


func _push_demo_ctrl_click(demo: Node, position: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.ctrl_pressed = true
	event.position = position
	demo.get_viewport().push_input(event)
	await process_frame


func _wait_for_entity_presence(stream: ProceduralObjectStream, instance_id: String, expected_present: bool) -> void:
	for _frame in range(60):
		await process_frame
		if stream.get_instance_ids().has(instance_id) == expected_present:
			return


func _find_stable_object_node(stream: ProceduralObjectStream, instance_id: String) -> Node3D:
	for region_root in stream.get_children():
		for child in region_root.get_children():
			if child.get_meta("stable_instance_id", "") == instance_id:
				return child
	return null


func _mesh_snapshots(manager: ProceduralObjectStream, region_key: Vector2i) -> Array:
	var result: Array = []
	var region_id := "%d,%d" % [region_key.x, region_key.y]
	var region_root := manager.get_node("Objects_%d_%d" % [region_key.x, region_key.y])
	for object_node in region_root.get_children():
		var mesh_instance: MeshInstance3D = object_node.get_child(0)
		var arrays: Array = mesh_instance.mesh.surface_get_arrays(0)
		var representation_ids: Array = []
		var geometry_version := -1
		if object_node.has_meta("stable_instance_id"):
			representation_ids.append(String(object_node.get_meta("stable_instance_id")))
			geometry_version = int(object_node.get_meta("geometry_adapter_version", -1))
		elif object_node.has_meta("stable_instance_ids"):
			representation_ids = object_node.get_meta("stable_instance_ids")
			geometry_version = int(object_node.get_meta("population_batch_version", -1))
		result.append({"ids": representation_ids, "geometry_version": geometry_version, "vertices": arrays[Mesh.ARRAY_VERTEX], "normals": arrays[Mesh.ARRAY_NORMAL]})
	return result


func _flatten_snapshot_ids(snapshots: Array) -> Array[String]:
	var ids: Array[String] = []
	for snapshot in snapshots:
		for value in snapshot.get("ids", []):
			ids.append(String(value))
	ids.sort()
	return ids


func _create_external_package(package_path: String) -> String:
	var global_path: String = ProjectSettings.globalize_path(package_path)
	DirAccess.make_dir_recursive_absolute(global_path.path_join("objects"))
	DirAccess.make_dir_recursive_absolute(global_path.path_join("populations"))
	var source_root := ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir().path_join("mods/examples/procedural-rock")
	for relative_path in ["manifest.json", "objects/procedural_rock.json", "populations/basalt_legacy.json", "populations/basalt_population.json"]:
		var source_path: String = source_root.path_join(relative_path)
		var bytes: PackedByteArray = FileAccess.get_file_as_bytes(source_path)
		if bytes.is_empty() or not _write_bytes(package_path.path_join(relative_path), bytes):
			return ""
	return package_path


func _write_bytes(path: String, bytes: PackedByteArray) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_buffer(bytes)
	file.close()
	return true


func _unique_state_path(label: String) -> String:
	return ProjectSettings.globalize_path("user://p2_0b_state/%s_%d" % [label, Time.get_ticks_usec()])


func _test_roots() -> Array[String]:
	return ["res://mods/first-party", "user://mods"]


func _cleanup_stale_p2b_fixtures() -> void:
	var old_mod_root := "user://mods"
	var directory := DirAccess.open(old_mod_root)
	if directory != null:
		var stale_names: Array[String] = []
		directory.list_dir_begin()
		while true:
			var entry := directory.get_next()
			if entry.is_empty():
				break
			if directory.current_is_dir() and entry.begins_with("p2_0b_roundtrip_"):
				stale_names.append(entry)
		directory.list_dir_end()
		for entry in stale_names:
			_remove_tree(ProjectSettings.globalize_path(old_mod_root.path_join(entry)))


func _write_text(path: String, value: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_check(false, "disposable fixture file can be written")
		return
	file.store_string(value)
	file.close()


func _remove_tree(path: String) -> void:
	var full_path := path.replace("\\", "/")
	var user_mod_root := ProjectSettings.globalize_path("user://mods").replace("\\", "/").trim_suffix("/")
	var test_state_root := ProjectSettings.globalize_path("user://p2_0b_state").replace("\\", "/").trim_suffix("/")
	if not full_path.begins_with(user_mod_root + "/") and not full_path.begins_with(test_state_root + "/"):
		_check(false, "test cleanup path is strictly contained under an owned disposable user:// fixture root")
		return
	var directory := DirAccess.open(full_path)
	if directory == null:
		return
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if entry != "." and entry != "..":
			var child := full_path.path_join(entry)
			if directory.current_is_dir():
				_remove_tree(child)
			else:
				DirAccess.remove_absolute(child)
		entry = directory.get_next()
	directory.list_dir_end()
	directory = null
	DirAccess.remove_absolute(full_path)


func _check(condition: bool, description: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + description)
	else:
		print("PASS: " + description)


func _sample_percentile(sorted_values: Array[int], fraction: float) -> int:
	if sorted_values.is_empty():
		return 0
	var index := clampi(int(floor(float(sorted_values.size() - 1) * fraction)), 0, sorted_values.size() - 1)
	return sorted_values[index]
