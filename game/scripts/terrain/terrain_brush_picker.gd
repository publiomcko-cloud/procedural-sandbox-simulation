class_name TerrainBrushPicker
extends RefCounted

## Deterministic fixed-step ray/field intersection with a hard per-click work bound.
const SAMPLE_STEP := 0.1
# The orbit camera can be up to 96 units from the target; leave room to reach
# the surface at maximum zoom while retaining a fixed per-click work bound.
const MAX_STEPS := 1200
const BISECTION_STEPS := 12
const MAX_DISTANCE := MAX_STEPS * SAMPLE_STEP



static func pick_surface(
	ray_origin: Vector3,
	ray_direction: Vector3,
	sample_field: Callable
) -> Dictionary:
	if not ray_origin.is_finite() or not ray_direction.is_finite() or ray_direction.length_squared() <= 0.000001:
		return {"hit": false}
	if not sample_field.is_valid():
		return {"hit": false}

	var direction := ray_direction.normalized()
	var previous_distance := 0.0
	var previous_density: float = sample_field.call(ray_origin)
	if not is_finite(previous_density) or previous_density >= 0.0:
		return {"hit": false}

	for step_index in range(1, MAX_STEPS + 1):
		var distance := float(step_index) * SAMPLE_STEP
		var point := ray_origin + direction * distance
		var density: float = sample_field.call(point)
		if not is_finite(density):
			return {"hit": false}
		if density >= 0.0:
			var empty_distance := previous_distance
			var solid_distance := distance
			for _iteration in range(BISECTION_STEPS):
				var middle_distance := (empty_distance + solid_distance) * 0.5
				var middle_point := ray_origin + direction * middle_distance
				var middle_density: float = sample_field.call(middle_point)
				if not is_finite(middle_density):
					return {"hit": false}
				if middle_density >= 0.0:
					solid_distance = middle_distance
				else:
					empty_distance = middle_distance
			return {"hit": true, "position": ray_origin + direction * solid_distance}
		previous_distance = distance
	return {"hit": false}
