class_name ProceduralObjectVisualGeometryJob
extends RefCounted

## Worker-only CPU geometry preparation for mutable/placed render variants.
## Rendering resources remain main-thread only.
const RockMeshAdapter := preload("res://scripts/objects/procedural_rock_mesh_adapter.gd")

var variants: Array[Dictionary] = []
var result: Dictionary = {}
var worker_started_usec := 0
var worker_finished_usec := 0
var worker_thread_id := 0


func _init(variant_values: Array[Dictionary]) -> void:
	for value in variant_values:
		variants.append(value.duplicate(true))


func run() -> void:
	worker_started_usec = Time.get_ticks_usec()
	worker_thread_id = OS.get_thread_caller_id()
	var cpu_by_cache_key: Dictionary = {}
	for variant in variants:
		var cache_key := String(variant.get("cache_key", ""))
		if cache_key.is_empty() or cpu_by_cache_key.has(cache_key):
			result = {
				"ok": false,
				"reason": "visual_geometry_variant_identity_invalid",
			}
			_finish()
			return
		var cpu: Dictionary = RockMeshAdapter.build_cpu_data(
			variant.get("geometry", {}),
			variant.get("geometry_seeds", {})
		)
		if not cpu.get("ok", false):
			result = {
				"ok": false,
				"reason": "visual_geometry_cpu_build_failed:%s"
					% cpu.get("reason", "unknown"),
				"cache_key": cache_key,
			}
			_finish()
			return
		cpu_by_cache_key[cache_key] = cpu
	result = {
		"ok": true,
		"reason": "ok",
		"cpu_by_cache_key": cpu_by_cache_key,
		"variant_count": variants.size(),
	}
	_finish()


func _finish() -> void:
	worker_finished_usec = Time.get_ticks_usec()
	result["worker_usec"] = worker_finished_usec - worker_started_usec
	result["worker_thread_id"] = worker_thread_id
