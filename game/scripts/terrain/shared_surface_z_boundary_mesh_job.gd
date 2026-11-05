class_name SharedSurfaceZBoundaryMeshJob
extends RefCounted

const Authority := preload("res://scripts/terrain/shared_surface_boundary_authority.gd")

var world_seed: int
var low_z_region_key: Vector2i
var x_chunk: int
var brush_snapshot: Dictionary
var result: Dictionary = {}
var queued_usec: int
var worker_started_usec := 0
var worker_finished_usec := 0
var worker_thread_id := 0


func _init(
	seed_value: int,
	low_z_region_value: Vector2i,
	x_chunk_value: int,
	brush_snapshot_value: Dictionary,
	queued_value: int = 0
) -> void:
	world_seed = seed_value
	low_z_region_key = low_z_region_value
	x_chunk = x_chunk_value
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
		result = Authority.build_z_region_boundary_pair(
			world_seed, low_z_region_key, x_chunk, brush_snapshot
		)
	worker_finished_usec = Time.get_ticks_usec()
