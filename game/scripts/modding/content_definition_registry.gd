extends RefCounted
class_name ContentDefinitionRegistry

const ROCK_TYPE := "procedural_rock"
const ROCK_KEYS := ["schema_version", "type", "id", "display_name", "tags", "recipe"]
const POPULATION_RULE_TYPE := "static_population_rule"
const POPULATION_RULE_KEYS := ["schema_version", "type", "id", "definition_id", "algorithm", "density_milli_per_region", "legacy_slot", "distribution", "transform", "surface"]
const DISTRIBUTION_KEYS := ["grid_spacing_mm", "jitter_milli", "minimum_separation_mm", "edge_margin_mm", "geometry_variant_count"]
const TRANSFORM_KEYS := ["scale_min_milli", "scale_max_milli", "orientation", "yaw_min_mdeg", "yaw_max_mdeg"]
const SURFACE_KEYS := ["mode", "minimum_height_mm", "maximum_height_mm", "maximum_slope_mdeg"]
const POPULATION_ALGORITHM := "region_grid_density_v1"
const LEGACY_POPULATION_ALGORITHM := "p2a_compatibility_slot_v1"
const MAX_POPULATION_RULES := 128
const MAX_LEGACY_COMPATIBILITY_SLOTS := 32
const TERRAIN_INTERACTION_RULE_TYPE := "terrain_interaction_rule"
const TERRAIN_INTERACTION_KEYS := ["schema_version", "type", "id", "definition_id", "algorithm", "shape_source", "operation", "embed_depth_mm", "blend_radius_mm", "edit_order"]
const TERRAIN_INTERACTION_ALGORITHM := "sdf_ground_imprint_v1"
const TERRAIN_INTERACTION_SHAPE_SOURCE := "recipe_envelope_v1"
const TERRAIN_INTERACTION_OPERATION := "subtract_solid_v1"
const TERRAIN_INTERACTION_EDIT_ORDER := "terrain_edits_then_imprint_v1"
const MAX_TERRAIN_INTERACTION_RULES := 128
const LEGACY_RECIPE_KEYS := ["algorithm", "lobe_count", "radius_min_mm", "radius_max_mm", "vertical_step_mm", "spread_mm", "jitter_mm"]
const GEOLOGICAL_RECIPE_KEYS := [
	"algorithm", "profile", "half_extent_x_mm", "half_extent_y_mm", "half_extent_z_mm",
	"primary_plane_count", "fracture_plane_count", "anisotropy_axis", "anisotropy_milli",
	"bevel_count", "weathering_milli", "macro_roughness_mm", "meso_roughness_mm", "fine_roughness_mm"
]
const GEOLOGICAL_ALGORITHM := "geological_halfspace_v1"
const Loader := preload("res://scripts/modding/declarative_mod_loader.gd")
const ContentTypeHandlerScript := preload("res://scripts/modding/content_type_handler.gd")

var _definitions: Dictionary = {}
var _population_rules: Dictionary = {}
var _terrain_interactions: Dictionary = {}
var _terrain_interaction_by_definition: Dictionary = {}
var _mods: Dictionary = {}
var _content_handlers: Dictionary = {}
var _content_records_by_type: Dictionary = {}


func _init() -> void:
	_register_handler_internal(ContentTypeHandlerScript.new(
		ROCK_TYPE, 10, Callable(self, "_validate_rock_handler"),
		"duplicate_content_definition", 0
	))
	_register_handler_internal(ContentTypeHandlerScript.new(
		POPULATION_RULE_TYPE, 20, Callable(self, "_validate_population_handler"),
		"duplicate_population_rule", MAX_POPULATION_RULES
	))
	_register_handler_internal(ContentTypeHandlerScript.new(
		TERRAIN_INTERACTION_RULE_TYPE, 30, Callable(self, "_validate_terrain_interaction_handler"),
		"duplicate_terrain_interaction_rule", MAX_TERRAIN_INTERACTION_RULES
	))


func _register_handler_internal(handler: RefCounted) -> Dictionary:
	if handler == null or not handler.has_method("is_valid") or not bool(handler.call("is_valid")):
		return _failure("content_type_handler_invalid")
	var content_type := String(handler.get("type_id"))
	if not _valid_content_type_id(content_type):
		return _failure("content_type_handler_invalid")
	if _content_handlers.has(content_type):
		return _failure("duplicate_content_type_handler")
	_content_handlers[content_type] = handler
	return {"ok": true, "reason": "ok"}


func _valid_content_type_id(value: String) -> bool:
	if value.is_empty() or value.length() > 64:
		return false
	for index in range(value.length()):
		var code := value.unicode_at(index)
		var valid := (
			(code >= 97 and code <= 122)
			or (code >= 48 and code <= 57 and index > 0)
			or (code == 95 and index > 0)
		)
		if not valid:
			return false
	return true


func _package_content_records(package: Dictionary) -> Dictionary:
	if package.has("content_records"):
		if not package["content_records"] is Array:
			return _failure("invalid_content_record_collection")
		var direct: Array[Dictionary] = []
		for value in package["content_records"]:
			if not value is Dictionary:
				return _failure("invalid_content_record")
			direct.append((value as Dictionary).duplicate(true))
		return {"ok": true, "records": direct}
	var legacy: Array[Dictionary] = []
	for key in ["definitions", "population_rules", "terrain_interactions"]:
		var values: Variant = package.get(key, [])
		if not values is Array:
			return _failure("invalid_content_record_collection")
		for value in values:
			if not value is Dictionary:
				return _failure("invalid_content_record")
			legacy.append((value as Dictionary).duplicate(true))
	return {"ok": true, "records": legacy}


func _validate_common_content_identity(
	record: Dictionary, mod_id: String, expected_type: String
) -> Dictionary:
	if not record.has("schema_version") or not record.has("type") or not record.has("id"):
		return _failure("content_record_identity_fields")
	if String(record.get("type", "")) != expected_type:
		return _failure("content_record_type_mismatch")
	if not _is_integer(record["schema_version"]) or int(record["schema_version"]) <= 0:
		return _failure("content_record_schema_invalid")
	if not record["id"] is String or not _valid_local_id(record["id"], mod_id):
		return _failure("content_record_namespace_mismatch")
	return {"ok": true, "reason": "ok"}


func _validate_rock_handler(
	record: Dictionary, mod_id: String, _context: Dictionary
) -> Dictionary:
	return _validate_definition(record, mod_id)


func _validate_population_handler(
	record: Dictionary, mod_id: String, context: Dictionary
) -> Dictionary:
	var records_by_type: Dictionary = context.get("records_by_type", {})
	var definitions: Dictionary = records_by_type.get(ROCK_TYPE, {})
	return _validate_population_rule(record, mod_id, definitions)


func _validate_terrain_interaction_handler(
	record: Dictionary, mod_id: String, context: Dictionary
) -> Dictionary:
	var records_by_type: Dictionary = context.get("records_by_type", {})
	var definitions: Dictionary = records_by_type.get(ROCK_TYPE, {})
	return _validate_terrain_interaction(record, mod_id, definitions)


func _build_content_fingerprint(
	content_type: String,
	namespaced_id: String,
	record: Dictionary,
	mods: Dictionary
) -> Dictionary:
	var separator := namespaced_id.find(":")
	if separator <= 0:
		return _failure("invalid_content_record_id")
	var mod_id := namespaced_id.substr(0, separator)
	if not mods.has(mod_id):
		return _failure("content_record_package_missing")
	var canonical := JSON.stringify(record, "", true, true)
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return _failure("content_fingerprint_failed")
	if context.update(canonical.to_utf8_buffer()) != OK:
		return _failure("content_fingerprint_failed")
	return {"ok": true, "fingerprint": {
		"content_id": namespaced_id,
		"content_type": content_type,
		"mod_id": mod_id,
		"mod_version": String(mods[mod_id]["version"]),
		"schema_version": int(record["schema_version"]),
		"content_sha256": context.finish().hex_encode(),
	}}




func discover_and_register(roots: Array[String], optional_roots: Array[String] = []) -> Dictionary:
	var effective_optional_roots := optional_roots
	if effective_optional_roots.is_empty():
		effective_optional_roots = Loader.optional_user_roots(roots)
	var discovered: Dictionary = Loader.discover_and_validate(roots, effective_optional_roots)
	if not discovered.get("ok", false):
		return discovered
	return register_discovered(discovered)


func register_engine_content_type_handler(handler: RefCounted) -> Dictionary:
	if not _mods.is_empty() or not _content_records_by_type.is_empty():
		return _failure("content_type_handler_registration_closed")
	return _register_handler_internal(handler)


func get_registered_content_type_ids() -> Array[String]:
	var ids: Array[String] = []
	for type_value in _content_handlers.keys():
		ids.append(String(type_value))
	ids.sort()
	return ids


func get_content_record(content_type: String, namespaced_id: String) -> Dictionary:
	var typed: Dictionary = _content_records_by_type.get(content_type, {})
	if not typed.has(namespaced_id):
		return {}
	return (typed[namespaced_id] as Dictionary).duplicate(true)


func get_content_record_ids(content_type: String) -> Array[String]:
	var result: Array[String] = []
	var typed: Dictionary = _content_records_by_type.get(content_type, {})
	for id_value in typed.keys():
		result.append(String(id_value))
	result.sort()
	return result


func pin_content_record(content_type: String, namespaced_id: String) -> Dictionary:
	var record := get_content_record(content_type, namespaced_id)
	if record.is_empty():
		return _failure("content_record_missing")
	var fingerprint := _build_content_fingerprint(content_type, namespaced_id, record, _mods)
	if not fingerprint.get("ok", false):
		return fingerprint
	return {"ok": true, "fingerprint": fingerprint["fingerprint"]}


func validate_content_fingerprint(fingerprint: Dictionary) -> Dictionary:
	var required := [
		"content_id", "content_type", "mod_id", "mod_version",
		"schema_version", "content_sha256"
	]
	if not _has_exact_keys(fingerprint, required):
		return _failure("invalid_content_fingerprint")
	var content_type := String(fingerprint.get("content_type", ""))
	var content_id := String(fingerprint.get("content_id", ""))
	var record := get_content_record(content_type, content_id)
	if record.is_empty():
		return _failure("content_record_missing")
	var current := _build_content_fingerprint(content_type, content_id, record, _mods)
	if not current.get("ok", false):
		return current
	if current["fingerprint"] != fingerprint:
		return _failure("content_fingerprint_mismatch")
	return {"ok": true, "reason": "ok"}


func register_discovered(discovery: Dictionary) -> Dictionary:
	if not discovery.get("ok", false) or not discovery.get("packages") is Array:
		return _failure("invalid_discovery_result")
	var candidate_records: Dictionary = _content_records_by_type.duplicate(true)
	var candidate_terrain_interaction_by_definition := _terrain_interaction_by_definition.duplicate(true)
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
		candidate_mods[mod_id] = {
			"version": manifest.get("version", ""),
			"schema_version": manifest.get("schema_version", -1)
		}
		var records_result := _package_content_records(package)
		if not records_result.get("ok", false):
			return records_result
		var records: Array[Dictionary] = records_result["records"]
		records.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var a_type := String(a.get("type", ""))
			var b_type := String(b.get("type", ""))
			var a_handler: RefCounted = _content_handlers.get(a_type)
			var b_handler: RefCounted = _content_handlers.get(b_type)
			var a_priority := int(a_handler.get("registration_priority")) if a_handler != null else 2147483647
			var b_priority := int(b_handler.get("registration_priority")) if b_handler != null else 2147483647
			if a_priority != b_priority:
				return a_priority < b_priority
			return "%s|%s" % [a_type, String(a.get("id", ""))] < "%s|%s" % [b_type, String(b.get("id", ""))]
		)
		for record in records:
			var content_type := String(record.get("type", ""))
			if not _content_handlers.has(content_type):
				return _failure("unsupported_content_record_type")
			var common_validation := _validate_common_content_identity(record, mod_id, content_type)
			if not common_validation.get("ok", false):
				return common_validation
			var handler: RefCounted = _content_handlers[content_type]
			var validation: Dictionary = handler.call("validate", record, mod_id, {
				"records_by_type": candidate_records,
				"terrain_interaction_by_definition": candidate_terrain_interaction_by_definition,
			})
			if not validation.get("ok", false):
				return validation
			var records_for_type: Dictionary = candidate_records.get(content_type, {}).duplicate(true)
			var record_id := String(record["id"])
			if records_for_type.has(record_id):
				return _failure(String(handler.get("duplicate_reason")))
			if content_type == TERRAIN_INTERACTION_RULE_TYPE:
				var definition_id := String(record["definition_id"])
				if candidate_terrain_interaction_by_definition.has(definition_id):
					return _failure("duplicate_terrain_interaction_for_definition")
				candidate_terrain_interaction_by_definition[definition_id] = record_id
			records_for_type[record_id] = record.duplicate(true)
			var max_records := int(handler.get("max_records"))
			if max_records > 0 and records_for_type.size() > max_records:
				if content_type == POPULATION_RULE_TYPE:
					return _failure("population_rule_limit_exceeded")
				if content_type == TERRAIN_INTERACTION_RULE_TYPE:
					return _failure("terrain_interaction_rule_limit_exceeded")
				return _failure("content_type_record_limit_exceeded")
			candidate_records[content_type] = records_for_type
	_content_records_by_type = candidate_records
	_definitions = candidate_records.get(ROCK_TYPE, {}).duplicate(true)
	_population_rules = candidate_records.get(POPULATION_RULE_TYPE, {}).duplicate(true)
	_terrain_interactions = candidate_records.get(TERRAIN_INTERACTION_RULE_TYPE, {}).duplicate(true)
	_terrain_interaction_by_definition = candidate_terrain_interaction_by_definition
	_mods = candidate_mods
	var content_record_count := 0
	for typed_records_value in _content_records_by_type.values():
		var typed_records: Dictionary = typed_records_value
		content_record_count += typed_records.size()
	return {
		"ok": true,
		"reason": "ok",
		"mod_count": _mods.size(),
		"definition_count": _definitions.size(),
		"population_rule_count": _population_rules.size(),
		"terrain_interaction_count": _terrain_interactions.size(),
		"content_type_count": _content_records_by_type.size(),
		"content_record_count": content_record_count,
	}


func get_definition(namespaced_id: String) -> Dictionary:
	if not _definitions.has(namespaced_id):
		return {}
	return _definitions[namespaced_id].duplicate(true)


func has_mod(mod_id: String) -> bool:
	return _mods.has(mod_id)


func get_definition_ids() -> Array[String]:
	var ids: Array[String] = []
	for id_value in _definitions.keys():
		ids.append(String(id_value))
	ids.sort()
	return ids


func get_population_rule(namespaced_id: String) -> Dictionary:
	if not _population_rules.has(namespaced_id):
		return {}
	return _population_rules[namespaced_id].duplicate(true)


func get_population_rule_ids() -> Array[String]:
	var ids: Array[String] = []
	for id_value in _population_rules.keys():
		ids.append(String(id_value))
	ids.sort()
	return ids


func get_compatibility_population_rules() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for rule_id in get_population_rule_ids():
		var rule: Dictionary = _population_rules[rule_id]
		if rule.get("algorithm", "") == LEGACY_POPULATION_ALGORITHM:
			result.append(rule.duplicate(true))
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("legacy_slot", -1)) < int(b.get("legacy_slot", -1)))
	return result



func get_terrain_interaction_rule(namespaced_id: String) -> Dictionary:
	if not _terrain_interactions.has(namespaced_id):
		return {}
	return _terrain_interactions[namespaced_id].duplicate(true)


func get_terrain_interaction_for_definition(definition_id: String) -> Dictionary:
	var interaction_id := String(_terrain_interaction_by_definition.get(definition_id, ""))
	return get_terrain_interaction_rule(interaction_id) if not interaction_id.is_empty() else {}


func get_terrain_interaction_rule_ids() -> Array[String]:
	var ids: Array[String] = []
	for id_value in _terrain_interactions.keys():
		ids.append(String(id_value))
	ids.sort()
	return ids


func resolve_terrain_interaction(definition_id: String) -> Dictionary:
	var rule := get_terrain_interaction_for_definition(definition_id)
	if rule.is_empty():
		return {"ok": true, "rule": {}, "pin": {}}
	var interaction_id := String(rule["id"])
	var separator := interaction_id.find(":")
	if separator <= 0:
		return _failure("terrain_interaction_id_invalid")
	var mod_id := interaction_id.substr(0, separator)
	if not _mods.has(mod_id):
		return _failure("terrain_interaction_package_missing")
	var uniform := pin_content_record(TERRAIN_INTERACTION_RULE_TYPE, interaction_id)
	if not uniform.get("ok", false):
		return _failure("terrain_interaction_pin_failed")
	var fingerprint: Dictionary = uniform["fingerprint"]
	return {"ok": true, "rule": rule, "pin": {
		"rule_id": interaction_id,
		"definition_id": definition_id,
		"mod_id": mod_id,
		"mod_version": String(_mods[mod_id]["version"]),
		"rule_schema_version": int(rule["schema_version"]),
		"algorithm": String(rule["algorithm"]),
		"rule_sha256": String(fingerprint["content_sha256"]),
	}}


func pin_population_rule(namespaced_id: String) -> Dictionary:
	var rule := get_population_rule(namespaced_id)
	if rule.is_empty():
		return _failure("population_rule_missing")
	var separator := namespaced_id.find(":")
	if separator <= 0:
		return _failure("invalid_population_rule_id")
	var mod_id := namespaced_id.substr(0, separator)
	if not _mods.has(mod_id):
		return _failure("population_rule_package_missing")
	var uniform := pin_content_record(POPULATION_RULE_TYPE, namespaced_id)
	if not uniform.get("ok", false):
		return _failure("population_rule_pin_failed")
	var fingerprint: Dictionary = uniform["fingerprint"]
	return {"ok": true, "pin": {
		"rule_id": namespaced_id,
		"mod_id": mod_id,
		"mod_version": String(_mods[mod_id]["version"]),
		"rule_schema_version": int(rule["schema_version"]),
		"algorithm": String(rule["algorithm"]),
		"rule_sha256": String(fingerprint["content_sha256"]),
	}}


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
			"mod_version": String(_mods[mod_id]["version"]),
			"definition_schema_version": int(definition["schema_version"])
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


func _validate_population_rule(rule: Dictionary, mod_id: String, definitions: Dictionary) -> Dictionary:
	if not _has_exact_keys(rule, POPULATION_RULE_KEYS):
		return _failure("population_rule_schema_fields")
	if not _valid_local_id(rule["id"], mod_id) or not _is_integer(rule["schema_version"]) or int(rule["schema_version"]) != 1 or rule["type"] != POPULATION_RULE_TYPE:
		return _failure("population_rule_identity_invalid")
	if not rule["definition_id"] is String or not definitions.has(rule["definition_id"]):
		return _failure("population_rule_definition_missing")
	var definition: Dictionary = definitions[rule["definition_id"]]
	if definition.get("type") != ROCK_TYPE or definition.get("schema_version") != 2:
		return _failure("population_rule_definition_unsupported")
	if not rule["distribution"] is Dictionary or not _has_exact_keys(rule["distribution"], DISTRIBUTION_KEYS):
		return _failure("population_rule_distribution_fields")
	if not rule["transform"] is Dictionary or not _has_exact_keys(rule["transform"], TRANSFORM_KEYS):
		return _failure("population_rule_transform_fields")
	if not rule["surface"] is Dictionary or not _has_exact_keys(rule["surface"], SURFACE_KEYS):
		return _failure("population_rule_surface_fields")
	if not rule["algorithm"] is String or not [POPULATION_ALGORITHM, LEGACY_POPULATION_ALGORITHM].has(rule["algorithm"]):
		return _failure("population_rule_algorithm_unsupported")
	if not _is_integer(rule["density_milli_per_region"]) or int(rule["density_milli_per_region"]) < 0 or int(rule["density_milli_per_region"]) > 15000:
		return _failure("population_rule_density_out_of_range")
	if not _is_integer(rule["legacy_slot"]) or int(rule["legacy_slot"]) < -1 or int(rule["legacy_slot"]) >= MAX_LEGACY_COMPATIBILITY_SLOTS:
		return _failure("population_rule_legacy_slot_invalid")
	var distribution: Dictionary = rule["distribution"]
	for key in DISTRIBUTION_KEYS:
		if not _is_integer(distribution[key]):
			return _failure("population_rule_distribution_invalid")
	if int(distribution["geometry_variant_count"]) < 1 or int(distribution["geometry_variant_count"]) > 16:
		return _failure("population_rule_geometry_variants_invalid")
	var transform: Dictionary = rule["transform"]
	if transform["orientation"] != "yaw_uniform_v1" or not _is_integer(transform["yaw_min_mdeg"]) or not _is_integer(transform["yaw_max_mdeg"]):
		return _failure("population_rule_orientation_invalid")
	if int(transform["yaw_min_mdeg"]) < -360000 or int(transform["yaw_max_mdeg"]) > 360000 or int(transform["yaw_min_mdeg"]) > int(transform["yaw_max_mdeg"]):
		return _failure("population_rule_orientation_invalid")
	for axis in range(3):
		var scale_min: Variant = transform["scale_min_milli"][axis] if transform["scale_min_milli"] is Array and transform["scale_min_milli"].size() == 3 else null
		var scale_max: Variant = transform["scale_max_milli"][axis] if transform["scale_max_milli"] is Array and transform["scale_max_milli"].size() == 3 else null
		if not _is_integer(scale_min) or not _is_integer(scale_max) or int(scale_min) < 500 or int(scale_max) > 2000 or int(scale_min) > int(scale_max):
			return _failure("population_rule_scale_invalid")
	var surface: Dictionary = rule["surface"]
	if surface["mode"] != "top_surface_v1" or not _is_integer(surface["minimum_height_mm"]) or not _is_integer(surface["maximum_height_mm"]) or not _is_integer(surface["maximum_slope_mdeg"]):
		return _failure("population_rule_surface_invalid")
	if int(surface["minimum_height_mm"]) < -100000 or int(surface["maximum_height_mm"]) > 100000 or int(surface["minimum_height_mm"]) > int(surface["maximum_height_mm"]) or int(surface["maximum_slope_mdeg"]) < 0 or int(surface["maximum_slope_mdeg"]) > 90000:
		return _failure("population_rule_surface_invalid")
	var recipe: Dictionary = definition["recipe"]
	var horizontal_radius_mm := sqrt(pow(float(recipe["half_extent_x_mm"]), 2.0) + pow(float(recipe["half_extent_z_mm"]), 2.0))
	if rule["algorithm"] == LEGACY_POPULATION_ALGORITHM:
		var legacy_scale_identity := true
		for axis in range(3):
			legacy_scale_identity = legacy_scale_identity and int(transform["scale_min_milli"][axis]) == 1000 and int(transform["scale_max_milli"][axis]) == 1000
		var legacy_distribution: Dictionary = rule["distribution"]
		var legacy_surface: Dictionary = rule["surface"]
		var legacy_distribution_identity: bool = int(legacy_distribution["grid_spacing_mm"]) == 3000 and int(legacy_distribution["jitter_milli"]) == 100 and int(legacy_distribution["minimum_separation_mm"]) == 2400 and int(legacy_distribution["edge_margin_mm"]) == 2000 and int(legacy_distribution["geometry_variant_count"]) == 4
		var legacy_surface_identity: bool = legacy_surface["mode"] == "top_surface_v1" and int(legacy_surface["minimum_height_mm"]) == -1000 and int(legacy_surface["maximum_height_mm"]) == 12000 and int(legacy_surface["maximum_slope_mdeg"]) == 90000
		if int(rule["legacy_slot"]) < 0 or int(rule["density_milli_per_region"]) != 1000 or not legacy_scale_identity or not legacy_distribution_identity or not legacy_surface_identity or transform["orientation"] != "yaw_uniform_v1" or int(transform["yaw_min_mdeg"]) != 0 or int(transform["yaw_max_mdeg"]) != 0:
			return _failure("population_rule_legacy_contract_invalid")
	else:
		if int(rule["legacy_slot"]) != -1:
			return _failure("population_rule_legacy_slot_invalid")
		var spacing := int(distribution["grid_spacing_mm"])
		var jitter := int(distribution["jitter_milli"])
		var min_separation := int(distribution["minimum_separation_mm"])
		var edge_margin := int(distribution["edge_margin_mm"])
		if spacing < 2000 or spacing > 8000 or jitter < 0 or jitter > 100 or min_separation < 1000 or min_separation > 8000 or edge_margin < 1000 or edge_margin > 6000:
			return _failure("population_rule_distribution_invalid")
		if spacing - (2 * spacing * jitter / 1000) < min_separation or edge_margin < ceil(horizontal_radius_mm) + 100:
			return _failure("population_rule_clearance_invalid")
		var candidate_count := _population_candidate_count(distribution)
		if candidate_count < 1 or int(rule["density_milli_per_region"]) > candidate_count * 1000:
			return _failure("population_rule_density_exceeds_lattice")
	return {"ok": true, "reason": "ok"}



func _validate_terrain_interaction(rule: Dictionary, mod_id: String, definitions: Dictionary) -> Dictionary:
	if not _has_exact_keys(rule, TERRAIN_INTERACTION_KEYS):
		return _failure("terrain_interaction_schema_fields")
	if not _valid_local_id(rule["id"], mod_id) or not _is_integer(rule["schema_version"]) or int(rule["schema_version"]) != 1 or rule["type"] != TERRAIN_INTERACTION_RULE_TYPE:
		return _failure("terrain_interaction_identity_invalid")
	if not rule["definition_id"] is String or not _valid_local_id(rule["definition_id"], mod_id) or not definitions.has(rule["definition_id"]):
		return _failure("terrain_interaction_definition_invalid")
	var definition: Dictionary = definitions[rule["definition_id"]]
	if definition.get("type") != ROCK_TYPE or int(definition.get("schema_version", -1)) != 2:
		return _failure("terrain_interaction_definition_unsupported")
	if rule["algorithm"] != TERRAIN_INTERACTION_ALGORITHM or rule["shape_source"] != TERRAIN_INTERACTION_SHAPE_SOURCE or rule["operation"] != TERRAIN_INTERACTION_OPERATION or rule["edit_order"] != TERRAIN_INTERACTION_EDIT_ORDER:
		return _failure("terrain_interaction_algorithm_unsupported")
	if not _is_integer(rule["embed_depth_mm"]) or int(rule["embed_depth_mm"]) < 0 or int(rule["embed_depth_mm"]) > 3000:
		return _failure("terrain_interaction_embed_depth_invalid")
	if not _is_integer(rule["blend_radius_mm"]) or int(rule["blend_radius_mm"]) < 0 or int(rule["blend_radius_mm"]) > 2000:
		return _failure("terrain_interaction_blend_radius_invalid")
	return {"ok": true, "reason": "ok"}


func _population_candidate_count(distribution: Dictionary) -> int:
	const REGION_X_MM := 16000
	const REGION_Z_MM := 12000
	var spacing := int(distribution["grid_spacing_mm"])
	var margin := int(distribution["edge_margin_mm"])
	var count_x := floori(float(REGION_X_MM - 2 * margin) / float(spacing)) + 1
	var count_z := floori(float(REGION_Z_MM - 2 * margin) / float(spacing)) + 1
	return maxi(0, count_x) * maxi(0, count_z)


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
	if not _valid_profile_id(recipe["profile"]):
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


func _valid_profile_id(value: Variant) -> bool:
	if not value is String or String(value).length() < 3 or String(value).length() > 64:
		return false
	var regex := RegEx.new()
	regex.compile("^[a-z][a-z0-9_]*_v[1-9][0-9]*$")
	return regex.search(String(value)) != null


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
