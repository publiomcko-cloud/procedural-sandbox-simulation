class_name SdfWorld
extends RefCounted

## Versioned, stateless terrain samples. Scene nodes and rendering are not inputs.
const GENERATOR_VERSION := 1
const REGION_SIZE_X := 16.0
const REGION_SIZE_Z := 12.0
const MIN_Y := -1.0


static func sample_density(
	world_seed: int,
	region_key: Vector2i,
	local_position: Vector3,
	show_cave_section: bool = false
) -> float:
	var world_x := float(region_key.x) * REGION_SIZE_X + local_position.x
	var world_z := float(region_key.y) * REGION_SIZE_Z + local_position.z
	var phase := float(posmod(world_seed, 100003)) * 0.000173
	var surface_y := 3.8 \
		+ 1.25 * sin(world_x * 0.22 + phase) \
		+ 0.70 * cos(world_z * 0.31 - phase * 0.7) \
		+ 0.28 * sin((world_x + world_z) * 0.11 + phase * 0.3)
	var bounded_surface: float = minf(surface_y - local_position.y, local_position.y - MIN_Y)

	# A continuous tunnel runs along X, below the lowest terrain surface.
	var cave_center_y := 1.15 + 0.24 * sin(world_x * 0.25 + phase)
	var cave_center_z := 6.0 + 1.05 * sin(world_x * 0.17 + phase * 0.6)
	var cave_distance := Vector2(
		local_position.y - cave_center_y,
		world_z - cave_center_z
	).length() - 0.92
	var density: float = minf(bounded_surface, cave_distance)
	if show_cave_section:
		# Positive density means solid; this removes the half-space above the cut plane.
		density = minf(density, 6.0 - local_position.z)
	return density


static func cave_center(seed: int, region_key: Vector2i, local_x: float) -> Vector2:
	var world_x := float(region_key.x) * REGION_SIZE_X + local_x
	var phase := float(posmod(seed, 100003)) * 0.000173
	var local_z := 6.0 + 1.05 * sin(world_x * 0.17 + phase * 0.6) \
		- float(region_key.y) * REGION_SIZE_Z
	var center_y := 1.15 + 0.24 * sin(world_x * 0.25 + phase)
	return Vector2(local_z, center_y)
