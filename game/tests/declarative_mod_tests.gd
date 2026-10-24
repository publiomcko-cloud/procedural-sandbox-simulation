extends SceneTree

const Loader := preload("res://scripts/modding/declarative_mod_loader.gd")
const Registry := preload("res://scripts/modding/content_definition_registry.gd")
const Store := preload("res://scripts/terrain/terrain_world_save_store.gd")
const Brush := preload("res://scripts/terrain/sdf_brush_edit_state.gd")
const Field := preload("res://scripts/terrain/sdf_world.gd")

var assertions := 0
var failures := 0
var _test_root := ""


func _initialize() -> void:
	_test_root = "user://mods/p0_3_test_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_test_root))
	_test_real_packages_and_stable_order()
	_test_controlled_manifest_rejections()
	_test_dependency_failures()
	_test_content_validation_and_atomicity()
	_test_deterministic_recipe()
	_test_failed_package_preserves_save()
	_remove_tree(ProjectSettings.globalize_path(_test_root))
	if failures == 0:
		print("DECLARATIVE_MOD_PASS: assertions=%d failures=0" % assertions)
	else:
		push_error("DECLARATIVE_MOD_FAIL: assertions=%d failures=%d" % [assertions, failures])
	quit(0 if failures == 0 else 1)


func _test_real_packages_and_stable_order() -> void:
	var roots_a: Array[String] = [_repo_mod_path("examples"), "res://mods/first-party"]
	var roots_b: Array[String] = ["res://mods/first-party", _repo_mod_path("examples")]
	var discovered_a: Dictionary = Loader.discover_and_validate(roots_a)
	var discovered_b: Dictionary = Loader.discover_and_validate(roots_b)
	_check(discovered_a.get("ok", false), "first-party and external example packages discover and validate (%s)" % discovered_a.get("reason", "ok"))
	_check(discovered_b.get("ok", false), "same packages validate when discovery roots are reversed")
	if not discovered_a.get("ok", false) or not discovered_b.get("ok", false) or not discovered_a.get("packages") is Array or not discovered_b.get("packages") is Array:
		return
	var order_a: Array[String] = _package_ids(discovered_a["packages"])
	var order_b: Array[String] = _package_ids(discovered_b["packages"])
	_check(order_a == order_b, "registration order is independent of root discovery order")
	_check(order_a == ["firstparty.core_rocks", "official.example.procedural_rock"], "dependency precedes external package deterministically")
	var registry := Registry.new()
	var registration: Dictionary = registry.discover_and_register(roots_a)
	_check(registration.get("ok", false) and registration.get("mod_count", 0) == 2, "shared registry accepts both package sources")
	_check(registration.get("definition_count", 0) == 2, "both first-party and external definitions register")
	var example_id := "official.example.procedural_rock:basalt_stack"
	var builtin_id := "firstparty.core_rocks:granite"
	_check(registry.get_definition(example_id).get("display_name", "") == "Example Basalt Stack", "external definition lookup uses stable namespaced ID")
	_check(registry.get_definition(builtin_id).get("display_name", "") == "Granite Formation", "first-party definition uses the same lookup API")
	_check(registry.get_definition("missing.mod:rock").is_empty(), "unknown definition lookup returns an empty result")
	var pins: Dictionary = registry.pin_definitions([example_id, builtin_id])
	_check(pins.get("ok", false) and pins["pins"].size() == 2, "content use can be represented by stable ID, mod version and schema pins")
	_check(registry.validate_content_pins(pins.get("pins", [])).get("ok", false), "matching saved content pins validate without reinterpretation")
	var changed_pin: Array[Dictionary] = pins.get("pins", []).duplicate(true)
	changed_pin[0]["mod_version"] = "9.9.9"
	_check(registry.validate_content_pins(changed_pin).get("reason") == "pinned_mod_version_mismatch", "changed required mod version is rejected")
	_check(registry.pin_definitions(["missing.mod:rock"]).get("reason") == "pinned_content_missing", "disappeared referenced content is rejected")


func _test_controlled_manifest_rejections() -> void:
	var invalid_roots: Array[String] = ["res://mods/../game"]
	_check(Loader.discover_and_validate(invalid_roots).get("reason") == "unauthorized_package_root", "root traversal outside authorized mod roots is rejected")
	var malformed := _new_root("malformed")
	_write_raw_package(malformed, "bad", "not-json", [])
	_check(Loader.discover_and_validate([malformed]).get("reason") == "malformed_manifest", "malformed manifest fails with controlled reason")
	var schema := _new_root("schema")
	var schema_manifest := _manifest("sample.schema", "1.0.0", [], ["objects/"])
	schema_manifest["schema_version"] = 2
	_write_package(schema, "schema", schema_manifest, [])
	_check(Loader.discover_and_validate([schema]).get("reason") == "incompatible_manifest_schema", "unsupported manifest schema is rejected")
	var engine := _new_root("engine")
	var engine_manifest := _manifest("sample.engine", "1.0.0", [], ["objects/"])
	engine_manifest["requires_engine"] = "9.9.9"
	_write_package(engine, "engine", engine_manifest, [])
	_check(Loader.discover_and_validate([engine]).get("reason") == "incompatible_engine_version", "incompatible engine version is rejected")
	var script_policy := _new_root("script_policy")
	var script_manifest := _manifest("sample.script_policy", "1.0.0", [], ["objects/"])
	script_manifest["script_policy"] = "execute_scripts"
	_write_package(script_policy, "script", script_manifest, [])
	_check(Loader.discover_and_validate([script_policy]).get("reason") == "script_execution_forbidden", "script execution policy is rejected")
	var traversal := _new_root("traversal")
	var traversal_manifest := _manifest("sample.traversal", "1.0.0", [], ["../outside/"])
	_write_package(traversal, "unsafe", traversal_manifest, [])
	_check(Loader.discover_and_validate([traversal]).get("reason") == "unsafe_content_root", "manifest content-root traversal is rejected")
	var duplicate_ids := _new_root("duplicate_ids")
	_write_package(duplicate_ids, "one", _manifest("sample.duplicate", "1.0.0", [], ["objects/"]), [])
	_write_package(duplicate_ids, "two", _manifest("sample.duplicate", "1.0.0", [], ["objects/"]), [])
	_check(Loader.discover_and_validate([duplicate_ids]).get("reason") == "duplicate_mod_id", "duplicate package IDs fail closed")
	var missing_content := _new_root("missing_content")
	_write_package(missing_content, "pkg", _manifest("sample.missing_content", "1.0.0", [], ["objects/"]), [])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(missing_content.path_join("pkg/objects")))
	_check(Loader.discover_and_validate([missing_content]).get("reason") == "content_root_unavailable", "missing declared package content root is rejected")


func _test_dependency_failures() -> void:
	var missing := _new_root("missing_dependency")
	_write_package(missing, "pkg", _manifest("sample.dependent", "1.0.0", [{"id": "sample.absent", "version": "1.0.0"}], ["objects/"]), [])
	_check(Loader.discover_and_validate([missing]).get("reason") == "missing_dependency", "missing dependency is rejected")
	var mismatch := _new_root("dependency_version")
	_write_package(mismatch, "base", _manifest("sample.base", "1.1.0", [], ["objects/"]), [])
	_write_package(mismatch, "dependent", _manifest("sample.dependent", "1.0.0", [{"id": "sample.base", "version": "1.0.0"}], ["objects/"]), [])
	_check(Loader.discover_and_validate([mismatch]).get("reason") == "dependency_version_mismatch", "dependency version mismatch is rejected")
	var cycle := _new_root("cycle")
	_write_package(cycle, "a", _manifest("sample.alpha", "1.0.0", [{"id": "sample.beta", "version": "1.0.0"}], ["objects/"]), [])
	_write_package(cycle, "b", _manifest("sample.beta", "1.0.0", [{"id": "sample.alpha", "version": "1.0.0"}], ["objects/"]), [])
	_check(Loader.discover_and_validate([cycle]).get("reason") == "dependency_cycle", "dependency cycle is rejected")
	var invalid_dependency := _new_root("invalid_dependency")
	_write_package(invalid_dependency, "pkg", _manifest("sample.invalid_dependency", "1.0.0", [{"id": "broken", "version": "1.0.0"}], ["objects/"]), [])
	_check(Loader.discover_and_validate([invalid_dependency]).get("reason") == "invalid_dependency", "malformed dependency identity is rejected")


func _test_content_validation_and_atomicity() -> void:
	var good_roots: Array[String] = ["res://mods/first-party"]
	var good_discovery: Dictionary = Loader.discover_and_validate(good_roots)
	var registry := Registry.new()
	var baseline_registration: Dictionary = registry.register_discovered(good_discovery)
	_check(baseline_registration.get("ok", false), "baseline registry registration succeeds")
	if not baseline_registration.get("ok", false):
		return
	var before: Dictionary = registry.get_definition("firstparty.core_rocks:granite")
	var invalid_definition := _rock_definition("sample.invalid:broken")
	invalid_definition["recipe"]["lobe_count"] = 0
	var mixed_root := _new_root("atomic_registry")
	var duplicate_def_a := _rock_definition("sample.atomic:first")
	var duplicate_def_b := _rock_definition("sample.atomic:first")
	_write_package(mixed_root, "pkg", _manifest("sample.atomic", "1.0.0", [], ["objects/"]), [duplicate_def_a, duplicate_def_b])
	var duplicate_discovery: Dictionary = Loader.discover_and_validate([mixed_root])
	var duplicate_result: Dictionary = registry.register_discovered(duplicate_discovery)
	_check(not duplicate_result.get("ok", false) and duplicate_result.get("reason") == "duplicate_content_definition", "duplicate content IDs are rejected")
	_check(registry.get_definition(before["id"]) == before and not registry.has_mod("sample.atomic"), "failed package batch cannot partially mutate registry")
	var invalid_root := _new_root("invalid_definition")
	_write_package(invalid_root, "pkg", _manifest("sample.invalid", "1.0.0", [], ["objects/"]), [invalid_definition])
	var invalid_discovery: Dictionary = Loader.discover_and_validate([invalid_root])
	_check(not registry.register_discovered(invalid_discovery).get("ok", false), "invalid rock recipe is rejected")
	_check(not registry.has_mod("sample.invalid") and registry.get_definition(before["id"]) == before, "invalid package leaves prior registry contents unchanged")
	var wrong_namespace_root := _new_root("namespace")
	_write_package(wrong_namespace_root, "pkg", _manifest("sample.namespace", "1.0.0", [], ["objects/"]), [_rock_definition("other.namespace:rock")])
	var wrong_namespace := Loader.discover_and_validate([wrong_namespace_root])
	_check(not registry.register_discovered(wrong_namespace).get("ok", false), "definition cannot claim another package namespace")


func _test_deterministic_recipe() -> void:
	var discovered: Dictionary = Loader.discover_and_validate([_repo_mod_path("examples"), "res://mods/first-party"])
	var registry := Registry.new()
	if not discovered.get("ok", false) or not registry.register_discovered(discovered).get("ok", false):
		_check(false, "real package setup supports deterministic recipe evaluation")
		return
	var first: Dictionary = registry.evaluate_rock_recipe("official.example.procedural_rock:basalt_stack", 24680)
	var second: Dictionary = registry.evaluate_rock_recipe("official.example.procedural_rock:basalt_stack", 24680)
	var other_seed: Dictionary = registry.evaluate_rock_recipe("official.example.procedural_rock:basalt_stack", 24681)
	_check(first.get("ok", false) and first == second, "same definition and explicit seed yield identical recipe data")
	_check(first.get("schema_version") == 2 and first.get("algorithm") == "geological_halfspace_v1" and first.get("profile") == "basalt_fractured_anisotropic_v1", "geological recipe output identifies its schema, algorithm, and profile")
	_check(first.get("geometry", {}).get("fracture_plane_count") == 5, "geological recipe output retains its declared fracture structure")
	var first_seeds: Dictionary = first.get("geometry_seeds", {})
	var other_seeds: Dictionary = other_seed.get("geometry_seeds", {})
	_check(first_seeds.keys().size() == 4 and first_seeds.has("structure") and first_seeds.has("fracture") and first_seeds.has("wear") and first_seeds.has("detail"), "geological recipe exposes four independent stage seeds")
	_check(first_seeds != other_seeds, "different explicit seed changes the geological stage seeds")
	_check(registry.evaluate_rock_recipe("missing.mod:rock", 1).get("reason") == "rock_definition_missing", "missing recipe lookup is controlled")
	_check(registry.evaluate_rock_recipe("official.example.procedural_rock:basalt_stack", -1).get("reason") == "seed_out_of_range", "invalid recipe seed is rejected")


func _test_failed_package_preserves_save() -> void:
	var save_directory := ProjectSettings.globalize_path(_test_root.path_join("saved_world"))
	var store := Store.new(save_directory)
	var ledger: RefCounted = Brush.new(1234, Field.GENERATOR_VERSION)
	_check(ledger.add_sphere(Brush.Mode.CARVE, Vector3(-2.0, 2.0, -3.0), 0.7), "disposable preservation save command is accepted")
	var saved: Dictionary = store.save_ledger(Store.WORLD_ID, ledger)
	_check(saved.get("ok", false), "disposable schema-1 world save is created for preservation check")
	if not saved.get("ok", false):
		return
	var save_path := save_directory.path_join("save-%08d.json" % int(saved["generation"]))
	var before: PackedByteArray = FileAccess.get_file_as_bytes(save_path)
	var registry := Registry.new()
	var missing_discovery: Dictionary = Loader.discover_and_validate([_test_root.path_join("does_not_exist")])
	_check(not missing_discovery.get("ok", false), "missing package root returns controlled failure")
	_check(not registry.register_discovered(missing_discovery).get("ok", false), "failed package discovery is not promoted to registry state")
	var after: PackedByteArray = FileAccess.get_file_as_bytes(save_path)
	_check(before == after, "failed mod discovery leaves existing save bytes unchanged")
	_check(store.load_world().get("ok", false), "existing schema-1 save remains readable after package failure")


func _manifest(mod_id: String, version: String, dependencies: Array, roots: Array) -> Dictionary:
	return {"id": mod_id, "version": version, "schema_version": 1, "requires_engine": "4.7.2", "dependencies": dependencies, "script_policy": "data_only", "content_roots": roots}


func _rock_definition(definition_id: String) -> Dictionary:
	return {
		"schema_version": 1,
		"type": "procedural_rock",
		"id": definition_id,
		"display_name": "Test Rock",
		"tags": ["rock", "test"],
		"recipe": {"algorithm": "stacked_spheres_v1", "lobe_count": 3, "radius_min_mm": 100, "radius_max_mm": 250, "vertical_step_mm": 200, "spread_mm": 100, "jitter_mm": 20}
	}


func _package_ids(packages: Array) -> Array[String]:
	var result: Array[String] = []
	for package in packages:
		result.append(package["manifest"]["id"])
	return result


func _new_root(label: String) -> String:
	var path := _test_root.path_join(label)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path))
	return path


func _repo_mod_path(suffix: String) -> String:
	var project_directory := ProjectSettings.globalize_path("res://").trim_suffix("/")
	return project_directory.get_base_dir().path_join("mods").path_join(suffix)


func _write_package(root: String, folder: String, manifest: Dictionary, definitions: Array) -> void:
	var package_path := root.path_join(folder)
	var content_path := package_path.path_join("objects")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(content_path))
	_write_text(package_path.path_join("manifest.json"), JSON.stringify(manifest))
	for index in range(definitions.size()):
		_write_text(content_path.path_join("definition_%02d.json" % index), JSON.stringify(definitions[index]))


func _write_raw_package(root: String, folder: String, manifest_text: String, definitions: Array) -> void:
	var package_path := root.path_join(folder)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(package_path))
	_write_text(package_path.path_join("manifest.json"), manifest_text)


func _write_text(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_check(false, "fixture file opens for write: %s" % path)
		return
	file.store_string(text)
	file.close()


func _remove_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	var directory := DirAccess.open(path)
	if directory == null:
		return
	directory.list_dir_begin()
	while true:
		var entry := directory.get_next()
		if entry.is_empty():
			break
		if entry == "." or entry == "..":
			continue
		var child := path.path_join(entry)
		if directory.current_is_dir():
			_remove_tree(child)
		else:
			DirAccess.remove_absolute(child)
	directory.list_dir_end()
	DirAccess.remove_absolute(path)


func _check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error("ASSERTION FAILED: " + label)
