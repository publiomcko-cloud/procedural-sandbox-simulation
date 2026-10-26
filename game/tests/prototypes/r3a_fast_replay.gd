extends RefCounted

## A test-only exact-preserving replay candidate. It skips square roots only
## when a conservative distance bound proves a min/max operation is a no-op.
const Field := preload("res://scripts/terrain/sdf_world.gd")
const Brush := preload("res://scripts/terrain/sdf_brush_edit_state.gd")
const SAFE_DISTANCE_MARGIN := 0.001

var _seed: int
var _centers: PackedVector3Array
var _radii: PackedFloat64Array
var _modes: PackedByteArray
var operation_tests := 0
var distance_sqrts := 0
var skipped_sqrts := 0


func _init(seed_value: int, snapshot: Dictionary) -> void:
	_seed = seed_value
	_centers = snapshot.get("centers", PackedVector3Array())
	_radii = snapshot.get("radii", PackedFloat64Array())
	_modes = snapshot.get("modes", PackedByteArray())


func sample_density(world_point: Vector3) -> float:
	var density: float = Field.sample_density(_seed, Vector2i.ZERO, world_point)
	for index in range(_centers.size()):
		operation_tests += 1
		var center: Vector3 = _centers[index]
		var radius: float = _radii[index]
		var threshold := radius + density if _modes[index] == Brush.Mode.CARVE else radius - density
		if threshold <= 0.0:
			skipped_sqrts += 1
			continue
		var dx := world_point.x - center.x
		var dy := world_point.y - center.y
		var dz := world_point.z - center.z
		var distance_squared := dx * dx + dy * dy + dz * dz
		var margin := SAFE_DISTANCE_MARGIN * maxf(1.0, absf(threshold))
		if distance_squared > (threshold + margin) * (threshold + margin):
			skipped_sqrts += 1
			continue
		distance_sqrts += 1
		# Match the canonical Vector3 distance operation at every possibly active term.
		var signed_distance: float = world_point.distance_to(center) - radius
		if _modes[index] == Brush.Mode.CARVE:
			density = minf(density, signed_distance)
		else:
			density = maxf(density, -signed_distance)
	return density
