class_name SdfBrushEditState
extends RefCounted

## Bounded transient sphere edits, stored as ordered data separate from scene nodes.
const FIELD := preload("res://scripts/terrain/sdf_world.gd")
const MAX_EDITS := 32
const MIN_RADIUS := 0.45
const MAX_RADIUS := 2.0

enum Mode { CARVE, FILL }

var _operations: Array[Dictionary] = []
var revision := 0
var _next_sequence := 0


func add_sphere(mode: int, center: Vector3, radius: float) -> bool:
	if _operations.size() >= MAX_EDITS:
		return false
	if mode != Mode.CARVE and mode != Mode.FILL:
		return false
	if not center.is_finite() or not is_finite(radius):
		return false
	if radius < MIN_RADIUS or radius > MAX_RADIUS:
		return false
	_operations.append({"sequence": _next_sequence, "mode": mode, "center": center, "radius": radius})
	_next_sequence += 1
	revision += 1
	return true


func clear() -> void:
	if _operations.is_empty():
		return
	_operations.clear()
	revision += 1


func get_edit_count() -> int:
	return _operations.size()


func get_operations_snapshot() -> Array[Dictionary]:
	var snapshot: Array[Dictionary] = []
	for operation in _operations:
		snapshot.append(operation.duplicate())
	return snapshot


func sample_density(
	world_seed: int,
	region_key: Vector2i,
	local_position: Vector3,
	show_cave_section: bool = false
) -> float:
	var density: float = FIELD.sample_density(world_seed, region_key, local_position)
	for operation in _operations:
		var center: Vector3 = operation["center"]
		var radius: float = operation["radius"]
		var distance_to_surface := local_position.distance_to(center) - radius
		if operation["mode"] == Mode.CARVE:
			# density >= 0 is solid; min removes a spherical volume.
			density = minf(density, distance_to_surface)
		else:
			# max adds the sphere interior to the solid field.
			density = maxf(density, -distance_to_surface)
	if show_cave_section:
		# The section affects only this visualization sample, after canonical edits.
		density = minf(density, 6.0 - local_position.z)
	return density
