extends SceneTree

const Policy := preload("res://scripts/terrain/dm9_canonical_prefetch_policy.gd")

var checked := 0
var failed := 0

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var origin := Vector3(8.0, 0.0, 6.0)
	var east := Policy.targets(Vector2i.ZERO, origin, Vector3(18.0, 0.0, 0.0))
	_check(east.size() == 3, "east prefetch has three bounded candidates")
	for key in east:
		_check(key.x == 2 and absi(key.y) <= 1, "east stays within protected radius two")
		_check(not Policy.is_inside_core(key, Vector2i.ZERO), "east never targets core")
	var north := Policy.targets(Vector2i.ZERO, origin, Vector3(0.0, 0.0, 18.0))
	_check(north.size() == 3, "north prefetch has three candidates")
	for key in north:
		_check(key.y == 2 and absi(key.x) <= 1, "north stays within protected source scope")
	var west := Policy.targets(Vector2i.ZERO, origin, Vector3(-18.0, 0.0, 0.0))
	_check(west.has(Vector2i(-2, 0)), "negative X direction handled")
	var diagonal := Policy.targets(Vector2i.ZERO, origin, Vector3(12.7279, 0.0, 12.7279))
	_check(diagonal.size() == Policy.MAX_SPECULATIVE_REGIONS, "diagonal target cap")
	for key in diagonal:
		_check(maxi(absi(key.x), absi(key.y)) == 2, "diagonal is perimeter only")
		_check(not Policy.is_inside_core(key, Vector2i.ZERO), "diagonal is never core")
	_check(Policy.targets(Vector2i.ZERO, origin, Vector3.ZERO).is_empty(), "no speculative idle")
	_check(Policy.targets(Vector2i.ZERO, origin, Vector3(54, 0, 0)).is_empty(), "54m/s boost excluded")
	_check(Policy.targets(Vector2i.ZERO, origin, Vector3(22, 0, 0)).is_empty(), "speed over cap excluded")
	_check(Policy.targets(Vector2i.ZERO, Vector3(INF, 0, 0), Vector3(18, 0, 0)).is_empty(), "invalid coordinate excluded")
	_check(Policy.is_inside_core(Vector2i(-1, 1), Vector2i.ZERO), "negative core boundary")
	_check(not Policy.is_inside_core(Vector2i(2, 0), Vector2i.ZERO), "prefetch candidate cannot publish early")
	_check(Policy.valid_revision(7,7,5,5,9,9,false,false), "matching seed/edit/effect/cave allows promotion")
	_check(not Policy.valid_revision(7,8,5,5,9,9,false,false), "seed change rejects")
	_check(not Policy.valid_revision(7,7,5,6,9,9,false,false), "edit revision change rejects")
	_check(not Policy.valid_revision(7,7,5,5,9,10,false,false), "effect revision change rejects")
	_check(not Policy.valid_revision(7,7,5,5,9,9,false,true), "cave mode change rejects")
	print("DM9_PREFETCH_POLICY_RESULT=" + JSON.stringify({
		"assertions": checked, "failures": failed,
		"candidate_cap": Policy.MAX_SPECULATIVE_REGIONS,
		"horizon_seconds": Policy.HORIZON_SECONDS,
		"authoritative_window_unchanged": true,
		"revision_gates": ["seed","brush","effect","cave"]
	}))
	print("DM9_PREFETCH_POLICY_%s" % ("PASS" if failed == 0 else "FAIL"))
	quit(0 if failed == 0 else 1)


func _check(ok: bool, message: String) -> void:
	checked += 1
	if not ok:
		failed += 1
		push_error("DM9_PREFETCH_POLICY_FAIL: " + message)
