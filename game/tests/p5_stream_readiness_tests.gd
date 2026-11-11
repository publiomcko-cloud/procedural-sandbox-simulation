extends SceneTree

const Readiness := preload("res://scripts/terrain/terrain_stream_readiness_metrics.gd")
var assertions := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	assertions += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + label)

func _run() -> void:
	var focus := Vector2i(-5, 13)
	var none := Readiness.sample_window(focus, {})
	_check(none["requested"] == 9 and none["unpublished"] == 9, "cold 3x3 is entirely unpublished")
	_check(none["focus_unpublished"], "focus publication is absent")
	var published := {"-5,13": true, "-4,14": true}
	var sample := Readiness.sample_window(focus, published)
	_check(sample["published"] == 2 and sample["unpublished"] == 7, "partial window counts stable IDs")
	_check(not sample["focus_unpublished"], "central publication is distinguished from surrounding gaps")
	var shifted := Readiness.sample_window(Vector2i(-4, 13), published)
	_check(shifted["published"] == 2, "focus shift uses new window without editing scene state")
	var tight := Readiness.sample_window(focus, published, 0)
	_check(tight["requested"] == 1 and tight["unpublished"] == 0, "radius zero counts focus only")
	var clamped := Readiness.sample_window(focus, {}, 900)
	_check(clamped["requested"] == 25, "sampling remains hard bounded")
	var t := Readiness.load_latency(100, 120, 170, 250)
	_check(t["queue_to_first_dispatch_usec"] == 20, "dispatch milestone is queue relative")
	_check(t["queue_to_first_mesh_usec"] == 70, "mesh milestone is queue relative")
	_check(t["queue_to_visual_usec"] == 150, "scene commit milestone is queue relative")
	var bad := Readiness.load_latency(100, 0, 80, 0)
	_check(bad["queue_to_first_dispatch_usec"] == -1 and bad["queue_to_first_mesh_usec"] == -1, "missing/obsolete timestamps fail closed")
	_check(bad["queue_to_visual_usec"] == -1, "unpublished result does not fabricate latency")
	if failures == 0:
		print("P5_STREAM_READINESS_PASS: assertions=%d failures=0" % assertions)
		quit(0)
	else:
		push_error("P5_STREAM_READINESS_FAIL: assertions=%d failures=%d" % [assertions, failures])
		quit(1)
