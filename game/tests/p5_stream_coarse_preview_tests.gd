extends SceneTree

const Job := preload("res://scripts/terrain/terrain_coarse_preview_job.gd")
const Policy := preload("res://scripts/terrain/terrain_coarse_preview_policy.gd")
const Field := preload("res://scripts/terrain/sdf_world.gd")

var assertions := 0
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, name: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + name)


func _run() -> void:
	var focus := Vector2i(5, 13)
	var stage := {
		"region_key": focus, "stage_token": 11, "purpose": "load",
		"edit_revision": 0, "terrain_effect_authority_revision": 6,
	}
	var record := {
		"region_key": focus, "stage_token": 11, "seed": 424242,
		"edit_revision": 0, "effect_revision": 6,
		"generator_version": Field.GENERATOR_VERSION,
	}
	_check(Policy.eligible_stage("adaptive-skip-coarse-ready", stage, false, false, false, false, false),
		"ready-cache keeps the same coarse preview eligibility and visual authority")
	_check(Policy.eligible_stage("adaptive-skip-coarse", stage, false, false, false, false, false),
		"opt-in pristine LOAD stage is eligible")
	for legacy in ["baseline", "adaptive", "adaptive-skip", "adaptive-skip-lookahead"]:
		_check(not Policy.eligible_stage(legacy, stage, false, false, false, false, false),
			"legacy streaming profile unchanged " + legacy)
	_check(not Policy.eligible_stage("adaptive-skip-coarse", stage, true, false, false, false, false),
		"active region forbids overlay")
	_check(not Policy.eligible_stage("adaptive-skip-coarse", stage, false, true, false, false, false),
		"global rebuild forbids overlay")
	_check(not Policy.eligible_stage("adaptive-skip-coarse", stage, false, false, true, false, false),
		"edit transaction forbids overlay")
	_check(not Policy.eligible_stage("adaptive-skip-coarse", stage, false, false, false, true, false),
		"historical brush edits forbid base-only approximation")
	_check(not Policy.eligible_stage("adaptive-skip-coarse", stage, false, false, false, false, true),
		"cave cutaway forbids top-only approximation")
	var current := Policy.revision_matches(
		stage, record, 424242, Field.GENERATOR_VERSION, 0, 6,
		focus, false, false, false, false, false
	)
	_check(current, "matching revision and stage token permits provisional view")
	for field in ["stage_token", "seed", "edit_revision", "effect_revision", "generator_version"]:
		var stale := record.duplicate()
		stale[field] = int(record[field]) + 1
		_check(not Policy.revision_matches(stage, stale, 424242, Field.GENERATOR_VERSION,
			0, 6, focus, false, false, false, false, false),
			"stale preview is rejected for " + field)
	_check(not Policy.revision_matches(stage, record, 424242, Field.GENERATOR_VERSION,
		1, 6, focus, false, false, false, false, false), "brush revision advance rejects stale view")
	_check(not Policy.revision_matches(stage, record, 424242, Field.GENERATOR_VERSION,
		0, 7, focus, false, false, false, false, false), "effect revision advance rejects stale view")
	_check(not Policy.revision_matches(stage, record, 424242, Field.GENERATOR_VERSION,
		0, 6, Vector2i(8, 13), false, false, false, false, false),
		"moving beyond the visible window discards old preview")
	var job := Job.new(424242, focus, 11, 0, 6, Field.GENERATOR_VERSION)
	job.run()
	var result: Dictionary = job.result
	_check(result.get("valid", false), "pristine heightfield CPU mesh succeeds")
	_check(int(result.get("triangle_count", -1)) == 96, "preview uses bounded 96 triangles")
	_check(int(result.get("vertex_count", -1)) == 288, "preview uses bounded 288 vertices")
	var positions: PackedVector3Array = result.get("positions", PackedVector3Array())
	var normals: PackedVector3Array = result.get("normals", PackedVector3Array())
	_check(normals.size() == positions.size(), "each vertex has a normal")
	var winding_ok := true
	var finite_ok := true
	for v in positions:
		if not v.is_finite() or v.x < 0.0 or v.x > 16.0 or v.z < 0.0 or v.z > 12.0:
			finite_ok = false
	for n in normals:
		if not n.is_finite() or n.y <= 0.0:
			winding_ok = false
	_check(finite_ok and winding_ok, "preview vertices are finite, bounded and upward oriented")
	var second := Job.build_cpu_data(424242, focus)
	_check(second.get("positions", PackedVector3Array()) == positions,
		"same seed and region yield deterministic preview geometry")
	var neighbor := Job.build_cpu_data(424242, focus + Vector2i(1, 0))
	var other: PackedVector3Array = neighbor.get("positions", PackedVector3Array())
	var edge_equal := true
	for v in positions:
		if absf(v.x - 16.0) < 0.001:
			var matching := false
			for n in other:
				if absf(n.x) < 0.001 and absf(n.z - v.z) < 0.001 and absf(n.y - v.y) < 0.001:
					matching = true
			if not matching:
				edge_equal = false
	_check(edge_equal, "adjacent pristine previews share continuous seam heights")
	var mesh: ArrayMesh = Job.mesh_from_cpu_data(result)
	_check(mesh.get_surface_count() == 1, "main thread can upload preview surface")
	if failures == 0:
		print("P5_STREAM_COARSE_PREVIEW_PASS: assertions=%d failures=0" % assertions)
		quit(0)
	else:
		push_error("P5_STREAM_COARSE_PREVIEW_FAIL: assertions=%d failures=%d" % [assertions, failures])
		quit(1)
