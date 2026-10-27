extends SceneTree

## Isolated R6 diagnosis for the approximate R5-V field. This script never
## changes production SDF/ledger code and reports measured approximations only.
const Brush := preload("res://scripts/terrain/sdf_brush_edit_state.gd")
const Field := preload("res://scripts/terrain/sdf_world.gd")
const Spatial := preload("res://scripts/terrain/terrain_spatial_ownership.gd")
const Grid := preload("res://scripts/terrain/terrain_chunk_grid.gd")
const Mesher := preload("res://scripts/terrain/marching_tetrahedra.gd")
const LodMesher := preload("res://scripts/terrain/lod01_chunk_mesher.gd")
const Picker := preload("res://scripts/terrain/terrain_brush_picker.gd")
const Adaptive := preload("res://tests/prototypes/r5_adaptive_voxel_snapshot.gd")

const SEED := 131102026
const REGION := Vector2i.ZERO
const VARIANTS := [
	{"id": "A_baseline_coarse_boundary_center_residual", "boundary": "coarse", "refinement": "center"},
	{"id": "B_canonical_refined_boundary_center_residual", "boundary": "canonical", "refinement": "center"},
	{"id": "C_coarse_boundary_face_curvature_residual", "boundary": "coarse", "refinement": "curvature"},
	{"id": "BC_canonical_boundary_plus_curvature_residual", "boundary": "canonical", "refinement": "curvature"},
]
const SCENARIOS := ["zero_edit", "cave_wall_carve", "center_fill_then_wall_carve"]
var _assertions := 0
var _failures: Array[String] = []
var _active_snapshot: Dictionary = {}
var _candidate_canonical_fallback_samples := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var started := Time.get_ticks_usec()
	for scenario in SCENARIOS:
		var ledger: RefCounted = _make_ledger(String(scenario))
		var snapshot: Dictionary = ledger.get_meshing_snapshot()
		_active_snapshot = snapshot
		_candidate_canonical_fallback_samples = 0
		_check(snapshot.size() > 0, "%s_snapshot" % scenario)
		_check(int(snapshot.get("revision", -1)) == int(snapshot.get("centers", PackedVector3Array()).size()),
			"%s_snapshot_revision_matches_edit_count" % scenario)
		for variant in VARIANTS:
			var variant_started := Time.get_ticks_usec()
			var fields := _build_fields(snapshot, variant)
			_check(fields.size() == 16, "%s_%s_all_cave_chunks_built" % [scenario, variant.id])
			if fields.size() != 16:
				continue
			var cross_sections := _cross_section_metrics(fields, snapshot)
			var chunk_seams := _chunk_seam_metrics(fields)
			var macro_seams := _macro_seam_metrics(fields)
			var picker_metrics := _picker_metrics(fields, snapshot)
			var mesh_metrics: Dictionary = {"status": "NOT_RUN_FOR_EDITED_CASE"}
			var mesh_canonical_fallbacks := 0
			if scenario == "zero_edit":
				_candidate_canonical_fallback_samples = 0
				mesh_metrics = _mesh_metrics(fields, snapshot)
				mesh_canonical_fallbacks = _candidate_canonical_fallback_samples
			var stats := _aggregate_stats(fields)
			var record := {"scenario": scenario, "scenario_revision": snapshot.get("revision", -1),
				"scenario_command_count": snapshot.get("centers", PackedVector3Array()).size(),
				"variant": variant.id, "boundary_policy": variant.boundary,
				"refinement_policy": variant.refinement, "seed": SEED,
				"original_canonical_cave_radius_world": 0.92,
				"original_control_vertical_diameter_world": 1.75,
				"geometry_tolerance_status": "EXPLORATORY_NO_OWNER_APPROVED_TOLERANCE",
				"cross_sections": cross_sections, "chunk_interfaces": chunk_seams,
				"within_chunk_refinement_interfaces": macro_seams,
				"ray_picker": picker_metrics, "lod_meshes": mesh_metrics,
			"candidate_mesh_sampler_canonical_fallback_count": mesh_canonical_fallbacks,
				"build": stats, "variant_elapsed_usec": Time.get_ticks_usec() - variant_started,
				"collision_proxy": {"status": "NOT_MEASURED", "reason": "no production collision provider"}}
			print("R6V_CASE " + JSON.stringify(record))
			print("R6V_VARIANT_RESULT scenario=%s variant=%s centerline_open=%d/%d diameter_min_max=%.6f/%.6f seam_gap=%.9f macro_gap=%.9f refined=%d build_ms=%.3f" % [
				String(scenario), String(variant.id), int(cross_sections.centerline_open),
				int(cross_sections.centerline_samples), float(cross_sections.get("diameter_min_world", 0.0)),
				float(cross_sections.get("diameter_max_world", 0.0)),
				float(chunk_seams.get("maximum_density_gap_world", 0.0)),
				float(macro_seams.get("maximum_absolute_density_gap", 0.0)),
				int(stats.refined_cells), float(stats.build_ms)])
	var result := {"status": "FAIL" if not _failures.is_empty() else "PASS",
		"suite": "P3_1_R6V_CAVE_CAUSAL_DIAGNOSTIC", "variant_count": VARIANTS.size(),
		"scenario_count": SCENARIOS.size(), "assertions": _assertions, "failures": _failures,
		"duration_usec": Time.get_ticks_usec() - started,
		"scope_note": "R6 test-only approximate-field diagnosis; no production changes or approved geometry tolerance"}
	print("R6V_RESULT " + JSON.stringify(result))
	quit(1 if not _failures.is_empty() else 0)


func _make_ledger(scenario: String) -> RefCounted:
	var ledger: RefCounted = Brush.new(SEED, Field.GENERATOR_VERSION)
	var cave: Vector2 = Field.cave_center(SEED, REGION, 8.0)
	var center := Vector3(8.0, cave.y, cave.x)
	if scenario == "cave_wall_carve":
		_check(ledger.add_sphere(Brush.Mode.CARVE, center + Vector3(0.0, 0.0, 0.80), 0.58), "wall_carve_accepts")
	elif scenario == "center_fill_then_wall_carve":
		_check(ledger.add_sphere(Brush.Mode.FILL, center, 0.58), "center_fill_accepts")
		_check(ledger.add_sphere(Brush.Mode.CARVE, center + Vector3(0.0, 0.0, 0.82), 0.58), "wall_carve_after_fill_accepts")
	return ledger


func _build_fields(snapshot: Dictionary, variant: Dictionary) -> Dictionary:
	var fields := {}
	for chunk_x in range(4):
		for chunk_z in range(4):
			var key := Vector2i(chunk_x, chunk_z)
			var candidate: RefCounted = Adaptive.new()
			var valid: bool = candidate.materialize(SEED, REGION, key, snapshot, 0.125, 0.02,
				String(variant.boundary), String(variant.refinement))
			_check(valid, "%s_%s_chunk_%d_%d_materializes" % [variant.id, snapshot.get("revision", -1), chunk_x, chunk_z])
			if valid:
				fields[key] = candidate
	return fields


func _cross_section_metrics(fields: Dictionary, snapshot: Dictionary) -> Dictionary:
	var diameters := PackedFloat64Array()
	var normal_angles := PackedFloat64Array()
	var displacement := PackedFloat64Array()
	var canonical_vertical := PackedFloat64Array()
	var candidate_vertical := PackedFloat64Array()
	var centerline_samples := 0
	var centerline_open := 0
	var canonical_open := 0
	var candidate_closed_slices := 0
	var section_areas := PackedFloat64Array()
	var canonical_section_areas := PackedFloat64Array()
	var radial_max_x := NAN
	var radial_max_diameter := 0.0
	var vertical_max_x := NAN
	var vertical_max_diameter := 0.0
	var section_xs := [0.125, 3.875, 4.125, 7.875, 8.125, 11.875, 12.125, 15.875]
	for step in range(1, 128):
		var world_x := float(step) * 0.125
		var center2: Vector2 = Field.cave_center(SEED, REGION, world_x)
		var center := Vector3(world_x, center2.y, center2.x)
		var exact_center := _canonical_sample(center, snapshot)
		var approx_center := _candidate_sample(fields, center)
		centerline_samples += 1
		if exact_center < 0.0: canonical_open += 1
		if approx_center < 0.0:
			centerline_open += 1
			var per_angle := PackedFloat64Array()
			for angle_index in range(16):
				var angle := TAU * float(angle_index) / 16.0
				var direction := Vector3(0.0, sin(angle), cos(angle))
				var exact_radius := _first_zero_radius(center, direction, snapshot, fields, true)
				var candidate_radius := _first_zero_radius(center, direction, snapshot, fields, false)
				if bool(exact_radius.get("valid", false)) and bool(candidate_radius.get("valid", false)):
					per_angle.append(float(candidate_radius.radius))
					displacement.append(absf(float(candidate_radius.radius) - float(exact_radius.radius)))
					var exact_normal := _gradient(center + direction * float(exact_radius.radius), snapshot, fields, true)
					var candidate_normal := _gradient(center + direction * float(candidate_radius.radius), snapshot, fields, false)
					if exact_normal.length_squared() > 0.0 and candidate_normal.length_squared() > 0.0:
						normal_angles.append(rad_to_deg(exact_normal.angle_to(candidate_normal)))
			if per_angle.size() >= 8:
				var slice_diameter := float(_max(per_angle) * 2.0)
				diameters.append(slice_diameter)
				if slice_diameter > radial_max_diameter:
					radial_max_diameter = slice_diameter
					radial_max_x = world_x
			var exact_vertical := _vertical_open_diameter(center, snapshot, fields, true)
			var approx_vertical := _vertical_open_diameter(center, snapshot, fields, false)
			canonical_vertical.append(exact_vertical)
			candidate_vertical.append(approx_vertical)
			if approx_vertical > vertical_max_diameter:
				vertical_max_diameter = approx_vertical
				vertical_max_x = world_x
		else:
			candidate_closed_slices += 1
	for x_value in section_xs:
		var c2: Vector2 = Field.cave_center(SEED, REGION, float(x_value))
		var center := Vector3(float(x_value), c2.y, c2.x)
		var negative_count := 0
		var exact_negative_count := 0
		var total := 0
		for y_index in range(-40, 41):
			for z_index in range(-40, 41):
				var p := center + Vector3(0.0, float(y_index) * 0.0625, float(z_index) * 0.0625)
				if _candidate_sample(fields, p) < 0.0: negative_count += 1
				if _canonical_sample(p, snapshot) < 0.0: exact_negative_count += 1
				total += 1
		section_areas.append(float(negative_count) * 0.0625 * 0.0625)
		canonical_section_areas.append(float(exact_negative_count) * 0.0625 * 0.0625)
	return {"centerline_samples": centerline_samples, "canonical_centerline_open": canonical_open,
		"centerline_open": centerline_open, "candidate_centerline_closed_slices": candidate_closed_slices,
		"cross_section_sample_grid": "81x81 at 0.0625 world unit around seeded centerline at x=%s" % str(section_xs),
		"approx_negative_area_world2": _summary(section_areas),
		"canonical_negative_area_world2": _summary(canonical_section_areas),
		"radial_diameter_world": _summary(diameters), "diameter_min_world": _min(diameters),
		"diameter_max_world": _max(diameters), "radial_diameter_max_at_world_x": radial_max_x,
		"vertical_diameter_candidate_world": _summary(candidate_vertical),
		"vertical_diameter_candidate_max_at_world_x": vertical_max_x,
		"vertical_diameter_canonical_world": _summary(canonical_vertical),
		"radial_surface_displacement_world": _summary(displacement),
		"radial_surface_normal_deviation_degrees": _summary(normal_angles)}


func _first_zero_radius(center: Vector3, direction: Vector3, snapshot: Dictionary,
		fields: Dictionary, canonical: bool) -> Dictionary:
	var previous_radius := 0.0
	var previous_density := _canonical_sample(center, snapshot) if canonical else _candidate_sample(fields, center)
	if previous_density >= 0.0: return {"valid": false, "reason": "center_not_empty"}
	var step := 0.03125
	for index in range(1, 81):
		var radius := float(index) * step
		var point := center + direction * radius
		var density := _canonical_sample(point, snapshot) if canonical else _candidate_sample(fields, point)
		if not is_finite(density): return {"valid": false, "reason": "sample_outside_materialized_chunks"}
		if density >= 0.0:
			var low := previous_radius
			var high := radius
			for _iteration in range(18):
				var middle := (low + high) * 0.5
				var middle_density := _canonical_sample(center + direction * middle, snapshot) if canonical else _candidate_sample(fields, center + direction * middle)
				if middle_density < 0.0: low = middle
				else: high = middle
			return {"valid": true, "radius": (low + high) * 0.5}
		previous_radius = radius
		previous_density = density
	return {"valid": false, "reason": "no_zero_crossing_within_2_5"}


func _vertical_open_diameter(center: Vector3, snapshot: Dictionary, fields: Dictionary, canonical: bool) -> float:
	var step := 0.0625
	var negative_below := 0
	var negative_above := 0
	for direction in [-1, 1]:
		for index in range(1, 65):
			var point := center + Vector3(0.0, float(direction * index) * step, 0.0)
			var density := _canonical_sample(point, snapshot) if canonical else _candidate_sample(fields, point)
			if density < 0.0:
				if direction < 0: negative_below += 1
				else: negative_above += 1
			else: break
	return float(negative_below + negative_above) * step


func _chunk_seam_metrics(fields: Dictionary) -> Dictionary:
	var interfaces := 0
	var mismatches := 0
	var maximum_gap := 0.0
	var maximum_normal_angle := 0.0
	for chunk_x in range(3):
		for chunk_z in range(4):
			var left: RefCounted = fields[Vector2i(chunk_x, chunk_z)]
			var right: RefCounted = fields[Vector2i(chunk_x + 1, chunk_z)]
			var x := float(chunk_x + 1) * 4.0
			for y_i in range(0, 41):
				for z_i in range(0, 13):
					var point := Vector3(x, Grid.MIN_BOUND.y + float(y_i) * 0.25,
						float(chunk_z) * 3.0 + float(z_i) * 0.25)
					var a: float = left.sample_world(point)
					var b: float = right.sample_world(point)
					if not is_finite(a) or not is_finite(b): continue
					var gap := absf(a - b)
					maximum_gap = maxf(maximum_gap, gap)
					if gap > 0.00001: mismatches += 1
					if absf(a) <= 0.0625 or absf(b) <= 0.0625:
						var left_normal := _gradient_single(left, point)
						var right_normal := _gradient_single(right, point)
						if left_normal.length_squared() > 0.0 and right_normal.length_squared() > 0.0:
							maximum_normal_angle = maxf(maximum_normal_angle, rad_to_deg(left_normal.angle_to(right_normal)))
					interfaces += 1
	for chunk_x in range(4):
		for chunk_z in range(3):
			var low: RefCounted = fields[Vector2i(chunk_x, chunk_z)]
			var high: RefCounted = fields[Vector2i(chunk_x, chunk_z + 1)]
			var z := float(chunk_z + 1) * 3.0
			for y_i in range(0, 41):
				for x_i in range(0, 17):
					var point := Vector3(float(chunk_x) * 4.0 + float(x_i) * 0.25,
						Grid.MIN_BOUND.y + float(y_i) * 0.25, z)
					var a: float = low.sample_world(point)
					var b: float = high.sample_world(point)
					if not is_finite(a) or not is_finite(b): continue
					var gap := absf(a - b)
					maximum_gap = maxf(maximum_gap, gap)
					if gap > 0.00001: mismatches += 1
					if absf(a) <= 0.0625 or absf(b) <= 0.0625:
						var low_normal := _gradient_single(low, point)
						var high_normal := _gradient_single(high, point)
						if low_normal.length_squared() > 0.0 and high_normal.length_squared() > 0.0:
							maximum_normal_angle = maxf(maximum_normal_angle, rad_to_deg(low_normal.angle_to(high_normal)))
					interfaces += 1
	return {"sample_count": interfaces, "density_mismatch_count_gt_1e-5": mismatches,
		"maximum_density_gap_world": maximum_gap,
		"maximum_chunk_face_normal_angle_degrees_near_surface": maximum_normal_angle,
		"interpretation": "identical scalar field on common chunk-face probes is a seam diagnostic, not a full mesh-topology proof"}


func _macro_seam_metrics(fields: Dictionary) -> Dictionary:
	var maximum := 0.0
	var interfaces := 0
	var mismatches := 0
	for key in fields:
		var candidate: RefCounted = fields[key]
		var dims := Vector3i(candidate.base.nx - 1, candidate.base.ny - 1, candidate.base.nz - 1)
		for y in range(dims.y):
			for z in range(dims.z):
				for x in range(dims.x):
					for axis_value in [Vector3i.RIGHT, Vector3i.UP, Vector3i.BACK]:
						var axis: Vector3i = axis_value
						var next_cell: Vector3i = Vector3i(x, y, z) + axis
						if next_cell.x >= dims.x or next_cell.y >= dims.y or next_cell.z >= dims.z: continue
						var a_key: int = candidate._macro_key(x, y, z)
						var b_key: int = candidate._macro_key(next_cell.x, next_cell.y, next_cell.z)
						if not candidate.refined_cells.has(a_key) and not candidate.refined_cells.has(b_key): continue
						for u in range(3):
							for v in range(3):
								var grid_point := Vector3(x, y, z)
								if axis.x != 0: grid_point += Vector3(1.0, float(u) * 0.5, float(v) * 0.5)
								elif axis.y != 0: grid_point += Vector3(float(u) * 0.5, 1.0, float(v) * 0.5)
								else: grid_point += Vector3(float(u) * 0.5, float(v) * 0.5, 1.0)
								var point: Vector3 = candidate.base.world_min + grid_point * 0.5
								var av: float = candidate.sample_world_in_macro_cell(point, Vector3i(x, y, z))
								var bv: float = candidate.sample_world_in_macro_cell(point, next_cell)
								var gap := absf(av - bv)
								maximum = maxf(maximum, gap)
								if gap > 0.00001: mismatches += 1
								interfaces += 1
	return {"checked_interfaces": interfaces, "mismatches_gt_1e-5": mismatches,
		"maximum_absolute_density_gap": maximum}


func _gradient_single(candidate: RefCounted, point: Vector3) -> Vector3:
	var h := 0.01
	var gradient := Vector3(
		candidate.sample_world(point + Vector3.RIGHT * h) - candidate.sample_world(point - Vector3.RIGHT * h),
		candidate.sample_world(point + Vector3.UP * h) - candidate.sample_world(point - Vector3.UP * h),
		candidate.sample_world(point + Vector3.BACK * h) - candidate.sample_world(point - Vector3.BACK * h))
	return gradient.normalized() if gradient.is_finite() and gradient.length_squared() > 0.0000000001 else Vector3.ZERO


func _picker_metrics(fields: Dictionary, snapshot: Dictionary) -> Dictionary:
	var outcomes: Array[Dictionary] = []
	var mismatch := 0
	for x in [2.125, 6.125, 8.125, 12.125, 15.625]:
		var cave: Vector2 = Field.cave_center(SEED, REGION, x)
		var origin := Vector3(x, cave.y, cave.x)
		var exact_sampler := func(point: Vector3) -> float: return _canonical_sample(point, snapshot)
		var candidate_sampler := func(point: Vector3) -> float: return _candidate_sample(fields, point)
		var exact: Dictionary = Picker.pick_sdf_v1_surface(origin, Vector3.UP, exact_sampler)
		var approx: Dictionary = Picker.pick_sdf_v1_surface(origin, Vector3.UP, candidate_sampler)
		var same := bool(exact.get("hit", false)) == bool(approx.get("hit", false))
		var error := INF
		if same and bool(exact.get("hit", false)):
			error = exact.position.distance_to(approx.position)
			if error > 0.0: mismatch += 1
		elif not same:
			mismatch += 1
		outcomes.append({"world_x": x, "canonical_hit": exact.get("hit", false),
			"candidate_hit": approx.get("hit", false), "position_error_world": error})
	return {"ray_count": outcomes.size(), "strict_hit_or_position_difference_count": mismatch,
		"outcomes": outcomes, "position_difference_policy": "bitwise position differences are reported, no owner tolerance applied"}


func _mesh_metrics(fields: Dictionary, snapshot: Dictionary) -> Dictionary:
	var output := {}
	for lod in [0, 1]:
		var chunk := Vector2i(1, 1)
		var candidate_sampler := func(point: Vector3) -> float: return _candidate_sample(fields, point)
		var build_started := Time.get_ticks_usec()
		var exact: Dictionary
		if lod == 0:
			exact = Mesher.build_chunk_cpu_data(SEED, REGION, chunk, false, snapshot)
		else:
			exact = LodMesher.build_chunk_cpu_data(SEED, REGION, chunk, snapshot)
		var exact_usec := Time.get_ticks_usec() - build_started
		build_started = Time.get_ticks_usec()
		var approx: Dictionary
		if lod == 0:
			approx = Mesher.build_chunk_cpu_data(SEED, REGION, chunk, false, {}, candidate_sampler)
		else:
			approx = LodMesher.build_chunk_cpu_data(SEED, REGION, chunk, {}, candidate_sampler)
		var candidate_usec := Time.get_ticks_usec() - build_started
		var comparison := _surface_metrics(exact, approx)
		var key := "lod%d" % lod
		output[key] = {"reference_build_usec": exact_usec, "candidate_build_usec": candidate_usec,
			"reference_valid": exact.get("valid", false), "candidate_valid": approx.get("valid", false),
			"reference_triangles": exact.get("triangle_count", 0), "candidate_triangles": approx.get("triangle_count", 0),
			"sampled_surface_comparison": comparison}
	return output


func _surface_metrics(reference: Dictionary, candidate: Dictionary) -> Dictionary:
	var rp: PackedVector3Array = reference.get("positions", PackedVector3Array())
	var rn: PackedVector3Array = reference.get("normals", PackedVector3Array())
	var cp: PackedVector3Array = candidate.get("positions", PackedVector3Array())
	var cn: PackedVector3Array = candidate.get("normals", PackedVector3Array())
	if rp.is_empty() or cp.is_empty() or rp.size() % 3 != 0 or cp.size() % 3 != 0:
		return {"valid": false, "reason": "empty_or_malformed_mesh"}
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
				var closest := _closest_triangle(source[source_index], target[tri], target[tri + 1], target[tri + 2])
				var distance2 := source[source_index].distance_squared_to(closest)
				if distance2 < best:
					best = distance2
					best_normal = (target_normals[tri] + target_normals[tri + 1] + target_normals[tri + 2]).normalized()
			distances.append(sqrt(maxf(0.0, best)))
			angles.append(rad_to_deg(source_normals[source_index].normalized().angle_to(best_normal)))
	return {"valid": true, "sampled_symmetric_vertex_to_triangle_distance_world": _summary(distances),
		"sampled_normal_angle_degrees": _summary(angles), "method": "sampled vertex-to-triangle in both directions, not certified Hausdorff"}


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
	if va <= 0.0 and d4 - d3 >= 0.0 and d5 - d6 >= 0.0:
		return b + (c - b) * ((d4 - d3) / ((d4 - d3) + (d5 - d6)))
	var denominator := 1.0 / (va + vb + vc)
	return a + ab * (vb * denominator) + ac * (vc * denominator)


func _aggregate_stats(fields: Dictionary) -> Dictionary:
	var refined := 0
	var samples := 0
	var payload := 0
	var build_usec := 0
	for key in fields:
		var stats: Dictionary = fields[key].statistics()
		refined += int(stats.get("refined_cell_count", 0))
		samples += int(stats.get("fine_interior_samples", 0))
		payload += int(stats.get("serialized_payload_bytes", 0))
		build_usec += int(stats.get("build_usec", 0))
	return {"chunk_count": fields.size(), "refined_cells": refined, "interior_fine_samples": samples,
		"serialized_payload_bytes_estimate": payload, "build_usec": build_usec,
		"build_ms": float(build_usec) / 1000.0}


func _candidate_sample(fields: Dictionary, point: Vector3) -> float:
	var mapped: Dictionary = Spatial.world_to_region_local(point)
	if not bool(mapped.get("valid", false)):
		_candidate_canonical_fallback_samples += 1
		return _canonical_sample(point, _active_snapshot)
	var local: Vector3 = mapped.local_position
	var chunk_key := Vector2i(floori(local.x / Grid.size_for(Vector2i.ZERO).x),
		floori(local.z / Grid.size_for(Vector2i.ZERO).z))
	var candidate: Variant = fields.get(chunk_key, null)
	if candidate == null:
		_candidate_canonical_fallback_samples += 1
		return _canonical_sample(point, _active_snapshot)
	var density: float = candidate.sample_world(point)
	if not is_finite(density):
		_candidate_canonical_fallback_samples += 1
		return _canonical_sample(point, _active_snapshot)
	return density


func _canonical_sample(point: Vector3, snapshot: Dictionary) -> float:
	var mapped: Dictionary = Spatial.world_to_region_local(point)
	if not bool(mapped.get("valid", false)): return NAN
	return Brush.sample_density_snapshot(SEED, mapped.region_key, mapped.local_position, false, snapshot)


func _gradient(point: Vector3, snapshot: Dictionary, fields: Dictionary, canonical: bool) -> Vector3:
	var h := 0.01
	var sample := func(p: Vector3) -> float:
		return _canonical_sample(p, snapshot) if canonical else _candidate_sample(fields, p)
	return Vector3(sample.call(point + Vector3.RIGHT * h) - sample.call(point - Vector3.RIGHT * h),
		sample.call(point + Vector3.UP * h) - sample.call(point - Vector3.UP * h),
		sample.call(point + Vector3.BACK * h) - sample.call(point - Vector3.BACK * h)).normalized()


func _summary(values: PackedFloat64Array) -> Dictionary:
	if values.is_empty(): return {"count": 0, "p50": NAN, "p95": NAN, "max": NAN}
	var sorted := values.duplicate()
	sorted.sort()
	return {"count": sorted.size(), "min": sorted[0], "p50": sorted[int(floor(float(sorted.size() - 1) * 0.50))],
		"p95": sorted[int(floor(float(sorted.size() - 1) * 0.95))], "max": sorted[-1]}


func _min(values: PackedFloat64Array) -> float:
	if values.is_empty(): return 0.0
	var result := INF
	for value in values: result = minf(result, value)
	return result


func _max(values: PackedFloat64Array) -> float:
	var result := 0.0
	for value in values: result = maxf(result, value)
	return result


func _check(condition: bool, label: String) -> void:
	_assertions += 1
	if not condition: _failures.append(label)
