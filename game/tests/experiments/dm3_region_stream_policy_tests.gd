extends SceneTree

## DM4 supersedes the DM3 fifth-ring LOW contract. Entire 11x11
## viewport ultimately uses 0.5m B4; only visibility is nonauthoritative.
const Policy := preload("res://scripts/experiments/b4_region_stream_policy.gd")
const Visual := preload("res://scripts/experiments/b4_region_visual_job.gd")
const Field := preload("res://scripts/terrain/sdf_world.gd")
var tests := 0
var fails := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var focus := Vector2i(12, -8)
	var facing := Vector3(1, 0, 0)
	var regions := Policy.desired_regions(focus, facing)
	_check(regions.size() == 121, "11x11 HIGH set including provisional 3x3 center")
	_check(regions[0] == focus, "focus region enqueued first")
	var seen: Dictionary = {}
	var last_rank := -1
	for r in regions:
		var d := Policy.distance(r, focus)
		_check(d >= 0 and d <= 5, "all regions within 0..5")
		_check(Policy.lod_for_distance(d) == 0, "ALL five rings HIGH")
		_check(not seen.has(r), "no duplicate region jobs")
		seen[r] = true
		var priority := Policy.rank(r, focus, facing)
		_check(priority >= last_rank, "priority drains queue in sorted order")
		last_rank = priority
	_check(Policy.distance(Vector2i(-5, -5), Vector2i.ZERO) == 5, "negative keys")
	for radius in range(2, 6):
		_check(Policy.rank(focus + Vector2i(radius, 0), focus, facing) \
			< Policy.rank(focus + Vector2i(-radius, 0), focus, facing),
			"forward ahead of rear in SAME distance ring")
	_check(Policy.rank(focus + Vector2i(-2, 0), focus, facing) \
		< Policy.rank(focus + Vector2i(3, 0), focus, facing),
		"near ring outranks far ring even when rear")
	_check(Policy.rank(focus, focus, facing) \
		< Policy.rank(focus + Vector2i(2, 0), focus, facing),
		"canonical region priority")
	var now := 30_000_000
	_check(Policy.keep(0, now, 10), "radius ten retains")
	_check(Policy.keep(now - 19_000_000, now, 11), "retains 19s outside ten")
	_check(not Policy.keep(now - 21_000_000, now, 11), "expires outside ten")
	var low := Visual.build_data(424242, Vector2i(1, -1), 1)
	_check(not bool(low.get("valid", true)), "LOW worker explicitly rejected")
	var high := Visual.build_data(424242, Vector2i(1, -1), 0)
	_check(bool(high.get("valid", false)), "HIGH B4 full-region CPU worker valid")
	_check(String(high.get("backend", "")) == "b4_surface_nets", "full B4 topology")
	_check(is_equal_approx(float(high.get("step", -1.0)), 0.5), "0.5m resolution")
	_check(int(high.get("chunk_triangle_counts", {}).size()) == 16, "full 16 chunks")
	_check(int(high.get("triangle_count", 0)) > 1000, "full 3D geometry not 384-triangle heightfield")
	_check(Field.GENERATOR_VERSION > 0, "pinned generator available")
	print("DM4_REGION_POLICY_RESULT=" + JSON.stringify({
		"tests": tests, "failures": fails,
		"requested_visual_region_count": regions.size(),
		"high_triangles": int(high.get("triangle_count", 0)),
		"b4_sample_step": float(high.get("step", 0)),
		"low_forbidden": true,
	}))
	print("DM4_REGION_POLICY_%s" % ("PASS" if fails == 0 else "FAIL"))
	quit(0 if fails == 0 else 1)

func _check(ok: bool, label: String) -> void:
	tests += 1
	if not ok:
		fails += 1
		push_error("DM4_REGION_POLICY_FAIL: " + label)
