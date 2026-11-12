extends SceneTree

const Policy := preload("res://scripts/experiments/b4_region_stream_policy.gd")
const Grid := preload("res://scripts/terrain/terrain_spatial_ownership.gd")

var assertions := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var focus := Vector2i.ZERO
	var player := Policy.focus_center_world(focus)
	_check(Policy.REGION_X_M == Grid.REGION_SIZE_X, "radial X meters matches grid")
	_check(Policy.REGION_Z_M == Grid.REGION_SIZE_Z, "radial Z meters matches grid")
	_check(is_equal_approx(Policy.radial_radius_m(6), 130.0),
		"terrain HIGH circular world radius is 130m")
	_check(is_equal_approx(Policy.radial_radius_m(4), 90.0),
		"rocks HIGH circular world radius is 90m")
	_check(is_equal_approx(Policy.radial_radius_m(10), 210.0),
		"visual HIGH retention circular world radius is 210m")
	_check(Policy.RETAIN_USEC == 20_000_000, "retention grace unchanged")
	_check(Policy.expected_region_count() == 277, "center reference 277 terrain HIGH")
	_check(Policy.expected_external_region_count() == 268,
		"center reference 268 visual-only terrain HIGH")
	_check(Policy.expected_rock_region_count() == 137,
		"center reference 137 rock HIGH including canonical 9")
	_check(Policy.within_high(Vector2i(6,6), player), "old diagonal 6,6 HIGH")
	_check(Policy.within_high(Vector2i(8,0), player),
		"new straight X extension at 8 regions")
	_check(Policy.within_high(Vector2i(0,10), player),
		"new straight Z extension at 10 regions")
	_check(not Policy.within_high(Vector2i(9,0), player),
		"outside world-radius at 9 X regions")
	_check(not Policy.within_high(Vector2i(0,11), player),
		"outside world-radius at 11 Z regions")
	_check(Policy.within_rock_high(Vector2i(4,4), player),
		"old diagonal 4,4 rocks HIGH")
	_check(Policy.within_rock_high(Vector2i(5,0), player),
		"new rock HIGH straight X extension")
	_check(Policy.within_rock_high(Vector2i(0,7), player),
		"new rock HIGH straight Z extension")
	_check(not Policy.within_rock_high(Vector2i(6,0), player),
		"rock HIGH not unlimited")

	# Guarantee old diagonal square remains included for ALL representative
	# positions in a focus region, including near opposite corners.
	for position in [
		Vector3(8.0, 0.0, 6.0),
		Vector3(0.001, 0.0, 0.001),
		Vector3(15.999, 0.0, 11.999),
		Vector3(0.001, 0.0, 11.999),
		Vector3(15.999, 0.0, 0.001)
	]:
		for old_radius in [4, 6, 10]:
			for z in range(-old_radius, old_radius + 1):
				for x in range(-old_radius, old_radius + 1):
					_check(Policy.within_radius(
						Vector2i(x,z), position, old_radius
					), "old diagonal cell preserved at actual player position")

	var a := Vector3(0.001, 0.0, 6.0)
	var b := Vector3(15.999, 0.0, 6.0)
	_check(Grid.region_key_for_world_position(a) ==
		Grid.region_key_for_world_position(b), "player stays in same focus cell")
	_check(not Policy.within_high(Vector2i(8,0), a),
		"left edge player excludes distant cell")
	_check(Policy.within_high(Vector2i(8,0), b),
		"right edge player admits SAME cell without a region crossing")
	var left := Policy.desired_regions(focus, Vector3.FORWARD, a)
	var right := Policy.desired_regions(focus, Vector3.FORWARD, b)
	_check(left != right, "moving within same focus changes coverage set")
	var center := Policy.desired_regions(focus, Vector3(1,0,0), player)
	_check(center.size() == 268, "exact centered circle enumeration")
	var seen: Dictionary = {}
	var last_rank := -1
	for region in center:
		var key_rank := Policy.rank(region, focus, Vector3(1,0,0), player)
		_check(Policy.distance(region, focus) >= 2, "core 3x3 excluded")
		_check(Policy.within_high(region, player), "no region beyond radial limit")
		_check(not seen.has(region), "no duplicate radial region")
		_check(key_rank >= last_rank, "distance-first radial queue monotone")
		seen[region] = true
		last_rank = key_rank

	_check(not Policy.within_retention(Vector2i(17,0), player),
		"region beyond 210m retention circle is exterior")
	_check(Policy.keep_radial(0, 100_000_000, Vector2i(10,10), player),
		"old diagonal 10,10 protected for any elapsed time")
	_check(Policy.keep_radial(0, 19_000_000, Vector2i(17,0), player),
		"20s grace while outside 210m")
	_check(not Policy.keep_radial(0, 20_000_000, Vector2i(17,0), player),
		"evict only after full 20s outside 210m")
	_check(Policy.within_high(Vector2i(6,6), Vector3(8,999,6)),
		"flying vertically must not unload world below the camera")
	print("DM8_RADIAL_POLICY_RESULT=" + JSON.stringify({
		"assertions": assertions,
		"failures": failures,
		"terrain_radius_m": Policy.radial_radius_m(6),
		"rocks_radius_m": Policy.radial_radius_m(4),
		"retention_radius_m": Policy.radial_radius_m(10),
		"terrain_center_regions": Policy.expected_region_count(),
		"rocks_center_regions": Policy.expected_rock_region_count(),
		"preserves_all_old_diagonal_cells": true,
		"centered_on_actual_player_world_position": true,
		"plane": "XZ",
	}))
	print("DM8_RADIAL_POLICY_%s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)


func _check(ok: bool, description: String) -> void:
	assertions += 1
	if not ok:
		failures += 1
		push_error("DM8_RADIAL_POLICY_FAIL: " + description)
