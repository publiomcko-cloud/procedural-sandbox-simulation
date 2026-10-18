extends RefCounted

## Worker-only immutable input and CPU result. This object never owns a scene or Mesh resource.
const Mesher := preload("res://scripts/terrain/marching_tetrahedra.gd")

var seed: int
var region_key: Vector2i
var coordinate: Vector2i
var cave_section_enabled: bool
var brush_snapshot: Variant
var result: Dictionary = {}
var queued_usec: int
var worker_started_usec := 0
var worker_finished_usec := 0
var worker_thread_id := 0


func _init(
	seed_value: int,
	region_value: Vector2i,
	coordinate_value: Vector2i,
	cave_value: bool,
	brush_snapshot_value: Variant,
	queued_value: int
) -> void:
	seed = seed_value
	region_key = region_value
	coordinate = coordinate_value
	cave_section_enabled = cave_value
	brush_snapshot = brush_snapshot_value
	queued_usec = queued_value


func run() -> void:
	worker_started_usec = Time.get_ticks_usec()
	worker_thread_id = OS.get_thread_caller_id()
	result = Mesher.build_chunk_cpu_data(
		seed, region_key, coordinate, cave_section_enabled, brush_snapshot
	)
	worker_finished_usec = Time.get_ticks_usec()
