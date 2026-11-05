class_name ProceduralObjectRegionGenerationJob
extends RefCounted

## Worker-only deterministic procedural object generation.
## Registry content is immutable after stream initialization; scene/resource
## publication remains on the main thread.

const ObjectWorld := preload("res://scripts/objects/procedural_object_world.gd")
const RockMeshAdapter := preload("res://scripts/objects/procedural_rock_mesh_adapter.gd")

var world_seed := 0
var world_id := ""
var region_key := Vector2i.ZERO
var registry: RefCounted
var result: Dictionary = {}
var worker_started_usec := 0
var worker_finished_usec := 0
var worker_thread_id := 0


func _init(seed_value: int, world_identifier: String, key: Vector2i, content_registry: RefCounted) -> void:
	world_seed = seed_value
	world_id = world_identifier
	region_key = key
	registry = content_registry


func run() -> void:
	worker_started_usec = Time.get_ticks_usec()
	worker_thread_id = OS.get_thread_caller_id()
	var generated: Dictionary = ObjectWorld.build_region_instances(world_seed, world_id, region_key, registry)
	if generated.get("ok", false):
		var geometry_started_usec := Time.get_ticks_usec()
		var geometry_cpu_by_instance: Dictionary = {}
		for instance_value in generated.get("instances", []):
			var instance: Dictionary = instance_value
			var cpu_data: Dictionary = RockMeshAdapter.build_cpu_data(
				instance.get("geometry", {}), instance.get("geometry_seeds", {})
			)
			if not cpu_data.get("ok", false):
				generated = {
					"ok": false,
					"reason": "object_geometry_cpu_build_failed:%s" % cpu_data.get("reason", "unknown"),
					"instance_id": String(instance.get("instance_id", "")),
				}
				break
			geometry_cpu_by_instance[String(instance.get("instance_id", ""))] = cpu_data
		if generated.get("ok", false):
			generated["geometry_cpu_by_instance"] = geometry_cpu_by_instance
			generated["geometry_cpu_usec"] = Time.get_ticks_usec() - geometry_started_usec
	result = generated
	worker_finished_usec = Time.get_ticks_usec()
	result["worker_usec"] = worker_finished_usec - worker_started_usec
	result["worker_thread_id"] = worker_thread_id
