extends RefCounted

## DM7: exact pristine mod-first rock geometry for a visual-only regional
## mesh. The worker never creates ArrayMesh, scene nodes, collision bodies,
## state services or mutable authority. It shares the same placement and
## geometry kernels used by ProceduralObjectStream.
const ObjectWorld := preload("res://scripts/objects/procedural_object_world.gd")
const RockMeshAdapter := preload("res://scripts/objects/procedural_rock_mesh_adapter.gd")
const StaticBatch := preload("res://scripts/objects/procedural_object_static_batch.gd")

const MAX_ROCKS := ObjectWorld.MAX_OBJECTS_PER_REGION

var world_seed := 0
var world_id := ""
var region_key := Vector2i.ZERO
var registry: ContentDefinitionRegistry
var result: Dictionary = {}

func _init(seed: int, id: String, key: Vector2i, content_registry: ContentDefinitionRegistry) -> void:
	world_seed = seed
	world_id = id
	region_key = key
	registry = content_registry


func run() -> void:
	result = build_data(world_seed, world_id, region_key, registry)


static func build_data(
	seed: int, id: String, key: Vector2i, content_registry: ContentDefinitionRegistry
) -> Dictionary:
	var start := Time.get_ticks_usec()
	if content_registry == null or id.is_empty():
		return {"ok": false, "reason": "mod_registry_unavailable"}
	var generated: Dictionary = ObjectWorld.build_region_instances(
		seed, id, key, content_registry
	)
	if not bool(generated.get("ok", false)):
		return {"ok": false, "reason": "population_failed:%s" % generated.get("reason", "")}
	var instances: Array = generated.get("instances", [])
	if instances.size() > MAX_ROCKS:
		return {"ok": false, "reason": "object_budget_exceeded"}
	var items: Array[Dictionary] = []
	var generator_geometry_usec := 0
	for instance_value in instances:
		var instance: Dictionary = instance_value
		if String(instance.get("recipe_algorithm", "")) != RockMeshAdapter.ALGORITHM:
			return {"ok": false, "reason": "unsupported_mod_geometry"}
		var before := Time.get_ticks_usec()
		var cpu: Dictionary = RockMeshAdapter.build_cpu_data(
			instance.get("geometry", {}), instance.get("geometry_seeds", {})
		)
		generator_geometry_usec += Time.get_ticks_usec() - before
		if not cpu.get("ok", false):
			return {"ok": false, "reason": "rock_geometry_failed:%s" % cpu.get("reason", "")}
		items.append({
			"instance_id": String(instance["instance_id"]),
			"position": Vector3(instance["position_mm"]) / 1000.0,
			"scale_milli": instance.get(
				"default_scale_milli", Vector3i(1000, 1000, 1000)
			),
			"yaw_mdeg": int(instance.get("default_yaw_mdeg", 0)),
			"cpu_data": cpu,
		})
	var prepared: Dictionary = StaticBatch.prepare(items)
	if not prepared.get("ok", false):
		return {"ok": false, "reason": "regional_batch_failed:%s" % prepared.get("reason", "")}
	return {
		"ok": true,
		"region_key": key,
		"rock_count": instances.size(),
		"instance_ids": prepared.get("instance_ids", []).duplicate(),
		"positions": prepared.get("positions", PackedVector3Array()),
		"normals": prepared.get("normals", PackedVector3Array()),
		"triangle_count": int(prepared.get("triangle_count", 0)),
		"vertex_count": int(prepared.get("vertex_count", 0)),
		"worker_usec": Time.get_ticks_usec() - start,
		"geometry_usec": generator_geometry_usec,
		"source": "procedural_object_world_and_rock_shape_descriptor",
		"visual_only": true,
		"mutable_components_applied": false,
	}
