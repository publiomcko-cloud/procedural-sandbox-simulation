class_name DM10MotionAwareVisualPolicy
extends RefCounted

## CPU-only derived B4 visual QoS. Never changes canonical jobs, revisions,
## saved terrain, retention, terrain resolution, or authoritative 3x3 scope.
## Rejects speculative visual submissions while the player-adjacent core is
## urgent; draining in-flight tasks are never cancelled or reused as authority.
const MAX_WORKERS := 4
const SLOW_MPS := 3.0
const FAST_MPS := 7.0
const MAX_FRAME_MS := 35.0
const MAX_PROCESS_MS := 22.0

static func plan(
	max_workers: int,
	mode: String,
	speed_mps: float,
	core_ready: bool,
	canonical_loading: int,
	canonical_mesh_jobs: int,
	frame_ms: float,
	process_ms: float,
	since_last_submit_usec: int
) -> Dictionary:
	var maximum := clampi(max_workers, 1, MAX_WORKERS)
	var result := {
		"state": "idle",
		"reason": "stationary",
		"limit": 1,
		"may_submit": false,
		"interval_usec": 0,
		"canonical_pressure": not core_ready or canonical_loading > 0 or canonical_mesh_jobs > 0,
	}
	if not is_finite(speed_mps) or speed_mps < 0.0 \
		or not is_finite(frame_ms) or not is_finite(process_ms):
		result["reason"] = "invalid_telemetry"
		return result
	if frame_ms >= MAX_FRAME_MS or process_ms >= MAX_PROCESS_MS:
		result["reason"] = "frame_pressure"
		return result
	var busy := bool(result["canonical_pressure"])
	var interval := 0
	if speed_mps < 0.05:
		result["state"] = "idle"
		if busy:
			result["reason"] = "canonical_first_idle"
			return result
		result["limit"] = maximum
		result["reason"] = "idle_full_throughput"
	elif speed_mps <= SLOW_MPS:
		result["state"] = "slow"
		if not core_ready:
			result["reason"] = "canonical_first_slow"
			return result
		if busy:
			result["limit"] = 1
			interval = 650_000
			result["reason"] = "slow_canonical_pending"
		else:
			result["limit"] = maximum
			interval = 160_000
			result["reason"] = "slow_high_throughput"
	else:
		result["state"] = "directional"
		result["limit"] = 1
		if not core_ready:
			if mode == "guarded":
				result["reason"] = "guarded_missing_core"
				return result
			interval = 1_000_000
			result["reason"] = "moving_missing_core"
		elif busy:
			interval = 700_000
			result["reason"] = "moving_canonical_busy"
		else:
			interval = 320_000
			result["reason"] = "moving_core_ready"
		if speed_mps >= FAST_MPS and (frame_ms >= 22.0 or process_ms >= 14.0):
			interval = maxi(interval, 1_250_000)
			result["reason"] += "_frame_throttle"
	result["interval_usec"] = interval
	result["may_submit"] = since_last_submit_usec >= interval
	if not bool(result["may_submit"]):
		result["reason"] += "_cooldown"
	return result


## Strong forward bias during directional motion, without changing the set
## or LOD. Near-forward region first, lateral second, behind last. Original
## Euclidean nearest-first order remains in place for stationary/slow motion.
static func prioritize_direction(
	keys: Array[Vector2i], player_world: Vector3,
	velocity: Vector3
) -> Array[Vector2i]:
	var prioritized: Array[Vector2i] = keys.duplicate()
	var motion := Vector2(velocity.x, velocity.z)
	if not motion.is_finite() or motion.length_squared() <= 0.001:
		return prioritized
	motion = motion.normalized()
	var score: Dictionary = {}
	for key in prioritized:
		var center := Vector2((float(key.x) + 0.5) * 16.0,
			(float(key.y) + 0.5) * 12.0)
		var displacement := center - Vector2(player_world.x, player_world.z)
		var align := 0.0
		if displacement.length_squared() > 0.00001:
			align = displacement.normalized().dot(motion)
		var tier := 0 if align >= 0.35 else (1 if align >= -0.2 else 2)
		# Preserve radial priority within each directional tier.
		score[key] = int(tier) * 100_000_000 + roundi(displacement.length_squared() * 1000.0)
	prioritized.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var sa: int = score[a]
		var sb: int = score[b]
		return sa < sb if sa != sb else (a.y < b.y if a.y != b.y else a.x < b.x)
	)
	return prioritized
