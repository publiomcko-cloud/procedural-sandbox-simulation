class_name ProceduralObjectStream
extends Node3D

## Owns only transient visual representatives for published terrain regions.
## Deterministic instance records are built by ProceduralObjectWorld.
const Loader := preload("res://scripts/modding/declarative_mod_loader.gd")
const RegistryScript := preload("res://scripts/modding/content_definition_registry.gd")
const ObjectWorld := preload("res://scripts/objects/procedural_object_world.gd")
const RockMeshAdapter := preload("res://scripts/objects/procedural_rock_mesh_adapter.gd")
const Spatial := preload("res://scripts/terrain/terrain_spatial_ownership.gd")
const FIELD := preload("res://scripts/terrain/sdf_world.gd")
const StateServiceScript := preload("res://scripts/objects/procedural_object_state_service.gd")
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
var state_service: RefCounted
var state_directory_override := ""
var _expected_publication_tokens: Dictionary = {}
var _published_publication_tokens: Dictionary = {}


func initialize(seed_value: int, world_identifier: String, package_roots: Array[String] = [], object_state_directory: String = "") -> Dictionary:
	_clear_region_nodes()
	initialized = false
	registry = null
	_definition_ids.clear()
	world_seed = seed_value
	world_id = world_identifier
	_expected_publication_tokens.clear()
	_published_publication_tokens.clear()
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
	state_directory_override = object_state_directory
	var state_load := _initialize_state_service(world_seed)
	if not state_load.get("ok", false):
		return _fail_initialize("object_state_unavailable:%s" % state_load.get("reason", "invalid"))
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


func expect_region_publication(region_key: Vector2i, publication_token: int) -> void:
	var id := _region_id(region_key)
	if publication_token > int(_expected_publication_tokens.get(id, -1)):
		_expected_publication_tokens[id] = publication_token


func publish_region(region_key: Vector2i, state: RefCounted, force_rebuild: bool = false, publication_token: int = -1) -> Dictionary:
	var id := _region_id(region_key)
	if _expected_publication_tokens.has(id) and publication_token != int(_expected_publication_tokens[id]):
		return _failure("stale_object_region_publication")
	if publication_token >= 0 and publication_token < int(_published_publication_tokens.get(id, -1)):
		return _failure("stale_object_region_publication")
	if not initialized:
		return _record_region_failure(id, "object_stream_not_initialized")
	if state == null or state.get("region_key") != region_key:
		return _record_region_failure(id, "region_world_identity_mismatch")
	var region_world_seed: int = int(state.get("world_seed"))
	if region_world_seed != world_seed:
		# A stream can never present object nodes from two world-seed domains at once.
		# The terrain stream owns cancellation/requeue of its corresponding regions.
		_clear_region_nodes()
		var state_load := _initialize_state_service(region_world_seed)
		if not state_load.get("ok", false):
			return _record_region_failure(id, "object_state_unavailable:%s" % state_load.get("reason", "invalid"))
		world_seed = region_world_seed
	if not force_rebuild and _regions.has(id) and int(_regions[id]["world_seed"]) == region_world_seed and _regions[id].get("world_state") == state:
		if publication_token >= 0:
			_published_publication_tokens[id] = publication_token
		return {"ok": true, "reason": "already_published", "instance_count": _regions[id]["instances"].size()}
	var generated: Dictionary = ObjectWorld.build_region_instances(region_world_seed, world_id, region_key, registry)
	if not generated.get("ok", false):
		return _record_region_failure(id, String(generated.get("reason", "object_generation_failed")))
	var pending_nodes: Array[Node3D] = []
	var base_instances: Array[Dictionary] = generated["instances"]
	var instances: Array[Dictionary] = []
	for base_instance in base_instances:
		var resolved: Dictionary = state_service.resolve_instance(base_instance)
		if not resolved.get("ok", false):
			for pending_node in pending_nodes:
				pending_node.free()
			return _record_region_failure(id, String(resolved.get("reason", "object_state_resolution_failed")))
		if resolved.get("deleted", false):
			continue
		var instance: Dictionary = resolved["instance"]
		instances.append(instance)
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
		object_node.set_meta("instance_components", instance.get("instance_components", {}).duplicate(true))
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.mesh = mesh_result["mesh"]
		mesh_instance.material_override = _rock_material
		object_node.add_child(mesh_instance)
		_apply_components_to_node(object_node, instance)
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
	_regions[id] = {"root": region_root, "instances": instances, "base_instances": base_instances, "world_state": state, "world_seed": region_world_seed}
	if publication_token >= 0:
		_published_publication_tokens[id] = publication_token
	_region_errors.erase(id)
	return {"ok": true, "reason": "ok", "instance_count": instances.size()}


func get_instance_ids() -> Array[String]:
	var ids: Array[String] = []
	for entry in _regions.values():
		for instance in entry.get("instances", []):
			ids.append(String(instance.get("instance_id", "")))
	ids.sort()
	return ids


func get_instance_state_revision() -> int:
	return int(state_service.get_revision()) if state_service != null and state_service.initialized else 0


func set_instance_component(instance_id: String, component_id: String, value: Dictionary) -> Dictionary:
	var located := _find_base_instance(instance_id)
	if not located.get("ok", false):
		return _failure(String(located.get("reason", "instance_not_active")))
	var result: Dictionary = state_service.set_component(located.instance, component_id, value)
	if not result.get("ok", false):
		return result
	var rebuilt := _republish_after_state_mutation(located.region_key, located.world_state)
	if not rebuilt.get("ok", false):
		return _failure("state_committed_region_rebuild_failed")
	return result


func delete_instance(instance_id: String) -> Dictionary:
	var located := _find_base_instance(instance_id)
	if not located.get("ok", false):
		return _failure(String(located.get("reason", "instance_not_active")))
	var result: Dictionary = state_service.delete_instance(located.instance)
	if not result.get("ok", false):
		return result
	var rebuilt := _republish_after_state_mutation(located.region_key, located.world_state)
	if not rebuilt.get("ok", false):
		return _failure("state_committed_region_rebuild_failed")
	return result


func restore_instance(instance_id: String) -> Dictionary:
	var located := _find_base_instance(instance_id, true)
	if not located.get("ok", false):
		var deleted_identity: Dictionary = state_service.get_deleted_identity(instance_id)
		if deleted_identity.is_empty():
			return _failure(String(located.get("reason", "instance_not_active")))
		var region_values: Array = deleted_identity.get("region_key", [])
		if region_values.size() != 2:
			return _failure("deleted_instance_identity_invalid")
		var region_key := Vector2i(int(region_values[0]), int(region_values[1]))
		var rebuilt: Dictionary = ObjectWorld.build_region_instances(world_seed, world_id, region_key, registry)
		if not rebuilt.get("ok", false):
			return _failure("deleted_instance_baseline_rebuild_failed")
		var baseline: Dictionary = {}
		for candidate in rebuilt.instances:
			if String(candidate.instance_id) == instance_id:
				baseline = candidate
				break
		if baseline.is_empty():
			return _failure("deleted_instance_identity_no_longer_generated")
		var resolved: Dictionary = state_service.resolve_instance(baseline)
		if not resolved.get("ok", false) or not resolved.get("deleted", false):
			return _failure(String(resolved.get("reason", "deleted_instance_content_pin_mismatch")))
		var restored_unloaded: Dictionary = state_service.restore_instance(baseline)
		return restored_unloaded
	var result: Dictionary = state_service.restore_instance(located.instance)
	if not result.get("ok", false):
		return result
	var rebuilt := _republish_after_state_mutation(located.region_key, located.world_state)
	if not rebuilt.get("ok", false):
		return _failure("state_committed_region_rebuild_failed")
	return result


func _find_base_instance(instance_id: String, include_deleted: bool = false) -> Dictionary:
	for region_id in _regions:
		var entry: Dictionary = _regions[region_id]
		for instance in entry.get("base_instances", []):
			if String(instance.get("instance_id", "")) == instance_id:
				if not include_deleted and state_service.snapshot.get("deleted", []).has(instance_id):
					return _failure("instance_logically_deleted")
				return {"ok": true, "instance": instance, "region_key": instance.region_key, "world_state": entry.world_state}
	return _failure("instance_not_active")


func _republish_after_state_mutation(region_key: Vector2i, world_state: RefCounted) -> Dictionary:
	var token := int(_expected_publication_tokens.get(_region_id(region_key), -1))
	return publish_region(region_key, world_state, true, token)


func _apply_components_to_node(node: Node3D, instance: Dictionary) -> void:
	var components: Dictionary = instance.get("instance_components", {})
	var transform_component: Dictionary = components.get("core.transform", {})
	if not transform_component.is_empty():
		var values: Dictionary = transform_component.get("properties", {})
		var position_delta: Array = values.get("translation_mm", [0, 0, 0])
		var rotation_mdeg: Array = values.get("rotation_mdeg", [0, 0, 0])
		var scale_milli: Array = values.get("scale_milli", [1000, 1000, 1000])
		node.position = Vector3(instance["position_mm"]) / 1000.0 + Vector3(position_delta[0], position_delta[1], position_delta[2]) / 1000.0
		node.rotation = Vector3(rotation_mdeg[0], rotation_mdeg[1], rotation_mdeg[2]) * (PI / 180000.0)
		node.scale = Vector3(scale_milli[0], scale_milli[1], scale_milli[2]) / 1000.0
	var appearance: Dictionary = components.get("core.appearance", {})
	if not appearance.is_empty():
		var properties: Dictionary = appearance.properties
		var tint: Array = properties.get("tint_milli", [1000, 1000, 1000])
		var label := String(properties.get("label", ""))
		node.set_meta("instance_label", label)
		if node.get_child_count() > 0 and node.get_child(0) is MeshInstance3D:
			var mesh_instance: MeshInstance3D = node.get_child(0)
			var material := _rock_material.duplicate() as StandardMaterial3D
			material.albedo_color = _rock_material.albedo_color * Color(float(tint[0]) / 1000.0, float(tint[1]) / 1000.0, float(tint[2]) / 1000.0, 1.0)
			mesh_instance.material_override = material
	var logical: Dictionary = components.get("core.logical", {})
	if not logical.is_empty():
		node.set_meta("logical_state", logical.get("properties", {}).get("values", {}).duplicate(true))


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


func _initialize_state_service(seed_value: int) -> Dictionary:
	var base_directory := state_directory_override
	if base_directory.is_empty():
		base_directory = ProjectSettings.globalize_path("user://worlds/%s/object-state" % world_id)
	else:
		base_directory = ProjectSettings.globalize_path(base_directory) if base_directory.begins_with("user://") or base_directory.begins_with("res://") else base_directory
	var partition := base_directory.path_join("seed-%d-generator-%d" % [seed_value, FIELD.GENERATOR_VERSION])
	var candidate: RefCounted = StateServiceScript.new()
	var loaded: Dictionary = candidate.initialize(world_id, seed_value, FIELD.GENERATOR_VERSION, partition)
	if not loaded.get("ok", false):
		state_service = null
		return loaded
	state_service = candidate
	return loaded


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
