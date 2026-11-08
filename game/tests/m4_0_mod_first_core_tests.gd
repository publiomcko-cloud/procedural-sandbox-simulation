extends SceneTree

const Loader := preload("res://scripts/modding/declarative_mod_loader.gd")
const Registry := preload("res://scripts/modding/content_definition_registry.gd")
const Handler := preload("res://scripts/modding/content_type_handler.gd")
const ObjectWorld := preload("res://scripts/objects/procedural_object_world.gd")
const ObjectStream := preload("res://scripts/objects/procedural_object_stream.gd")

const SYNTHETIC_TYPE := "synthetic_simulation_profile"

var assertions := 0
var failures := 0
var test_root := ""


func _initialize() -> void:
	test_root = "user://mods/m4_0_test_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(test_root))
	_test_handler_lifetime_is_acyclic()
	_test_builtin_compatibility_and_fingerprints()
	_test_legacy_discovery_view_compatibility()
	_test_loader_is_type_agnostic_and_registry_is_fail_closed()
	_remove_tree(ProjectSettings.globalize_path(test_root))
	if failures == 0:
		print("M4_0_MOD_FIRST_CORE_PASS: assertions=%d failures=0" % assertions)
	else:
		push_error("M4_0_MOD_FIRST_CORE_FAIL: assertions=%d failures=%d" % [assertions, failures])
	quit(0 if failures == 0 else 1)


func _test_handler_lifetime_is_acyclic() -> void:
	var registry: ContentDefinitionRegistry = Registry.new()
	var registry_weak: WeakRef = weakref(registry)
	registry = null
	_check(
		registry_weak.get_ref() == null,
		"built-in handler callbacks do not create a RefCounted registry cycle"
	)


func _test_builtin_compatibility_and_fingerprints() -> void:
	var discovered: Dictionary = Loader.discover_and_validate(["res://mods/first-party"])
	_check(discovered.get("ok", false), "M4.0 first-party package discovery succeeds")
	if not discovered.get("ok", false):
		return
	var packages: Array = discovered.get("packages", [])
	_check(packages.size() == 1, "M4.0 first-party discovery remains bounded to its declared package")
	if not packages.is_empty():
		var package: Dictionary = packages[0]
		var content_records: Array = package.get("content_records", [])
		var definitions: Array = package.get("definitions", [])
		var population_rules: Array = package.get("population_rules", [])
		var terrain_interactions: Array = package.get("terrain_interactions", [])
		var compatibility_count := (
			definitions.size() + population_rules.size() + terrain_interactions.size()
		)
		_check(
			content_records.size() == compatibility_count and not content_records.is_empty(),
			"generic loader records are authoritative while legacy typed views remain equivalent"
		)

	var registry: ContentDefinitionRegistry = Registry.new()
	_check(
		registry.get_registered_content_type_ids()
			== ["procedural_rock", "static_population_rule", "terrain_interaction_rule"],
		"built-in M4.0 handlers are registered deterministically"
	)
	var registered: Dictionary = registry.register_discovered(discovered)
	_check(registered.get("ok", false), "built-in content registers through handlers")
	if not registered.get("ok", false):
		return
	_check(
		int(registered.get("content_type_count", 0)) == 3
			and int(registered.get("content_record_count", 0)) >= 3,
		"generic registry reports typed content totals"
	)

	var definition_id := "firstparty.core_rocks:granite"
	var population_id := "firstparty.core_rocks:granite_population"
	var interaction_id := "firstparty.core_rocks:granite_ground_imprint"
	var legacy_pins: Dictionary = registry.pin_definitions([definition_id])
	_check(
		legacy_pins.get("ok", false)
			and legacy_pins.get("pins", []).size() == 1
			and legacy_pins["pins"][0].size() == 4
			and not legacy_pins["pins"][0].has("content_sha256"),
		"legacy persisted definition pin shape remains unchanged"
	)

	var rock_fp: Dictionary = registry.pin_content_record(Registry.ROCK_TYPE, definition_id)
	var population_fp: Dictionary = registry.pin_content_record(Registry.POPULATION_RULE_TYPE, population_id)
	var interaction_fp: Dictionary = registry.pin_content_record(Registry.TERRAIN_INTERACTION_RULE_TYPE, interaction_id)
	for result in [rock_fp, population_fp, interaction_fp]:
		var fingerprint: Dictionary = result.get("fingerprint", {})
		_check(
			result.get("ok", false)
				and String(fingerprint.get("content_sha256", "")).length() == 64
				and fingerprint.size() == 6,
			"uniform content fingerprint includes canonical SHA-256 and identity"
		)
		_check(
			registry.validate_content_fingerprint(fingerprint).get("ok", false),
			"current uniform content fingerprint validates exactly"
		)

	var old_population: Dictionary = registry.pin_population_rule(population_id)
	var old_interaction: Dictionary = registry.resolve_terrain_interaction(definition_id)
	_check(
		old_population.get("ok", false)
			and String(old_population.get("pin", {}).get("rule_sha256", ""))
				== String(population_fp.get("fingerprint", {}).get("content_sha256", "")),
		"legacy population pin reuses the uniform canonical content hash"
	)
	_check(
		old_interaction.get("ok", false)
			and String(old_interaction.get("pin", {}).get("rule_sha256", ""))
				== String(interaction_fp.get("fingerprint", {}).get("content_sha256", "")),
		"legacy terrain-interaction pin reuses the uniform canonical content hash"
	)

	var tampered: Dictionary = rock_fp.get("fingerprint", {}).duplicate(true)
	tampered["content_sha256"] = "0000000000000000000000000000000000000000000000000000000000000000"
	_check(
		registry.validate_content_fingerprint(tampered).get("reason", "")
			== "content_fingerprint_mismatch",
		"silent content fingerprint drift fails closed"
	)
	var late_handler: ContentTypeHandler = Handler.new(
		SYNTHETIC_TYPE, 40, Callable(self, "_validate_synthetic"),
		"duplicate_synthetic_profile", 16
	)
	_check(
		registry.register_engine_content_type_handler(late_handler).get("reason", "")
			== "content_type_handler_registration_closed",
		"handler set is immutable after content registration begins"
	)

	var first_generation: Dictionary = ObjectWorld.build_region_instances(
		424242, "m4-compat", Vector2i.ZERO, registry
	)
	var second_generation: Dictionary = ObjectWorld.build_region_instances(
		424242, "m4-compat", Vector2i.ZERO, registry
	)
	_check(
		first_generation.get("ok", false)
			and first_generation.get("instances", []) == second_generation.get("instances", []),
		"existing procedural world generation remains deterministic through compatibility APIs"
	)


func _test_legacy_discovery_view_compatibility() -> void:
	var discovered: Dictionary = Loader.discover_and_validate(["res://mods/first-party"])
	_check(discovered.get("ok", false), "legacy-view compatibility fixture discovers first-party content")
	if not discovered.get("ok", false):
		return
	var packages: Array = discovered["packages"]
	var package: Dictionary = packages[0]
	var rules: Array = package.get("population_rules", [])
	for rule_value in rules:
		var rule: Dictionary = rule_value
		if String(rule.get("algorithm", "")) == Registry.POPULATION_ALGORITHM:
			rule["density_milli_per_region"] = 15001
	package["population_rules"] = rules
	packages[0] = package
	discovered["packages"] = packages
	var rejected: Dictionary = Registry.new().register_discovered(discovered)
	_check(
		not rejected.get("ok", false)
			and String(rejected.get("reason", "")) == "population_rule_density_out_of_range",
		"legacy typed discovery view remains authoritative for pre-M4.0 fixture mutation"
	)


func _test_loader_is_type_agnostic_and_registry_is_fail_closed() -> void:
	var package_root: String = test_root.path_join("synthetic")
	var package_path: String = package_root.path_join("package")
	var profile_path: String = package_path.path_join("profiles")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(profile_path))
	var manifest: Dictionary = {
		"id": "sample.m4",
		"version": "1.0.0",
		"schema_version": 1,
		"requires_engine": "4.7.2",
		"dependencies": [],
		"content_roots": ["profiles/"],
		"script_policy": "data_only",
	}
	var record: Dictionary = {
		"schema_version": 1,
		"type": SYNTHETIC_TYPE,
		"id": "sample.m4:temperate",
		"value_milli": 420,
		"label": " Temperate ",
	}
	_write_text(package_path.path_join("manifest.json"), JSON.stringify(manifest))
	_write_text(profile_path.path_join("temperate.json"), JSON.stringify(record))

	var discovered: Dictionary = Loader.discover_and_validate([package_root])
	_check(
		discovered.get("ok", false)
			and discovered.get("packages", [])[0]
				.get("content_records", []).size() == 1,
		"loader discovers a new declarative type without type-specific discovery code"
	)
	if not discovered.get("ok", false):
		return

	var unsupported: ContentDefinitionRegistry = Registry.new()
	_check(
		unsupported.register_discovered(discovered).get("reason", "")
			== "unsupported_content_record_type",
		"unknown content type remains fail-closed when the engine has no handler"
	)

	var invalid_normalizer_registry: ContentDefinitionRegistry = Registry.new()
	var invalid_normalizer_handler: ContentTypeHandler = Handler.new(
		SYNTHETIC_TYPE, 40, Callable(self, "_validate_synthetic"),
		"duplicate_synthetic_profile", 16,
		Callable(self, "_normalize_synthetic_invalid")
	)
	invalid_normalizer_registry.register_engine_content_type_handler(
		invalid_normalizer_handler
	)
	_check(
		invalid_normalizer_registry.register_discovered(discovered).get(
			"reason", ""
		) == "synthetic_value_invalid",
		"normalized content is revalidated before it can enter the registry"
	)

	var registry: ContentDefinitionRegistry = Registry.new()
	var handler: ContentTypeHandler = Handler.new(
		SYNTHETIC_TYPE, 40, Callable(self, "_validate_synthetic"),
		"duplicate_synthetic_profile", 16,
		Callable(self, "_normalize_synthetic")
	)
	_check(
		registry.register_engine_content_type_handler(handler).get("ok", false),
		"engine can register a new data-only content handler before discovery commit"
	)
	_check(
		not registry.register_engine_content_type_handler(handler).get("ok", false),
		"duplicate engine content handler is rejected"
	)
	var registered: Dictionary = registry.register_discovered(discovered)
	_check(
		registered.get("ok", false),
		"synthetic content registers without loader modification (%s)"
			% registered.get("reason", "ok")
	)
	var loaded: Dictionary = registry.get_content_record(SYNTHETIC_TYPE, "sample.m4:temperate")
	_check(
		int(loaded.get("value_milli", -1)) == 420
			and String(loaded.get("label", "")) == "Temperate",
		"generic registry exposes handler-normalized synthetic content"
	)
	var first_fp: Dictionary = registry.pin_content_record(SYNTHETIC_TYPE, "sample.m4:temperate")
	_check(
		first_fp.get("ok", false)
			and registry.validate_content_fingerprint(first_fp.get("fingerprint", {})).get("ok", false),
		"synthetic type receives the same canonical fingerprint contract"
	)

	var runtime_handler: ContentTypeHandler = Handler.new(
		SYNTHETIC_TYPE, 40, Callable(self, "_validate_synthetic"),
		"duplicate_synthetic_profile", 16,
		Callable(self, "_normalize_synthetic")
	)
	var stream: ProceduralObjectStream = ObjectStream.new()
	var stream_result: Dictionary = stream.initialize(
		424242,
		"m4-synthetic-runtime",
		[package_root],
		test_root.path_join("synthetic-runtime-state"),
		[runtime_handler]
	)
	_check(
		stream_result.get("ok", false)
			and stream.registry != null
			and stream.registry.get_content_record(
				SYNTHETIC_TYPE, "sample.m4:temperate"
			).get("label", "") == "Temperate",
		"shared runtime registry accepts an engine-owned future content handler before package commit (%s)"
			% stream_result.get("reason", "ok")
	)
	stream.free()

	record["value_milli"] = 421
	_write_text(profile_path.path_join("temperate.json"), JSON.stringify(record))
	var drift_discovery: Dictionary = Loader.discover_and_validate([package_root])
	var drift_registry: ContentDefinitionRegistry = Registry.new()
	drift_registry.register_engine_content_type_handler(Handler.new(
		SYNTHETIC_TYPE, 40, Callable(self, "_validate_synthetic"),
		"duplicate_synthetic_profile", 16,
		Callable(self, "_normalize_synthetic")
	))
	var drift_registered: Dictionary = drift_registry.register_discovered(drift_discovery)
	var second_fp: Dictionary = drift_registry.pin_content_record(SYNTHETIC_TYPE, "sample.m4:temperate")
	_check(
		drift_registered.get("ok", false)
			and String(first_fp.get("fingerprint", {}).get("mod_version", ""))
				== String(second_fp.get("fingerprint", {}).get("mod_version", ""))
			and String(first_fp.get("fingerprint", {}).get("content_sha256", ""))
				!= String(second_fp.get("fingerprint", {}).get("content_sha256", "")),
		"same package version with changed content is detectable by canonical fingerprint"
	)


func _validate_synthetic(
	record: Dictionary, _mod_id: String, _context: Dictionary
) -> Dictionary:
	var expected: Array[String] = ["schema_version", "type", "id", "value_milli", "label"]
	if record.size() != expected.size():
		return {"ok": false, "reason": "synthetic_schema_fields"}
	for key in expected:
		if not record.has(key):
			return {"ok": false, "reason": "synthetic_schema_fields"}
	if int(record.get("schema_version", -1)) != 1:
		return {"ok": false, "reason": "synthetic_schema_version"}
	if String(record.get("type", "")) != SYNTHETIC_TYPE:
		return {"ok": false, "reason": "synthetic_type_mismatch"}
	var value: Variant = record.get("value_milli")
	var integer_like := (
		typeof(value) == TYPE_INT
		or (
			typeof(value) == TYPE_FLOAT
			and is_finite(float(value))
			and floor(float(value)) == float(value)
		)
	)
	if not integer_like or int(value) < 0 or int(value) > 1000:
		return {"ok": false, "reason": "synthetic_value_invalid"}
	if not record.get("label") is String or String(record.get("label", "")).strip_edges().is_empty():
		return {"ok": false, "reason": "synthetic_label_invalid"}
	return {"ok": true, "reason": "ok"}


func _normalize_synthetic_invalid(
	record: Dictionary, _mod_id: String, _context: Dictionary
) -> Dictionary:
	var normalized: Dictionary = record.duplicate(true)
	normalized["value_milli"] = 2001
	return {"ok": true, "reason": "ok", "record": normalized}


func _normalize_synthetic(
	record: Dictionary, _mod_id: String, _context: Dictionary
) -> Dictionary:
	var normalized: Dictionary = record.duplicate(true)
	normalized["value_milli"] = int(normalized.get("value_milli", 0))
	normalized["label"] = String(normalized.get("label", "")).strip_edges()
	return {"ok": true, "reason": "ok", "record": normalized}


func _write_text(path: String, value: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_check(false, "fixture file opens for write: %s" % path)
		return
	file.store_string(value)
	file.close()


func _remove_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	var directory: DirAccess = DirAccess.open(path)
	if directory == null:
		return
	directory.list_dir_begin()
	while true:
		var entry: String = directory.get_next()
		if entry.is_empty():
			break
		if entry == "." or entry == "..":
			continue
		var child: String = path.path_join(entry)
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
