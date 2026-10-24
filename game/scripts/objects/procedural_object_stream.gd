class_name ProceduralObjectStream
extends Node3D

## Owns only transient visual representatives for published terrain regions.
## Deterministic instance records are built by ProceduralObjectWorld.
const Loader := preload("res://scripts/modding/declarative_mod_loader.gd")
const RegistryScript := preload("res://scripts/modding/content_definition_registry.gd")
const ObjectWorld := preload("res://scripts/objects/procedural_object_world.gd")
const RockMeshAdapter := preload("res://scripts/objects/procedural_rock_mesh_adapter.gd")
const Spatial := preload("res://scripts/terrain/terrain_spatial_ownership.gd")
const REQUIRED_MOD_IDS := ["firstparty.core_rocks", "official.example.procedural_rock"]

var registry: ContentDefinitionRegistry
var world_seed := 0
var world_id := ""
var initialized := false
var initialization_error := ""
var objects_visible := true
var _regions: Dictionary = {} # region id -> {root, instances, world_seed}
var _region_errors: Dictionary = {}
var _definition_ids: Array[String] = []
var _mod_count := 0
var _rock_material: StandardMaterial3D


func initialize(seed_value: int, world_identifier: String, package_roots: Array[String] = []) -> Dictionary:
	_clear_region_nodes()
	initialized = false
	registry = null
	_definition_ids.clear()
	world_seed = seed_value
	world_id = world_identifier
	var roots: Array[String] = []
	for package_root in package_roots:
		roots.append(package_root)
	if roots.is_empty():
		roots = _configured_package_roots()
		if roots.is_empty():
			return _fail_initialize("user_mod_directory_unavailable")
	var candidate: ContentDefinitionRegistry = RegistryScript.new()
	var discovery: Dictionary = Loader.discover_and_validate(roots)
	if not discovery.get("ok", false):
		return _fail_initialize("package_discovery_failed:%s" % discovery.get("reason", "unknown"))
	var registration: Dictionary = candidate.register_discovered(discovery)
	if not registration.get("ok", false):
		return _fail_initialize("package_registration_failed:%s" % registration.get("reason", "unknown"))
	for mod_id in REQUIRED_MOD_IDS:
		if not candidate.has_mod(mod_id):
			return _fail_initialize("required_mod_missing:%s" % mod_id)
	for definition_id in ObjectWorld.SLOT_DEFINITIONS:
		var definition: Dictionary = candidate.get_definition(definition_id)
		if definition.is_empty():
			return _fail_initialize("required_definition_missing:%s" % definition_id)
		if int(definition.get("schema_version", -1)) != 2 or definition.get("recipe", {}).get("algorithm", "") != RockMeshAdapter.ALGORITHM:
			return _fail_initialize("required_definition_geometry_version_unsupported:%s" % definition_id)
	registry = candidate
	_mod_count = int(registration.get("mod_count", 0))
	_definition_ids.clear()
	for package in discovery.get("packages", []):
		for definition in package.get("definitions", []):
			_definition_ids.append(String(definition.get("id", "")))
	_definition_ids.sort()
	_rock_material = StandardMaterial3D.new()
	_rock_material.albedo_color = Color(0.38, 0.39, 0.37, 1.0)
	_rock_material.roughness = 0.94
	initialized = true
	initialization_error = ""
	return {"ok": true, "reason": "ok", "mod_count": _mod_count, "definition_ids": _definition_ids.duplicate()}


func publish_region(region_key: Vector2i, state: RefCounted) -> Dictionary:
	var id := _region_id(region_key)
	if not initialized:
		return _record_region_failure(id, "object_stream_not_initialized")
	if state == null or state.get("region_key") != region_key:
		return _record_region_failure(id, "region_world_identity_mismatch")
	var region_world_seed: int = int(state.get("world_seed"))
	world_seed = region_world_seed
	if _regions.has(id) and int(_regions[id]["world_seed"]) == region_world_seed:
		return {"ok": true, "reason": "already_published", "instance_count": _regions[id]["instances"].size()}
	var generated: Dictionary = ObjectWorld.build_region_instances(region_world_seed, world_id, region_key, registry)
	if not generated.get("ok", false):
		return _record_region_failure(id, String(generated.get("reason", "object_generation_failed")))
	var pending_nodes: Array[Node3D] = []
	var instances: Array[Dictionary] = generated["instances"]
	for instance in instances:
		var mesh_result: Dictionary = RockMeshAdapter.build_mesh(instance["geometry"], instance["geometry_seeds"])
		if not mesh_result.get("ok", false):
			for pending_node in pending_nodes:
				pending_node.free()
			return _record_region_failure(id, "object_mesh_build_failed:%s" % mesh_result.get("reason", "unknown"))
		var object_node := Node3D.new()
		object_node.name = "Object_%s" % String(instance["instance_id"]).sha256_text().substr(0, 12)
		object_node.position = Vector3(instance["position_mm"]) / 1000.0
		object_node.set_meta("stable_instance_id", instance["instance_id"])
		object_node.set_meta("definition_id", instance["definition_id"])
		object_node.set_meta("content_pin", instance["content_pin"])
		object_node.set_meta("recipe_algorithm", instance["recipe_algorithm"])
		object_node.set_meta("geometry_profile", instance["geometry_profile"])
		object_node.set_meta("geometry_seeds", instance["geometry_seeds"].duplicate(true))
		object_node.set_meta("geometry_adapter_version", RockMeshAdapter.GEOMETRY_VERSION)
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.mesh = mesh_result["mesh"]
		mesh_instance.material_override = _rock_material
		object_node.add_child(mesh_instance)
		pending_nodes.append(object_node)
	var region_root := Node3D.new()
	region_root.name = "Objects_%d_%d" % [region_key.x, region_key.y]
	region_root.position = Spatial.region_origin_world(region_key)
	region_root.visible = objects_visible
	for object_node in pending_nodes:
		region_root.add_child(object_node)
	if _regions.has(id):
		var previous_root: Node3D = _regions[id]["root"]
		if is_instance_valid(previous_root):
			remove_child(previous_root)
			previous_root.free()
	_regions.erase(id)
	add_child(region_root)
	_regions[id] = {"root": region_root, "instances": instances, "world_seed": region_world_seed}
	_region_errors.erase(id)
	return {"ok": true, "reason": "ok", "instance_count": instances.size()}


func unload_region(region_key: Vector2i) -> void:
	var id := _region_id(region_key)
	_region_errors.erase(id)
	if not _regions.has(id):
		return
	var region_root: Node3D = _regions[id]["root"]
	_regions.erase(id)
	if is_instance_valid(region_root):
		remove_child(region_root)
		region_root.free()


func set_object_visibility(enabled: bool) -> void:
	objects_visible = enabled
	for entry in _regions.values():
		(entry["root"] as Node3D).visible = enabled


func get_visible_instance_count() -> int:
	var count := 0
	if not objects_visible:
		return 0
	for entry in _regions.values():
		count += (entry["instances"] as Array).size()
	return count


func get_active_region_count() -> int:
	return _regions.size()


func get_region_instance_records(region_key: Vector2i) -> Array[Dictionary]:
	var entry: Dictionary = _regions.get(_region_id(region_key), {})
	var result: Array[Dictionary] = []
	for instance in entry.get("instances", []):
		result.append(instance.duplicate(true))
	return result


func get_definition_ids() -> Array[String]:
	return _definition_ids.duplicate()


func get_error_summary() -> String:
	if not initialized:
		return initialization_error
	if _region_errors.is_empty():
		return ""
	var ids: Array[String] = []
	for id_value in _region_errors:
		ids.append(String(id_value))
	ids.sort()
	return "region %s: %s" % [ids[0], _region_errors[ids[0]]]


func _configured_package_roots() -> Array[String]:
	var user_root := ProjectSettings.globalize_path("user://mods")
	var mkdir_error := DirAccess.make_dir_recursive_absolute(user_root)
	if mkdir_error != OK and mkdir_error != ERR_ALREADY_EXISTS:
		initialization_error = "user_mod_directory_unavailable"
		return []
	var project_root := ProjectSettings.globalize_path("res://").trim_suffix("/")
	var repository_example_root := project_root.get_base_dir().path_join("mods/examples")
	var user_roots: Array[String] = ["res://mods/first-party", "user://mods"]
	var installed_discovery: Dictionary = Loader.discover_and_validate(user_roots)
	if installed_discovery.get("ok", false):
		for package in installed_discovery.get("packages", []):
			if package.get("manifest", {}).get("id", "") == "official.example.procedural_rock":
				return user_roots
	return ["res://mods/first-party", repository_example_root, "user://mods"]


func _fail_initialize(reason: String) -> Dictionary:
	_clear_region_nodes()
	initialized = false
	registry = null
	_definition_ids.clear()
	_mod_count = 0
	_region_errors.clear()
	initialization_error = reason
	return _failure(reason)


func _record_region_failure(region_id: String, reason: String) -> Dictionary:
	_region_errors[region_id] = reason
	return _failure(reason)


func _clear_region_nodes() -> void:
	for entry in _regions.values():
		var region_root: Node3D = entry.get("root")
		if is_instance_valid(region_root):
			if region_root.get_parent() == self:
				remove_child(region_root)
			region_root.free()
	_regions.clear()
	_region_errors.clear()


func _region_id(region_key: Vector2i) -> String:
	return "%d,%d" % [region_key.x, region_key.y]


func _failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
