extends RefCounted
class_name DeclarativeModLoader

const MANIFEST_FILE := "manifest.json"
const MANIFEST_SCHEMA_VERSION := 1
const ENGINE_VERSION := "4.7.2"
const MAX_PACKAGES := 128
const MAX_DEFINITIONS := 1024
const MAX_MANIFEST_BYTES := 65536
const MAX_DEFINITION_BYTES := 262144
const ID_PATTERN := "^[a-z][a-z0-9_]*(\\.[a-z][a-z0-9_]*)+$"
const SEMVER_PATTERN := "^(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)$"
const MANIFEST_KEYS := ["id", "version", "schema_version", "requires_engine", "dependencies", "content_roots", "script_policy"]


static func discover_and_validate(roots: Array[String]) -> Dictionary:
	var packages_by_id: Dictionary = {}
	var package_paths: Array[String] = []
	var total_content_record_count := 0
	for root in roots:
		if not _is_authorized_root(root):
			return _failure("unauthorized_package_root")
		var directory := DirAccess.open(ProjectSettings.globalize_path(root))
		if directory == null:
			return _failure("package_root_unavailable")
		directory.list_dir_begin()
		var entry := directory.get_next()
		var root_entry_count := 0
		while not entry.is_empty():
			root_entry_count += 1
			if root_entry_count > MAX_PACKAGES * 2:
				directory.list_dir_end()
				return _failure("package_root_entry_limit_exceeded")
			if entry != "." and entry != ".." and not entry.begins_with(".") and directory.current_is_dir():
				if directory.is_link(entry):
					directory.list_dir_end()
					return _failure("reparse_package_path_forbidden")
				package_paths.append(root.path_join(entry))
			entry = directory.get_next()
		directory.list_dir_end()
		if package_paths.size() > MAX_PACKAGES:
			return _failure("package_limit_exceeded")
	package_paths.sort()
	for package_path in package_paths:
		var parsed := _read_package(package_path)
		if not parsed.get("ok", false):
			return parsed
		var package: Dictionary = parsed["package"]
		var mod_id: String = package["manifest"]["id"]
		if packages_by_id.has(mod_id):
			return _failure("duplicate_mod_id")
		total_content_record_count += package["definitions"].size() + package["population_rules"].size()
		if total_content_record_count > MAX_DEFINITIONS:
			return _failure("content_record_limit_exceeded")
		packages_by_id[mod_id] = package
	var ordered := _resolve_order(packages_by_id)
	if not ordered.get("ok", false):
		return ordered
	return {"ok": true, "reason": "ok", "packages": ordered["packages"]}


static func _is_authorized_root(path: String) -> bool:
	if path.contains("\\"):
		return false
	for segment in path.split("/"):
		if segment == ".." or segment == ".":
			return false
	var normalized := ProjectSettings.globalize_path(path) if path.begins_with("res://") or path.begins_with("user://") else path
	normalized = normalized.trim_suffix("/").to_lower()
	var project_directory := ProjectSettings.globalize_path("res://").trim_suffix("/")
	var repository_mod_root := project_directory.get_base_dir().path_join("mods").trim_suffix("/").to_lower()
	var bundled_mod_root := project_directory.path_join("mods").trim_suffix("/").to_lower()
	var user_mod_root := ProjectSettings.globalize_path("user://mods").trim_suffix("/").to_lower()
	if normalized.find("//") >= 0:
		return false
	var authorized := normalized == repository_mod_root or normalized.begins_with(repository_mod_root + "/") or normalized == bundled_mod_root or normalized.begins_with(bundled_mod_root + "/") or normalized == user_mod_root or normalized.begins_with(user_mod_root + "/")
	return authorized and not _has_reparse_component(normalized, repository_mod_root) and not _has_reparse_component(normalized, bundled_mod_root) and not _has_reparse_component(normalized, user_mod_root)


static func _has_reparse_component(path: String, anchor: String) -> bool:
	if path != anchor and not path.begins_with(anchor + "/"):
		return false
	var current := anchor.get_base_dir()
	var anchor_name := anchor.get_file()
	var parent := DirAccess.open(current)
	if parent != null and parent.is_link(anchor_name):
		return true
	current = anchor
	if path == anchor:
		return false
	var relative := path.substr(anchor.length() + 1)
	for segment in relative.split("/"):
		var directory := DirAccess.open(current)
		if directory == null:
			return false
		if directory.is_link(segment):
			return true
		current = current.path_join(segment)
	return false


static func _read_package(package_path: String) -> Dictionary:
	if not _is_authorized_root(package_path):
		return _failure("unsafe_package_path")
	var package_directory := DirAccess.open(ProjectSettings.globalize_path(package_path))
	if package_directory == null:
		return _failure("package_unavailable")
	if package_directory.is_link(MANIFEST_FILE):
		return _failure("reparse_manifest_forbidden")
	var manifest_path := package_path.path_join(MANIFEST_FILE)
	if not FileAccess.file_exists(manifest_path):
		return _failure("missing_manifest")
	var manifest_file := FileAccess.open(manifest_path, FileAccess.READ)
	if manifest_file == null:
		return _failure("manifest_unreadable")
	if manifest_file.get_length() <= 0 or manifest_file.get_length() > MAX_MANIFEST_BYTES:
		manifest_file.close()
		return _failure("manifest_size_invalid")
	var text := manifest_file.get_as_text()
	manifest_file.close()
	var json := JSON.new()
	if json.parse(text) != OK or not json.data is Dictionary:
		return _failure("malformed_manifest")
	var manifest: Dictionary = json.data
	var manifest_result := validate_manifest(manifest)
	if not manifest_result.get("ok", false):
		return manifest_result
	var definitions: Array[Dictionary] = []
	var population_rules: Array[Dictionary] = []
	for content_root in manifest["content_roots"]:
		if not _is_safe_relative_root(content_root):
			return _failure("unsafe_content_root")
		var content_path := package_path.path_join(content_root.trim_suffix("/"))
		if package_directory.is_link(content_root.trim_suffix("/")):
			return _failure("reparse_content_root_forbidden")
		var content_directory := DirAccess.open(ProjectSettings.globalize_path(content_path))
		if content_directory == null:
			return _failure("content_root_unavailable")
		content_directory.list_dir_begin()
		var entry := content_directory.get_next()
		var entry_count := 0
		while not entry.is_empty():
			if entry != "." and entry != "..":
				entry_count += 1
				if entry_count > MAX_DEFINITIONS:
					content_directory.list_dir_end()
					return _failure("content_file_limit_exceeded")
				if content_directory.is_link(entry):
					content_directory.list_dir_end()
					return _failure("reparse_content_forbidden")
				if content_directory.current_is_dir():
					content_directory.list_dir_end()
					return _failure("nested_content_directory_forbidden")
				if entry.to_lower().ends_with(".json"):
					var definition := _read_json_dictionary(content_path.path_join(entry))
					if not definition.get("ok", false):
						content_directory.list_dir_end()
						return definition
					var content_record: Dictionary = definition["value"]
					match String(content_record.get("type", "")):
						"procedural_rock":
							definitions.append(content_record)
						"static_population_rule":
							population_rules.append(content_record)
						_:
							content_directory.list_dir_end()
							return _failure("unsupported_content_record_type")
					if definitions.size() + population_rules.size() > MAX_DEFINITIONS:
						content_directory.list_dir_end()
						return _failure("content_record_limit_exceeded")
			entry = content_directory.get_next()
		content_directory.list_dir_end()
	definitions.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.get("id", "")) < str(b.get("id", "")))
	population_rules.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.get("id", "")) < str(b.get("id", "")))
	return {"ok": true, "package": {"path": package_path, "manifest": manifest, "definitions": definitions, "population_rules": population_rules}}


static func validate_manifest(manifest: Dictionary) -> Dictionary:
	if manifest.size() != MANIFEST_KEYS.size():
		return _failure("manifest_schema_fields")
	for key in MANIFEST_KEYS:
		if not manifest.has(key):
			return _failure("manifest_schema_fields")
	if not manifest["id"] is String or not _matches(ID_PATTERN, manifest["id"]):
		return _failure("invalid_mod_id")
	if not manifest["version"] is String or not _matches(SEMVER_PATTERN, manifest["version"]):
		return _failure("invalid_mod_version")
	if not _is_integer(manifest["schema_version"]) or int(manifest["schema_version"]) != MANIFEST_SCHEMA_VERSION:
		return _failure("incompatible_manifest_schema")
	if manifest["requires_engine"] != ENGINE_VERSION:
		return _failure("incompatible_engine_version")
	if manifest["script_policy"] != "data_only":
		return _failure("script_execution_forbidden")
	if not manifest["dependencies"] is Array or not manifest["content_roots"] is Array or manifest["content_roots"].is_empty():
		return _failure("invalid_manifest_collection")
	var dependency_ids: Dictionary = {}
	for dependency in manifest["dependencies"]:
		if not dependency is Dictionary or dependency.size() != 2 or not dependency.has("id") or not dependency.has("version"):
			return _failure("invalid_dependency")
		if not dependency["id"] is String or not _matches(ID_PATTERN, dependency["id"]):
			return _failure("invalid_dependency")
		if not dependency["version"] is String or not _matches(SEMVER_PATTERN, dependency["version"]):
			return _failure("invalid_dependency")
		if dependency_ids.has(dependency["id"]):
			return _failure("duplicate_dependency")
		dependency_ids[dependency["id"]] = true
	var roots: Dictionary = {}
	for content_root in manifest["content_roots"]:
		if not content_root is String or not _is_safe_relative_root(content_root):
			return _failure("unsafe_content_root")
		if roots.has(content_root):
			return _failure("duplicate_content_root")
		roots[content_root] = true
	return {"ok": true, "reason": "ok"}


static func _resolve_order(packages_by_id: Dictionary) -> Dictionary:
	var indegree: Dictionary = {}
	var dependents: Dictionary = {}
	for mod_id in packages_by_id:
		indegree[mod_id] = 0
		dependents[mod_id] = []
	for mod_id in packages_by_id:
		var manifest: Dictionary = packages_by_id[mod_id]["manifest"]
		for dependency in manifest["dependencies"]:
			var dependency_id: String = dependency["id"]
			if not packages_by_id.has(dependency_id):
				return _failure("missing_dependency")
			if packages_by_id[dependency_id]["manifest"]["version"] != dependency["version"]:
				return _failure("dependency_version_mismatch")
			indegree[mod_id] += 1
			dependents[dependency_id].append(mod_id)
		var child_ids: Array = dependents[mod_id]
		child_ids.sort()
		dependents[mod_id] = child_ids
	var ready: Array[String] = []
	for mod_id in indegree:
		if indegree[mod_id] == 0:
			ready.append(mod_id)
	ready.sort()
	var ordered: Array[Dictionary] = []
	while not ready.is_empty():
		var mod_id: String = ready.pop_front()
		ordered.append(packages_by_id[mod_id])
		for dependent_id in dependents[mod_id]:
			indegree[dependent_id] -= 1
			if indegree[dependent_id] == 0:
				ready.append(dependent_id)
				ready.sort()
	if ordered.size() != packages_by_id.size():
		return _failure("dependency_cycle")
	return {"ok": true, "packages": ordered}


static func _is_safe_relative_root(path: String) -> bool:
	if path.is_empty() or path.contains("\\") or path.begins_with("/") or path.contains(":") or not path.ends_with("/"):
		return false
	for segment in path.trim_suffix("/").split("/"):
		if segment.is_empty() or segment == "." or segment == "..":
			return false
	return true


static func _read_json_dictionary(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _failure("content_unreadable")
	if file.get_length() <= 0 or file.get_length() > MAX_DEFINITION_BYTES:
		file.close()
		return _failure("content_size_invalid")
	var json := JSON.new()
	var parse_error := json.parse(file.get_as_text())
	file.close()
	if parse_error != OK or not json.data is Dictionary:
		return _failure("malformed_content")
	return {"ok": true, "value": json.data}


static func _is_integer(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or (typeof(value) == TYPE_FLOAT and is_finite(value) and floor(value) == value and abs(value) <= 9007199254740991.0)


static func _matches(pattern: String, value: String) -> bool:
	var regex := RegEx.new()
	if regex.compile(pattern) != OK:
		return false
	return regex.search(value) != null


static func _failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
