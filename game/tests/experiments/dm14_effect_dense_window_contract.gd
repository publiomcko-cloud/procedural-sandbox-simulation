extends SceneTree

const Fast := preload("res://scripts/terrain/dm14_effect_dense_window.gd")
const Runtime := preload("res://scripts/terrain/terrain_object_effect_runtime.gd")

var checks := 0
var fails := 0
var cases := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for center in [
		Vector2i.ZERO, Vector2i(3, 7), Vector2i(-1, -1),
		Vector2i(-100, 45), Vector2i(127, -84),
		Vector2i(100003, -100004)
	]:
		var targets: Array[Vector2i] = []
		for y in range(center.y - 2, center.y + 3):
			for x in range(center.x - 2, center.x + 3):
				targets.append(Vector2i(x, y))
		for reversed in [false, true]:
			var input := targets.duplicate()
			if reversed:
				input.reverse()
			var actual: Dictionary = Fast.ordered_required(input)
			_check(bool(actual.get("ok", false)), "dense window accepted")
			if not actual.get("ok", false):
				continue
			var expected := _legacy_ordered_sources(input)
			_check(actual["regions"] == expected,
				"81-item exact ordered scope equivalence for signed center " + str(center))
			_check(actual["center"] == center, "exact focus center")
			_check((actual["regions"] as Array[Vector2i]).size() == 81,
				"source scope cap remains 81")
			var temp := actual["regions"] as Array[Vector2i]
			var unique := {}
			for key in temp:
				unique[key] = true
			_check(unique.size() == 81, "no duplicate source scopes")
			cases += 1
	var irregular: Array[Vector2i] = []
	for i in 25:
		irregular.append(Vector2i(i, 0))
	_check(not Fast.ordered_required(irregular).get("ok", true),
		"same cardinality but irregular footprint falls back")
	var duplicate: Array[Vector2i] = []
	for i in 25:
		duplicate.append(Vector2i(i % 4, int(i / 4)))
	_check(not Fast.ordered_required(duplicate).get("ok", true),
		"not exactly dense 5x5 must fall back")
	var short: Array[Vector2i] = [Vector2i.ZERO]
	_check(not Fast.ordered_required(short).get("ok", true),
		"single target uses legacy path")
	var empty: Array[Vector2i] = []
	_check(not Fast.ordered_required(empty).get("ok", true),
		"empty target uses legacy path")
	# Mirror the original union + sorted-distance comparator, including source
	# radius and exact y/x tie-breaking, not merely set equality.
	var runtime := Runtime.new()
	var cold_targets: Array[Vector2i] = []
	for y in range(-2, 3):
		for x in range(-2, 3):
			cold_targets.append(Vector2i(x, y))
	var legacy := runtime._required_source_regions_for_regions(cold_targets)
	_check(legacy.size() == 81, "existing live runtime produced 81 source IDs")
	print("DM14_DENSE_CONTRACT_RESULT=" + JSON.stringify({
		"checks": checks, "failures": fails, "cases": cases,
		"full_order_exact": fails == 0,
		"irregular_fallback": fails == 0
	}))
	print("DM14_DENSE_CONTRACT_%s" % ("PASS" if fails == 0 else "FAIL"))
	quit(0 if fails == 0 else 1)


func _legacy_ordered_sources(targets: Array[Vector2i]) -> Array[Vector2i]:
	var by_key := {}
	for center in targets:
		for y in range(center.y - 2, center.y + 3):
			for x in range(center.x - 2, center.x + 3):
				var key := Vector2i(x, y)
				by_key[key] = true
	var minimum := targets[0]
	var maximum := targets[0]
	for key in targets:
		minimum.x = mini(minimum.x, key.x)
		minimum.y = mini(minimum.y, key.y)
		maximum.x = maxi(maximum.x, key.x)
		maximum.y = maxi(maximum.y, key.y)
	var center := Vector2i(
		int((minimum.x + maximum.x) / 2.0),
		int((minimum.y + maximum.y) / 2.0)
	)
	var sources: Array[Vector2i] = []
	for key in by_key:
		sources.append(key)
	sources.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var da := maxi(absi(a.x - center.x), absi(a.y - center.y))
		var db := maxi(absi(b.x - center.x), absi(b.y - center.y))
		if da != db:
			return da < db
		var ma := absi(a.x - center.x) + absi(a.y - center.y)
		var mb := absi(b.x - center.x) + absi(b.y - center.y)
		if ma != mb:
			return ma < mb
		return a.y < b.y or (a.y == b.y and a.x < b.x)
	)
	return sources


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		push_error("DM14_DENSE_FAIL: " + message)
