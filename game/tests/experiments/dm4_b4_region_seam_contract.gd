extends SceneTree

## DM4 seam regression. The visual halo MUST use the identical Q8.8
## field, Surface Nets samples and 16 chunk ownership as canonical B4.
const B4 := preload("res://scripts/experiments/discrete_surface_nets_backend.gd")
const ShellJob := preload("res://scripts/experiments/b4_region_visual_job.gd")
const Grid := preload("res://scripts/terrain/terrain_chunk_grid.gd")
const SEED := 424242
const EPSILON := 0.00002

var checks := 0
var failures := 0
var compared_chunk_vertices := 0
var compared_halo_vertices := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var origin := Vector2i(2,-3)
	var right := origin + Vector2i.RIGHT
	var below := origin + Vector2i.DOWN
	var shell := ShellJob.build_data(SEED, origin, 0)
	_check(bool(shell.get("valid", false)), "visual HIGH generation")
	_check(String(shell.get("backend", "")) == "b4_surface_nets", "same mesher")
	_check(float(shell.get("step", -1.0)) == Grid.SAMPLE_STEP, "same sample spacing")
	var positions: PackedVector3Array = shell.get("positions", PackedVector3Array())
	var normals: PackedVector3Array = shell.get("normals", PackedVector3Array())
	_check(positions.size() == normals.size() and not positions.is_empty(), "full mesh arrays valid")
	# Compare the actual visual aggregate with canonical per-chunk B4 mesh
	# for every face/corner; no resampling, simplification or re-triangulation.
	var offset := 0
	var total := 0
	for coordinate in Grid.all_coordinates():
		var count := int(shell.get("chunk_triangle_counts", {}).get(coordinate,-1))*3
		_check(count >= 0, "all sixteen chunks accounted for")
		var canonical := B4.new()
		_check(canonical.generate_chunk(SEED,origin,coordinate,{},false),
			"canonical pristine per-chunk materialization")
		var reference: Dictionary = canonical.build_chunk(coordinate)
		_check(bool(reference.get("valid", false)), "canonical chunk mesh valid")
		var reference_pos: PackedVector3Array = reference["positions"]
		var reference_norm: PackedVector3Array = reference["normals"]
		_check(reference_pos.size() == count, "same triangle ownership/count")
		if reference_pos.size() == count and offset + count <= positions.size():
			var mesh_origin := Grid.origin_for(coordinate)
			for i in range(count):
				var expected: Vector3 = reference_pos[i] + mesh_origin
				var actual: Vector3 = positions[offset+i]
				_check(actual.distance_to(expected) <= EPSILON,
					"exact canonical triangle vertex")
				_check(normals[offset+i].distance_to(reference_norm[i]) <= EPSILON,
					"same canonical normal/winding")
				compared_chunk_vertices += count
		offset += maxi(count,0)
		total += int(reference.get("triangle_count",0))
	_check(offset == positions.size(), "aggregate contains all canonical triangles")
	_check(total == int(shell.get("triangle_count",-1)), "aggregate triangle sum")
	# Cross-region halo cells are a seam invariant independent of topology
	# edge ownership. Both adjacent regions must compute identical world
	# positions for the SAME two layers of cells straddling the boundary.
	var a := B4.new()
	var b := B4.new()
	var d := B4.new()
	_check(a.generate(SEED, origin, Grid.SAMPLE_STEP), "full left region")
	_check(b.generate(SEED, right, Grid.SAMPLE_STEP), "full right region")
	_check(d.generate(SEED, below, Grid.SAMPLE_STEP), "full down region")
	for global_x in [Grid.CELL_COUNT_X-1, Grid.CELL_COUNT_X]:
		var local_b: int = int(global_x) - Grid.CELL_COUNT_X
		for y in range(-1, Grid.CELL_COUNT_Y+1):
			for z in range(-1, Grid.CELL_COUNT_Z+1):
				_compare_halo(a,Vector3.ZERO,Vector3i(global_x,y,z),
					b,Vector3(16.0,0.0,0.0),Vector3i(local_b,y,z))
	for global_z in [Grid.CELL_COUNT_Z-1, Grid.CELL_COUNT_Z]:
		var local_d: int = int(global_z) - Grid.CELL_COUNT_Z
		for y in range(-1, Grid.CELL_COUNT_Y+1):
			for x in range(-1, Grid.CELL_COUNT_X+1):
				_compare_halo(a,Vector3.ZERO,Vector3i(x,y,global_z),
					d,Vector3(0.0,0.0,12.0),Vector3i(x,y,local_d))
	print("DM4_SEAM_RESULT=" + JSON.stringify({
		"checks":checks,"failures":failures,
		"canonical_chunk_vertices_compared":compared_chunk_vertices,
		"adjacent_halo_cells_compared":compared_halo_vertices,
		"mesh_triangles":int(shell.get("triangle_count",0)),
		"seam_epsilon_m":EPSILON,
	}))
	print("DM4_SEAM_%s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)


func _compare_halo(
	left: RefCounted,left_offset:Vector3,left_cell:Vector3i,
	right:RefCounted,right_offset:Vector3,right_cell:Vector3i
) -> void:
	var ia: int = int(left._cell_index(left_cell.x,left_cell.y,left_cell.z))
	var ib: int = int(right._cell_index(right_cell.x,right_cell.y,right_cell.z))
	var active_a := int(left.cell_active[ia])
	var active_b := int(right.cell_active[ib])
	_check(active_a == active_b, "adjacent overlapping cell occupancy matches")
	if active_a == 1 and active_b == 1:
		var p:Vector3 = left.cell_vertices[ia] + left_offset
		var q:Vector3 = right.cell_vertices[ib] + right_offset
		_check(p.distance_to(q) <= EPSILON, "adjacent cell world-space vertex matches")
		compared_halo_vertices += 1


func _check(ok:bool,what:String) -> void:
	checks += 1
	if not ok:
		failures += 1
		if failures <= 20:
			push_error("DM4_SEAM_MISMATCH: "+what)
