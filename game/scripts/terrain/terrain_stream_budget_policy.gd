extends RefCounted
class_name TerrainStreamBudgetPolicy

## Optional, presentation/streaming-only adaptive submit budget.
## This never changes worker concurrency, terrain authority, edits, uploads or
## checkpoints. The default profile remains bit-for-bit one dispatch/frame.
const BASE_DISPATCHES := 1
const ADAPTIVE_DISPATCHES := 2
const STABLE_FRAMES_REQUIRED := 12
const SPIKE_COOLDOWN_FRAMES := 45
const SOFT_FRAME_LIMIT_MS := 17.2
const SOFT_PROCESS_LIMIT_MS := 10.5
const SPIKE_FRAME_MS := 20.0
const SPIKE_PROCESS_MS := 14.0


## Resolve actual runtime mode once, from env with an explicit CLI override.
## Keeping this pure allows a regression test for the profile the GUI uses.
static func resolve_profile(env_value: String, cli_args: PackedStringArray) -> String:
	var selected := env_value.strip_edges().to_lower()
	for arg in cli_args:
		if arg.begins_with("--stream-profile="):
			selected = arg.trim_prefix("--stream-profile=").strip_edges().to_lower()
	if selected not in ["baseline", "adaptive", "adaptive-skip", "adaptive-skip-lookahead", "adaptive-skip-coarse", "adaptive-skip-coarse-demand"]:
		return "baseline"
	return selected


static func next(previous: Dictionary, frame_ms: float, previous_process_ms: float, adaptive: bool) -> Dictionary:
	var state := {
		"dispatch_limit": BASE_DISPATCHES,
		"stable_frames": 0,
		"cooldown_frames": 0,
		"reason": "baseline",
	}
	if not adaptive:
		return state
	var stable := maxi(0, int(previous.get("stable_frames", 0)))
	var cooldown := maxi(0, int(previous.get("cooldown_frames", 0)))
	if frame_ms >= SPIKE_FRAME_MS or previous_process_ms >= SPIKE_PROCESS_MS:
		state["cooldown_frames"] = SPIKE_COOLDOWN_FRAMES
		state["reason"] = "frame_spike"
		return state
	if cooldown > 0:
		state["cooldown_frames"] = cooldown - 1
		state["reason"] = "cooldown"
		return state
	if frame_ms <= SOFT_FRAME_LIMIT_MS and previous_process_ms <= SOFT_PROCESS_LIMIT_MS:
		stable = mini(STABLE_FRAMES_REQUIRED, stable + 1)
	else:
		stable = maxi(0, stable - 3)
	state["stable_frames"] = stable
	if stable >= STABLE_FRAMES_REQUIRED:
		state["dispatch_limit"] = ADAPTIVE_DISPATCHES
		state["reason"] = "headroom"
	else:
		state["reason"] = "sampling_headroom"
	return state
