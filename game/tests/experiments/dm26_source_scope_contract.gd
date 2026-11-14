extends SceneTree

const Runtime := preload("res://scripts/terrain/terrain_object_effect_runtime.gd")
const Probe := preload("res://scripts/diagnostics/dm24_canonical_stage_funnel_probe.gd")

var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(value: bool, msg: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("DM26_SCOPE_CONTRACT_FAIL: " + msg)


func _run() -> void:
	var runtime := Runtime.new()
	var initial: Dictionary = runtime.dm26_scope_state(Vector2i(23, 14))
	_check(initial.get("state") == "outside_protected", "uninitialized scope unprotected")
	_check(int(initial.get("queued_index", -2)) == -1, "uninitialized queue index")
	_check(not bool(initial.get("resident", true)), "uninitialized scope not resident")
	var probe := Probe.new()
	var stage := {
		"purpose": "load", "region_key": Vector2i(21, 14),
		"submit_index": 0, "stage_token": 19,
		"chunk_coordinates": range(16),
		"dm9_speculative": false, "dm18_cache_ready": false
	}
	var focus := Vector2i(21, 14)
	probe.begin("focus", 19, 100_000, true)
	probe.frame({"focus": stage}, focus, 1, 0, 0, 8)
	var request := {"id": "focus", "index": 0, "coordinate": 0}
	probe.selected(request, request, request, {"focus": stage}, 100_100, false)
	probe.first_snapshot("focus", 19, 100_200)
	probe.effect_pending("focus", 19, [Vector2i(23, 14)])
	probe.dm26_observe_sources("focus", 19, [initial])
	var queued := initial.duplicate()
	queued["state"] = "queued_urgent"
	queued["protected"] = true
	queued["tracked"] = true
	queued["queued_index"] = 0
	queued["queue_length"] = 8
	probe.dm26_observe_sources("focus", 19, [queued])
	probe.dm26_observe_sources("focus", 99, [queued])
	var summary: Dictionary = probe.summary()
	var sources: Dictionary = summary.get("dm26_source_states", {})
	var region: Dictionary = sources.get("region:23,14", {})
	_check(sources.size() == 1, "single source identity")
	_check(int(summary["counts"].get("dm26_state_outside_protected", 0)) == 1,
		"unprotected observed")
	_check(int(summary["counts"].get("dm26_state_queued_urgent", 0)) == 1,
		"queued observed")
	_check(int(region.get("transitions", 0)) == 1, "transition counted")
	_check(int(region.get("last_queue_index", -1)) == 0, "queue position captured")
	_check(bool(region.get("last_protected", false)), "protected boundary captured")
	_check(int(summary.get("dm25_missing_source_hits", {}).get("region:23,14", 0)) == 1,
		"dm25 classification unchanged")
	_check(probe.summary().get("dm26_source_states", {}).size() == 1,
		"no unbounded synthetic expansion")
	probe.reset_measurements_preserving_active()
	_check(probe.summary().get("dm26_source_states", {}).is_empty(),
		"warm-up reset clears DM26")
	print("DM26_SCOPE_CONTRACT_RESULT=" + JSON.stringify({"checks": checks, "failures": failures}))
	print("DM26_SCOPE_CONTRACT_%s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
