extends SceneTree

const Runtime := preload("res://scripts/terrain/terrain_object_effect_runtime.gd")
var assertions := 0
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, detail: String) -> void:
	assertions += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + detail)


func _run() -> void:
	var runtime := Runtime.new()
	var standard: Dictionary = runtime.get_projection_pipeline_configuration()
	_check(int(standard["source_worker_limit"]) == 2, "base source concurrency remains 2")
	_check(int(standard["projection_worker_limit"]) == 2, "baseline projection concurrency is 2")
	_check(int(standard["publish_limit_per_frame"]) == 1, "baseline publication is 1")
	runtime.set_projection_pipeline_enabled(true)
	var faster: Dictionary = runtime.get_projection_pipeline_configuration()
	_check(int(faster["source_worker_limit"]) == 2, "source generation stays at 2")
	_check(int(faster["projection_worker_limit"]) == 4, "experimental projection concurrency is capped at 4")
	_check(int(faster["publish_limit_per_frame"]) == 2, "experimental per-frame projection publication capped at 2")
	runtime.set_projection_pipeline_enabled(false)
	var restored: Dictionary = runtime.get_projection_pipeline_configuration()
	_check(restored == standard, "switching experiment off recovers exact baseline")
	if failures == 0:
		print("P5_PROJECTION_E6_CAPACITY_PASS: assertions=" + str(assertions) + " failures=0")
		quit(0)
	else:
		push_error("P5_PROJECTION_E6_CAPACITY_FAIL: assertions=" + str(assertions) + " failures=" + str(failures))
		quit(1)
