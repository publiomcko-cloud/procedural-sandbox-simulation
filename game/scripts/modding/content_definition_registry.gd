extends RefCounted
class_name ContentDefinitionRegistry

const ROCK_TYPE := "procedural_rock"
const ROCK_KEYS := ["schema_version", "type", "id", "display_name", "tags", "recipe"]
const LEGACY_RECIPE_KEYS := ["algorithm", "lobe_count", "radius_min_mm", "radius_max_mm", "vertical_step_mm", "spread_mm", "jitter_mm"]
const GEOLOGICAL_RECIPE_KEYS := [
	"algorithm", "profile", "half_extent_x_mm", "half_extent_y_mm", "half_extent_z_mm",
	"primary_plane_count", "fracture_plane_count", "anisotropy_axis", "anisotropy_milli",
	"bevel_count", "weathering_milli", "macro_roughness_mm", "meso_roughness_mm", "fine_roughness_mm"
]
const GEOLOGICAL_ALGORITHM := "geological_halfspace_v1"
const GRANITE_PROFILE := "granite_massive_weathered_v1"
const BASALT_PROFILE := "basalt_fractured_anisotropic_v1"
const Loader := preload("res://scripts/modding/declarative_mod_loader.gd")

var _definitions: Dictionary = {}
var _mods: Dictionary = {}


func discover_and_register(roots: Array[String]) -> Dictionary:
	var discovered: Dictionary = Loader.discover_and_validate(roots)
	if not discovered.get("ok", false):
		return discovered
	return register_discovered(discovered)


func register_discovered(discovery: Dictionary) -> Dictionary:
	if not discovery.get("ok", false) or not discovery.get("packages") is Array:
		return _failure("invalid_discovery_result")
	var candidate_definitions := _definitions.duplicate(true)
	var candidate_mods := _mods.duplicate(true)
	for package_value in discovery["packages"]:
		if not package_value is Dictionary:
			return _failure("invalid_package_record")
		var package: Dictionary = package_value
		var manifest: Dictionary = package.get("manifest", {})
		var manifest_validation: Dictionary = Loader.validate_manifest(manifest)
		if not manifest_validation.get("ok", false):
			return manifest_validation
		var mod_id: String = str(manifest.get("id", ""))
		if candidate_mods.has(mod_id):
			return _failure("duplicate_mod_registration")
		for dependency in manifest["dependencies"]:
			var dependency_id: String = dependency["id"]
			if not candidate_mods.has(dependency_id) or str(candidate_mods[dependency_id]["version"]) != str(dependency["version"]):
				return _failure("dependency_order_or_version_invalid")
		candidate_mods[mod_id] = {"version": manifest.get("version", ""), "schema_version": manifest.get("schema_version", -1)}
		for definition_value in package.get("definitions", []):
			if not definition_value is Dictionary:
				return _failure("invalid_definition")
			var definition: Dictionary = definition_value
			var validation := _validate_definition(definition, mod_id)
			if not validation.get("ok", false):
				return validation
			var definition_id: String = definition["id"]
			if candidate_definitions.has(definition_id):
				return _failure("duplicate_content_definition")
			candidate_definitions[definition_id] = definition.duplicate(true)
	_definitions = candidate_definitions
	_mods = candidate_mods
	return {"ok": true, "reason": "ok", "mod_count": _mods.size(), "definition_count": _definitions.size()}


func get_definition(namespaced_id: String) -> Dictionary:
	if not _definitions.has(namespaced_id):
		return {}
	return _definitions[namespaced_id].duplicate(true)


func has_mod(mod_id: String) -> bool:
	return _mods.has(mod_id)


func pin_definitions(namespaced_ids: Array[String]) -> Dictionary:
	var pins: Array[Dictionary] = []
	var unique_ids: Dictionary = {}
	for definition_id in namespaced_ids:
		if unique_ids.has(definition_id):
			return _failure("duplicate_pinned_content_id")
		unique_ids[definition_id] = true
		var definition := get_definition(definition_id)
		if definition.is_empty():
			return _failure("pinned_content_missing")
		var separator := definition_id.find(":")
		if separator <= 0:
			return _failure("invalid_pinned_content_id")
		var mod_id := definition_id.substr(0, separator)
		if not _mods.has(mod_id):
			return _failure("pinned_mod_missing")
		pins.append({
			"content_id": definition_id,
			"mod_id": mod_id,
			"mod_version": _mods[mod_id]["version"],
			"definition_schema_version": definition["schema_version"]
		})
	pins.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["content_id"]) < str(b["content_id"]))
	return {"ok": true, "pins": pins}


func validate_content_pins(pins: Array[Dictionary]) -> Dictionary:
	var seen: Dictionary = {}
	for pin in pins:
		if pin.size() != 4 or not pin.has("content_id") or not pin.has("mod_id") or not pin.has("mod_version") or not pin.has("definition_schema_version"):
			return _failure("invalid_content_pin")
		if not pin["content_id"] is String or not pin["mod_id"] is String or not pin["mod_version"] is String or not _is_integer(pin["definition_schema_version"]):
			return _failure("invalid_content_pin")
		var content_id: String = str(pin["content_id"])
		if seen.has(content_id):
			return _failure("duplicate_content_pin")
		seen[content_id] = true
		var definition := get_definition(content_id)
		if definition.is_empty():
			return _failure("pinned_content_missing")
		var separator := content_id.find(":")
		if separator <= 0:
			return _failure("invalid_content_pin")
		var actual_mod_id := content_id.substr(0, separator)
		if str(pin["mod_id"]) != actual_mod_id or not _mods.has(actual_mod_id):
			return _failure("pinned_mod_missing")
		if str(pin["mod_version"]) != str(_mods[actual_mod_id]["version"]):
			return _failure("pinned_mod_version_mismatch")
		if int(pin["definition_schema_version"]) != int(definition["schema_version"]):
			return _failure("pinned_definition_schema_mismatch")
	return {"ok": true, "reason": "ok"}


func evaluate_rock_recipe(namespaced_id: String, seed: int) -> Dictionary:
	var definition := get_definition(namespaced_id)
	if definition.is_empty() or definition.get("type") != ROCK_TYPE:
		return _failure("rock_definition_missing")
	if seed < 0 or seed > 2147483647:
		return _failure("seed_out_of_range")
	var recipe: Dictionary = definition["recipe"]
	if recipe.get("algorithm") == GEOLOGICAL_ALGORITHM and int(definition.get("schema_version", -1)) == 2:
		var seeds := {
			"structure": _derive_seed(seed, 0x13579),
			"fracture": _derive_seed(seed, 0x2468B),
			"wear": _derive_seed(seed, 0x3579D),
			"detail": _derive_seed(seed, 0x468AF),
		}
		var geometry := recipe.duplicate(true)
		return {
			"ok": true,
			"definition_id": namespaced_id,
			"seed": seed,
			"algorithm": GEOLOGICAL_ALGORITHM,
			"schema_version": 2,
			"profile": recipe["profile"],
			"geometry": geometry,
			"geometry_seeds": seeds,
		}
	if recipe.get("algorithm") != "stacked_spheres_v1" or int(definition.get("schema_version", -1)) != 1:
		return _failure("recipe_schema_algorithm_mismatch")
	var state: int = seed
	var lobes: Array[Dictionary] = []
	var count: int = recipe["lobe_count"]
	for index in range(count):
		state = _next_random(state)
		var radius: int = int(recipe["radius_min_mm"]) + state % (int(recipe["radius_max_mm"]) - int(recipe["radius_min_mm"]) + 1)
		state = _next_random(state)
		var x_jitter: int = _signed_offset(state, int(recipe["jitter_mm"]))
		state = _next_random(state)
		var z_jitter: int = _signed_offset(state, int(recipe["jitter_mm"]))
		var centered_index: int = index - int(count / 2)
		lobes.append({
			"center_mm": Vector3i(centered_index * int(recipe["spread_mm"]) + x_jitter, index * int(recipe["vertical_step_mm"]), z_jitter),
			"radius_mm": radius
		})
	return {"ok": true, "definition_id": namespaced_id, "seed": seed, "algorithm": recipe["algorithm"], "schema_version": 1, "lobes": lobes}


func _validate_definition(definition: Dictionary, mod_id: String) -> Dictionary:
	if definition.size() != ROCK_KEYS.size():
		return _failure("definition_schema_fields")
	for key in ROCK_KEYS:
		if not definition.has(key):
			return _failure("definition_schema_fields")
	if not _valid_local_id(definition["id"], mod_id):
		return _failure("definition_namespace_mismatch")
	if not _is_integer(definition["schema_version"]) or not [1, 2].has(int(definition["schema_version"])) or definition["type"] != ROCK_TYPE:
		return _failure("unsupported_definition_schema")
	if not definition["display_name"] is String or definition["display_name"].strip_edges().is_empty():
		return _failure("invalid_definition_metadata")
	if not definition["tags"] is Array or definition["tags"].is_empty():
		return _failure("invalid_definition_metadata")
	var seen_tags: Dictionary = {}
	for tag in definition["tags"]:
		if not tag is String or tag.is_empty() or seen_tags.has(tag):
			return _failure("invalid_definition_metadata")
		seen_tags[tag] = true
	if not definition["recipe"] is Dictionary:
		return _failure("invalid_rock_recipe")
	var recipe: Dictionary = definition["recipe"]
	match int(definition["schema_version"]):
		1:
			return _validate_legacy_recipe(recipe)
		2:
			return _validate_geological_recipe(recipe)
	return _failure("unsupported_definition_schema")


func _validate_legacy_recipe(recipe: Dictionary) -> Dictionary:
	if not _has_exact_keys(recipe, LEGACY_RECIPE_KEYS):
		return _failure("invalid_rock_recipe")
	if recipe["algorithm"] != "stacked_spheres_v1":
		return _failure("unsupported_rock_algorithm")
	for key in LEGACY_RECIPE_KEYS.slice(1):
		if not _is_integer(recipe[key]):
			return _failure("invalid_rock_recipe")
	if int(recipe["lobe_count"]) < 1 or int(recipe["lobe_count"]) > 32:
		return _failure("invalid_rock_recipe")
	if int(recipe["radius_min_mm"]) < 50 or int(recipe["radius_max_mm"]) < int(recipe["radius_min_mm"]) or int(recipe["radius_max_mm"]) > 5000:
		return _failure("invalid_rock_recipe")
	if int(recipe["vertical_step_mm"]) < 0 or int(recipe["vertical_step_mm"]) > 5000 or int(recipe["spread_mm"]) < 0 or int(recipe["spread_mm"]) > 5000 or int(recipe["jitter_mm"]) < 0 or int(recipe["jitter_mm"]) > 2000:
		return _failure("invalid_rock_recipe")
	return {"ok": true, "reason": "ok"}


func _validate_geological_recipe(recipe: Dictionary) -> Dictionary:
	if not _has_exact_keys(recipe, GEOLOGICAL_RECIPE_KEYS):
		return _failure("invalid_rock_recipe")
	if recipe["algorithm"] != GEOLOGICAL_ALGORITHM:
		return _failure("unsupported_rock_algorithm")
	if recipe["profile"] != GRANITE_PROFILE and recipe["profile"] != BASALT_PROFILE:
		return _failure("unsupported_rock_profile")
	for key in GEOLOGICAL_RECIPE_KEYS.slice(2):
		if key == "anisotropy_axis":
			if not ["x", "y", "z"].has(recipe[key]):
				return _failure("invalid_rock_recipe")
		elif not _is_integer(recipe[key]):
			return _failure("invalid_rock_recipe")
	for key in ["half_extent_x_mm", "half_extent_y_mm", "half_extent_z_mm"]:
		if int(recipe[key]) < 300 or int(recipe[key]) > 1800:
			return _failure("invalid_rock_recipe")
	if int(recipe["primary_plane_count"]) < 4 or int(recipe["primary_plane_count"]) > 10:
		return _failure("invalid_rock_recipe")
	if int(recipe["fracture_plane_count"]) < 1 or int(recipe["fracture_plane_count"]) > 7:
		return _failure("invalid_rock_recipe")
	if int(recipe["bevel_count"]) < 1 or int(recipe["bevel_count"]) > 5:
		return _failure("invalid_rock_recipe")
	if int(recipe["anisotropy_milli"]) < 700 or int(recipe["anisotropy_milli"]) > 1900:
		return _failure("invalid_rock_recipe")
	if int(recipe["weathering_milli"]) < 0 or int(recipe["weathering_milli"]) > 1000:
		return _failure("invalid_rock_recipe")
	if int(recipe["macro_roughness_mm"]) < 0 or int(recipe["macro_roughness_mm"]) > 100 or int(recipe["meso_roughness_mm"]) < 0 or int(recipe["meso_roughness_mm"]) > 60 or int(recipe["fine_roughness_mm"]) < 0 or int(recipe["fine_roughness_mm"]) > 30:
		return _failure("invalid_rock_recipe")
	if recipe["profile"] == GRANITE_PROFILE:
		if int(recipe["fracture_plane_count"]) > 3 or int(recipe["weathering_milli"]) < 600 or int(recipe["anisotropy_milli"]) > 1300:
			return _failure("profile_parameter_mismatch")
	else:
		if int(recipe["fracture_plane_count"]) < 4 or int(recipe["weathering_milli"]) > 450 or int(recipe["anisotropy_milli"]) < 1300:
			return _failure("profile_parameter_mismatch")
	return {"ok": true, "reason": "ok"}


func _has_exact_keys(value: Dictionary, expected: Array) -> bool:
	if value.size() != expected.size():
		return false
	for key in expected:
		if not value.has(key):
			return false
	return true


func _derive_seed(seed: int, discriminator: int) -> int:
	return posmod(seed * 48271 + discriminator * 69621 + 104729, 2147483646) + 1


func _valid_local_id(value: Variant, mod_id: String) -> bool:
	if not value is String:
		return false
	var prefix := mod_id + ":"
	if not value.begins_with(prefix):
		return false
	var local_id: String = value.trim_prefix(prefix)
	var regex := RegEx.new()
	regex.compile("^[a-z][a-z0-9_]*(\\.[a-z][a-z0-9_]*)*$")
	return regex.search(local_id) != null


func _next_random(state: int) -> int:
	return (1664525 * state + 1013904223) % 4294967296


func _signed_offset(value: int, magnitude: int) -> int:
	if magnitude == 0:
		return 0
	return value % (magnitude * 2 + 1) - magnitude


func _is_integer(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or (typeof(value) == TYPE_FLOAT and is_finite(value) and floor(value) == value and abs(value) <= 9007199254740991.0)


func _failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
