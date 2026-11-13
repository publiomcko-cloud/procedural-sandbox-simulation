extends SceneTree

const Batch := preload("res://scripts/terrain/dm12_surface_snapshot_batch.gd")
const Grid := preload("res://scripts/terrain/terrain_chunk_grid.gd")
const Brush := preload("res://scripts/terrain/sdf_brush_edit_state.gd")
const Field := preload("res://scripts/terrain/sdf_world.gd")

var assertions := 0
var failures := 0
var cases := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for region in [Vector2i.ZERO, Vector2i(-3, 4), Vector2i(9, -12)]:
		var seed := 424242
		for edited in [false, true]:
			var ledger := Brush.new(seed, Field.GENERATOR_VERSION)
			if edited:
				var pos := Vector3(
					float(region.x) * Field.REGION_SIZE_X + 5.5,
					2.8,
					float(region.y) * Field.REGION_SIZE_Z + 4.5
				)
				_check(ledger.add_sphere(0, pos, 1.15), "carve added")
				_check(ledger.add_sphere(1, pos + Vector3(0.5, -0.25, 0.0), 0.8), "fill added")
			var baseline := {}
			var expected: Array[Dictionary] = []
			for coordinate in Grid.all_coordinates():
				var snapshot: Dictionary = ledger.get_meshing_snapshot_for_chunk(region, coordinate)
				_check(bool(snapshot.get("valid", false)), "baseline snapshot valid")
				baseline[coordinate] = snapshot
				expected.append({"region_key": region, "chunk_coordinate": coordinate})
			var batch := Batch.new(region, int(ledger.revision), int(ledger.get_instance_id()))
			var calls := 0
			var done := false
			while calls < 20 and not done:
				var response: Dictionary = batch.capture(ledger, 3, 2500)
				_check(bool(response.get("ok", false)), "batch preparation succeeded")
				_check(int(response.get("processed", -1)) >= 1 and int(response.get("processed", 4)) <= 3,
					"at least one and max three chunks per frame")
				calls += 1
				done = bool(response.get("complete", false))
			_check(done, "six or more bounded frames suffice")
			var prepared: Dictionary = batch.prepared_inputs()
			_check((prepared.get("base_snapshots", {}) as Dictionary).size() == 16,
				"all 16 chunks captured")
			_check(int(prepared.get("capture_calls", -1)) == calls, "accurate batch call receipt")
			_check(prepared.get("effect_targets", []) == expected, "effect target order and identity exact")
			_check(prepared.get("anchor_snapshot", {}) == baseline[Vector2i.ZERO],
				"anchor is same first snapshot")
			for coordinate in Grid.all_coordinates():
				_check(prepared["base_snapshots"][coordinate] == baseline[coordinate],
					"exact ordered typed arrays and revisions for chunk " + str(coordinate))
			cases += 1
	var mutable := Brush.new(424242, Field.GENERATOR_VERSION)
	var invalidated := Batch.new(Vector2i.ZERO, int(mutable.revision), int(mutable.get_instance_id()))
	_check(bool(invalidated.capture(mutable, 2, 10000).get("ok", false)), "valid initial phase")
	_check(mutable.add_sphere(0, Vector3(2.5, 2.5, 2.5), 1.0), "new brush revision")
	_check(not invalidated.capture(mutable, 2, 10000).get("ok", true),
		"revision change rejects stale partial input")
	_check(invalidated.prepared_inputs().is_empty(), "no partial batch can publish")
	var other := Brush.new(424242, Field.GENERATOR_VERSION)
	_check(not Batch.new(Vector2i.ZERO, int(mutable.revision), int(mutable.get_instance_id())).capture(
		other, 2, 10000).get("ok", true), "scope identity mismatch rejects input")
	_check(not Batch.new(Vector2i.ZERO, int(other.revision), int(other.get_instance_id())).capture(
		other, 0, 10000).get("ok", true), "zero budget rejected")
	print("DM12_SURFACE_BATCH_RESULT=" + JSON.stringify({
		"assertions": assertions,
		"failures": failures,
		"cases": cases,
		"chunk_count_per_case": 16,
		"exact_snapshots": failures == 0,
		"revision_guard": failures == 0,
	}))
	print("DM12_SURFACE_BATCH_%s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)


func _check(ok: bool, message: String) -> void:
	assertions += 1
	if not ok:
		failures += 1
		push_error("DM12_SURFACE_BATCH_FAIL: " + message)
