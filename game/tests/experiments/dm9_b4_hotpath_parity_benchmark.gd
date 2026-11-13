extends SceneTree

const B4 := preload("res://scripts/experiments/discrete_surface_nets_backend.gd")
const Grid := preload("res://scripts/terrain/terrain_chunk_grid.gd")
const VisualJob := preload("res://scripts/experiments/b4_region_visual_job.gd")

var assertions := 0
var failures := 0
var runs: Array[Dictionary] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var combinations := [
		{"seed": 424242, "region": Vector2i.ZERO},
		{"seed": 0, "region": Vector2i(-7, 9)},
		{"seed": -16384, "region": Vector2i(12, -8)},
		{"seed": 741, "region": Vector2i(-1, -1)},
	]
	var unsupported := B4.new()
	_check(not unsupported.generate_pristine_fast(424242, Vector2i.ZERO, 0.25),
		"fast pristine path must not accidentally replace 0.25m/edited backend")
	for datum in combinations:
		var seed: int = datum["seed"]
		var region: Vector2i = datum["region"]
		var original := B4.new()
		var fast := B4.new()
		var a_started := Time.get_ticks_usec()
		_check(original.generate(seed, region, 0.5), "baseline pristine B4 generation")
		var original_usec := Time.get_ticks_usec() - a_started
		var b_started := Time.get_ticks_usec()
		_check(fast.generate_pristine_fast(seed, region, 0.5), "DM9 fast pristine B4 generation")
		var fast_usec := Time.get_ticks_usec() - b_started
		_check(original.nodes == fast.nodes, "exact Q8.8 lattice parity")
		_check(original.cell_active == fast.cell_active, "exact Surface Nets active-cell parity")
		_check(original.cell_vertices == fast.cell_vertices, "exact Surface Nets vertex parity")
		_check(original.last_generation_sample_count == fast.last_generation_sample_count,
			"unchanged sample density and halo footprint")
		var original_mesh_started := Time.get_ticks_usec()
		var originals: Array[Dictionary] = []
		for coord in Grid.all_coordinates():
			originals.append(original.build_chunk(coord))
		var original_mesh_usec := Time.get_ticks_usec() - original_mesh_started
		var fast_mesh_started := Time.get_ticks_usec()
		var i := 0
		for coord in Grid.all_coordinates():
			var actual: Dictionary = fast.build_chunk(coord)
			var expected: Dictionary = originals[i]
			_check(actual.get("valid", false) == expected.get("valid", false),
				"exact chunk validity")
			_check(actual.get("quad_count", -1) == expected.get("quad_count", -2),
				"exact quad count")
			_check(actual.get("positions", PackedVector3Array()) ==
				expected.get("positions", PackedVector3Array()), "exact mesh positions")
			_check(actual.get("normals", PackedVector3Array()) ==
				expected.get("normals", PackedVector3Array()), "exact mesh normals")
			i += 1
		var fast_mesh_usec := Time.get_ticks_usec() - fast_mesh_started
		var receipt := {
			"seed": seed,
			"region": [region.x, region.y],
			"sample_sites": original.last_generation_sample_count,
			"baseline_lattice_ms": float(original.last_pristine_lattice_usec) / 1000.0,
			"baseline_cell_ms": float(original.last_pristine_rebuild_usec) / 1000.0,
			"fast_precompute_ms": float(fast.last_pristine_precompute_usec) / 1000.0,
			"fast_lattice_ms": float(fast.last_pristine_lattice_usec) / 1000.0,
			"fast_cell_ms": float(fast.last_pristine_rebuild_usec) / 1000.0,
			"uniform_cells_skipped": fast.last_pristine_uniform_cells,
			"baseline_generation_ms": float(original_usec) / 1000.0,
			"fast_generation_ms": float(fast_usec) / 1000.0,
			"baseline_16_chunk_ms": float(original_mesh_usec) / 1000.0,
			"fast_16_chunk_ms": float(fast_mesh_usec) / 1000.0,
		}
		runs.append(receipt)
		print("DM9_B4_HOTPATH_CASE=" + JSON.stringify(receipt))
	var total_original := 0.0
	var total_fast := 0.0
	for record in runs:
		total_original += float(record["baseline_generation_ms"])
		total_fast += float(record["fast_generation_ms"])
	print("DM9_B4_HOTPATH_RESULT=" + JSON.stringify({
		"cases": runs.size(), "assertions": assertions, "failures": failures,
		"lattice_and_mesh_exact": failures == 0,
		"baseline_generation_total_ms": total_original,
		"fast_generation_total_ms": total_fast,
		"speedup_generation": total_original / maxf(0.00001, total_fast),
		"authority_untouched": true
	}))
	print("DM9_B4_HOTPATH_%s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)


func _check(ok: bool, message: String) -> void:
	assertions += 1
	if not ok:
		failures += 1
		push_error("DM9_B4_HOTPATH_FAIL: " + message)
