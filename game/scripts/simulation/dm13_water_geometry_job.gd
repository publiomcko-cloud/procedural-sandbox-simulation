extends RefCounted

## DM13: CPU-only immutable derived geometry. Never touches a SceneTree,
## Mesh, RenderingServer or mutable authoritative hydrology state.
const WaterVisual := preload("res://scripts/simulation/environment_visual_presentation.gd")

var region_key: Vector2i
var environment: Dictionary
var surface_cache: Dictionary
var shoreline: Dictionary
var water_mode: String
var hydrology_enabled: bool
var neighbor_anchors: Dictionary
var queued_usec := 0
var started_usec := 0
var finished_usec := 0
var worker_thread_id := 0
var result: Dictionary = {}


func _init(
	key: Vector2i,
	environment_snapshot: Dictionary,
	surface_snapshot: Dictionary,
	shoreline_snapshot: Dictionary,
	mode: String,
	hydrology: bool,
	anchors: Dictionary
) -> void:
	region_key = key
	# All values are duplicated while still on the main thread, before
	# submission. Packed array values, sparse shore samples, and ocean edge
	# masks cannot change beneath this worker.
	environment = environment_snapshot.duplicate(true)
	surface_cache = surface_snapshot.duplicate(true)
	shoreline = shoreline_snapshot.duplicate(true)
	water_mode = mode
	hydrology_enabled = hydrology
	neighbor_anchors = anchors.duplicate(true)
	queued_usec = Time.get_ticks_usec()


func run() -> void:
	started_usec = Time.get_ticks_usec()
	worker_thread_id = OS.get_thread_caller_id()
	result = WaterVisual.derive_shoreline_geometry(
		region_key, environment, surface_cache, shoreline,
		water_mode, hydrology_enabled, neighbor_anchors
	)
	finished_usec = Time.get_ticks_usec()
