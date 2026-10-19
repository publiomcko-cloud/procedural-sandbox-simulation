class_name TerrainBrushPicker
extends RefCounted

## Deterministic ray/field intersection with Lipschitz-safe empty-space jumps,
## then the legacy fixed grid for the first crossing and bisection bracket.
const SAMPLE_STEP := 0.1
# The surface derivative is bounded by sqrt(1 + 0.3058^2 + 0.2478^2) < 1.076;
# the cave field is below 1.02. Min/max CSG with unit sphere SDFs preserves the
# maximum bound, so 1.1 safely bounds SdfWorld v1 including its cut plane.
const SDF_LIPSCHITZ_BOUND := 1.1
# Keep 20% of the certified lower bound on distance to the zero set unused.
const ADAPTIVE_STEP_SAFETY := 0.8
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
	return _pick_surface(ray_origin, ray_direction, sample_field, false)


## V1-only fast path; the caller must supply the SdfWorld v1 field with ordered
## brush CSG. Arbitrary sample callables keep the legacy fixed-step contract.
static func pick_sdf_v1_surface(
	ray_origin: Vector3,
	ray_direction: Vector3,
	sample_field: Callable
) -> Dictionary:
	return _pick_surface(ray_origin, ray_direction, sample_field, true)


static func _pick_surface(
	ray_origin: Vector3,
	ray_direction: Vector3,
	sample_field: Callable,
	allow_sdf_v1_adaptive: bool
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

	var distance := 0.0
	var use_fixed_grid := not allow_sdf_v1_adaptive
	var fixed_step_index := 1
	for _step_index in range(MAX_STEPS):
		if distance >= MAX_DISTANCE:
			break
		if not use_fixed_grid:
			var safe_step := absf(previous_density) * ADAPTIVE_STEP_SAFETY / SDF_LIPSCHITZ_BOUND
			if previous_density < 0.0 and safe_step > SAMPLE_STEP:
				var prior_safe_distance := distance
				distance = minf(distance + safe_step, MAX_DISTANCE)
				var adaptive_point := ray_origin + direction * distance
				var adaptive_density: float = sample_field.call(adaptive_point)
				if not is_finite(adaptive_density):
					return {"hit": false}
				if adaptive_density >= 0.0:
					# If a caller supplies a field outside the v1 gradient bound, fall
					# back to legacy samples instead of turning an overshoot into a miss.
					use_fixed_grid = true
					fixed_step_index = int(floor(prior_safe_distance / SAMPLE_STEP)) + 1
					previous_distance = float(fixed_step_index - 1) * SAMPLE_STEP
					distance = previous_distance
					continue
				previous_density = adaptive_density
				continue
			use_fixed_grid = true
			fixed_step_index = int(floor(distance / SAMPLE_STEP)) + 1
			# Safe adaptive steps cannot have crossed the surface. Resume the exact
			# legacy grid so the first crossing and bisection bracket stay unchanged.
			previous_distance = float(fixed_step_index - 1) * SAMPLE_STEP
			distance = float(fixed_step_index) * SAMPLE_STEP
			if distance > MAX_DISTANCE:
				break
		else:
			distance = float(fixed_step_index) * SAMPLE_STEP
			if distance > MAX_DISTANCE:
				break
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
		previous_density = density
		fixed_step_index += 1
	return {"hit": false}
