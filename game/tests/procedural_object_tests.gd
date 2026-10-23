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
	_test_mesh_conversion()
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
	_check(builtin_recipe.get("lobes", []).size() == int(builtin.get("recipe", {}).get("lobe_count", -1)), "first-party output follows its declarative lobe count")
	_check(external_recipe.get("lobes", []).size() == int(external.get("recipe", {}).get("lobe_count", -1)), "external output follows its declarative lobe count")
	_check(registry.pin_definitions([builtin["id"], external["id"]]).get("ok", false), "runtime object definitions carry P0.3 content version pins")
	var runtime: ProceduralObjectStream = ObjectStream.new()
	var default_roots: Dictionary = runtime.initialize(SEED, WORLD_ID)
	_check(default_roots.get("ok", false), "default runtime discovers the external package installed under user://mods")
	_check(runtime._configured_package_roots().size() == 2, "installed example takes precedence over its repository copy to avoid duplicate package IDs")
	runtime.free()


func _test_mesh_conversion() -> void:
	var registry := Registry.new()
	var registration: Dictionary = registry.discover_and_register(["res://mods/first-party", "user://mods"])
	_check(registration.get("ok", false), "mesh conversion fixture can load both package definitions")
	if not registration.get("ok", false):
		return
	for definition_id in ObjectWorld.SLOT_DEFINITIONS:
		var recipe: Dictionary = registry.evaluate_rock_recipe(definition_id, 91234)
		var first: Dictionary = RockMeshAdapter.build_mesh(recipe.get("lobes", []))
		var second: Dictionary = RockMeshAdapter.build_mesh(recipe.get("lobes", []))
		_check(first.get("ok", false) and second.get("ok", false), "%s recipe converts to visible mesh data" % definition_id)
		if not first.get("ok", false) or not second.get("ok", false):
			continue
		var first_arrays: Array = first["mesh"].surface_get_arrays(0)
		var second_arrays: Array = second["mesh"].surface_get_arrays(0)
		var vertices: PackedVector3Array = first_arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = first_arrays[Mesh.ARRAY_NORMAL]
		_check(not vertices.is_empty() and vertices.size() == normals.size(), "%s mesh has matched vertex and normal arrays" % definition_id)
		_check(vertices == second_arrays[Mesh.ARRAY_VERTEX] and normals == second_arrays[Mesh.ARRAY_NORMAL], "%s geometry conversion is deterministic" % definition_id)
		var finite := true
		for index in range(vertices.size()):
			if not vertices[index].is_finite() or not normals[index].is_finite() or normals[index].length_squared() < 0.9:
				finite = false
				break
		_check(finite, "%s mesh positions and normals are finite and normalized" % definition_id)
	_check(not RockMeshAdapter.build_mesh([]).get("ok", false), "empty geometry recipe is rejected")


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
			_check(instance["content_pin"].get("mod_version", "").is_empty() == false and instance["recipe_algorithm"] == "stacked_spheres_v1", "instance pins its definition and recipe version")
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
		result.append({"id": object_node.get_meta("stable_instance_id"), "vertices": arrays[Mesh.ARRAY_VERTEX], "normals": arrays[Mesh.ARRAY_NORMAL]})
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
