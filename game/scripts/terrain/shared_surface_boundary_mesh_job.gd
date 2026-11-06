class_name SharedSurfaceBoundaryMeshJob
extends RefCounted

## Worker-compatible immutable job for one X-adjacent region-edge chunk pair.

const Authority := preload("res://scripts/terrain/shared_surface_boundary_authority.gd")
const WorkCache := preload("res://scripts/terrain/shared_surface_work_cache.gd")

var world_seed: int
var left_region_key: Vector2i
var z_chunk: int
var brush_snapshot: Dictionary
var result: Dictionary = {}
var queued_usec: int
var diagnostics_enabled := true
var worker_started_usec := 0
var worker_finished_usec := 0
var worker_thread_id := 0


func _init(
	seed_value: int,
	left_region_value: Vector2i,
	z_chunk_value: int,
	brush_snapshot_value: Dictionary,
	queued_value: int = 0,
	diagnostics_enabled_value: bool = true
) -> void:
	world_seed = seed_value
	left_region_key = left_region_value
	z_chunk = z_chunk_value
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
		var key := "x:%d:%d:%d:%d:%d:%d:%d:%d" % [
			world_seed,
			int(brush_snapshot.get("revision", -1)),
			int(brush_snapshot.get("cache_scope_id", -1)),
			int(brush_snapshot.get("ledger_operation_count", -1)),
			1 if diagnostics_enabled else 0,
			left_region_key.x,
			left_region_key.y,
			z_chunk,
		]
		key += ":%s" % String(brush_snapshot.get("terrain_object_effect_snapshot_sha256", "none"))
		result = WorkCache.get_or_build(key, Callable(self, "_build_uncached"))
	worker_finished_usec = Time.get_ticks_usec()


func _build_uncached() -> Dictionary:
	return Authority.build_x_region_boundary_pair(
		world_seed, left_region_key, z_chunk, brush_snapshot, diagnostics_enabled
	)
