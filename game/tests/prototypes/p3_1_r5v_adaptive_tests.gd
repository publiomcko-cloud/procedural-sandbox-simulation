extends SceneTree

const Brush := preload("res://scripts/terrain/sdf_brush_edit_state.gd")
const Field := preload("res://scripts/terrain/sdf_world.gd")
const Spatial := preload("res://scripts/terrain/terrain_spatial_ownership.gd")
const Grid := preload("res://scripts/terrain/terrain_chunk_grid.gd")
const Mesher := preload("res://scripts/terrain/marching_tetrahedra.gd")
const Picker := preload("res://scripts/terrain/terrain_brush_picker.gd")
const Adaptive := preload("res://tests/prototypes/r5_adaptive_voxel_snapshot.gd")
const Uniform := preload("res://tests/prototypes/r4_voxel_snapshot.gd")

const SEED := 131102026
var _assertions := 0
var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var started := Time.get_ticks_usec()
	var count := int(OS.get_environment("R5V_COUNT"))
	if count != 0 and count != 256 and count != 640 and count != 2048 and count != 8192:
		count = 256
	var layout := OS.get_environment("R5V_LAYOUT").to_upper()
	if layout != "DISTRIBUTED":
		layout = "CONCENTRATED"
	var region := Vector2i.ZERO if layout == "CONCENTRATED" else Vector2i(-31, -64)
	var chunk := Vector2i.ZERO if layout == "CONCENTRATED" else Vector2i(2, 2)
	var fixture := "res://tests/fixtures/p3_1_r4/issue131/P31.EDIT.%s.N%04d.v1.R01.commands.json" % [layout, count]
	var bytes := FileAccess.get_file_as_bytes(fixture)
	_check(not bytes.is_empty(), "frozen_fixture_present")
	var commands: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	_check(typeof(commands) == TYPE_ARRAY and (commands as Array).size() == count, "frozen_fixture_count")
	var ledger: RefCounted = Brush.new(SEED, 1)
	if typeof(commands) == TYPE_ARRAY:
		for index in range((commands as Array).size()):
			var command: Dictionary = commands[index]
			var mm: Array = command.center_mm
			var center := Vector3(float(mm[0]), float(mm[1]), float(mm[2])) / 1000.0
			var mode := Brush.Mode.CARVE if String(command.mode) == "CARVE" else Brush.Mode.FILL
			_check(ledger.add_sphere(mode, center, float(command.radius_mm) / 1000.0), "ledger_append_%d" % index)
	var full: Dictionary = ledger.get_meshing_snapshot()
	var probe_snapshot: Dictionary = ledger.get_meshing_snapshot()
	var build_times := {}
	var adaptive_025 := _build_adaptive(ledger, region, chunk, 0.25, build_times)
	var adaptive_0125 := _build_adaptive(ledger, region, chunk, 0.125, build_times)
	_check(adaptive_025 != null and adaptive_0125 != null, "adaptive_materialization")
	if adaptive_025 == null or adaptive_0125 == null:
		_finish(started)
		return
	var probe_errors := PackedFloat64Array()
	for index in range(512):
		var local := _probe_local(region, chunk, index)
		var world := Spatial.region_origin_world(region) + local
		var expected := Brush.sample_density_snapshot(SEED, region, local, false, full)
		var actual: float = adaptive_0125.sample_world(world)
		probe_errors.append(absf(expected - actual))
	_check(_all_finite(probe_errors), "adaptive_density_probes_finite")
	var seam_result := _check_adaptive_macro_seams(adaptive_0125)
	_check(int(seam_result.get("checked_interfaces", 0)) > 0, "adaptive_refined_coarse_interfaces_tested")
	_check(int(seam_result.get("mismatches", -1)) == 0, "adaptive_macro_face_c0_continuity")
	var canonical_mesh_started := Time.get_ticks_usec()
	var canonical_mesh: Dictionary = Mesher.build_chunk_cpu_data(SEED, region, chunk, false, full)
	var canonical_mesh_usec := Time.get_ticks_usec() - canonical_mesh_started
	var adaptive_callback := func(point: Vector3) -> float: return adaptive_0125.sample_world(point)
	var adaptive_mesh_started := Time.get_ticks_usec()
	var adaptive_mesh: Dictionary = Mesher.build_chunk_cpu_data(SEED, region, chunk, false, {}, adaptive_callback)
	var adaptive_mesh_usec := Time.get_ticks_usec() - adaptive_mesh_started
	_check(bool(canonical_mesh.get("valid", false)) and bool(adaptive_mesh.get("valid", false)), "adaptive_meshes_valid")
	var surface_error := _surface_metrics(canonical_mesh, adaptive_mesh)
	_check(bool(surface_error.get("valid", false)), "adaptive_surface_error_measured")
	var picker_result := _picker_compare(region, chunk, probe_snapshot, adaptive_0125)
	_check(int(picker_result.get("mismatch_count", -1)) == 0, "adaptive_picker_hit_agreement")
	var cave_result: Dictionary = _cave_connectivity_control() if count == 0 else {
		"status": "NOT_RUN_IN_EDIT_WORKLOAD", "separate_zero_edit_control": "P31.R5V.CONCENTRATED.N0000.v1"}
	if count == 0:
		_check(int(cave_result.get("centerline_samples", 0)) > 0, "canonical_cave_samples_present")
		_check(int(cave_result.get("canonical_open_samples", 0)) == int(cave_result.get("centerline_samples", -1)),
			"canonical_tunnel_centerline_open")
		_check(int(cave_result.get("adaptive_open_samples", 0)) == int(cave_result.get("centerline_samples", -1)),
			"adaptive_tunnel_centerline_connectivity")
	var revisit := Adaptive.new()
	var revisit_started := Time.get_ticks_usec()
	var revisit_ok: bool = revisit.materialize(SEED, region, chunk, probe_snapshot, 0.125)
	var revisit_usec := Time.get_ticks_usec() - revisit_started
	_check(revisit_ok and revisit.digest() == adaptive_0125.digest(), "adaptive_deterministic_restart_rebuild")
	var storage_root := ProjectSettings.globalize_path("user://p31-r5v-%d" % Time.get_ticks_usec())
	var saved: Dictionary = adaptive_0125.save_atomic(storage_root)
	_check(bool(saved.get("valid", false)), "adaptive_atomic_snapshot_save")
	var reload_started := Time.get_ticks_usec()
	var deserialized: RefCounted = Adaptive.new()
	var reload_ok: bool = deserialized.load_file(String(saved.get("path", "")), adaptive_0125.digest())
	var reload_usec := Time.get_ticks_usec() - reload_started
	_check(reload_ok and deserialized.digest() == adaptive_0125.digest(), "adaptive_snapshot_reload_integrity")
	var corruption_path := storage_root.path_join("corrupt.r5v")
	var original_bytes := FileAccess.get_file_as_bytes(String(saved.get("path", "")))
	var corruption_file := FileAccess.open(corruption_path, FileAccess.WRITE)
	if corruption_file != null:
		if not original_bytes.is_empty(): original_bytes[original_bytes.size() - 1] = original_bytes[original_bytes.size() - 1] ^ 0x20
		corruption_file.store_buffer(original_bytes)
		corruption_file.close()
	var corrupt_loader: RefCounted = Adaptive.new()
	var corrupt_rejected: bool = corruption_file != null and not corrupt_loader.load_file(corruption_path, adaptive_0125.digest())
	_check(corrupt_rejected, "adaptive_corruption_fails_closed")
	var result := {"status": "FAIL" if not _failures.is_empty() else "PASS",
		"scenario": "P31.R5V.%s.N%04d.v1" % [layout, count],
		"source_baseline": "92b442d7f5b605c7bc9c48fac2aceea9d71813aa",
		"inherited_r4_head": "051249642611a7fa9cd2006be450bad0e184e4ee",
		"scenario_fixture_sha256": _sha256(bytes), "operation_count": count,
		"build_usec": build_times, "adaptive_0125": adaptive_0125.statistics(),
		"adaptive_025": adaptive_025.statistics(), "density_abs_error": _summary(probe_errors),
		"surface_error": surface_error, "canonical_lod0_usec": canonical_mesh_usec,
		"adaptive_lod0_usec": adaptive_mesh_usec, "macro_seam": seam_result,
		"picker": picker_result, "cave_connectivity": cave_result, "restart_rebuild_usec": revisit_usec,
		"restart_digest_match": revisit.digest() == adaptive_0125.digest(),
		"serialized_reload_usec": reload_usec, "snapshot_bytes": int(adaptive_0125.statistics().serialized_payload_bytes),
		"snapshot_envelope_bytes_written": int(saved.get("bytes_written", 0)),
		"corruption_rejected": corrupt_rejected,
		"collision": {"status": "NOT_MEASURED", "reason": "no production collision provider"},
		"failures": _failures, "assertions": _assertions,
		"timing_note": "headless CPU only; surface metric is sampled vertex-to-triangle, not certified Hausdorff; no owner geometry tolerance"}
	_finish(started, result)


func _build_adaptive(ledger: RefCounted, region: Vector2i, chunk: Vector2i, spacing: float,
		build_times: Dictionary) -> RefCounted:
	var candidate := Adaptive.new()
	var snapshot: Dictionary = ledger.get_meshing_snapshot()
	var ok: bool = candidate.materialize(SEED, region, chunk, snapshot, spacing)
	build_times[String.num(spacing, 3)] = candidate.build_usec
	_check(ok, "adaptive_%s_build" % String.num(spacing, 3))
	return candidate if ok else null


func _check_adaptive_macro_seams(candidate: RefCounted) -> Dictionary:
	var interfaces := 0
	var mismatches := 0
	var maximum_error := 0.0
	var dimensions := Vector3i(candidate.base.nx - 1, candidate.base.ny - 1, candidate.base.nz - 1)
	for y in range(dimensions.y):
		for z in range(dimensions.z):
			for x in range(dimensions.x):
				var current_key: int = candidate._macro_key(x, y, z)
				for axis in [Vector3i(1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, 0, 1)]:
					var next_cell: Vector3i = Vector3i(x, y, z) + axis
					if next_cell.x >= dimensions.x or next_cell.y >= dimensions.y or next_cell.z >= dimensions.z:
						continue
					var next_key: int = candidate._macro_key(next_cell.x, next_cell.y, next_cell.z)
					if not candidate.refined_cells.has(current_key) and not candidate.refined_cells.has(next_key):
						continue
					for a in range(3):
						for b in range(3):
							var point_grid := Vector3(x, y, z)
							if axis.x == 1: point_grid += Vector3(1.0, float(a) / 2.0, float(b) / 2.0)
							elif axis.y == 1: point_grid += Vector3(float(a) / 2.0, 1.0, float(b) / 2.0)
							else: point_grid += Vector3(float(a) / 2.0, float(b) / 2.0, 1.0)
							var point: Vector3 = candidate.base.world_min + point_grid * 0.5
							var left: float = candidate.sample_world_in_macro_cell(point, Vector3i(x, y, z))
							var right: float = candidate.sample_world_in_macro_cell(point, next_cell)
							var error := absf(left - right)
							maximum_error = maxf(maximum_error, error)
							interfaces += 1
							if error > 0.00001: mismatches += 1
	return {"checked_interfaces": interfaces, "mismatches": mismatches, "maximum_absolute_density_gap": maximum_error}


func _picker_compare(region: Vector2i, chunk: Vector2i, snapshot: Dictionary, candidate: RefCounted) -> Dictionary:
	var origin: Vector3 = Spatial.region_origin_world(region) + Grid.origin_for(chunk)
	var size: Vector3 = Grid.size_for(chunk)
	var outcomes: Array[Dictionary] = []
	var mismatch := 0
	for index in range(3):
		var x := origin.x + size.x * (0.2 + float(index) * 0.25)
		var z := origin.z + size.z * (0.22 + float(index) * 0.2)
		var ray_origin := Vector3(x, Grid.MAX_BOUND.y + Grid.SAMPLE_STEP * 0.2, z)
		var exact_sampler := func(point: Vector3) -> float:
			var mapped: Dictionary = Spatial.world_to_region_local(point)
			return Brush.sample_density_snapshot(SEED, mapped.region_key, mapped.local_position, false, snapshot)
		var candidate_sampler := func(point: Vector3) -> float: return candidate.sample_world(point)
		var exact: Dictionary = Picker.pick_sdf_v1_surface(ray_origin, Vector3.DOWN, exact_sampler)
		var approx: Dictionary = Picker.pick_sdf_v1_surface(ray_origin, Vector3.DOWN, candidate_sampler)
		var matches := bool(exact.get("hit", false)) == bool(approx.get("hit", false))
		var distance_error := INF
		if matches and bool(exact.get("hit", false)):
			distance_error = exact.position.distance_to(approx.position)
			if distance_error > 0.02: matches = false
		if not matches: mismatch += 1
		outcomes.append({"exact_hit": exact.get("hit", false), "adaptive_hit": approx.get("hit", false),
			"position_error": distance_error})
	return {"ray_count": outcomes.size(), "mismatch_count": mismatch, "outcomes": outcomes,
		"comparison_tolerance_world_units": 0.02, "tolerance_status": "EXPLORATORY_NOT_OWNER_APPROVED"}


func _cave_connectivity_control() -> Dictionary:
	var region := Vector2i.ZERO
	var ledger: RefCounted = Brush.new(SEED, 1)
	var snapshot: Dictionary = ledger.get_meshing_snapshot()
	var fields := {}
	var chunks_built := 0
	for x_chunk in range(4):
		for z_chunk in [1, 2]:
			var candidate: RefCounted = Adaptive.new()
			if candidate.materialize(SEED, region, Vector2i(x_chunk, z_chunk), snapshot, 0.125):
				fields[Vector2i(x_chunk, z_chunk)] = candidate
				chunks_built += 1
	var centerline_count := 0
	var canonical_open := 0
	var adaptive_open := 0
	var canonical_min_diameter := INF
	var adaptive_min_diameter := INF
	var canonical_max_diameter := 0.0
	var adaptive_max_diameter := 0.0
	var maximum_centerline_density_error := 0.0
	var first_centerline_probe: Dictionary = {}
	for step in range(1, 128):
		var world_x := float(step) * 0.125
		var center: Vector2 = Field.cave_center(SEED, region, world_x)
		var world_point := Vector3(world_x, center.y, center.x)
		var chunk_key := Vector2i(clampi(floori(world_x / 4.0), 0, 3), clampi(floori(center.x / 3.0), 1, 2))
		if not fields.has(chunk_key):
			continue
		var local := world_point - Spatial.region_origin_world(region)
		var canonical_center := Brush.sample_density_snapshot(SEED, region, local, false, snapshot)
		var adaptive_center: float = fields[chunk_key].sample_world(world_point)
		if first_centerline_probe.is_empty():
			first_centerline_probe = {"world": [world_point.x, world_point.y, world_point.z],
				"chunk": [chunk_key.x, chunk_key.y], "adaptive": adaptive_center,
				"canonical": canonical_center, "base_world_min": [fields[chunk_key].base.world_min.x,
					fields[chunk_key].base.world_min.y, fields[chunk_key].base.world_min.z]}
		centerline_count += 1
		if canonical_center < 0.0: canonical_open += 1
		if adaptive_center < 0.0: adaptive_open += 1
		maximum_centerline_density_error = maxf(maximum_centerline_density_error, absf(canonical_center - adaptive_center))
		var canonical_diameter := _vertical_open_diameter(region, snapshot, null, world_x, center, false)
		var adaptive_diameter := _vertical_open_diameter(region, snapshot, fields[chunk_key], world_x, center, true)
		canonical_min_diameter = minf(canonical_min_diameter, canonical_diameter)
		adaptive_min_diameter = minf(adaptive_min_diameter, adaptive_diameter)
		canonical_max_diameter = maxf(canonical_max_diameter, canonical_diameter)
		adaptive_max_diameter = maxf(adaptive_max_diameter, adaptive_diameter)
	return {"chunks_built": chunks_built, "centerline_samples": centerline_count,
		"canonical_open_samples": canonical_open, "adaptive_open_samples": adaptive_open,
		"canonical_min_vertical_open_diameter_world": canonical_min_diameter,
		"adaptive_min_vertical_open_diameter_world": adaptive_min_diameter,
		"canonical_max_vertical_open_diameter_world": canonical_max_diameter,
		"adaptive_max_vertical_open_diameter_world": adaptive_max_diameter,
		"maximum_centerline_density_error_world": maximum_centerline_density_error,
		"first_centerline_probe": first_centerline_probe,
		"geometry_contract_status": "EXPLORATORY_NOT_OWNER_APPROVED"}


func _vertical_open_diameter(region: Vector2i, snapshot: Dictionary, candidate: RefCounted,
		world_x: float, center: Vector2, use_candidate: bool) -> float:
	var step := 0.0625
	var negative_below := 0
	var negative_above := 0
	for direction in [-1, 1]:
		for index in range(1, 65):
			var point := Vector3(world_x, center.y + float(direction * index) * step, center.x)
			var density: float
			if use_candidate:
				density = candidate.sample_world(point)
			else:
				var mapped: Dictionary = Spatial.world_to_region_local(point)
				density = Brush.sample_density_snapshot(SEED, mapped.region_key, mapped.local_position, false, snapshot)
			if density < 0.0:
				if direction < 0: negative_below += 1
				else: negative_above += 1
			else:
				break
	return float(negative_below + negative_above) * step


func _surface_metrics(reference: Dictionary, candidate: Dictionary) -> Dictionary:
	var rp: PackedVector3Array = reference.get("positions", PackedVector3Array())
	var rn: PackedVector3Array = reference.get("normals", PackedVector3Array())
	var cp: PackedVector3Array = candidate.get("positions", PackedVector3Array())
	var cn: PackedVector3Array = candidate.get("normals", PackedVector3Array())
	if rp.is_empty() or cp.is_empty() or rp.size() % 3 != 0 or cp.size() % 3 != 0:
		return {"valid": false, "reason": "empty_mesh"}
	var distances := PackedFloat64Array()
	var angles := PackedFloat64Array()
	for direction in [0, 1]:
		var source: PackedVector3Array = rp if direction == 0 else cp
		var source_normals: PackedVector3Array = rn if direction == 0 else cn
		var target: PackedVector3Array = cp if direction == 0 else rp
		var target_normals: PackedVector3Array = cn if direction == 0 else rn
		var stride := maxi(1, ceili(float(source.size()) / 128.0))
		for source_index in range(0, source.size(), stride):
			var best := INF
			var best_normal := Vector3.ZERO
			for tri in range(0, target.size(), 3):
				var q := _closest_triangle(source[source_index], target[tri], target[tri + 1], target[tri + 2])
				var d2 := source[source_index].distance_squared_to(q)
				if d2 < best:
					best = d2
					best_normal = (target_normals[tri] + target_normals[tri + 1] + target_normals[tri + 2]).normalized()
			distances.append(sqrt(maxf(0.0, best)))
			angles.append(rad_to_deg(source_normals[source_index].normalized().angle_to(best_normal)))
	return {"valid": true, "sampled_symmetric_vertex_to_triangle_distance_world": _summary(distances),
		"sampled_normal_angle_degrees": _summary(angles), "reference_vertex_count": rp.size(),
		"candidate_vertex_count": cp.size(), "method": "vertex samples both directions to target triangles; sampled estimate only"}


func _closest_triangle(p: Vector3, a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	var ab := b - a
	var ac := c - a
	var ap := p - a
	var d1 := ab.dot(ap)
	var d2 := ac.dot(ap)
	if d1 <= 0.0 and d2 <= 0.0: return a
	var bp := p - b
	var d3 := ab.dot(bp)
	var d4 := ac.dot(bp)
	if d3 >= 0.0 and d4 <= d3: return b
	var vc := d1 * d4 - d3 * d2
	if vc <= 0.0 and d1 >= 0.0 and d3 <= 0.0: return a + ab * (d1 / (d1 - d3))
	var cp := p - c
	var d5 := ab.dot(cp)
	var d6 := ac.dot(cp)
	if d6 >= 0.0 and d5 <= d6: return c
	var vb := d5 * d2 - d1 * d6
	if vb <= 0.0 and d2 >= 0.0 and d6 <= 0.0: return a + ac * (d2 / (d2 - d6))
	var va := d3 * d6 - d5 * d4
	if va <= 0.0 and d4 - d3 >= 0.0 and d5 - d6 >= 0.0: return b + (c - b) * ((d4 - d3) / ((d4 - d3) + (d5 - d6)))
	var denominator := 1.0 / (va + vb + vc)
	return a + ab * (vb * denominator) + ac * (vc * denominator)


func _probe_local(region: Vector2i, chunk: Vector2i, index: int) -> Vector3:
	var size := Grid.size_for(chunk)
	var origin := Grid.origin_for(chunk)
	return origin + Vector3(0.26 + float(posmod(index * 37, 997)) / 997.0 * (size.x - 0.52),
		Grid.MIN_BOUND.y + 0.3 + float(posmod(index * 71, 983)) / 983.0 * (Grid.MAX_BOUND.y - Grid.MIN_BOUND.y - 0.6),
		0.26 + float(posmod(index * 53, 991)) / 991.0 * (size.z - 0.52))


func _all_finite(values: PackedFloat64Array) -> bool:
	for value in values:
		if not is_finite(value): return false
	return true


func _summary(values: PackedFloat64Array) -> Dictionary:
	var sorted: Array[float] = []
	for value in values: sorted.append(value)
	sorted.sort()
	return {"count": sorted.size(), "p50": _percentile(sorted, 0.5), "p95": _percentile(sorted, 0.95),
		"max": sorted[-1] if not sorted.is_empty() else 0.0}


func _percentile(values: Array[float], q: float) -> float:
	if values.is_empty(): return 0.0
	return values[clampi(ceili(q * values.size()) - 1, 0, values.size() - 1)]


func _check(value: bool, label: String) -> void:
	_assertions += 1
	if not value:
		_failures.append(label)
		push_error("R5V_FAIL " + label)


func _finish(started: int, result: Dictionary = {}) -> void:
	var output := {"assertions": _assertions, "failures": _failures, "duration_usec": Time.get_ticks_usec() - started}
	output.merge(result, true)
	print("P31_R5V_JSON " + JSON.stringify(output))
	print("P31_R5V_TESTS_%s assertions=%d failures=%d" % ["FAIL" if not _failures.is_empty() else "PASS", _assertions, _failures.size()])
	quit(1 if not _failures.is_empty() else 0)


func _sha256(value: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(value)
	return context.finish().hex_encode()
