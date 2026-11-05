class_name SharedSurfaceCornerMeshJob
extends RefCounted

const Authority := preload("res://scripts/terrain/shared_surface_boundary_authority.gd")
const WorkCache := preload("res://scripts/terrain/shared_surface_work_cache.gd")

var world_seed: int
var min_region_key: Vector2i
var brush_snapshot: Dictionary
var result: Dictionary = {}
var queued_usec: int
var worker_started_usec := 0
var worker_finished_usec := 0
var worker_thread_id := 0


func _init(
	seed_value: int,
	min_region_value: Vector2i,
	brush_snapshot_value: Dictionary,
	queued_value: int = 0
) -> void:
	world_seed = seed_value
	min_region_key = min_region_value
	brush_snapshot = brush_snapshot_value
	queued_usec = queued_value


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
		var key := "corner:%d:%d:%d:%d:%d:%d" % [
			world_seed,
			int(brush_snapshot.get("revision", -1)),
			int(brush_snapshot.get("cache_scope_id", -1)),
			int(brush_snapshot.get("ledger_operation_count", -1)),
			min_region_key.x,
			min_region_key.y,
		]
		result = WorkCache.get_or_build(key, Callable(self, "_build_uncached"))
	worker_finished_usec = Time.get_ticks_usec()


func _build_uncached() -> Dictionary:
	return Authority.build_xz_corner_quad(
		world_seed, min_region_key, brush_snapshot
	)
