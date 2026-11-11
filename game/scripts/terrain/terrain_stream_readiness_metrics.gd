extends RefCounted
class_name TerrainStreamReadinessMetrics

## E0 instrumentation. "Published" means present in the terrain region scene
## index, not pixels on the GPU, collision readiness, or hydrology coverage.
static func sample_window(focus: Vector2i, published: Dictionary, radius: int = 1) -> Dictionary:
	var requested := 0
	var unpublished := 0
	var radius_safe := clampi(radius, 0, 2)
	for z in range(focus.y - radius_safe, focus.y + radius_safe + 1):
		for x in range(focus.x - radius_safe, focus.x + radius_safe + 1):
			requested += 1
			if not published.has("%d,%d" % [x, z]):
				unpublished += 1
	return {
		"requested": requested,
		"published": requested - unpublished,
		"unpublished": unpublished,
		"focus_unpublished": not published.has("%d,%d" % [focus.x, focus.y]),
	}


## Milestone times are monotonic process timestamps, not simulated tick times.
## A zero timestamp reports unavailable evidence (-1), rather than fabricating
## a 0ms first-mesh or first-dispatch latency.
static func load_latency(queued: int, first_dispatch: int, first_mesh: int, visible: int) -> Dictionary:
	return {
		"queue_to_first_dispatch_usec": first_dispatch - queued if queued > 0 and first_dispatch >= queued else -1,
		"queue_to_first_mesh_usec": first_mesh - queued if queued > 0 and first_mesh >= queued else -1,
		"queue_to_visual_usec": visible - queued if queued > 0 and visible >= queued else -1,
	}
