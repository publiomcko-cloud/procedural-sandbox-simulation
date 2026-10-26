extends SceneTree

const Brush := preload("res://scripts/terrain/sdf_brush_edit_state.gd")
const Grid := preload("res://scripts/terrain/terrain_chunk_grid.gd")
const Spatial := preload("res://scripts/terrain/terrain_spatial_ownership.gd")
const ExactReplay := preload("res://tests/prototypes/r3c_exact_replay.gd")

const SEED := 135031
const OPERATION_COUNT := 512
const RANDOM_PROBES := 1024

var _failures: Array[String] = []
var _assertions := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var ledger: RefCounted = Brush.new(SEED, 1)
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	for index in range(OPERATION_COUNT):
		var center := Vector3(rng.randf_range(-48.0, 48.0), rng.randf_range(-0.95, 5.95), rng.randf_range(-36.0, 36.0))
		var radius := rng.randf_range(0.45, 1.20)
		var mode := Brush.Mode.CARVE if index % 2 == 0 else Brush.Mode.FILL
		_expect(ledger.add_sphere(mode, center, radius), "ordered_operation_accepted_%d" % index)
	var snapshot: Dictionary = ledger.get_meshing_snapshot()
	var operations: Array[Dictionary] = ledger.get_operations_snapshot()
	var exact: RefCounted = ExactReplay.new(SEED, snapshot)
	var probes: Array[Vector3] = [
		Vector3(-16.0001, 1.15, -12.0001), Vector3(-16.0, 1.15, -12.0), Vector3(-15.9999, 1.15, -11.9999),
		Vector3(15.9999, -0.9999, 11.9999), Vector3(16.0, -1.0, 12.0), Vector3(16.0001, -1.0001, 12.0001),
		Vector3(-32.0, 3.0, -24.0), Vector3(32.0, 3.0, 24.0), Vector3(-0.0001, 1.15, 5.99), Vector3(0.0001, 1.15, 6.01)
	]
	for index in range(RANDOM_PROBES):
		probes.append(Vector3(rng.randf_range(-64.0, 64.0), rng.randf_range(-1.2, 7.2), rng.randf_range(-48.0, 48.0)))
	for index in range(operations.size()):
		var operation: Dictionary = operations[index]
		var center: Vector3 = operation["center_world"]
		var radius := float(operation["radius"])
		for offset in [-0.00001, 0.0, 0.00001]:
			probes.append(center + Vector3.RIGHT * (radius + float(offset)))
			probes.append(center + Vector3(1.0, 1.0, 1.0).normalized() * (radius + float(offset)))
	var mismatch_count := 0
	for index in range(probes.size()):
		var point: Vector3 = probes[index]
		var canonical := _canonical_density(point, snapshot)
		var candidate: float = exact.sample_density(point)
		if canonical != candidate:
			mismatch_count += 1
	_expect(mismatch_count == 0, "exact_density_all_signed_boundary_and_threshold_probes")
	var normal_mismatches := 0
	for index in range(48):
		var point: Vector3 = probes[(index * 29) % probes.size()]
		if _canonical_normal(point, snapshot) != _exact_normal(point, exact):
			normal_mismatches += 1
	_expect(normal_mismatches == 0, "exact_finite_difference_normals")
	var picker_mismatches := 0
	for index in range(6):
		var point: Vector3 = probes[(index * 83 + 7) % probes.size()]
		var origin := Vector3(point.x, 8.0, point.z)
		if _canonical_ray_hit(origin, Vector3.DOWN, snapshot) != _exact_ray_hit(origin, Vector3.DOWN, exact):
			picker_mismatches += 1
	_expect(picker_mismatches == 0, "exact_picker_first_hit_and_bisection")
	var stats: Dictionary = exact.stats()
	_expect(int(stats.get("dominated_noop_operations", 0)) > 0, "conservative_dominance_skips_proven_noops")
	_expect(int(stats.get("distance_evaluations", 0)) < int(stats.get("operation_visits", 0)), "no_op_pruning_reduces_distance_evaluations")
	if _failures.is_empty():
		print("R3C_EXACTNESS_TESTS_PASS assertions=%d probes=%d normals=48 pickers=6 pruned=%d distance_evaluations=%d operation_visits=%d" % [
			_assertions, probes.size(), int(stats.get("dominated_noop_operations", 0)), int(stats.get("distance_evaluations", 0)), int(stats.get("operation_visits", 0))])
		quit(0)
	else:
		push_error("R3C_EXACTNESS_TESTS_FAIL assertions=%d failures=%s" % [_assertions, ";".join(_failures)])
		quit(1)


func _expect(condition: bool, name: String) -> void:
	_assertions += 1
	if not condition:
		_failures.append(name)


func _canonical_density(point: Vector3, snapshot: Dictionary) -> float:
	var mapped := Spatial.world_to_region_local(point)
	if not bool(mapped.get("valid", false)):
		return NAN
	return Brush.sample_density_snapshot(SEED, mapped["region_key"], mapped["local_position"], false, snapshot)


func _canonical_normal(point: Vector3, snapshot: Dictionary) -> Vector3:
	var delta := Grid.SAMPLE_STEP * 0.5
	return Vector3(
		_canonical_density(point + Vector3.RIGHT * delta, snapshot) - _canonical_density(point - Vector3.RIGHT * delta, snapshot),
		_canonical_density(point + Vector3.UP * delta, snapshot) - _canonical_density(point - Vector3.UP * delta, snapshot),
		_canonical_density(point + Vector3.BACK * delta, snapshot) - _canonical_density(point - Vector3.BACK * delta, snapshot)
	).normalized()


func _exact_normal(point: Vector3, exact: RefCounted) -> Vector3:
	var delta := Grid.SAMPLE_STEP * 0.5
	return Vector3(
		exact.sample_density(point + Vector3.RIGHT * delta) - exact.sample_density(point - Vector3.RIGHT * delta),
		exact.sample_density(point + Vector3.UP * delta) - exact.sample_density(point - Vector3.UP * delta),
		exact.sample_density(point + Vector3.BACK * delta) - exact.sample_density(point - Vector3.BACK * delta)
	).normalized()


func _canonical_ray_hit(origin: Vector3, direction: Vector3, snapshot: Dictionary) -> Vector3:
	return _ray_hit(origin, direction, snapshot, Callable())


func _exact_ray_hit(origin: Vector3, direction: Vector3, exact: RefCounted) -> Vector3:
	return _ray_hit(origin, direction, {}, Callable(exact, "sample_density"))


func _ray_hit(origin: Vector3, direction: Vector3, snapshot: Dictionary, evaluator: Callable) -> Vector3:
	var previous_point := origin
	var previous_density := _canonical_density(previous_point, snapshot) if not evaluator.is_valid() else float(evaluator.call(previous_point))
	for index in range(1, 256):
		var point := origin + direction * (float(index) * Grid.SAMPLE_STEP * 0.5)
		var density := _canonical_density(point, snapshot) if not evaluator.is_valid() else float(evaluator.call(point))
		if previous_density >= 0.0 and density < 0.0:
			var low := previous_point
			var high := point
			for _iteration in range(20):
				var middle := (low + high) * 0.5
				var value := _canonical_density(middle, snapshot) if not evaluator.is_valid() else float(evaluator.call(middle))
				if value >= 0.0:
					low = middle
				else:
					high = middle
			return (low + high) * 0.5
		previous_point = point
		previous_density = density
	return Vector3(INF, INF, INF)
