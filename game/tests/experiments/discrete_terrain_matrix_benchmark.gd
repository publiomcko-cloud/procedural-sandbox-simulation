extends SceneTree

## Standalone headless workload: *real* SDF mesher versus experimental
## byte-quantized occupancy and greedy quad extraction, same seed/chunks/edits.
## Outputs objective timings and quality loss. No production-path override.
const Grid := preload("res://scripts/terrain/terrain_chunk_grid.gd")
const Field := preload("res://scripts/terrain/sdf_world.gd")
const Mesher := preload("res://scripts/terrain/marching_tetrahedra.gd")
const Brush := preload("res://scripts/terrain/sdf_brush_edit_state.gd")
const Backend := preload("res://scripts/experiments/discrete_terrain_backend.gd")

const SEED := 424242
const REGION := Vector2i(1, -1)
const ORDER := [
	"sdf", "discrete_050", "discrete_025", "discrete_0125",
	"discrete_0125", "discrete_025", "discrete_050", "sdf"
]
const EDITS := [
	{"mode": 0, "center": Vector3(4.1, 3.0, 3.4), "radius": 0.85},
	{"mode": 0, "center": Vector3(8.0, 2.8, 7.0), "radius": 1.05},
	{"mode": 1, "center": Vector3(5.2, 2.5, 5.0), "radius": 0.75},
	{"mode": 0, "center": Vector3(11.7, 3.8, 8.6), "radius": 0.95},
	{"mode": 1, "center": Vector3(8.5, 2.5, 7.6), "radius": 0.95},
	{"mode": 0, "center": Vector3(6.6, 1.9, 8.5), "radius": 0.85},
	{"mode": 1, "center": Vector3(3.2, 4.1, 7.6), "radius": 0.75},
	{"mode": 0, "center": Vector3(12.3, 3.2, 4.7), "radius": 0.9},
]

var failures := 0
var all_trials: Array[Dictionary] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for label in ORDER:
		var trial := _trial(label)
		if not bool(trial.get("valid", false)):
			failures += 1
			push_error("DISCRETE_TERRAIN_TRIAL_FAILURE " + JSON.stringify(trial))
		print("DISCRETE_TERRAIN_TRIAL=" + JSON.stringify(trial))
		all_trials.append(trial)
	var summary := _summarize()
	print("DISCRETE_TERRAIN_SUMMARY=" + JSON.stringify(summary))
	print("DISCRETE_TERRAIN_BENCH_%s trials=%d failures=%d" % [
		"PASS" if failures == 0 else "FAIL", all_trials.size(), failures
	])
	quit(0 if failures == 0 else 1)


func _trial(label: String) -> Dictionary:
	var baseline := label == "sdf"
	var step := 0.0
	if label == "discrete_050":
		step = 0.5
	elif label == "discrete_025":
		step = 0.25
	elif label == "discrete_0125":
		step = 0.125
	elif not baseline:
		return {"valid": false, "reason": "unknown_label", "label": label}
	var backend: RefCounted = null
	var cold_started := Time.get_ticks_usec()
	var generate_usec := 0
	if not baseline:
		backend = Backend.new()
		var generation_started := Time.get_ticks_usec()
		if not backend.generate(SEED, REGION, step):
			return {"valid": false, "reason": "generation_failed", "label": label}
		generate_usec = Time.get_ticks_usec() - generation_started
	var cold_geometry := _mesh_all(baseline, backend)
	var cold_usec := Time.get_ticks_usec() - cold_started
	if not bool(cold_geometry.get("valid", false)):
		return {"valid": false, "reason": "cold_mesh_failed", "label": label}
	var warm_started := Time.get_ticks_usec()
	var warm_geometry := _mesh_all(baseline, backend)
	var warm_usec := Time.get_ticks_usec() - warm_started
	if not bool(warm_geometry.get("valid", false)):
		return {"valid": false, "reason": "warm_mesh_failed", "label": label}
	if cold_geometry["triangles"] != warm_geometry["triangles"]:
		return {"valid": false, "reason": "cold_warm_mesh_mismatch", "label": label}
	var brush := Brush.new(SEED, Field.GENERATOR_VERSION)
	var edits_usec := 0
	var remeshed_chunks := 0
	var changed_cells := 0
	var final_edit_triangles := 0
	var region_world_origin := Vector3(
		float(REGION.x) * Field.REGION_SIZE_X,
		0.0,
		float(REGION.y) * Field.REGION_SIZE_Z
	)
	for edit in EDITS:
		var mode: int = edit["mode"]
		var center_local: Vector3 = edit["center"]
		var center_world := region_world_origin + center_local
		var radius: float = edit["radius"]
		var impacted := Grid.affected_chunks_for_sphere(center_local, radius)
		var edit_started := Time.get_ticks_usec()
		if baseline:
			if not brush.add_sphere(mode, center_world, radius):
				return {"valid": false, "reason": brush.last_rejection_reason, "label": label}
		else:
			changed_cells += int(backend.edit_sphere(mode, center_world, radius))
		for chunk in impacted:
			var result: Dictionary
			if baseline:
				var snapshot: Dictionary = brush.get_meshing_snapshot_for_chunk(REGION, chunk)
				if not bool(snapshot.get("valid", false)):
					return {"valid": false, "reason": "invalid_edited_snapshot", "label": label}
				result = Mesher.build_chunk_cpu_data(SEED, REGION, chunk, false, snapshot)
			else:
				result = backend.build_chunk(chunk)
			if not bool(result.get("valid", false)):
				return {"valid": false, "reason": "invalid_edited_mesh", "label": label}
			final_edit_triangles += int(result.get("triangle_count", 0))
		edits_usec += Time.get_ticks_usec() - edit_started
		remeshed_chunks += impacted.size()
		if not baseline:
			# Reference ledger is only for independent correctness, not candidate timing.
			if not brush.add_sphere(mode, center_world, radius):
				return {"valid": false, "reason": "oracle_edit_failed", "label": label}
	var quality: Dictionary = {}
	if not baseline:
		quality = _fidelity(backend, brush)
		if int(quality.get("lattice_center_sign_mismatches", -1)) != 0:
			return {"valid": false, "reason": "lattice_sign_drift", "label": label, "quality": quality}
	var result := {
		"valid": true,
		"label": label,
		"step_m": step,
		"cold_usec": cold_usec,
		"generate_usec": generate_usec,
		"cold_mesh_only_usec": cold_usec - generate_usec,
		"warm_usec": warm_usec,
		"edits_usec": edits_usec,
		"edits_count": EDITS.size(),
		"remeshed_chunks": remeshed_chunks,
		"changed_cells": changed_cells,
		"edited_triangle_work": final_edit_triangles,
		"cold_triangles": int(cold_geometry["triangles"]),
		"cold_vertices": int(cold_geometry["vertices"]),
		"warm_triangles": int(warm_geometry["triangles"]),
		"resident_bytes": 0 if baseline else int(backend.byte_count()),
		"quality": quality,
	}
	return result


func _mesh_all(baseline: bool, backend: RefCounted) -> Dictionary:
	var triangle_total := 0
	var vertex_total := 0
	for chunk in Grid.all_coordinates():
		var output: Dictionary
		if baseline:
			output = Mesher.build_chunk_cpu_data(SEED, REGION, chunk, false, null)
		else:
			output = backend.build_chunk(chunk)
		if not bool(output.get("valid", false)):
			return {"valid": false}
		triangle_total += int(output.get("triangle_count", 0))
		vertex_total += int(output.get("vertex_count", 0))
	return {"valid": true, "triangles": triangle_total, "vertices": vertex_total}


func _fidelity(backend: RefCounted, brush: RefCounted) -> Dictionary:
	var oracle: Dictionary = brush.get_meshing_snapshot()
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261112
	var lattice_mismatch := 0
	var arbitrary_mismatch := 0
	var center_samples := 384
	var arbitrary_samples := 384
	for _i in range(center_samples):
		var p := Vector3(
			(float(rng.randi_range(0, backend.dims.x - 1)) + 0.5) * backend.step,
			Grid.MIN_BOUND.y + (float(rng.randi_range(0, backend.dims.y - 1)) + 0.5) * backend.step,
			(float(rng.randi_range(0, backend.dims.z - 1)) + 0.5) * backend.step
		)
		var oracle_solid := Brush.sample_density_snapshot(SEED, REGION, p, false, oracle) >= 0.0
		if (backend.sample_local(p) == 1) != oracle_solid:
			lattice_mismatch += 1
	for _i in range(arbitrary_samples):
		var p := Vector3(
			rng.randf_range(0.1, 15.9),
			rng.randf_range(-1.9, 7.9),
			rng.randf_range(0.1, 11.9)
		)
		var oracle_solid := Brush.sample_density_snapshot(SEED, REGION, p, false, oracle) >= 0.0
		if (backend.sample_local(p) == 1) != oracle_solid:
			arbitrary_mismatch += 1
	var surface_distances: Array[float] = []
	for chunk in Grid.all_coordinates():
		var mesh: Dictionary = backend.build_chunk(chunk)
		var positions: PackedVector3Array = mesh.get("positions", PackedVector3Array())
		var stride := maxi(1, ceili(float(positions.size()) / 24.0))
		for index in range(0, positions.size(), stride):
			var p := positions[index] + Grid.origin_for(chunk)
			var density := Brush.sample_density_snapshot(SEED, REGION, p, false, oracle)
			surface_distances.append(absf(density))
	surface_distances.sort()
	var p95 := 0.0
	if not surface_distances.is_empty():
		p95 = surface_distances[mini(surface_distances.size() - 1, floori(0.95 * float(surface_distances.size())))]
	return {
		"lattice_center_sign_mismatches": lattice_mismatch,
		"lattice_center_samples": center_samples,
		"arbitrary_sign_mismatches": arbitrary_mismatch,
		"arbitrary_samples": arbitrary_samples,
		"arbitrary_disagreement_pct": 100.0 * float(arbitrary_mismatch) / float(arbitrary_samples),
		"surface_abs_sdf_p95_m_approx": p95,
		"surface_samples": surface_distances.size(),
	}


func _summarize() -> Dictionary:
	var grouped: Dictionary = {}
	for trial in all_trials:
		if not bool(trial.get("valid", false)):
			continue
		var label: String = trial["label"]
		if not grouped.has(label):
			grouped[label] = []
		(grouped[label] as Array).append(trial)
	var summary := {"experiment": "discrete_occupancy_greedy_vs_sdf", "runs_per_mode": 2}
	for label in grouped:
		var group: Array = grouped[label]
		var cold := _median(group, "cold_usec")
		var warm := _median(group, "warm_usec")
		var edit := _median(group, "edits_usec")
		summary[label] = {
			"cold_median_ms": cold / 1000.0,
			"warm_median_ms": warm / 1000.0,
			"edits_median_ms": edit / 1000.0,
			"triangles": int((group[0] as Dictionary)["cold_triangles"]),
			"resident_bytes": int((group[0] as Dictionary)["resident_bytes"]),
			"quality": (group[0] as Dictionary)["quality"],
		}
	if summary.has("sdf"):
		var baseline: Dictionary = summary["sdf"]
		for label in ["discrete_050", "discrete_025", "discrete_0125"]:
			if not summary.has(label):
				continue
			var candidate: Dictionary = summary[label]
			candidate["cold_speedup_vs_sdf"] = float(baseline["cold_median_ms"]) / maxf(0.001, float(candidate["cold_median_ms"]))
			candidate["warm_speedup_vs_sdf"] = float(baseline["warm_median_ms"]) / maxf(0.001, float(candidate["warm_median_ms"]))
			candidate["edit_speedup_vs_sdf"] = float(baseline["edits_median_ms"]) / maxf(0.001, float(candidate["edits_median_ms"]))
	return summary


func _median(rows: Array, key: String) -> float:
	var values: Array[float] = []
	for row in rows:
		values.append(float((row as Dictionary)[key]))
	values.sort()
	if values.size() % 2 == 1:
		return values[values.size() / 2]
	return (values[values.size() / 2 - 1] + values[values.size() / 2]) / 2.0
