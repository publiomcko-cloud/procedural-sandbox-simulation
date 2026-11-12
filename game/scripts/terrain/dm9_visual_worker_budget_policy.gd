extends RefCounted
class_name DM9VisualWorkerBudgetPolicy

## DM9 adaptive visual CPU throughput: spend spare cores only after canonical
## terrain in the 3x3 gameplay core is ready. Never occupy worker capacity
## when seed/edit/effects/mesh jobs or missing player-adjacent regions demand it.
const MAX_WORKERS := 8
const MOVING_VISUAL_WORKERS := 2
const SPIKE_FRAME_MS := 20.0
const SPIKE_PROCESS_MS := 14.0

static func effective_limit(
	configured_max: int,
	core_fully_ready: bool,
	canonical_loading: int,
	canonical_mesh_jobs: int,
	speed_mps: float,
	frame_ms: float,
	process_ms: float
) -> int:
	var maximum := clampi(configured_max, 1, MAX_WORKERS)
	if maximum == 1:
		return 1
	if not core_fully_ready or canonical_loading > 0 or canonical_mesh_jobs > 0:
		return 1
	if not is_finite(frame_ms) or not is_finite(process_ms) \
	or frame_ms >= SPIKE_FRAME_MS or process_ms >= SPIKE_PROCESS_MS:
		return 1
	if not is_finite(speed_mps) or speed_mps > 0.01:
		return mini(MOVING_VISUAL_WORKERS, maximum)
	return maximum
