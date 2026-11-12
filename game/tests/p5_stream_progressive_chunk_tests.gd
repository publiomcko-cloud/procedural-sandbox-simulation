extends SceneTree

const Policy := preload("res://scripts/terrain/terrain_stream_progressive_load_policy.gd")
const Splitter := preload("res://scripts/terrain/terrain_coarse_preview_chunk_splitter.gd")
const PreviewJob := preload("res://scripts/terrain/terrain_coarse_preview_job.gd")
const Grid := preload("res://scripts/terrain/terrain_chunk_grid.gd")
const Field := preload("res://scripts/terrain/sdf_world.gd")

var assertions := 0
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, detail: String) -> void:
	assertions += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + detail)


static func _xz_area(points: PackedVector3Array) -> float:
	var result := 0.0
	for i in range(0, points.size(), 3):
		var a := points[i]
		var b := points[i + 1]
		var c := points[i + 2]
		result += absf((b.x - a.x) * (c.z - a.z) - (b.z - a.z) * (c.x - a.x)) * 0.5
	return result


func _run() -> void:
	var coords := Grid.all_coordinates()
	var ordered := Policy.interior_first(coords, Grid.CHUNK_COUNT_X, Grid.CHUNK_COUNT_Z)
	_check(ordered.size() == coords.size(), "all 16 authoritative chunks retained")
	for coordinate in coords:
		_check(ordered.has(coordinate) and ordered.count(coordinate) == 1,
			"chunk identity kept exactly once")
	for i in range(4):
		var coordinate: Vector2i = ordered[i]
		_check(coordinate.x in [1, 2] and coordinate.y in [1, 2],
			"four interior chunks dispatched before boundary halo")
	for i in range(12, 16):
		var coordinate: Vector2i = ordered[i]
		_check(coordinate.x in [0, 3] and coordinate.y in [0, 3],
			"shared four-region corner chunks remain last")
	var stage := {
		"purpose": "load", "stage_token": 42, "edit_revision": 3,
		"terrain_effect_authority_revision": 7, "meshes": {Vector2i(1, 1): true}
	}
	_check(Policy.eligible(stage, false, false, false, false, false),
		"only unedited LOAD stage is eligible")
	_check(Policy.valid_chunk_publication(stage, Vector2i(1, 1), false, false,
		false, false, false, 3, 7), "revision-matching ready chunk is visible")
	_check(not Policy.valid_chunk_publication(stage, Vector2i(0, 0), false, false,
		false, false, false, 3, 7), "uncompleted chunk never appears as definitive")
	_check(not Policy.valid_chunk_publication(stage, Vector2i(1, 1), false, false,
		false, false, false, 3, 8), "source revision change revokes chunk")
	_check(not Policy.valid_chunk_publication(stage, Vector2i(1, 1), false, false,
		false, false, false, 4, 7), "brush revision change revokes chunk")
	for purpose in ["partial", "full", "edit_transaction"]:
		var other: Dictionary = stage.duplicate()
		other["purpose"] = purpose
		_check(not Policy.eligible(other, false, false, false, false, false),
			"atomic " + purpose + " never publishes individual chunks")
	_check(not Policy.eligible(stage, true, false, false, false, false),
		"active region cannot use transient early stage")
	_check(not Policy.eligible(stage, false, true, false, false, false),
		"global rebuild remains atomic")
	_check(not Policy.eligible(stage, false, false, true, false, false),
		"pending edit remains atomic")
	_check(not Policy.eligible(stage, false, false, false, true, false),
		"historical brush data never enters pristine-only fast path")
	_check(not Policy.eligible(stage, false, false, false, false, true),
		"cave cutaway remains on original publication path")
	var preview := PreviewJob.build_cpu_data(424242, Vector2i(5, 13))
	_check(preview.get("valid", false), "original deterministic coarse preview succeeds")
	if preview.get("valid", false):
		var original: PackedVector3Array = preview["positions"]
		var patches: Dictionary = Splitter.split(preview)
		_check(patches.size() == 16, "one derived patch per chunk")
		var total_area := 0.0
		for coordinate in coords:
			var patch: Dictionary = patches.get(coordinate, {})
			var positions: PackedVector3Array = patch.get("positions", PackedVector3Array())
			var normals: PackedVector3Array = patch.get("normals", PackedVector3Array())
			_check(positions.size() > 0 and positions.size() == normals.size()
				and positions.size() % 3 == 0, "valid, nonempty, flattened patch")
			var origin := Grid.origin_for(coordinate)
			var size := Grid.size_for(coordinate)
			for vertex in positions:
				_check(vertex.is_finite() and vertex.x >= origin.x - 0.0001
					and vertex.x <= origin.x + size.x + 0.0001
					and vertex.z >= origin.z - 0.0001
					and vertex.z <= origin.z + size.z + 0.0001,
					"patch vertex never extends into an adjacent chunk")
			total_area += _xz_area(positions)
		_check(absf(total_area - _xz_area(original)) < 0.0001,
			"cropped patches have exactly the same total projected surface coverage")
		var mesh := PreviewJob.mesh_from_cpu_data(patches[Vector2i(1, 1)])
		_check(mesh.get_surface_count() == 1, "main thread can upload cropped patch")
	var job := PreviewJob.new(424242, Vector2i(5, 13), 11, 0, 6, Field.GENERATOR_VERSION, true)
	job.run()
	_check(job.result.get("valid", false) and (job.result.get("chunk_patches", {}) as Dictionary).size() == 16,
		"worker builds derived patch arrays without scene mutation")
	if failures == 0:
		print("P5_PROGRESSIVE_E7_POLICY_PASS: assertions=" + str(assertions) + " failures=0")
		quit(0)
	else:
		push_error("P5_PROGRESSIVE_E7_POLICY_FAIL: assertions=" + str(assertions) + " failures=" + str(failures))
		quit(1)
