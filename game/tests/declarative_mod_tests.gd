extends SceneTree

const Loader := preload("res://scripts/modding/declarative_mod_loader.gd")
const Registry := preload("res://scripts/modding/content_definition_registry.gd")
const Store := preload("res://scripts/terrain/terrain_world_save_store.gd")
const Brush := preload("res://scripts/terrain/sdf_brush_edit_state.gd")
const Field := preload("res://scripts/terrain/sdf_world.gd")
const ObjectStream := preload("res://scripts/objects/procedural_object_stream.gd")

var assertions := 0
var failures := 0
var _test_root := ""


func _initialize() -> void:
	_test_root = "user://mods/p0_3_test_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_test_root))
	_test_optional_user_mod_directories()
	_test_real_packages_and_stable_order()
	_test_controlled_manifest_rejections()
	_test_dependency_failures()
	_test_content_validation_and_atomicity()
	_test_deterministic_recipe()
	_test_missing_required_package()
	_test_failed_package_preserves_save()
	_remove_tree(ProjectSettings.globalize_path(_test_root))
	if failures == 0:
		print("DECLARATIVE_MOD_PASS: assertions=%d failures=0" % assertions)
	else:
		push_error("DECLARATIVE_MOD_FAIL: assertions=%d failures=%d" % [assertions, failures])
	quit(0 if failures == 0 else 1)


func _test_optional_user_mod_directories() -> void:
	var user_root := "user://mods"
	var first_party_root := "res://mods/first-party"
	var example_root := _repo_mod_path("examples")
	_check(Loader.optional_user_roots([user_root]) == [user_root], "only the exact canonical user mods root is inferred as optional")
	_check(Loader.optional_user_roots([first_party_root, example_root]).is_empty(), "required first-party and example roots are never inferred as optional")
	var required_root_rejection: Dictionary = Loader.discover_and_validate([first_party_root], [first_party_root])
	_check(not required_root_rejection.get("ok", false) and required_root_rejection.get("reason", "") == "invalid_optional_package_root", "a caller cannot downgrade the required first-party root to optional")
	_check(String(required_root_rejection.get("diagnostics", [{}])[0].get("reason", "")) == "optional_root_not_exact_user_mod_root", "first-party optional-root rejection explains the exact-root policy")
	var example_root_rejection: Dictionary = Loader.discover_and_validate([example_root], [example_root])
	_check(not example_root_rejection.get("ok", false) and example_root_rejection.get("reason", "") == "invalid_optional_package_root", "an authorized example package root cannot be promoted to optional")
	var descendant_root := "user://mods/issue118_required_descendant_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(descendant_root.path_join("undeclared-child")))
	var descendant_rejection: Dictionary = Loader.discover_and_validate([descendant_root], [descendant_root])
	_check(not descendant_rejection.get("ok", false) and descendant_rejection.get("reason", "") == "invalid_optional_package_root" and int(descendant_rejection.get("optional_directory_ignored_count", 0)) == 0, "an authorized descendant of user mods cannot inherit optional treatment")
	var prefix_root := "user://mods-issue118-prefix"
	var prefix_rejection: Dictionary = Loader.discover_and_validate([prefix_root], [prefix_root])
	_check(not prefix_rejection.get("ok", false) and prefix_rejection.get("reason", "") == "invalid_optional_package_root", "a path sharing the user mods string prefix is not the canonical user mods root")
	_check(Loader.optional_user_roots(["user://mods/issue118_child"]).is_empty(), "optional-root inference excludes descendants of user mods")
	_remove_tree(ProjectSettings.globalize_path(descendant_root))
	_test_reparse_package_root()
	var empty_name := "issue118_empty_%d" % Time.get_ticks_usec()
	var residual_name := "issue118_residual_%d" % Time.get_ticks_usec()
	var nested_name := "issue118_nested_parent_%d" % Time.get_ticks_usec()
	var empty_path := user_root.path_join(empty_name)
	var residual_path := user_root.path_join(residual_name)
	var nested_path := user_root.path_join(nested_name)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(empty_path))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(residual_path))
	_write_text(residual_path.path_join("test-output.log"), "not a package manifest")
	var nested_package := nested_path.path_join("child-package")
	_write_package(nested_path, "child-package", _manifest("sample.nested", "1.0.0", [], ["objects/"]), [])
	var real_example_root := _repo_mod_path("examples")
	var roots: Array[String] = [first_party_root, real_example_root, user_root]
	var optional_roots: Array[String] = [user_root]
	var discovered: Dictionary = Loader.discover_and_validate(roots, optional_roots)
	_check(discovered.get("ok", false), "empty, residual and nested non-package directories in optional user mods do not disable valid declared packages (%s)" % discovered.get("reason", "ok"))
	_check(int(discovered.get("accepted_package_count", 0)) == 2 and int(discovered.get("optional_directory_ignored_count", 0)) >= 3, "optional discovery reports accepted packages separately from ignored immediate directories")
	var optional_registry := Registry.new()
	var optional_registration: Dictionary = optional_registry.discover_and_register(roots)
	_check(optional_registration.get("ok", false) and optional_registry.has_mod("firstparty.core_rocks") and optional_registry.has_mod("official.example.procedural_rock"), "P0.3 registry applies the same exact user-root optional-directory policy")
	var diagnostics: Array = discovered.get("diagnostics", [])
	var saw_empty := false
	var saw_residual := false
	var saw_nested_parent := false
	for diagnostic in diagnostics:
		if String(diagnostic.get("root", "")) != user_root:
			continue
		if String(diagnostic.get("category", "")) != "optional_directory_without_manifest" or String(diagnostic.get("disposition", "")) != "IGNORED_NOT_A_PACKAGE":
			continue
		saw_empty = saw_empty or String(diagnostic.get("relative_package_directory", "")) == empty_name
		saw_residual = saw_residual or String(diagnostic.get("relative_package_directory", "")) == residual_name
		saw_nested_parent = saw_nested_parent or String(diagnostic.get("relative_package_directory", "")) == nested_name
	_check(saw_empty and saw_residual and saw_nested_parent, "discovery diagnostics identify optional root, relative folder and ignored-not-package disposition without recursive traversal")
	var reversed_roots: Array[String] = [user_root, real_example_root, first_party_root]
	var reversed_discovery: Dictionary = Loader.discover_and_validate(reversed_roots, optional_roots)
	_check(reversed_discovery.get("ok", false) and _package_ids(reversed_discovery.get("packages", [])) == _package_ids(discovered.get("packages", [])), "optional directory policy preserves deterministic package order regardless of root ordering")

	var malformed_name := "issue118_malformed_%d" % Time.get_ticks_usec()
	_write_raw_package(user_root, malformed_name, "not-json", [])
	var malformed_discovery: Dictionary = Loader.discover_and_validate(roots, optional_roots)
	_check(not malformed_discovery.get("ok", false) and malformed_discovery.get("reason", "") == "malformed_manifest", "a present but malformed optional package manifest remains fail-closed")
	var malformed_diagnostics: Array = malformed_discovery.get("diagnostics", [])
	var malformed_diagnostic_found := false
	for diagnostic in malformed_diagnostics:
		if String(diagnostic.get("category", "")) == "declared_package_invalid" and String(diagnostic.get("relative_package_directory", "")) == malformed_name and String(diagnostic.get("reason", "")) == "malformed_manifest":
			malformed_diagnostic_found = true
	_check(malformed_diagnostic_found, "declared-package rejection carries a categorized relative diagnostic")
	_remove_tree(ProjectSettings.globalize_path(user_root.path_join(malformed_name)))

	var invalid_content_root := _new_root("issue118_invalid_content")
	_write_package(invalid_content_root, "pkg", _manifest("sample.issue118_content", "1.0.0", [], ["objects/"]), [])
	_write_text(invalid_content_root.path_join("pkg/objects/bad.json"), "not-json")
	var invalid_content: Dictionary = Loader.discover_and_validate([invalid_content_root])
	_check(not invalid_content.get("ok", false) and invalid_content.get("reason", "") == "malformed_content", "manifest-declared invalid package content remains fail-closed")

	var missing_dependency_root := _new_root("issue118_missing_dependency")
	_write_package(missing_dependency_root, "pkg", _manifest("sample.issue118_dependent", "1.0.0", [{"id": "sample.issue118_absent", "version": "1.0.0"}], ["objects/"]), [])
	var missing_dependency: Dictionary = Loader.discover_and_validate([missing_dependency_root])
	_check(not missing_dependency.get("ok", false) and missing_dependency.get("reason", "") == "missing_dependency", "declared package with absent dependency remains fail-closed")
	var dependency_diagnostics: Array = missing_dependency.get("diagnostics", [])
	_check(not dependency_diagnostics.is_empty() and String(dependency_diagnostics[0].get("category", "")) == "dependency_resolution_failed", "dependency failure identifies its package category and relative directory")

	var strict_empty_root := _new_root("issue118_required_missing_manifest")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(strict_empty_root.path_join("undeclared")))
	var strict_result: Dictionary = Loader.discover_and_validate([strict_empty_root])
	_check(not strict_result.get("ok", false) and strict_result.get("reason", "") == "missing_manifest", "unmanifested directories remain failures in non-optional package roots")
	_check(String(strict_result.get("diagnostics", [{}])[0].get("category", "")) == "required_package_manifest_missing", "strict-root missing manifest is distinguished from an ignored optional folder")

	_remove_tree(ProjectSettings.globalize_path(empty_path))
	_remove_tree(ProjectSettings.globalize_path(residual_path))
	_remove_tree(ProjectSettings.globalize_path(nested_path))


func _test_missing_required_package() -> void:
	var stream: ProceduralObjectStream = ObjectStream.new()
	var no_example: Array[String] = ["res://mods/first-party"]
	var result: Dictionary = stream.initialize(118, "issue118-required-package", no_example, _test_root.path_join("missing-required-state"))
	_check(not result.get("ok", false) and String(result.get("reason", "")).begins_with("required_mod_missing:official.example.procedural_rock"), "missing required external package remains a distinct initialization failure")
	stream.free()


func _test_reparse_package_root() -> void:
	var prepared_reparse := OS.get_environment("ISSUE118_REPARSE_FIXTURE_PATH")
	if prepared_reparse == "user://mods/issue118_reparse_fixture":
		var prepared_link_path := ProjectSettings.globalize_path(prepared_reparse)
		var mods_directory := DirAccess.open(ProjectSettings.globalize_path("user://mods"))
		var prepared_link_present := mods_directory != null and mods_directory.is_link("issue118_reparse_fixture")
		var reparse_roots: Array[String] = ["res://mods/first-party", "user://mods"]
		var optional_roots: Array[String] = ["user://mods"]
		var reparse_discovery: Dictionary = Loader.discover_and_validate(reparse_roots, optional_roots)
		_check(prepared_link_present and not reparse_discovery.get("ok", false) and reparse_discovery.get("reason", "") == "reparse_package_path_forbidden", "prepared Windows junction/reparse path remains rejected under the optional user root")
		if prepared_link_present:
			_check(DirAccess.remove_absolute(prepared_link_path) == OK, "disposable reparse fixture is removed as a link without traversing its target")
		return
	var reparse_target := _new_root("issue118_reparse_target")
	_write_package(reparse_target, "pkg", _manifest("sample.issue118_reparse", "1.0.0", [], ["objects/"]), [])
	var link_container := _new_root("issue118_reparse_root")
	var link_path := link_container.path_join("linked-package")
	var link_directory := DirAccess.open(ProjectSettings.globalize_path(link_container))
	var link_error := ERR_UNAVAILABLE
	if link_directory != null:
		link_error = link_directory.create_link(ProjectSettings.globalize_path(reparse_target.path_join("pkg")), ProjectSettings.globalize_path(link_path))
	if link_error == OK:
		var reparse_discovery: Dictionary = Loader.discover_and_validate([link_container])
		_check(not reparse_discovery.get("ok", false) and reparse_discovery.get("reason", "") == "reparse_package_path_forbidden", "reparse package path remains rejected even under an optional user root")
	else:
		print("ISSUE118_REPARSE_FIXTURE_UNAVAILABLE: DirAccess.create_link returned %s; prepared Windows junction validation not supplied" % error_string(link_error))
		_check(Loader.discover_and_validate(["user://mods/../outside"]).get("reason", "") == "unauthorized_package_root", "traversal guard remains enforced when this runner cannot create a reparse fixture")
	_remove_tree(ProjectSettings.globalize_path(link_container))
	_remove_tree(ProjectSettings.globalize_path(reparse_target))


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
		if directory.is_link(entry):
			DirAccess.remove_absolute(child)
		elif directory.current_is_dir():
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
