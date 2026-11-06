class_name ProceduralObjectRegionGenerationJob
extends RefCounted

## Worker-only deterministic procedural object generation.
## Registry content is immutable after stream initialization; scene/resource
## publication remains on the main thread. D.2 may hydrate/store derived,
## non-authoritative CPU materialization on the same worker.
const ObjectWorld := preload("res://scripts/objects/procedural_object_world.gd")
const RockMeshAdapter := preload("res://scripts/objects/procedural_rock_mesh_adapter.gd")
const MaterializationStore := preload("res://scripts/objects/procedural_object_materialization_store.gd")

var world_seed := 0
var world_id := ""
var region_key := Vector2i.ZERO
var registry: RefCounted
var content_signature := ""
var materialization_directory := ""
var result: Dictionary = {}
var worker_started_usec := 0
var worker_finished_usec := 0
var worker_thread_id := 0


func _init(
	seed_value: int,
	world_identifier: String,
	key: Vector2i,
	content_registry: RefCounted,
	content_signature_value: String = "",
	materialization_directory_value: String = ""
) -> void:
	world_seed = seed_value
	world_id = world_identifier
	region_key = key
	registry = content_registry
	content_signature = content_signature_value
	materialization_directory = materialization_directory_value


func run() -> void:
	worker_started_usec = Time.get_ticks_usec()
	worker_thread_id = OS.get_thread_caller_id()
	var materialization_hit := false
	var materialization_load_usec := 0
	var materialization_save_usec := 0
	var materialization_reason := "materialization_disabled"
	var generated: Dictionary = {}

	var store: RefCounted = null
	if not materialization_directory.is_empty() and not content_signature.is_empty():
		store = MaterializationStore.new(
			materialization_directory,
			world_id,
			world_seed,
			ObjectWorld.FIELD.GENERATOR_VERSION,
			content_signature
		)
		var loaded: Dictionary = store.load_region(region_key)
		materialization_load_usec = int(loaded.get("load_usec", 0))
		materialization_hit = bool(loaded.get("hit", false))
		materialization_reason = String(loaded.get("reason", "materialization_miss"))
		if materialization_hit:
			generated = (loaded.get("generated", {}) as Dictionary).duplicate(true)

	if not materialization_hit:
		generated = ObjectWorld.build_region_instances(world_seed, world_id, region_key, registry)
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
				if store != null:
					var saved: Dictionary = store.save_region(region_key, generated)
					materialization_save_usec = int(saved.get("save_usec", 0))
					if saved.get("ok", false):
						materialization_reason = "materialization_miss_saved"
					else:
						materialization_reason = String(
							saved.get("reason", "materialization_save_failed")
						)

	result = generated
	result["materialization_hit"] = materialization_hit
	result["materialization_load_usec"] = materialization_load_usec
	result["materialization_save_usec"] = materialization_save_usec
	result["materialization_reason"] = materialization_reason
	worker_finished_usec = Time.get_ticks_usec()
	result["worker_usec"] = worker_finished_usec - worker_started_usec
	result["worker_thread_id"] = worker_thread_id
