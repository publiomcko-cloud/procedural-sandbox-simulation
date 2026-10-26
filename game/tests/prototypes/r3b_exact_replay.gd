extends RefCounted

## Disposable exact evaluator. It preserves command order and the canonical
## Vector3 distance operation. It only removes exact repeated complete blocks.
## A block is a composition of d -> min(d, c) / d -> max(d, c). Such a unary
## min/max composition is a clamp (or a constant), hence idempotent; applying
## the same complete block again cannot change its result. A trailing partial
## block remains in its original order.
const Field := preload("res://scripts/terrain/sdf_world.gd")
const Brush := preload("res://scripts/terrain/sdf_brush_edit_state.gd")
const Spatial := preload("res://scripts/terrain/terrain_spatial_ownership.gd")

var _seed: int
var _has_owner_region := false
var _owner_region := Vector2i.ZERO
var _centers := PackedVector3Array()
var _radii := PackedFloat64Array()
var _modes := PackedByteArray()
var _brush_keys := PackedStringArray()
var _unique_centers := PackedVector3Array()
var _unique_radii := PackedFloat64Array()
var _sequence_brush_indices := PackedInt32Array()
var _period := 0
var _tail := 0
var _unique_brushes := 0
var operation_visits := 0
var distance_evaluations := 0


func _init(seed_value: int, snapshot: Dictionary, owner_region: Variant = null) -> void:
	_seed = seed_value
	if typeof(owner_region) == TYPE_VECTOR2I:
		_has_owner_region = true
		_owner_region = owner_region
	_centers = snapshot.get("centers", PackedVector3Array())
	_radii = snapshot.get("radii", PackedFloat64Array())
	_modes = snapshot.get("modes", PackedByteArray())
	if _centers.size() == _radii.size() and _centers.size() == _modes.size():
		var brush_indices := {}
		for index in range(_centers.size()):
			var identity := var_to_bytes(_centers[index])
			identity.append_array(var_to_bytes(_radii[index]))
			var key: String = identity.hex_encode()
			_brush_keys.append(key)
			if not brush_indices.has(key):
				brush_indices[key] = _unique_centers.size()
				_unique_centers.append(_centers[index])
				_unique_radii.append(_radii[index])
			_sequence_brush_indices.append(int(brush_indices[key]))
	if _centers.size() != _radii.size() or _centers.size() != _modes.size():
		_period = _centers.size()
		return
	_period = _find_repeat_period()
	_tail = _centers.size() % _period if _period > 0 else 0
	_unique_brushes = _count_unique_brushes()


func sample_density(world_point: Vector3, show_cave_section: bool = false) -> float:
	var region_key: Vector2i
	var local_position: Vector3
	if _has_owner_region:
		region_key = _owner_region
		local_position = world_point - Spatial.region_origin_world(region_key)
	else:
		var mapped := Spatial.world_to_region_local(world_point)
		if not bool(mapped.get("valid", false)):
			return NAN
		region_key = mapped["region_key"]
		local_position = mapped["local_position"]
	var density: float = Field.sample_density(_seed, region_key, local_position)
	var canonical_world := Spatial.region_local_to_world(region_key, local_position)
	var reduced_count := _period + _tail if _period > 0 else _centers.size()
	# Avoid dictionary/allocation overhead when this query contains no repeated
	# brush identity or sequence block to exploit.
	if reduced_count == _centers.size() and _unique_brushes == _centers.size():
		for index in range(_centers.size()):
			var direct_distance := canonical_world.distance_to(_centers[index]) - _radii[index]
			if _modes[index] == Brush.Mode.CARVE:
				density = minf(density, direct_distance)
			elif _modes[index] == Brush.Mode.FILL:
				density = maxf(density, -direct_distance)
			else:
				return NAN
		operation_visits += _centers.size()
		distance_evaluations += _centers.size()
		if show_cave_section:
			density = minf(density, 6.0 - canonical_world.z)
		return density
	var thresholds := PackedFloat64Array()
	thresholds.resize(_unique_centers.size())
	for index in range(_unique_centers.size()):
		thresholds[index] = canonical_world.distance_to(_unique_centers[index]) - _unique_radii[index]
	# One period is sufficient for every complete duplicate block. Keep a
	# non-repeated suffix exactly as authored.
	for index in range(reduced_count):
		var signed_distance: float = thresholds[_sequence_brush_indices[index]]
		if _modes[index] == Brush.Mode.CARVE:
			density = minf(density, signed_distance)
		elif _modes[index] == Brush.Mode.FILL:
			density = maxf(density, -signed_distance)
		else:
			return NAN
	operation_visits += reduced_count
	distance_evaluations += _unique_centers.size()
	if show_cave_section:
		density = minf(density, 6.0 - canonical_world.z)
	return density


func can_reduce_exact_replay() -> bool:
	return _period > 0 and _period + _tail < _centers.size()


func stats() -> Dictionary:
	return {
		"source_operations": _centers.size(), "replay_operations": _period + _tail,
		"repeat_period": _period, "repeat_tail": _tail,
		"unique_brushes": _unique_brushes, "unique_geometry_count": _unique_centers.size(),
		"operation_visits": operation_visits, "distance_evaluations": distance_evaluations,
	}


func _find_repeat_period() -> int:
	var count := _centers.size()
	if count < 2:
		return count
	# Prefix-function search is linear. Equality is exact for mode, center and
	# radius; no quantization or geometric proximity is used.
	var prefix := PackedInt32Array()
	prefix.resize(count)
	for index in range(1, count):
		var matched: int = prefix[index - 1]
		while matched > 0 and not _same_operation(index, matched):
			matched = prefix[matched - 1]
		if _same_operation(index, matched):
			matched += 1
		prefix[index] = matched
	var candidate := count - prefix[count - 1]
	if candidate >= count:
		return count
	for index in range(candidate, count):
		if not _same_operation(index, index % candidate):
			return count
	return candidate


func _same_operation(left: int, right: int) -> bool:
	return _modes[left] == _modes[right] and _brush_keys[left] == _brush_keys[right]


func _count_unique_brushes() -> int:
	var keys := {}
	for key in _brush_keys:
		keys[key] = true
	return keys.size()
