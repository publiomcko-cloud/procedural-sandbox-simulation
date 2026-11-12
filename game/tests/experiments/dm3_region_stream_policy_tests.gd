extends SceneTree

const Policy := preload("res://scripts/experiments/b4_region_stream_policy.gd")
const Visual := preload("res://scripts/experiments/b4_region_visual_job.gd")
const Field := preload("res://scripts/terrain/sdf_world.gd")
var tests := 0
var fails := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var focus := Vector2i(12,-8)
	var facing := Vector3(1,0,0)
	var regions := Policy.desired_regions(focus, facing)
	_check(regions.size() == 112, "11x11 shell excluding canonical 3x3")
	for r in regions:
		var d := Policy.distance(r,focus)
		_check(d >= 2 and d <= 5, "all regions within 2..5")
		_check(Policy.lod_for_distance(d) == (1 if d == 5 else 0), "only fifth ring LOW")
	_check(Policy.distance(Vector2i(-5,-5), Vector2i.ZERO) == 5, "negative keys")
	_check(Policy.rank(focus + Vector2i(5,0),focus,facing)
		< Policy.rank(focus + Vector2i(-2,0),focus,facing), "ahead wins over close rear")
	_check(Policy.rank(focus,focus,facing)
		< Policy.rank(focus + Vector2i(5,0),focus,facing), "focus stays urgent")
	var now := 30_000_000
	_check(Policy.keep(0,now,10), "radius ten retains")
	_check(Policy.keep(now-19_000_000,now,11), "retained 19 seconds outside ten")
	_check(not Policy.keep(now-21_000_000,now,11), "expired outside ten")
	var low := Visual.build_data(424242,Vector2i(1,-1),1)
	var high := Visual.build_data(424242,Vector2i(1,-1),0)
	_check(bool(low.get("valid",false)), "low visual CPU job valid")
	_check(bool(high.get("valid",false)), "high visual CPU job valid")
	_check(int(low.get("sample_sites",0)) == 63, "LOW 9x7 height samples")
	_check(int(high.get("sample_sites",0)) == 221, "HIGH 17x13 height samples")
	_check(int(low.get("triangle_count",0)) > 0, "LOW has terrain")
	_check(int(high.get("triangle_count",0)) > int(low.get("triangle_count",0)),
		"HIGH has more triangles")
	_check(Field.GENERATOR_VERSION > 0, "pinned generator available")
	print("DM3_REGION_POLICY_RESULT=" + JSON.stringify({
		"tests": tests,"failures":fails,
		"requested_visual_region_count":regions.size(),
		"low_triangles":int(low.get("triangle_count",0)),
		"high_triangles":int(high.get("triangle_count",0)),
		"max_cache_regions":Policy.MAX_SHELL_REGIONS,
	}))
	print("DM3_REGION_POLICY_%s" % ("PASS" if fails == 0 else "FAIL"))
	quit(0 if fails == 0 else 1)

func _check(ok: bool,label:String) -> void:
	tests += 1
	if not ok:
		fails += 1
		push_error("DM3_REGION_POLICY_FAIL: " + label)
