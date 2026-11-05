extends SceneTree

const Authority := preload("res://scripts/terrain/shared_surface_boundary_authority.gd")
const Brush := preload("res://scripts/terrain/sdf_brush_edit_state.gd")
const Field := preload("res://scripts/terrain/sdf_world.gd")

const SEED := 424242
const BASE_REGION := Vector2i.ZERO

var assertions := 0
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	Authority.clear_incremental_cache()
	var ledger := Brush.new(SEED, Field.GENERATOR_VERSION)
	_check(ledger.add_sphere(Brush.Mode.CARVE, Vector3(15.6, 3.1, 11.5), 0.85), "initial edit accepted")
	_check(ledger.add_sphere(Brush.Mode.FILL, Vector3(16.3, 2.4, 12.2), 0.65), "second initial edit accepted")

	var initial := _build_all(ledger)
	_check(initial.get("valid", false), "initial shared geometry builds")
	if not initial.get("valid", false):
		_finish()
		return

	_check(ledger.add_sphere(Brush.Mode.CARVE, Vector3(16.1, 3.0, 12.1), 0.72), "append edit accepted")
	var incremental := _build_all(ledger)
	_check(incremental.get("valid", false), "incremental shared geometry builds")
	if not incremental.get("valid", false):
		_finish()
		return

	var x_counters: Dictionary = incremental["x"]["left"].get("work_counters", {})
	var z_counters: Dictionary = incremental["z"]["low"].get("work_counters", {})
	var corner_counters: Dictionary = incremental["corner"]["minx_minz"].get("work_counters", {})
	_check(int(x_counters.get("incremental_cache_hit", 0)) == 1, "X pair uses incremental cache")
	_check(int(z_counters.get("incremental_cache_hit", 0)) == 1, "Z pair uses incremental cache")
	_check(int(corner_counters.get("incremental_cache_hit", 0)) == 1, "corner uses incremental cache")
	_check(int(x_counters.get("dirty_cell_count", 999999)) < int(x_counters.get("cell_count", 0)), "X pair rebuilds a strict subvolume")
	_check(int(z_counters.get("dirty_cell_count", 999999)) < int(z_counters.get("cell_count", 0)), "Z pair rebuilds a strict subvolume")
	_check(int(corner_counters.get("dirty_cell_count", 999999)) < int(corner_counters.get("cell_count", 0)), "corner rebuilds a strict subvolume")

	Authority.clear_incremental_cache()
	var full := _build_all(ledger)
	_check(full.get("valid", false), "fresh full shared geometry builds")
	if full.get("valid", false):
		_compare_pair("x.left", incremental["x"]["left"], full["x"]["left"])
		_compare_pair("x.right", incremental["x"]["right"], full["x"]["right"])
		_compare_pair("z.low", incremental["z"]["low"], full["z"]["low"])
		_compare_pair("z.high", incremental["z"]["high"], full["z"]["high"])
		for owner in ["minx_minz", "maxx_minz", "minx_maxz", "maxx_maxz"]:
			_compare_pair("corner." + owner, incremental["corner"][owner], full["corner"][owner])
		_check(String(incremental["x"].get("mesh_signature", "")) == String(full["x"].get("mesh_signature", "")), "X signature matches full rebuild")
		_check(String(incremental["z"].get("mesh_signature", "")) == String(full["z"].get("mesh_signature", "")), "Z signature matches full rebuild")
		_check(String(incremental["corner"].get("mesh_signature", "")) == String(full["corner"].get("mesh_signature", "")), "corner signature matches full rebuild")

	# A revision that is irrelevant to this scope should reuse the full prior result.
	_check(ledger.add_sphere(Brush.Mode.CARVE, Vector3(100.0, 3.0, 100.0), 0.7), "distant edit accepted")
	var reused := _build_all(ledger)
	_check(reused.get("valid", false), "irrelevant revision shared geometry builds")
	if reused.get("valid", false):
		var reuse_counters: Dictionary = reused["corner"]["minx_minz"].get("work_counters", {})
		_check(int(reuse_counters.get("incremental_cache_hit", 0)) == 1, "irrelevant revision hits incremental cache")
		_check(int(reuse_counters.get("dirty_cell_count", -1)) == 0, "irrelevant revision rebuilds zero corner cells")

	print("P1_INCREMENTAL_SHARED_EVIDENCE=" + JSON.stringify({
		"x": x_counters,
		"z": z_counters,
		"corner": corner_counters,
	}))
	_finish()


func _build_all(ledger: RefCounted) -> Dictionary:
	var x_snapshot := Authority.make_x_pair_snapshot(ledger, BASE_REGION, 3)
	var z_snapshot := Authority.make_z_pair_snapshot(ledger, BASE_REGION, 3)
	var corner_snapshot := Authority.make_xz_corner_snapshot(ledger, BASE_REGION)
	if not x_snapshot.get("valid", false) or not z_snapshot.get("valid", false) or not corner_snapshot.get("valid", false):
		return {"valid": false, "reason": "snapshot_failed"}
	var x := Authority.build_x_region_boundary_pair(SEED, BASE_REGION, 3, x_snapshot, true)
	var z := Authority.build_z_region_boundary_pair(SEED, BASE_REGION, 3, z_snapshot, true)
	var corner := Authority.build_xz_corner_quad(SEED, BASE_REGION, corner_snapshot, true)
	return {
		"valid": x.get("valid", false) and z.get("valid", false) and corner.get("valid", false),
		"x": x,
		"z": z,
		"corner": corner,
	}


func _compare_pair(label: String, candidate: Dictionary, reference: Dictionary) -> void:
	_check(candidate.get("positions", PackedVector3Array()) == reference.get("positions", PackedVector3Array()), label + " positions exactly match")
	_check(candidate.get("normals", PackedVector3Array()) == reference.get("normals", PackedVector3Array()), label + " normals exactly match")
	_check(int(candidate.get("triangle_count", -1)) == int(reference.get("triangle_count", -2)), label + " triangle count matches")


func _check(condition: bool, message: String) -> void:
	assertions += 1
	if condition:
		print("PASS: " + message)
	else:
		failures += 1
		push_error("FAIL: " + message)


func _finish() -> void:
	if failures == 0:
		print("P1_INCREMENTAL_SHARED_PASS: assertions=%d failures=0" % assertions)
	else:
		push_error("P1_INCREMENTAL_SHARED_FAIL: assertions=%d failures=%d" % [assertions, failures])
	Authority.clear_incremental_cache()
	quit(0 if failures == 0 else 1)
