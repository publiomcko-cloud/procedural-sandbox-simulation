extends SceneTree

const Authority := preload("res://scripts/terrain/shared_surface_boundary_authority.gd")
const Brush := preload("res://scripts/terrain/sdf_brush_edit_state.gd")
const Field := preload("res://scripts/terrain/sdf_world.gd")

const SEED := 424242
const BASE_REGION := Vector2i.ZERO
const X_Z_CHUNK := 3
const Z_X_CHUNK := 3

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var ledger := Brush.new(SEED, Field.GENERATOR_VERSION)
	var initial_specs := [
		{"mode": Brush.Mode.FILL, "center": Vector3(15.8, 2.4, 11.8), "radius": 0.72},
		{"mode": Brush.Mode.CARVE, "center": Vector3(16.2, 3.1, 12.2), "radius": 0.62},
	]
	for spec in initial_specs:
		if not ledger.add_sphere(int(spec["mode"]), spec["center"], float(spec["radius"])):
			failures += 1

	var warm := _build_once(ledger)
	if not warm.get("ok", false):
		push_error("P1_SHARED_REPEAT_BENCHMARK warmup failed")
		quit(1)
		return

	var specs := [
		{"mode": Brush.Mode.CARVE, "center": Vector3(15.55, 3.0, 11.55), "radius": 0.62},
		{"mode": Brush.Mode.FILL, "center": Vector3(16.45, 3.3, 11.55), "radius": 0.64},
		{"mode": Brush.Mode.CARVE, "center": Vector3(15.55, 2.7, 12.45), "radius": 0.66},
		{"mode": Brush.Mode.FILL, "center": Vector3(16.45, 3.1, 12.45), "radius": 0.68},
		{"mode": Brush.Mode.CARVE, "center": Vector3(15.25, 3.5, 12.0), "radius": 0.70},
		{"mode": Brush.Mode.FILL, "center": Vector3(16.75, 2.5, 12.0), "radius": 0.72},
	]
	var x_ms: Array[float] = []
	var z_ms: Array[float] = []
	var corner_ms: Array[float] = []
	var total_ms: Array[float] = []
	var rows: Array[Dictionary] = []

	for spec in specs:
		if not ledger.add_sphere(int(spec["mode"]), spec["center"], float(spec["radius"])):
			failures += 1
			continue
		var result := _build_once(ledger)
		if not result.get("ok", false):
			failures += 1
			continue
		x_ms.append(float(result["x_ms"]))
		z_ms.append(float(result["z_ms"]))
		corner_ms.append(float(result["corner_ms"]))
		total_ms.append(float(result["total_ms"]))
		rows.append(result)

	var evidence := {
		"iterations": rows,
		"x_ms": _summary(x_ms),
		"z_ms": _summary(z_ms),
		"corner_ms": _summary(corner_ms),
		"total_ms": _summary(total_ms),
	}
	print("P1_SHARED_REPEAT_BENCHMARK=" + JSON.stringify(evidence))
	if failures == 0 and rows.size() == specs.size():
		print("P1_SHARED_REPEAT_BENCHMARK_PASS: iterations=%d failures=0" % rows.size())
		quit(0)
	else:
		push_error("P1_SHARED_REPEAT_BENCHMARK_FAIL: iterations=%d failures=%d" % [rows.size(), failures])
		quit(1)


func _build_once(ledger: RefCounted) -> Dictionary:
	var total_started := Time.get_ticks_usec()

	var x_snapshot := Authority.make_x_pair_snapshot(ledger, BASE_REGION, X_Z_CHUNK)
	if not x_snapshot.get("valid", false):
		return {"ok": false, "reason": "x_snapshot"}
	var x_started := Time.get_ticks_usec()
	var x := Authority.build_x_region_boundary_pair(SEED, BASE_REGION, X_Z_CHUNK, x_snapshot, false)
	var x_usec := Time.get_ticks_usec() - x_started
	if not x.get("valid", false):
		return {"ok": false, "reason": "x_build"}

	var z_snapshot := Authority.make_z_pair_snapshot(ledger, BASE_REGION, Z_X_CHUNK)
	if not z_snapshot.get("valid", false):
		return {"ok": false, "reason": "z_snapshot"}
	var z_started := Time.get_ticks_usec()
	var z := Authority.build_z_region_boundary_pair(SEED, BASE_REGION, Z_X_CHUNK, z_snapshot, false)
	var z_usec := Time.get_ticks_usec() - z_started
	if not z.get("valid", false):
		return {"ok": false, "reason": "z_build"}

	var corner_snapshot := Authority.make_xz_corner_snapshot(ledger, BASE_REGION)
	if not corner_snapshot.get("valid", false):
		return {"ok": false, "reason": "corner_snapshot"}
	var corner_started := Time.get_ticks_usec()
	var corner := Authority.build_xz_corner_quad(SEED, BASE_REGION, corner_snapshot, false)
	var corner_usec := Time.get_ticks_usec() - corner_started
	if not corner.get("valid", false):
		return {"ok": false, "reason": "corner_build"}

	var x_counters: Dictionary = x["left"].get("work_counters", {})
	var z_counters: Dictionary = z["low"].get("work_counters", {})
	var corner_counters: Dictionary = corner["minx_minz"].get("work_counters", {})
	return {
		"ok": true,
		"x_ms": float(x_usec) / 1000.0,
		"z_ms": float(z_usec) / 1000.0,
		"corner_ms": float(corner_usec) / 1000.0,
		"total_ms": float(Time.get_ticks_usec() - total_started) / 1000.0,
		"x_cache_hit": int(x_counters.get("incremental_cache_hit", 0)),
		"x_dirty": int(x_counters.get("dirty_cell_count", x_counters.get("cell_count", -1))),
		"x_cells": int(x_counters.get("cell_count", -1)),
		"z_cache_hit": int(z_counters.get("incremental_cache_hit", 0)),
		"z_dirty": int(z_counters.get("dirty_cell_count", z_counters.get("cell_count", -1))),
		"z_cells": int(z_counters.get("cell_count", -1)),
		"corner_cache_hit": int(corner_counters.get("incremental_cache_hit", 0)),
		"corner_dirty": int(corner_counters.get("dirty_cell_count", corner_counters.get("cell_count", -1))),
		"corner_cells": int(corner_counters.get("cell_count", -1)),
	}


func _summary(values: Array[float]) -> Dictionary:
	if values.is_empty():
		return {}
	var ordered := values.duplicate()
	ordered.sort()
	var count := ordered.size()
	var median := ordered[count / 2] if count % 2 == 1 else (ordered[count / 2 - 1] + ordered[count / 2]) * 0.5
	var total := 0.0
	for value in ordered:
		total += value
	return {
		"n": count,
		"min": ordered[0],
		"median": median,
		"mean": total / float(count),
		"max": ordered[-1],
	}
