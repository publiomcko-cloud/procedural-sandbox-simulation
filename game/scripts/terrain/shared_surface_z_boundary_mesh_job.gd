class_name SharedSurfaceZBoundaryMeshJob
extends RefCounted

const Authority := preload("res://scripts/terrain/shared_surface_boundary_authority.gd")
const WorkCache := preload("res://scripts/terrain/shared_surface_work_cache.gd")

var world_seed: int
var low_z_region_key: Vector2i
var x_chunk: int
var brush_snapshot: Dictionary
var result: Dictionary = {}
var queued_usec: int
var diagnostics_enabled := true
var worker_started_usec := 0
var worker_finished_usec := 0
var worker_thread_id := 0


func _init(
	seed_value: int,
	low_z_region_value: Vector2i,
	x_chunk_value: int,
	brush_snapshot_value: Dictionary,
	queued_value: int = 0,
	diagnostics_enabled_value: bool = true
) -> void:
	world_seed = seed_value
	low_z_region_key = low_z_region_value
	x_chunk = x_chunk_value
	brush_snapshot = brush_snapshot_value
	queued_usec = queued_value
	diagnostics_enabled = diagnostics_enabled_value


func run() -> void:
	worker_started_usec = Time.get_ticks_usec()
	worker_thread_id = OS.get_thread_caller_id()
	if not bool(brush_snapshot.get("valid", true)):
		result = {
			"valid": false,
			"reason": String(brush_snapshot.get("storage_error", "invalid_brush_snapshot")),
			"ledger_revision": int(brush_snapshot.get("revision", -1)),
		}
	else:
		var key := "z:%d:%d:%d:%d:%d:%d:%d:%d:%s" % [
			world_seed,
			int(brush_snapshot.get("revision", -1)),
			int(brush_snapshot.get("cache_scope_id", -1)),
			int(brush_snapshot.get("ledger_operation_count", -1)),
			1 if diagnostics_enabled else 0,
			low_z_region_key.x,
			low_z_region_key.y,
			x_chunk,
			String(brush_snapshot.get("terrain_object_effect_snapshot_sha256", "")),
		]
		result = WorkCache.get_or_build(key, Callable(self, "_build_uncached"))
	worker_finished_usec = Time.get_ticks_usec()


func _build_uncached() -> Dictionary:
	return Authority.build_z_region_boundary_pair(
		world_seed, low_z_region_key, x_chunk, brush_snapshot, diagnostics_enabled
	)
