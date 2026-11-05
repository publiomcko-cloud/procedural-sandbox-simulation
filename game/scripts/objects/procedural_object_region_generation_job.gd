class_name ProceduralObjectRegionGenerationJob
extends RefCounted

## Worker-only deterministic procedural object generation.
## Registry content is immutable after stream initialization; scene/resource
## publication remains on the main thread.

const ObjectWorld := preload("res://scripts/objects/procedural_object_world.gd")

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
	result = ObjectWorld.build_region_instances(world_seed, world_id, region_key, registry)
	worker_finished_usec = Time.get_ticks_usec()
	result["worker_usec"] = worker_finished_usec - worker_started_usec
	result["worker_thread_id"] = worker_thread_id
