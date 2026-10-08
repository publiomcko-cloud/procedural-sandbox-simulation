extends SceneTree

const RegionGen = preload("res://scripts/region_generator.gd")

var assertion_count := 0
var failure_count := 0


func _initialize() -> void:
	_test_reproducibility()
	_test_request_order_independence()
	_test_input_failures()
	if failure_count == 0:
		print("SMOKE_PASS: assertions=%d failures=0" % assertion_count)
	else:
		push_error("SMOKE_FAIL: assertions=%d failures=%d" % [assertion_count, failure_count])
	quit(0 if failure_count == 0 else 1)


func _test_reproducibility() -> void:
	var baseline: Dictionary = RegionGen.generate_region(12345, 1, Vector2i(3, -2))
	_check(baseline.get("ok", false), "valid generation succeeds")
	_check(baseline.get("cells", []).size() == 8, "default height is eight")
	_check(baseline.get("cells", [])[0].size() == 8, "default width is eight")
	_check(baseline.get("algorithm_version") == 1, "algorithm version is returned")
	_check(baseline == RegionGen.generate_region(12345, 1, Vector2i(3, -2)), "fixed input is reproducible")
	_check(baseline.get("cells", [])[0] == [29, 99, 47, 82, 36, 46, 25, 46], "algorithm v1 golden row is stable")
	_check(baseline != RegionGen.generate_region(12346, 1, Vector2i(3, -2)), "seed changes output")
	_check(baseline != RegionGen.generate_region(12345, 1, Vector2i(4, -2)), "region key changes output")
	_check(baseline.get("cells", [])[0][0] >= 0 and baseline.get("cells", [])[0][0] < 100, "cell values are bounded")
	var sized: Dictionary = RegionGen.generate_region(0, 1, Vector2i(0, 0), 3, 2)
	_check(sized.get("ok", false) and sized.get("cells", []).size() == 2, "custom dimensions are honored")
	_check(sized.get("cells", [])[0].size() == 3, "custom row width is honored")


func _test_request_order_independence() -> void:
	var a_first: Dictionary = RegionGen.generate_region(8128, 1, Vector2i(-4, 7))
	var b_second: Dictionary = RegionGen.generate_region(8128, 1, Vector2i(2, 9))
	var b_first: Dictionary = RegionGen.generate_region(8128, 1, Vector2i(2, 9))
	var a_second: Dictionary = RegionGen.generate_region(8128, 1, Vector2i(-4, 7))
	_check(a_first == a_second, "region A does not depend on request order")
	_check(b_second == b_first, "region B does not depend on request order")


func _test_input_failures() -> void:
	_check_error(RegionGen.generate_region(-1, 1, Vector2i.ZERO), "invalid_seed")
	_check_error(RegionGen.generate_region(1.5, 1, Vector2i.ZERO), "invalid_seed")
	_check_error(RegionGen.generate_region(true, 1, Vector2i.ZERO), "invalid_seed")
	_check_error(RegionGen.generate_region(0, "1", Vector2i.ZERO), "invalid_algorithm_version")
	_check_error(RegionGen.generate_region(0, 2, Vector2i.ZERO), "unsupported_algorithm_version")
	_check_error(RegionGen.generate_region(0, 1, Vector2(1, 2)), "invalid_region_key")
	_check_error(RegionGen.generate_region(0, 1, Vector2i(1000001, 0)), "region_key_out_of_range")
	_check_error(RegionGen.generate_region(0, 1, Vector2i(-2147483648, 0)), "region_key_out_of_range")
	_check_error(RegionGen.generate_region(0, 1, Vector2i.ZERO, 0, 1), "invalid_width")
	_check_error(RegionGen.generate_region(0, 1, Vector2i.ZERO, 65, 1), "invalid_width")
	_check_error(RegionGen.generate_region(0, 1, Vector2i.ZERO, 2.5, 1), "invalid_width")
	_check_error(RegionGen.generate_region(0, 1, Vector2i.ZERO, 1, -1), "invalid_height")
	_check_error(RegionGen.generate_region(0, 1, Vector2i.ZERO, 1, 65), "invalid_height")


func _check_error(result: Dictionary, expected_code: String) -> void:
	_check(not result.get("ok", true), "invalid input is rejected: %s" % expected_code)
	var error: Dictionary = result.get("error", {})
	_check(error.get("code", "") == expected_code, "failure code is stable: %s" % expected_code)
	_check(not error.get("message", "").is_empty(), "failure has a diagnostic: %s" % expected_code)


func _check(condition: bool, label: String) -> void:
	assertion_count += 1
	if not condition:
		failure_count += 1
		push_error("ASSERTION FAILED: " + label)
