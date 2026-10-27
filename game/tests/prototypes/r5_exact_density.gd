extends RefCounted

## R5-E experimental exact evaluator. This does not replace the ledger or the
## production sampler. It keeps global command order and skips only an operator
## when one coordinate alone proves its min/max is a no-op. Ambiguous cases use
## the canonical Vector3.distance_to path.
const Field := preload("res://scripts/terrain/sdf_world.gd")
const Spatial := preload("res://scripts/terrain/terrain_spatial_ownership.gd")
const Brush := preload("res://scripts/terrain/sdf_brush_edit_state.gd")

# Conservative guard for float32 Vector3 distance arithmetic. It only reduces
# the number of fast-path skips near the boundary; it cannot alter a density.
const DISTANCE_GUARD_RELATIVE := 0.001

var world_seed := 0
var region := Vector2i.ZERO
var snapshot: Dictionary = {}
var axis_dominance_skips := 0
var exact_distance_evaluations := 0
var query_count := 0


func configure(seed: int, region_key: Vector2i, operation_snapshot: Dictionary) -> bool:
	axis_dominance_skips = 0
	exact_distance_evaluations = 0
	query_count = 0
	if not bool(operation_snapshot.get("valid", true)):
		return false
	var centers_value: Variant = operation_snapshot.get("centers", null)
	var radii_value: Variant = operation_snapshot.get("radii", null)
	var modes_value: Variant = operation_snapshot.get("modes", null)
	if typeof(centers_value) != TYPE_PACKED_VECTOR3_ARRAY \
		or typeof(radii_value) != TYPE_PACKED_FLOAT64_ARRAY \
		or typeof(modes_value) != TYPE_PACKED_BYTE_ARRAY:
		return false
	var centers: PackedVector3Array = centers_value
	var radii: PackedFloat64Array = radii_value
	var modes: PackedByteArray = modes_value
	if centers.size() != radii.size() or centers.size() != modes.size():
		return false
	for index in range(centers.size()):
		if not centers[index].is_finite() or not is_finite(radii[index]) \
			or (modes[index] != Brush.Mode.CARVE and modes[index] != Brush.Mode.FILL):
			return false
	world_seed = seed
	region = region_key
	snapshot = operation_snapshot
	return true


func sample_world(world_position: Vector3, show_cave_section: bool = false) -> float:
	if not world_position.is_finite() or snapshot.is_empty():
		return NAN
	query_count += 1
	var mapped: Dictionary = Spatial.world_to_region_local(world_position)
	if not bool(mapped.get("valid", false)):
		return NAN
	var density: float = Field.sample_density(world_seed, mapped["region_key"], mapped["local_position"])
	var centers: PackedVector3Array = snapshot["centers"]
	var radii: PackedFloat64Array = snapshot["radii"]
	var modes: PackedByteArray = snapshot["modes"]
	for index in range(centers.size()):
		var center: Vector3 = centers[index]
		var delta := world_position - center
		var radius := float(radii[index])
		var no_op_distance := density + radius if modes[index] == Brush.Mode.CARVE else radius - density
		if no_op_distance <= 0.0 or _axis_proves_noop(delta, no_op_distance):
			axis_dominance_skips += 1
			continue
		exact_distance_evaluations += 1
		var distance_to_surface := world_position.distance_to(center) - radius
		if modes[index] == Brush.Mode.CARVE:
			density = minf(density, distance_to_surface)
		else:
			density = maxf(density, -distance_to_surface)
	if show_cave_section:
		density = minf(density, 6.0 - world_position.z)
	return density


func statistics() -> Dictionary:
	return {"queries": query_count, "ledger_operations": int(snapshot.get("candidate_operation_count", 0)),
		"axis_dominance_skips": axis_dominance_skips,
		"exact_distance_evaluations": exact_distance_evaluations}


static func sample_world_optimized(seed: int, region_key: Vector2i, operation_snapshot: Dictionary,
		world_position: Vector3, show_cave_section: bool = false,
		remap_base_field_from_world: bool = false) -> float:
	if not world_position.is_finite() or not bool(operation_snapshot.get("valid", true)):
		return NAN
	var density: float
	if remap_base_field_from_world:
		var mapped: Dictionary = Spatial.world_to_region_local(world_position)
		if not bool(mapped.get("valid", false)):
			return NAN
		density = Field.sample_density(seed, mapped["region_key"], mapped["local_position"])
	else:
		var local_position := world_position - Spatial.region_origin_world(region_key)
		density = Field.sample_density(seed, region_key, local_position)
	var centers: PackedVector3Array = operation_snapshot["centers"]
	var radii: PackedFloat64Array = operation_snapshot["radii"]
	var modes: PackedByteArray = operation_snapshot["modes"]
	for index in range(centers.size()):
		var center: Vector3 = centers[index]
		var delta := world_position - center
		var radius := float(radii[index])
		var cutoff := density + radius if modes[index] == Brush.Mode.CARVE else radius - density
		if cutoff <= 0.0:
			continue
		var guard := maxf(0.0000001, cutoff * DISTANCE_GUARD_RELATIVE)
		var guarded_cutoff := cutoff + guard
		if absf(delta.x) > guarded_cutoff or absf(delta.y) > guarded_cutoff \
			or absf(delta.z) > guarded_cutoff:
			continue
		var distance_to_surface := world_position.distance_to(center) - radius
		if modes[index] == Brush.Mode.CARVE:
			density = minf(density, distance_to_surface)
		else:
			density = maxf(density, -distance_to_surface)
	if show_cave_section:
		density = minf(density, 6.0 - world_position.z)
	return density


func _axis_proves_noop(delta: Vector3, threshold: float) -> bool:
	# If |one component| exceeds the Euclidean cutoff with a conservative
	# numerical guard, then the full distance is above the cutoff. Radius-only
	# support is never used as a relevance test.
	var guard := maxf(0.0000001, absf(threshold) * DISTANCE_GUARD_RELATIVE)
	var guarded_threshold := threshold + guard
	return absf(delta.x) > guarded_threshold \
		or absf(delta.y) > guarded_threshold \
		or absf(delta.z) > guarded_threshold
