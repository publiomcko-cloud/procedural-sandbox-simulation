extends SceneTree

const Lookahead := preload("res://scripts/terrain/terrain_stream_lookahead_policy.gd")

var assertions := 0
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, message: String) -> void:
	assertions += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + message)


func _run() -> void:
	var center := Vector2i(5, 13)
	var ahead := Vector2i(7, 13)
	_check(Lookahead.clamp_lead(center, Vector2i(99, 14)) == Vector2i(7, 14),
		"prediction clamps X lead without altering permitted Z offset")
	_check(Lookahead.clamp_lead(center, Vector2i(5, -999)) == Vector2i(5, 11),
		"prediction clamps backward Z lead to the bounded source halo")
	_check(Lookahead.clamp_lead(center, center) == center,
		"stationary motion causes no predictive displacement")
	var queued: Array[Vector2i] = [
		Vector2i(10, 13),  # distant background
		Vector2i(7, 13),   # ahead priority
		Vector2i(5, 13),   # current focus
		Vector2i(4, 13),   # current-focus prerequisite
		Vector2i(9, 13),   # predicted frontier
		Vector2i(7, 14),   # ahead prerequisite
		Vector2i(4, 12),
		Vector2i(8, 15),
	]
	var result := Lookahead.ordered_queue(queued, center, ahead, {})
	_check(result.size() == queued.size(), "reordering does not add/remove source scopes")
	for region in queued:
		_check(result.has(region), "queue reordering preserves every original region")
	_check(result[0] == center, "current focus is ranked ahead of forward target")
	_check(result.find(Vector2i(7, 13)) < result.find(Vector2i(10, 13)),
		"ahead region precedes unrelated far background")
	_check(result == Lookahead.ordered_queue(queued, center, ahead, {}),
		"priority sort is deterministic across identical input")
	var urgent := {"region:10,13": true, "region:9,13": true}
	var with_urgents := Lookahead.ordered_queue(queued, center, ahead, urgent)
	_check(with_urgents[0] == Vector2i(10, 13) and with_urgents[1] == Vector2i(9, 13),
		"explicit missing-effect requirements retain their original FIFO precedence")
	_check(with_urgents.size() == queued.size(), "urgent selection preserves queue membership")
	_check(queued[0] == Vector2i(10, 13),
		"lookahead comparator leaves original queue unchanged")
	# A source required by the current visible 3x3 outranks an ahead-only far
	# source, preserving revision-gated region publication first.
	var current_required := Vector2i(2, 13)
	var prospective_far := Vector2i(10, 13)
	var mixed: Array[Vector2i] = [prospective_far, current_required]
	var ordered := Lookahead.ordered_queue(mixed, center, ahead, {})
	_check(ordered[0] == current_required,
		"current visible-window boundary prerequisites outrank distant lookahead")
	if failures == 0:
		print("P5_0F_STREAM_LOOKAHEAD_PASS: assertions=%d failures=0" % assertions)
		quit(0)
	else:
		push_error("P5_0F_STREAM_LOOKAHEAD_FAIL: assertions=%d failures=%d" % [
			assertions, failures
		])
		quit(1)
