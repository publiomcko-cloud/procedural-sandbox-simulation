extends Node3D
class_name EnvironmentVisualPresentation

## P5.0F presentation only. No authoritative mutation, persistence, or terrain writes.
## One MultiMeshInstance3D per resident region and one shared camera-local rain
## MultiMesh. Plans derive exclusively from P5 environment and SDF cache records.

const EnvironmentStore := preload("res://scripts/simulation/environment_state_store.gd")
const PerformanceTrace := preload("res://scripts/diagnostics/performance_trace.gd")

const MAX_CELLS_PER_REGION := 48
const MAX_POLLS_PER_FRAME := 3
const MAX_REBUILDS_PER_FRAME := 1
const MAX_RAIN_STREAKS := 64
const RAIN_UPDATE_SECONDS := 0.10
const WATER_EPSILON_M := 0.012
const MIN_VISIBLE_DEPTH_M := 0.025
const MAX_VISIBLE_DEPTH_M := 4.0

var _runtime: Node
var _regions: Dictionary = {}
var _region_ids: Array[String] = []
var _cursor := 0
var _water_mesh: PlaneMesh
var _rain_mesh: BoxMesh
var _rain_node: MultiMeshInstance3D
var _climate_profile: Dictionary = {}
var _profile_sha256 := ""
var _rain_accumulator := 0.0
var _rain_step := 0
var _polls_total := 0
var _rebuilds_total := 0
var _stale_hides_total := 0
var _peak_rebuild_usec := 0
var _trace_enabled := false


func _ready() -> void:
	_trace_enabled = PerformanceTrace.is_enabled()
	var water_material := StandardMaterial3D.new()
	water_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	water_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	water_material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	water_material.vertex_color_use_as_albedo = true
	water_material.albedo_color = Color.WHITE
	_water_mesh = PlaneMesh.new()
	_water_mesh.size = Vector2.ONE
	_water_mesh.material = water_material

	var rain_material := StandardMaterial3D.new()
	rain_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rain_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rain_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	rain_material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	rain_material.albedo_color = Color(0.64, 0.80, 1.0, 0.44)
	_rain_mesh = BoxMesh.new()
	_rain_mesh.size = Vector3(0.022, 0.84, 0.022)
	_rain_mesh.material = rain_material
	var rain_multi := MultiMesh.new()
	rain_multi.transform_format = MultiMesh.TRANSFORM_3D
	rain_multi.mesh = _rain_mesh
	rain_multi.instance_count = MAX_RAIN_STREAKS
	rain_multi.visible_instance_count = 0
	_rain_node = MultiMeshInstance3D.new()
	_rain_node.name = "DerivedRain"
	_rain_node.multimesh = rain_multi
	_rain_node.visible = false
	add_child(_rain_node)


func configure_environment(runtime: Node, climate_profile: Dictionary = {}, profile_sha256: String = "") -> void:
	_runtime = runtime
	_climate_profile = climate_profile.duplicate(true)
	_profile_sha256 = profile_sha256
	_rain_accumulator = 0.0
	if _rain_node != null:
		_rain_node.visible = false
	for id in _region_ids:
		var row: Dictionary = _regions[id]
		row["token"] = ""
		(row["node"] as MultiMeshInstance3D).visible = false
		_regions[id] = row


func register_region(region_key: Vector2i) -> void:
	var id := _scope_id(region_key)
	if _regions.has(id):
		return
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_colors = true
	multi.mesh = _water_mesh
	multi.instance_count = MAX_CELLS_PER_REGION
	multi.visible_instance_count = 0
	var node := MultiMeshInstance3D.new()
	node.name = "Water_%d_%d" % [region_key.x, region_key.y]
	node.multimesh = multi
	node.visible = false
	add_child(node)
	_regions[id] = {"region_key": region_key, "node": node, "token": ""}
	_region_ids.append(id)
	_region_ids.sort()


func unregister_region(region_key: Vector2i) -> void:
	var id := _scope_id(region_key)
	if not _regions.has(id):
		return
	var node: MultiMeshInstance3D = _regions[id]["node"]
	_regions.erase(id)
	_region_ids.erase(id)
	node.queue_free()
	_cursor = 0 if _region_ids.is_empty() else _cursor % _region_ids.size()


func process_visual_frame(delta: float, camera_position: Vector3, focus_region: Vector2i) -> void:
	if _runtime == null or not is_instance_valid(_runtime):
		return
	_poll_resident_regions()
	_update_rain(delta, camera_position, focus_region)


func get_visual_metrics() -> Dictionary:
	return {
		"resident_region_nodes": _regions.size(),
		"region_polls_total": _polls_total,
		"region_rebuilds_total": _rebuilds_total,
		"stale_hides_total": _stale_hides_total,
		"peak_rebuild_usec": _peak_rebuild_usec,
		"rain_visible": _rain_node != null and _rain_node.visible,
	}


## Pure, bounded derived geometry. Never writes to either supplied record.
static func derive_water_cells(region_key: Vector2i, environment: Dictionary, surface_cache: Dictionary) -> Dictionary:
	if environment.is_empty() or surface_cache.is_empty():
		return {"ok": false, "reason": "visual_source_missing"}
	if String(environment.get("scope_id", "")) != String(surface_cache.get("scope_id", "")):
		return {"ok": false, "reason": "visual_scope_mismatch"}
	if surface_cache.get("region_key") != region_key:
		return {"ok": false, "reason": "visual_region_mismatch"}
	var width := int(surface_cache.get("grid_width", 0))
	var height := int(surface_cache.get("grid_height", 0))
	var size_x_mm := int(surface_cache.get("cell_size_x_mm", 0))
	var size_z_mm := int(surface_cache.get("cell_size_z_mm", 0))
	var count := width * height
	if width != 8 or height != 6 or count > MAX_CELLS_PER_REGION or size_x_mm <= 0 or size_z_mm <= 0:
		return {"ok": false, "reason": "visual_grid_invalid"}
	var water: PackedInt64Array = environment.get("surface_water_ul", PackedInt64Array())
	var kinds: PackedByteArray = environment.get("reservoir_kind", PackedByteArray())
	var levels: PackedInt64Array = environment.get("reservoir_level_mm", PackedInt64Array())
	var heights: PackedInt64Array = surface_cache.get("surface_height_mm", PackedInt64Array())
	var valid: PackedByteArray = surface_cache.get("surface_valid", PackedByteArray())
	if water.size() != count or kinds.size() != count or levels.size() != count or heights.size() != count or valid.size() != count:
		return {"ok": false, "reason": "visual_arrays_invalid"}
	var x_size := float(size_x_mm) / 1000.0
	var z_size := float(size_z_mm) / 1000.0
	var cell_area := x_size * z_size
	var cells: Array[Dictionary] = []
	for index in range(count):
		if valid[index] == 0:
			continue
		var kind := int(kinds[index])
		var y := 0.0
		var tint := Color(0.13, 0.58, 0.90, 0.57)
		if kind == EnvironmentStore.RESERVOIR_FINITE:
			if water[index] <= 0:
				continue
			var depth_m := clampf(float(water[index]) / (1_000_000_000.0 * cell_area), MIN_VISIBLE_DEPTH_M, MAX_VISIBLE_DEPTH_M)
			y = float(heights[index]) / 1000.0 + depth_m + WATER_EPSILON_M
		elif kind == EnvironmentStore.RESERVOIR_RIVER:
			y = float(levels[index]) / 1000.0 + WATER_EPSILON_M
			tint = Color(0.08, 0.41, 0.73, 0.78)
		elif kind == EnvironmentStore.RESERVOIR_OCEAN:
			y = float(levels[index]) / 1000.0 + WATER_EPSILON_M
			tint = Color(0.05, 0.31, 0.60, 0.80)
		else:
			return {"ok": false, "reason": "visual_reservoir_kind_invalid"}
		var x := index % width
		var z := index / width
		cells.append({
			"position": Vector3(
				float(region_key.x) * x_size * float(width) + (float(x) + 0.5) * x_size,
				y,
				float(region_key.y) * z_size * float(height) + (float(z) + 0.5) * z_size
			),
			"size": Vector2(x_size, z_size),
			"color": tint,
			"kind": kind,
		})
	return {"ok": true, "reason": "ok", "cells": cells}


func _poll_resident_regions() -> void:
	if _region_ids.is_empty():
		return
	var rebuilt := 0
	for _i in range(mini(MAX_POLLS_PER_FRAME, _region_ids.size())):
		var id := _region_ids[_cursor % _region_ids.size()]
		_cursor = (_cursor + 1) % _region_ids.size()
		_polls_total += 1
		var row: Dictionary = _regions[id]
		var node: MultiMeshInstance3D = row["node"]
		var surface: Dictionary = _runtime.get_environment_surface_cache(id)
		var environment: Dictionary = _runtime.get_environment_scope(id)
		if surface.is_empty() or environment.is_empty():
			if node.visible:
				_stale_hides_total += 1
			node.visible = false
			row["token"] = ""
			_regions[id] = row
			continue
		var token := "%d:%d:%d:%d:%d:%d:%d" % [
			int(environment.get("state_revision", -1)),
			int(environment.get("last_environment_tick", -1)),
			int(surface.get("world_seed", -1)),
			int(surface.get("generator_version", -1)),
			int(surface.get("terrain_revision", -1)),
			int(surface.get("terrain_cache_scope_id", -1)),
			int(surface.get("terrain_effect_revision", -1)),
		]
		if String(row["token"]) == token:
			continue
		# Defer rather than bursting rebuilds on a loaded/revisited region window.
		if rebuilt >= MAX_REBUILDS_PER_FRAME:
			continue
		var started := Time.get_ticks_usec()
		var plan := derive_water_cells(row["region_key"], environment, surface)
		if not plan.get("ok", false):
			node.visible = false
			row["token"] = ""
			_regions[id] = row
			continue
		var cells: Array = plan["cells"]
		var multi := node.multimesh
		for index in range(cells.size()):
			var cell: Dictionary = cells[index]
			var size: Vector2 = cell["size"]
			multi.set_instance_transform(index, Transform3D(
				Basis().scaled(Vector3(size.x, 1.0, size.y)),
				cell["position"]
			))
			multi.set_instance_color(index, cell["color"])
		multi.visible_instance_count = cells.size()
		node.visible = not cells.is_empty()
		row["token"] = token
		_regions[id] = row
		rebuilt += 1
		_rebuilds_total += 1
		var elapsed := Time.get_ticks_usec() - started
		_peak_rebuild_usec = maxi(_peak_rebuild_usec, elapsed)
		if _trace_enabled:
			PerformanceTrace.emit("p5_environment_visual_rebuild", {
				"scope": id,
				"duration_usec": elapsed,
				"instances": cells.size(),
				"state_revision": int(environment["state_revision"]),
				"terrain_revision": int(surface["terrain_revision"]),
			})


func _update_rain(delta: float, camera_position: Vector3, focus_region: Vector2i) -> void:
	if _rain_node == null:
		return
	_rain_node.global_position = camera_position
	_rain_accumulator += maxf(0.0, delta)
	if _rain_accumulator < RAIN_UPDATE_SECONDS:
		return
	_rain_accumulator = 0.0
	var rate := int(_climate_profile.get("precipitation_ul_per_cell_per_tick", 0))
	var focus: Dictionary = _runtime.get_environment_scope(_scope_id(focus_region))
	var enabled := (
		rate > 0
		and not _profile_sha256.is_empty()
		and String(_climate_profile.get("id", "")) == String(focus.get("profile_id", ""))
		and _profile_sha256 == String(focus.get("profile_sha256", ""))
	)
	_rain_node.visible = enabled
	if not enabled:
		_rain_node.multimesh.visible_instance_count = 0
		return
	var count := clampi(12 + int(float(rate) / 1_000_000.0), 12, MAX_RAIN_STREAKS)
	var multi := _rain_node.multimesh
	for index in range(count):
		var x := (float(posmod(index * 31 + _rain_step * 7, 103)) / 102.0 - 0.5) * 14.0
		var z := (float(posmod(index * 47 + _rain_step * 5, 109)) / 108.0 - 0.5) * 14.0
		var y := float(posmod(index * 17 - _rain_step * 13, 71)) / 10.0 + 1.0
		multi.set_instance_transform(index, Transform3D(Basis(), Vector3(x, y, z)))
	multi.visible_instance_count = count
	_rain_step += 1


static func _scope_id(region_key: Vector2i) -> String:
	return "region:%d,%d" % [region_key.x, region_key.y]
