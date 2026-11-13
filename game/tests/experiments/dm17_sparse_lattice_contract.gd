extends SceneTree

## DM17 exact parity: ALL 16 chunks, two regions, pristine and edited/cave.
## Baseline DM11 fast versus DM17-A+B, Q8.8 nodes and final mesh bit-exact.
const Grid := preload("res://scripts/terrain/terrain_chunk_grid.gd")
const Field := preload("res://scripts/terrain/sdf_world.gd")
const Brush := preload("res://scripts/terrain/sdf_brush_edit_state.gd")
const B4 := preload("res://scripts/experiments/discrete_surface_nets_backend.gd")
const Cache := preload("res://scripts/experiments/dm17_shared_region_lattice.gd")

var checks := 0
var failed := 0
var blocks := 0
var skipped_cells := 0
var shared_hits := 0
var shared_builds := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_check(Cache.clear(), "initial clean cache")
	for region in [Vector2i.ZERO, Vector2i(-3, 4)]:
		var ledger := Brush.new(424242, Field.GENERATOR_VERSION)
		for coord in Grid.all_coordinates():
			var snapshot: Dictionary = ledger.get_meshing_snapshot_for_chunk(region, coord)
			_compare(region, coord, snapshot, false, true, "pristine")
		_check(ledger.add_sphere(Brush.Mode.CARVE,
			Vector3(float(region.x) * 16.0 + 2.5, 2.0,
				float(region.y) * 12.0 + 1.5), 1.15), "valid edit")
		for coord in [Vector2i(0, 0), Vector2i(1, 1), Vector2i(3, 3)]:
			var edited: Dictionary = ledger.get_meshing_snapshot_for_chunk(region, coord)
			# An edit outside this chunk can be safely eliminated by the exact
			# meshing influence index; that chunk remains genuinely pristine.
			var affected := not (edited.get("centers", PackedVector3Array()) as PackedVector3Array).is_empty()
			_compare(region, coord, edited, false, not affected, "edited")
			_compare(region, coord, edited, true, false, "cave")
	_check(blocks > 0 and skipped_cells > 0, "sparse path executed")
	_check(shared_hits > 0 and shared_builds > 0, "regional lattice cache miss and hit")
	print("DM17_SPARSE_LATTICE_RESULT=" + JSON.stringify({
		"checks": checks, "failed": failed, "uniform_blocks": blocks,
		"cells_skipped_by_blocks": skipped_cells,
		"shared_cache_hits": shared_hits, "shared_cache_builds": shared_builds,
	}))
	print("DM17_SPARSE_LATTICE_%s" % ("PASS" if failed == 0 else "FAIL"))
	quit(0 if failed == 0 else 1)


func _compare(region: Vector2i, coord: Vector2i, snapshot: Dictionary,
	cave: bool, expected_shared: bool, label: String) -> void:
	OS.set_environment("SANDBOX_DM17_SPARSE_BLOCK", "0")
	OS.set_environment("SANDBOX_DM17_SHARED_LATTICE", "0")
	var baseline := B4.new()
	var ok_base := baseline.generate_chunk(424242, region, coord, snapshot, cave, true)
	_check(ok_base, label + " baseline generation")
	if not ok_base:
		return
	var mesh_base: Dictionary = baseline.build_chunk_canonical_fast(coord)

	OS.set_environment("SANDBOX_DM17_SPARSE_BLOCK", "1")
	OS.set_environment("SANDBOX_DM17_SHARED_LATTICE", "1")
	var candidate := B4.new()
	var ok_candidate := candidate.generate_chunk(424242, region, coord, snapshot, cave, true)
	_check(ok_candidate, label + " optimized generation")
	if not ok_candidate:
		return
	var mesh_candidate: Dictionary = candidate.build_chunk_canonical_fast(coord)
	_check(baseline.nodes == candidate.nodes, label + " exact lattice Q8.8")
	_check(baseline.cell_active == candidate.cell_active, label + " cell activity")
	_check(baseline.cell_vertices == candidate.cell_vertices, label + " cell vertices")
	_check(mesh_base.get("valid", false) == mesh_candidate.get("valid", false),
		label + " topology valid")
	_check(mesh_base.get("positions", PackedVector3Array()) ==
		mesh_candidate.get("positions", PackedVector3Array()), label + " exact positions")
	_check(mesh_base.get("normals", PackedVector3Array()) ==
		mesh_candidate.get("normals", PackedVector3Array()), label + " exact normals")
	_check(candidate.last_dm17_shared_used == expected_shared,
		label + " pristine-only shared lattice")
	blocks += candidate.last_dm17_sparse_blocks
	skipped_cells += candidate.last_dm17_sparse_cells
	if candidate.last_dm17_shared_used:
		if candidate.last_dm17_shared_hit:
			shared_hits += 1
		else:
			shared_builds += 1


func _check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok:
		failed += 1
		push_error("DM17_SPARSE_LATTICE_FAIL: " + reason)
