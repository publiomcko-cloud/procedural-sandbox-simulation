extends SceneTree

## Exact immutable canonical B4 snapshot geometry contract:
## pristine, positive/negative regions, brush, cave, materialized tiles,
## and validated terrain-object-effect frames. Not tolerance-based.
const Grid := preload("res://scripts/terrain/terrain_chunk_grid.gd")
const Field := preload("res://scripts/terrain/sdf_world.gd")
const Brush := preload("res://scripts/terrain/sdf_brush_edit_state.gd")
const B4 := preload("res://scripts/experiments/discrete_surface_nets_backend.gd")
const Effect := preload("res://scripts/terrain/terrain_object_effect_local_frame.gd")

var checks := 0
var fails := 0
var metrics: Array[Dictionary] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var effect := _validated_test_effect()
	_check(not effect.is_empty(), "effect frame validates")
	for region in [Vector2i.ZERO, Vector2i(-3, 4)]:
		for coord in [Vector2i(0, 0), Vector2i(1, 1), Vector2i(3, 3)]:
			var ledger := Brush.new(424242, Field.GENERATOR_VERSION)
			var pristine := ledger.get_meshing_snapshot_for_chunk(region, coord)
			_compare(424242, region, coord, pristine, false, "pristine")
			_compare(741, region, coord, pristine, true, "cave")
			var center := Vector3(
				float(region.x) * Field.REGION_SIZE_X + float(coord.x) * 4.0 + 2.0,
				2.5,
				float(region.y) * Field.REGION_SIZE_Z + float(coord.y) * 3.0 + 1.5
			)
			_check(ledger.add_sphere(0, center, 0.9), "valid carve")
			_check(ledger.add_sphere(1, center + Vector3(0.4, -0.5, 0.2), 1.15),
				"valid fill")
			var edited := ledger.get_meshing_snapshot_for_chunk(region, coord)
			_compare(424242, region, coord, edited, false, "brush")
			var effect_snap := edited.duplicate(true)
			effect_snap["terrain_object_effect_frames"] = [effect]
			_compare(424242, region, coord, effect_snap, false, "brush_effect")
			var tile_snap := edited.duplicate(true)
			var origin := Vector3(
				float(region.x) * Field.REGION_SIZE_X + float(coord.x) * 4.0,
				1.0,
				float(region.y) * Field.REGION_SIZE_Z + float(coord.y) * 3.0
			)
			var vals := PackedFloat64Array()
			vals.resize(5 * 5 * 5)
			vals.fill(-0.375)
			var tile := {
				"origin_world": origin, "dims": Vector3i(5, 5, 5),
				"step": Grid.SAMPLE_STEP, "values": vals,
			}
			tile_snap["materialized_tiles"] = [tile]
			tile_snap["materialized_tile_index"] = Brush.build_materialized_tile_index([tile])
			_compare(424242, region, coord, tile_snap, false, "brush_materialized")
	var base_ms := 0.0
	var fast_ms := 0.0
	for receipt in metrics:
		base_ms += float(receipt["baseline_ms"])
		fast_ms += float(receipt["optimized_ms"])
	print("DM11_CANONICAL_PARITY_RESULT=" + JSON.stringify({
		"checks": checks, "failures": fails, "cases": metrics.size(),
		"all_lattice_and_mesh_exact": fails == 0,
		"baseline_total_ms": base_ms, "optimized_total_ms": fast_ms,
		"speedup": base_ms / maxf(0.001, fast_ms)
	}))
	print("DM11_CANONICAL_PARITY_%s" % ("PASS" if fails == 0 else "FAIL"))
	quit(0 if fails == 0 else 1)


func _compare(
	seed: int, region: Vector2i, coord: Vector2i,
	snapshot: Dictionary, cave: bool, label: String
) -> void:
	_check(bool(snapshot.get("valid", false)), label + " snapshot")
	var original := B4.new()
	var optimized := B4.new()
	var t0 := Time.get_ticks_usec()
	var old_ok := original.generate_chunk(seed, region, coord, snapshot, cave, false)
	if not _check(old_ok, label + " original generation"):
		return
	var old_mesh: Dictionary = original.build_chunk(coord)
	var old_usec := Time.get_ticks_usec() - t0
	var t1 := Time.get_ticks_usec()
	var new_ok := optimized.generate_chunk(seed, region, coord, snapshot, cave, true)
	if not _check(new_ok, label + " optimized generation"):
		return
	var new_mesh: Dictionary = optimized.build_chunk_canonical_fast(coord)
	var new_usec := Time.get_ticks_usec() - t1
	_check(original.nodes == optimized.nodes, label + " exact Q8.8 nodes")
	_check(original.cell_active == optimized.cell_active, label + " exact active cells")
	_check(original.cell_vertices == optimized.cell_vertices, label + " exact cell vertices")
	_check(old_mesh.get("valid", false) == new_mesh.get("valid", false),
		label + " exact valid")
	_check(old_mesh.get("skipped_faces", -1) == new_mesh.get("skipped_faces", -2),
		label + " exact skipped")
	_check(old_mesh.get("positions", PackedVector3Array()) ==
		new_mesh.get("positions", PackedVector3Array()), label + " exact mesh positions")
	_check(old_mesh.get("normals", PackedVector3Array()) ==
		new_mesh.get("normals", PackedVector3Array()), label + " exact mesh normals")
	_check(old_mesh.get("sample_count", -1) == new_mesh.get("sample_count", -2),
		label + " exact sampling sites")
	_check(optimized.last_canonical_fast_sdf == (label == "pristine"),
		label + " pristine cache only; never bypass authoritative modifications")
	var receipt := {
		"label": label, "seed": seed, "region": [region.x, region.y],
		"chunk": [coord.x, coord.y],
		"baseline_ms": float(old_usec) / 1000.0,
		"optimized_ms": float(new_usec) / 1000.0,
		"optimized_sampling_ms": float(optimized.last_canonical_sample_usec) / 1000.0,
		"optimized_cell_ms": float(optimized.last_canonical_cell_usec) / 1000.0,
		"uniform_cells_skipped": optimized.last_canonical_uniform_cells,
	}
	metrics.append(receipt)
	print("DM11_CANONICAL_PARITY_CASE=" + JSON.stringify(receipt))


func _validated_test_effect() -> Dictionary:
	var frame := {
		"schema_version": 1,
		"type": Effect.FRAME_TYPE,
		"effect_id": "dm11-test",
		"source_instance_id": "dm11-instance",
		"source_revision": 1,
		"source_fingerprint_sha256": "a".repeat(64),
		"source_region_key": [0, 0],
		"blend_radius_mm": 300,
		"local_planes": [{"normal": [0.0, 1.0, 0.0], "distance_m": 2.5}],
		"bounds_min_local": [0.0, 0.0, 0.0],
		"bounds_max_local": [4.0, 5.0, 3.0],
		"interior_point_local": [2.0, 2.0, 1.5],
		"frame_sha256": "",
	}
	frame["frame_sha256"] = JSON.stringify(frame, "", true, true).sha256_text()
	var normalized := Effect.validate_frame(frame)
	_check(bool(normalized.get("ok", false)), "effect normalized and digest")
	return normalized.get("frame", {})


func _check(value: bool, reason: String) -> bool:
	checks += 1
	if not value:
		fails += 1
		push_error("DM11_CANONICAL_FAIL: " + reason)
	return value
