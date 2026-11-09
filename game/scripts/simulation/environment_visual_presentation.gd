extends Node3D
class_name EnvironmentVisualPresentation

## P5.0F presentation only. No authoritative mutation, persistence, or terrain writes.
## One MultiMeshInstance3D per resident region and one shared camera-local rain
## MultiMesh. Plans derive exclusively from P5 environment and SDF cache records.

const EnvironmentStore := preload("res://scripts/simulation/environment_state_store.gd")
const PerformanceTrace := preload("res://scripts/diagnostics/performance_trace.gd")

const MAX_CELLS_PER_REGION := 48
const SHORELINE_SUBDIVISIONS := 2
const SHORELINE_WIDTH := 8 * SHORELINE_SUBDIVISIONS + 1
const SHORELINE_HEIGHT := 6 * SHORELINE_SUBDIVISIONS + 1
const SHORELINE_CLEARANCE_M := 0.018
const MAX_SHORELINE_VERTICES := MAX_CELLS_PER_REGION * SHORELINE_SUBDIVISIONS * SHORELINE_SUBDIVISIONS * 2 * 2 * 3
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
var _water_material: StandardMaterial3D
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
	_water_material = water_material

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
		(row["node"] as MeshInstance3D).visible = false
		_regions[id] = row


func register_region(region_key: Vector2i) -> void:
	var id := _scope_id(region_key)
	if _regions.has(id):
		return
	var node := MeshInstance3D.new()
	node.name = "Water_%d_%d" % [region_key.x, region_key.y]
	node.visible = false
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	_regions[id] = {
		"region_key": region_key,
		"node": node,
		"token": "",
		"shoreline_token": "",
		"shoreline": {},
		"last_vertex_count": 0,
	}
	_region_ids.append(id)
	_region_ids.sort()


func unregister_region(region_key: Vector2i) -> void:
	var id := _scope_id(region_key)
	if not _regions.has(id):
		return
	var node: MeshInstance3D = _regions[id]["node"]
	_regions.erase(id)
	_region_ids.erase(id)
	if node.get_parent() == self:
		remove_child(node)
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
		"visible_shoreline_vertices": _count_visible_shoreline_vertices(),
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
			"cell_index": index,
		})
	return {"ok": true, "reason": "ok", "cells": cells}



## Called only when the immutable P5.0C worker product has been accepted by
## the runtime. These samples are transient, never persisted as hydrology.
func install_region_shoreline_samples(
	region_key: Vector2i, surface_record: Dictionary, shoreline: Dictionary
) -> bool:
	var id := _scope_id(region_key)
	if not _regions.has(id):
		return false
	if shoreline.is_empty() or not shoreline.get("ok", false):
		return false
	if shoreline.get("region_key") != region_key or surface_record.get("region_key") != region_key:
		return false
	for key in [
		"world_seed", "generator_version", "terrain_revision",
		"terrain_cache_scope_id", "terrain_effect_revision",
	]:
		if int(surface_record.get(key, -1)) != int(shoreline.get(key, -2)):
			return false
	if int(shoreline.get("width", -1)) != SHORELINE_WIDTH or int(shoreline.get("height", -1)) != SHORELINE_HEIGHT:
		return false
	var heights: PackedInt32Array = shoreline.get("height_mm", PackedInt32Array())
	var valid: PackedByteArray = shoreline.get("valid", PackedByteArray())
	if heights.size() != SHORELINE_WIDTH * SHORELINE_HEIGHT or valid.size() != heights.size():
		return false
	var row: Dictionary = _regions[id]
	row["shoreline"] = shoreline.duplicate(true)
	row["shoreline_token"] = _surface_identity(surface_record)
	row["token"] = ""
	_regions[id] = row
	return true



## Invalidate immediately when the terrain edit changes expected provenance.
## Prevents the prior coast mesh from lingering while its SDF worker runs.
func invalidate_region_shoreline_samples(region_key: Vector2i) -> void:
	var id := _scope_id(region_key)
	if not _regions.has(id):
		return
	var row: Dictionary = _regions[id]
	row["token"] = ""
	row["shoreline_token"] = ""
	row["shoreline"] = {}
	row["last_vertex_count"] = 0
	var node: MeshInstance3D = row["node"]
	node.visible = false
	node.mesh = null
	_regions[id] = row


func has_region_shoreline_samples(region_key: Vector2i, surface_record: Dictionary) -> bool:
	var id := _scope_id(region_key)
	return _regions.has(id) and String(_regions[id].get("shoreline_token", "")) == _surface_identity(surface_record)


func _count_visible_shoreline_vertices() -> int:
	var count := 0
	for id in _region_ids:
		var row: Dictionary = _regions[id]
		if (row["node"] as MeshInstance3D).visible:
			count += int(row.get("last_vertex_count", 0))
	return count


## All derived geometry is clipped against SDF topography at 1m resolution.
## Marching triangles handles every ambiguous case conservatively and never
## emits the old whole-cell quads over a known dry corner.
static func derive_shoreline_geometry(
	region_key: Vector2i,
	environment: Dictionary,
	surface_cache: Dictionary,
	shoreline: Dictionary
) -> Dictionary:
	var base := derive_water_cells(region_key, environment, surface_cache)
	if not base.get("ok", false):
		return base
	if int(shoreline.get("width", -1)) != SHORELINE_WIDTH or int(shoreline.get("height", -1)) != SHORELINE_HEIGHT:
		return {"ok": false, "reason": "shoreline_grid_invalid"}
	if shoreline.get("region_key") != region_key:
		return {"ok": false, "reason": "shoreline_region_mismatch"}
	for key in [
		"world_seed", "generator_version", "terrain_revision",
		"terrain_cache_scope_id", "terrain_effect_revision",
	]:
		if int(shoreline.get(key, -2)) != int(surface_cache.get(key, -1)):
			return {"ok": false, "reason": "shoreline_provenance_mismatch"}
	var heights: PackedInt32Array = shoreline.get("height_mm", PackedInt32Array())
	var valid: PackedByteArray = shoreline.get("valid", PackedByteArray())
	if heights.size() != SHORELINE_WIDTH * SHORELINE_HEIGHT or valid.size() != heights.size():
		return {"ok": false, "reason": "shoreline_samples_invalid"}
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	var water_cells := 0
	var region_origin_x := float(region_key.x) * 16.0
	var region_origin_z := float(region_key.y) * 12.0
	for cell_value in base["cells"]:
		var cell: Dictionary = cell_value
		var cell_index := int(cell["cell_index"])
		var col := cell_index % 8
		var row := int(cell_index / 8)
		var y := float((cell["position"] as Vector3).y)
		var threshold := y - SHORELINE_CLEARANCE_M
		var emitted := false
		for sub_z in range(SHORELINE_SUBDIVISIONS):
			for sub_x in range(SHORELINE_SUBDIVISIONS):
				var x := col * SHORELINE_SUBDIVISIONS + sub_x
				var z := row * SHORELINE_SUBDIVISIONS + sub_z
				var a := z * SHORELINE_WIDTH + x
				var b := (z + 1) * SHORELINE_WIDTH + x
				var c := (z + 1) * SHORELINE_WIDTH + x + 1
				var d := z * SHORELINE_WIDTH + x + 1
				if valid[a] == 0 or valid[b] == 0 or valid[c] == 0 or valid[d] == 0:
					continue
				var v0 := {"p": Vector2(region_origin_x + float(x), region_origin_z + float(z)), "h": float(heights[a]) / 1000.0}
				var v1 := {"p": Vector2(region_origin_x + float(x), region_origin_z + float(z + 1)), "h": float(heights[b]) / 1000.0}
				var v2 := {"p": Vector2(region_origin_x + float(x + 1), region_origin_z + float(z + 1)), "h": float(heights[c]) / 1000.0}
				var v3 := {"p": Vector2(region_origin_x + float(x + 1), region_origin_z + float(z)), "h": float(heights[d]) / 1000.0}
				for triangle in [[v0, v1, v2], [v0, v2, v3]]:
					var clipped := _clip_under_surface(triangle, threshold)
					for vertex_index in range(1, clipped.size() - 1):
						for corner in [clipped[0], clipped[vertex_index], clipped[vertex_index + 1]]:
							var point: Vector2 = corner["p"]
							vertices.append(Vector3(point.x, y, point.y))
							colors.append(cell["color"])
						emitted = true
		if emitted:
			water_cells += 1
	if vertices.size() > MAX_SHORELINE_VERTICES:
		return {"ok": false, "reason": "shoreline_vertex_budget_exceeded"}
	return {
		"ok": true, "reason": "ok",
		"vertices": vertices, "colors": colors,
		"water_cells": water_cells, "triangles": int(vertices.size() / 3),
	}


static func _clip_under_surface(triangle: Array, water_threshold: float) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for index in range(triangle.size()):
		var current: Dictionary = triangle[index]
		var previous: Dictionary = triangle[(index + triangle.size() - 1) % triangle.size()]
		var current_wet := float(current["h"]) <= water_threshold
		var previous_wet := float(previous["h"]) <= water_threshold
		if current_wet != previous_wet:
			var fraction := clampf(
				(water_threshold - float(previous["h"])) / (float(current["h"]) - float(previous["h"])),
				0.0, 1.0
			)
			result.append({
				"p": (previous["p"] as Vector2).lerp(current["p"], fraction),
				"h": water_threshold,
			})
		if current_wet:
			result.append(current)
	return result


static func _surface_identity(record: Dictionary) -> String:
	return "%d:%d:%d:%d:%d" % [
		int(record.get("world_seed", -1)),
		int(record.get("generator_version", -1)),
		int(record.get("terrain_revision", -1)),
		int(record.get("terrain_cache_scope_id", -1)),
		int(record.get("terrain_effect_revision", -1)),
	]


func _poll_resident_regions() -> void:
	if _region_ids.is_empty():
		return
	var rebuilt := 0
	for _i in range(mini(MAX_POLLS_PER_FRAME, _region_ids.size())):
		var id := _region_ids[_cursor % _region_ids.size()]
		_cursor = (_cursor + 1) % _region_ids.size()
		_polls_total += 1
		var row: Dictionary = _regions[id]
		var node: MeshInstance3D = row["node"]
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
		if row.get("shoreline_token", "") != _surface_identity(surface):
			# Never fall back to a square quad over dry land. Wait for SDF worker.
			if node.visible:
				_stale_hides_total += 1
			node.visible = false
			node.mesh = null
			row["token"] = ""
			_regions[id] = row
			continue
		var started := Time.get_ticks_usec()
		var plan := derive_shoreline_geometry(
			row["region_key"], environment, surface, row.get("shoreline", {})
		)
		if not plan.get("ok", false):
			node.visible = false
			node.mesh = null
			row["token"] = ""
			_regions[id] = row
			continue
		var vertices: PackedVector3Array = plan["vertices"]
		if vertices.is_empty():
			node.mesh = null
			node.visible = false
		else:
			var arrays: Array = []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = vertices
			arrays[Mesh.ARRAY_COLOR] = plan["colors"]
			var mesh := ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			mesh.surface_set_material(0, _water_material)
			node.mesh = mesh
			node.visible = true
		row["token"] = token
		row["last_vertex_count"] = vertices.size()
		_regions[id] = row
		rebuilt += 1
		_rebuilds_total += 1
		var elapsed := Time.get_ticks_usec() - started
		_peak_rebuild_usec = maxi(_peak_rebuild_usec, elapsed)
		if _trace_enabled:
			PerformanceTrace.emit("p5_environment_visual_rebuild", {
				"scope": id,
				"duration_usec": elapsed,
				"vertices": vertices.size(),
				"triangles": int(vertices.size() / 3),
				"water_cells": int(plan.get("water_cells", 0)),
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
