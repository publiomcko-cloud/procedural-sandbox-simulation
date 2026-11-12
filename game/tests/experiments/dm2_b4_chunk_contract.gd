extends SceneTree

## DM2: test that real TerrainMeshJob/B4 per-chunk geometry is identical
## to the independently built DM1 full-region B4 mesh at shared boundaries.
## Validates pristine/edited field and positive/negative region coordinates.
const Grid := preload("res://scripts/terrain/terrain_chunk_grid.gd")
const Field := preload("res://scripts/terrain/sdf_world.gd")
const Brush := preload("res://scripts/terrain/sdf_brush_edit_state.gd")
const B4 := preload("res://scripts/experiments/discrete_surface_nets_backend.gd")
const MeshJob := preload("res://scripts/terrain/terrain_mesh_job.gd")
const SEED := 424242
const TARGETS := [
	Vector2i(0, 0), Vector2i(1, 0), Vector2i(3, 0),
	Vector2i(0, 3), Vector2i(3, 3), Vector2i(2, 2),
]
var assertions := 0
var failures := 0
var generated_chunks := 0
var triangle_count := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for region in [Vector2i.ZERO, Vector2i(1, -1)]:
		var oracle := Brush.new(SEED, Field.GENERATOR_VERSION)
		var full := B4.new()
		if not _check(full.generate(SEED, region, Grid.SAMPLE_STEP), "region_seed_build"):
			continue
		_check_variant(region, oracle, full, "pristine")
		var origin := Vector3(
			float(region.x) * Field.REGION_SIZE_X,
			0.0, float(region.y) * Field.REGION_SIZE_Z
		)
		var center := origin + Vector3(5.25, 3.2, 4.2)
		_check(oracle.add_sphere(0, center, 0.95), "canonical_sdf_edit_accepted")
		full.edit_sphere(0, center, 0.95)
		_check_variant(region, oracle, full, "edited")
	print("DM2_B4_CHUNK_METRICS=" + JSON.stringify({
		"regions": 2,
		"modes": 2,
		"compared_chunks": generated_chunks,
		"triangles": triangle_count,
		"assertions": assertions,
		"failures": failures,
	}))
	print("DM2_B4_CHUNK_%s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)


func _check_variant(
	region: Vector2i,
	oracle: RefCounted,
	full: RefCounted,
	label: String
) -> void:
	for coordinate in TARGETS:
		var snap: Dictionary = oracle.get_meshing_snapshot_for_chunk(region, coordinate)
		if not _check(snap.get("valid", false), "snapshot_valid_" + label):
			continue
		var expected: Dictionary = full.build_chunk(coordinate)
		if not _check(expected.get("valid", false), "full_b4_valid_" + label):
			continue
		var job := MeshJob.new(
			SEED, region, coordinate, false, snap, Time.get_ticks_usec(), 0, true
		)
		job.run()
		var actual: Dictionary = job.result
		if not _check(actual.get("valid", false), "chunk_b4_valid_" + label):
			continue
		_check(String(actual.get("backend", "")) == "b4", "job_is_b4")
		_check(int(actual.get("lod_level", -1)) == 0, "job_is_lod0")
		_check(int(actual.get("sample_count", 0)) > 0, "samples_counted")
		_check(int(actual.get("triangle_count", -1)) == int(expected.get("triangle_count", -2)),
			"chunk_triangle_count_matches_full_" + label)
		var expected_p: PackedVector3Array = expected["positions"]
		var actual_p: PackedVector3Array = actual["positions"]
		if _check(expected_p.size() == actual_p.size(), "same_position_count_" + label):
			var error := 0.0
			for i in range(expected_p.size()):
				error = maxf(error, expected_p[i].distance_to(actual_p[i]))
			_check(error <= 0.00001, "match_all_vertex_positions_" + label)
		generated_chunks += 1
		triangle_count += int(actual["triangle_count"])


func _check(condition: bool, label: String) -> bool:
	assertions += 1
	if not condition:
		failures += 1
		push_error("DM2_FAIL: " + label)
	return condition
