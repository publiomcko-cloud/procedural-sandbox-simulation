extends SceneTree

const Policy := preload("res://scripts/experiments/b4_region_stream_policy.gd")
const Visual := preload("res://scripts/experiments/b4_region_visual_job.gd")
const B4 := preload("res://scripts/experiments/discrete_surface_nets_backend.gd")
const Grid := preload("res://scripts/terrain/terrain_chunk_grid.gd")
var tests := 0
var fails := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var focus := Vector2i(12, -8)
	var facing := Vector3(1, 0, 0)
	var regions := Policy.desired_regions(focus, facing)
	_check(regions.size() == 112, "11x11 window excluding canonical 3x3")
	_check(Policy.FINE_RADIUS == Policy.ACTIVE_RADIUS,
		"uniform full resolution through radius five")
	for r in regions:
		var d := Policy.distance(r, focus)
		_check(d >= 2 and d <= 5, "every shell region lies within 2..5")
		_check(Policy.lod_for_distance(d) == 0, "every region B4 HIGH")
	_check(Policy.distance(Vector2i(-5,-5), Vector2i.ZERO) == 5, "negative keys")
	_check(Policy.rank(focus + Vector2i(2,0), focus, facing)
		< Policy.rank(focus + Vector2i(3,0), focus, facing),
		"nearest region takes priority over distant forward")
	_check(Policy.rank(focus + Vector2i(3,0), focus, facing)
		< Policy.rank(focus + Vector2i(-3,0), focus, facing),
		"at same range forward wins over rear")
	_check(Policy.rank(focus, focus, facing)
		< Policy.rank(focus + Vector2i(2,0), focus, facing),
		"focus stays highest priority")
	for i in range(1, regions.size()):
		_check(Policy.rank(regions[i-1], focus, facing)
			<= Policy.rank(regions[i], focus, facing),
			"prioritized queue is monotone")
	var now := 30_000_000
	_check(Policy.keep(0,now,10), "radius 10 retains")
	_check(Policy.keep(now-19_000_000,now,11), "retain outside radius for 19 seconds")
	_check(not Policy.keep(now-21_000_000,now,11), "expire after 20 seconds")
	# The visual worker must produce the SAME positions as the DM1 B4 oracle,
	# chunk-by-chunk, not a heightfield approximation with a visible seam.
	for key in [Vector2i.ZERO, Vector2i(-1, 1)]:
		var preview := Visual.build_data(424242, key, 0)
		var legacy_low_request := Visual.build_data(424242, key, 1)
		_check(bool(preview.get("valid", false)), "B4 visual region generated")
		_check(bool(legacy_low_request.get("valid", false)), "legacy LOW request maps to HIGH")
		_check(preview.get("backend", "") == "b4", "true B4 backend")
		_check(float(preview.get("sample_step", 0)) == 0.5, "B4 exact 0.5m step")
		_check(int(preview.get("sample_sites", 0)) == 21735, "B4 lattice sample count")
		_check(preview["positions"] == legacy_low_request["positions"],
			"LOW request has identical HIGH positions")
		var oracle := B4.new()
		_check(oracle.generate(424242, key, 0.5), "DM1 full-region B4 oracle")
		var expected := PackedVector3Array()
		var normals := PackedVector3Array()
		for coordinate in Grid.all_coordinates():
			var part: Dictionary = oracle.build_chunk(coordinate)
			_check(part.get("valid", false), "B4 chunk has no skipped faces")
			var origin := Grid.origin_for(coordinate)
			var points: PackedVector3Array = part["positions"]
			for p in points:
				expected.append(p + origin)
			normals.append_array(part["normals"])
		_check(expected == preview["positions"], "EXACT B4 positions parity")
		_check(normals == preview["normals"], "EXACT B4 normals parity")
		_check(int(preview["triangle_count"]) == expected.size() / 3,
			"same B4 triangles as oracle")
	print("DM4_REGION_HIGH_POLICY_RESULT=" + JSON.stringify({
		"tests": tests,
		"failures": fails,
		"requested_visual_regions": regions.size(),
		"all_lod": 0,
		"backend": "b4",
		"sampling_step_m": 0.5,
	}))
	print("DM4_REGION_HIGH_POLICY_%s" % ("PASS" if fails == 0 else "FAIL"))
	quit(0 if fails == 0 else 1)

func _check(ok: bool, label: String) -> void:
	tests += 1
	if not ok:
		fails += 1
		push_error("DM4_REGION_HIGH_POLICY_FAIL: " + label)
