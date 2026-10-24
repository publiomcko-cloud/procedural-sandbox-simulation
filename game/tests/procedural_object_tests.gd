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

const SEED := 424242
const WORLD_ID := "procedural-object-test-world"

var assertions := 0
var failures := 0
var _mod_root := ""


func _initialize() -> void:
	await _run()
	if failures == 0:
		print("PROCEDURAL_OBJECT_PASS: assertions=%d failures=0" % assertions)
	else:
		push_error("PROCEDURAL_OBJECT_FAIL: assertions=%d failures=%d" % [assertions, failures])
	quit(0 if failures == 0 else 1)


func _run() -> void:
	_mod_root = "user://mods/p2_0a_test_%d" % Time.get_ticks_usec()
	var external_copy: String = _create_external_package(_mod_root)
	var roots: Array[String] = ["res://mods/first-party", "user://mods"]
	_test_same_registry_pipeline(roots)
	_test_versioned_recipe_compatibility()
	_test_mesh_conversion()
	_test_seed_family_variation()
	_test_order_independent_records(roots)
	_test_runtime_streaming_and_unload_reload(roots)
	_test_missing_and_incompatible_content(roots)
	_test_terrain_and_save_authority_isolation()
	_check(not external_copy.is_empty(), "external example was copied only into the disposable user://mods test fixture")
	_remove_tree(ProjectSettings.globalize_path(_mod_root))
	await _test_playable_scene_publication()


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
	var default_roots: Dictionary = runtime.initialize(SEED, WORLD_ID)
	_check(default_roots.get("ok", false), "default runtime discovers the external package installed under user://mods")
	_check(runtime._configured_package_roots().size() == 2, "installed example takes precedence over its repository copy to avoid duplicate package IDs")
	runtime.free()


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
	var registration: Dictionary = registry.discover_and_register(["res://mods/first-party", "user://mods"])
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
		_check(generated.get("ok", false), "signed region %s creates deterministic placements" % key)
		forward[key] = generated.get("instances", [])
	var reverse: Dictionary = {}
	visitation.reverse()
	for key in visitation:
		reverse[key] = ObjectWorld.build_region_instances(SEED, WORLD_ID, key, registry).get("instances", [])
	var all_ids: Dictionary = {}
	for key in forward:
		_check(forward[key] == reverse[key], "region %s placement is independent of region discovery order" % key)
		_check(forward[key].size() == 2, "region %s contains the fixed first-party and external slots" % key)
		for instance in forward[key]:
			var instance_id: String = instance["instance_id"]
			_check(not all_ids.has(instance_id), "stable instance ID is unique across signed regions")
			all_ids[instance_id] = true
			_check(instance["position_mm"] is Vector3i and instance["region_key"] == key, "placement uses integer local millimeters and its canonical signed region")
			_check(instance["content_pin"].get("mod_version", "").is_empty() == false and instance["recipe_algorithm"] == "geological_halfspace_v1" and instance["geometry_profile"] != "" and instance["geometry_seeds"].size() == 4, "instance pins its definition, recipe version, profile and independent stage seeds")
			_check(instance.get("instance_state", null) is Dictionary and instance["instance_state"].is_empty(), "future instance-state boundary is explicit but nonpersistent")
			var local_position := Vector3(instance["position_mm"]) / 1000.0
			var below: float = Field.sample_density(SEED, key, local_position + Vector3.DOWN * 0.05)
			var above: float = Field.sample_density(SEED, key, local_position + Vector3.UP * 0.05)
			_check(below > 0.0 and above < 0.0, "surface placement is derived from canonical solid-to-empty density crossing")


func _test_runtime_streaming_and_unload_reload(roots: Array[String]) -> void:
	var manager: ProceduralObjectStream = ObjectStream.new()
	var initialization: Dictionary = manager.initialize(SEED, WORLD_ID, roots)
	_check(initialization.get("ok", false), "runtime adapter initializes from the common registry")
	_check(manager.get_error_summary().is_empty(), "successful initialization has no hidden package or region errors")
	if not initialization.get("ok", false):
		return
	root.add_child(manager)
	var key := Vector2i(-3, 2)
	var state: RefCounted = WorldState.new(SEED, key, BrushState.new(SEED))
	var before_revision: int = state.get("brush_edits").revision
	var first: Dictionary = manager.publish_region(key, state)
	_check(first.get("ok", false) and first.get("instance_count", 0) == 2, "published negative region receives two static object representations")
	if not first.get("ok", false):
		manager.free()
		return
	var records_before: Array[Dictionary] = manager.get_region_instance_records(key)
	var geometry_before: Array = _mesh_snapshots(manager, key)
	_check(manager.get_active_region_count() == 1 and manager.get_visible_instance_count() == 2, "visual object residency is bounded to explicitly published regions")
	var duplicate: Dictionary = manager.publish_region(key, state)
	_check(duplicate.get("ok", false) and duplicate.get("reason") == "already_published" and manager.get_child_count() == 1, "repeated publication does not create duplicate region or object nodes")
	manager.set_object_visibility(false)
	_check(manager.get_visible_instance_count() == 0 and manager.get_child_count() == 1, "visibility toggle hides representations without changing domain records")
	manager.unload_region(key)
	_check(manager.get_active_region_count() == 0 and manager.get_child_count() == 0, "region unload releases all object rendering nodes")
	var second: Dictionary = manager.publish_region(key, state)
	_check(second.get("ok", false), "region reload succeeds while object visualization is hidden")
	if not second.get("ok", false):
		manager.free()
		return
	_check(not manager.get_child(0).visible and manager.get_visible_instance_count() == 0, "streamed-in regions preserve the user's hidden-object setting")
	manager.set_object_visibility(true)
	_check(manager.get_region_instance_records(key) == records_before, "reload recreates identical IDs, pins, seeds and placements")
	_check(_mesh_snapshots(manager, key) == geometry_before, "reloaded object geometry matches the original deterministic recipe conversion")
	_check(state.get("brush_edits").revision == before_revision and state.get("brush_edits").get_edit_count() == 0, "object publication does not mutate the canonical terrain ledger")
	manager.free()


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
	var legacy_stream_result: Dictionary = legacy_stream.initialize(SEED, WORLD_ID, ["res://mods/first-party", "user://mods"])
	_check(not legacy_stream_result.get("ok", false) and String(legacy_stream_result.get("reason", "")).begins_with("required_definition_geometry_version_unsupported:"), "legacy required runtime content fails explicitly rather than being interpreted by the new geometry adapter")
	legacy_stream.free()
	_write_bytes(definition_path, current_definition_bytes)
	var manifest_path := ProjectSettings.globalize_path(_mod_root.path_join("manifest.json"))
	var manifest_bytes: PackedByteArray = FileAccess.get_file_as_bytes(manifest_path)
	var parsed := JSON.parse_string(manifest_bytes.get_string_from_utf8()) as Dictionary
	parsed["requires_engine"] = "9.9.9"
	_write_text(_mod_root.path_join("manifest.json"), JSON.stringify(parsed))
	var incompatible: ProceduralObjectStream = ObjectStream.new()
	var bad_result: Dictionary = incompatible.initialize(SEED, WORLD_ID, ["res://mods/first-party", "user://mods"])
	_check(not bad_result.get("ok", false) and bad_result.get("reason") == "package_discovery_failed:incompatible_engine_version", "incompatible external package is rejected through the existing loader")
	_check(not incompatible.initialized, "incompatible content cannot be replaced by a fallback definition")
	incompatible.free()
	_write_text(_mod_root.path_join("manifest.json"), manifest_bytes.get_string_from_utf8())


func _test_terrain_and_save_authority_isolation() -> void:
	var registry := Registry.new()
	var registration: Dictionary = registry.discover_and_register(["res://mods/first-party", "user://mods"])
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
	root.add_child(demo)
	var center_ready := false
	for _frame in range(4000):
		await process_frame
		if demo.get("active_regions").has("0,0"):
			center_ready = true
			break
	var stream: ProceduralObjectStream = demo.get_node("ProceduralObjects")
	_check(center_ready, "playable terrain scene publishes its focused region during streaming")
	if center_ready:
		_check(stream.get_active_region_count() == demo.get("active_regions").size(), "object visibility follows actually published active regions (objects=%d terrain=%d init=%s status=%s)" % [stream.get_active_region_count(), demo.get("active_regions").size(), stream.initialized, demo.get("_procedural_object_status")])
		var center_records: Array[Dictionary] = stream.get_region_instance_records(Vector2i.ZERO)
		_check(center_records.size() == 2, "scene publication creates objects from both registered packages (instances=%d init=%s error=%s)" % [center_records.size(), stream.initialized, stream.initialization_error])
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
			_check(stream.get_region_instance_records(Vector2i.ZERO) == center_records, "playable stream revisit reproduces identical procedural object identities and placements")
	demo.queue_free()
	for _frame in range(2):
		await process_frame


func _mesh_snapshots(manager: ProceduralObjectStream, region_key: Vector2i) -> Array:
	var result: Array = []
	var region_id := "%d,%d" % [region_key.x, region_key.y]
	var region_root := manager.get_node("Objects_%d_%d" % [region_key.x, region_key.y])
	for object_node in region_root.get_children():
		var mesh_instance: MeshInstance3D = object_node.get_child(0)
		var arrays: Array = mesh_instance.mesh.surface_get_arrays(0)
		result.append({"id": object_node.get_meta("stable_instance_id"), "geometry_version": object_node.get_meta("geometry_adapter_version"), "vertices": arrays[Mesh.ARRAY_VERTEX], "normals": arrays[Mesh.ARRAY_NORMAL]})
	return result


func _create_external_package(package_path: String) -> String:
	var global_path: String = ProjectSettings.globalize_path(package_path)
	DirAccess.make_dir_recursive_absolute(global_path.path_join("objects"))
	var source_root := ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir().path_join("mods/examples/procedural-rock")
	for relative_path in ["manifest.json", "objects/procedural_rock.json"]:
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
	if not full_path.begins_with(user_mod_root + "/"):
		_check(false, "test cleanup path is strictly contained under user://mods")
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
