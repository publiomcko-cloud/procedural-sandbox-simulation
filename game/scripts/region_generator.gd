class_name RegionGenerator
extends RefCounted

## Deterministic pure-data placeholder. This is not a terrain generator.
## Algorithm v1: Park-Miller LCG (modulus 2^31 - 1, multiplier 16807),
## restarted independently for each (seed, version, region) request.
const ALGORITHM_VERSION := 1
const MODULUS := 2147483647
const MULTIPLIER := 16807
const MAX_REGION_AXIS := 1000000
const MAX_DIMENSION := 64


static func generate_region(
	world_seed: Variant,
	algorithm_version: Variant,
	region_key: Variant,
	width: Variant = 8,
	height: Variant = 8
) -> Dictionary:
	if typeof(world_seed) != TYPE_INT or world_seed < 0 or world_seed >= MODULUS:
		return _failure("invalid_seed", "world_seed must be an integer in [0, 2147483646]")
	if typeof(algorithm_version) != TYPE_INT:
		return _failure("invalid_algorithm_version", "algorithm_version must be integer 1")
	if algorithm_version != ALGORITHM_VERSION:
		return _failure("unsupported_algorithm_version", "supported algorithm_version is 1")
	if typeof(region_key) != TYPE_VECTOR2I:
		return _failure("invalid_region_key", "region_key must be Vector2i")
	if region_key.x < -MAX_REGION_AXIS or region_key.x > MAX_REGION_AXIS \
		or region_key.y < -MAX_REGION_AXIS or region_key.y > MAX_REGION_AXIS:
		return _failure("region_key_out_of_range", "region coordinates must be within +/-1000000")
	if typeof(width) != TYPE_INT or width < 1 or width > MAX_DIMENSION:
		return _failure("invalid_width", "width must be an integer in [1, 64]")
	if typeof(height) != TYPE_INT or height < 1 or height > MAX_DIMENSION:
		return _failure("invalid_height", "height must be an integer in [1, 64]")

	var state := _initial_state(world_seed, algorithm_version, region_key)
	var cells: Array[Array] = []
	for _y in range(height):
		var row: Array[int] = []
		for _x in range(width):
			state = (state * MULTIPLIER) % MODULUS
			row.append(state % 100)
		cells.append(row)
	return {
		"ok": true,
		"algorithm_version": algorithm_version,
		"region_key": region_key,
		"width": width,
		"height": height,
		"cells": cells,
	}


static func _initial_state(world_seed: int, algorithm_version: int, region_key: Vector2i) -> int:
	# Inputs are bounded so each intermediate remains safely within signed 64-bit range.
	var mixed := world_seed + 1
	mixed += region_key.x * 48271
	mixed += region_key.y * 69621
	mixed += algorithm_version * 104729
	return posmod(mixed, MODULUS - 1) + 1


static func _failure(code: String, message: String) -> Dictionary:
	return {"ok": false, "error": {"code": code, "message": message}}
