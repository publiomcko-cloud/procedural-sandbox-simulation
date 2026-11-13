extends Node3D
class_name EnvironmentVisualPresentation

## P5.0F presentation only. No authoritative mutation, persistence, or terrain writes.
## One MultiMeshInstance3D per resident region and one shared camera-local rain
## MultiMesh. Plans derive exclusively from P5 environment and SDF cache records.

const EnvironmentStore := preload("res://scripts/simulation/environment_state_store.gd")
const PerformanceTrace := preload("res://scripts/diagnostics/performance_trace.gd")
const OceanVisual := preload("res://scripts/simulation/environment_ocean_visual_domain.gd")

const MAX_CELLS_PER_REGION := 48
const SHORELINE_SUBDIVISIONS := 2
const SHORELINE_WIDTH := 8 * SHORELINE_SUBDIVISIONS + 1
const SHORELINE_HEIGHT := 6 * SHORELINE_SUBDIVISIONS + 1
const SHORELINE_CLEARANCE_M := 0.018
const SHORELINE_FINE_WIDTH := (SHORELINE_WIDTH - 1) * 2 + 1
const MAX_REFINED_COAST_QUADS := 96
# At most 96 adaptive 1m tiles and 96 regular tiles, with two triangles
# each and worst-case two output triangles per input triangle.
const MAX_SHORELINE_VERTICES := 5760
const MAX_SPARSE_FINE_SAMPLES := 512
const MAX_POLLS_PER_FRAME := 3
const MAX_REBUILDS_PER_FRAME := 1
const MAX_RAIN_STREAKS := 64
const RAIN_UPDATE_SECONDS := 0.10
const WATER_EPSILON_M := 0.012
# Below one centimeter the water remains authoritative but is not rendered
# as a misleading full-cell puddle after microscopic precipitation.
const MIN_RENDERABLE_FINITE_DEPTH_M := 0.010
const MAX_VISIBLE_DEPTH_M := 4.0
# Presentation-only depth quantization, no change to finite water authority.
const FINITE_VISUAL_DEPTH_STEP_MM := 2
const WATER_WAIT_REPORT_INTERVAL_USEC := 2_000_000

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
var _retained_refreshes_total := 0
var _completed_visual_swaps_total := 0
var _peak_retained_usec := 0
var _unchanged_visual_skips_total := 0
var _peak_rebuild_usec := 0
var _trace_enabled := false
var _dm12_water_trace := false
var _water_debug_mode := "normal"


func _ready() -> void:
	_trace_enabled = PerformanceTrace.is_enabled()
	_dm12_water_trace = _trace_enabled and OS.get_environment("SANDBOX_DM12_FRAME_TRACE") == "1"
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




## Visual-only diagnostic; no environment, terrain, or runtime mutation.
## "off" isolates terrain, "ocean-only" removes rendered finite/river water,
## "sources" assigns distinct colors to real ocean, coast halo and puddles.
func set_water_debug_mode(mode: String) -> bool:
	if mode not in ["normal", "off", "ocean-only", "sources"]:
		return false
	_water_debug_mode = mode
	for id in _region_ids:
		var row: Dictionary = _regions[id]
		row["token"] = ""
		var node: MeshInstance3D = row["node"]
		node.visible = false
		node.mesh = null
		_regions[id] = row
	return true


func get_water_debug_mode() -> String:
	return _water_debug_mode

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
		"water_signature": PackedInt64Array(),
		"refresh_pending": false,
		"retained_source_token": "",
		"retained_visible": false,
		"wait_started_usec": Time.get_ticks_usec(),
		"last_wait_report_usec": 0,
		"shoreline_token": "",
		"shoreline": {},
		"last_vertex_count": 0,
		"last_halo_cells": 0,
		"last_refined_coast_quads": 0,
		"last_ocean_sdf_tiles": 0,
		"last_ocean_seam_edges": 0,
		"ocean_boundary_edges": {},
		"ocean_neighbor_signature": PackedByteArray(),
		"last_ocean_neighbor_anchor_tiles": 0,
		"last_ocean_unadmitted_wet_tiles": 0,
		"last_ocean_unadmitted_boundary_tiles": 0,
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
	var started := Time.get_ticks_usec()
	if _water_debug_mode != "off":
		_poll_resident_regions()
	var poll_usec := Time.get_ticks_usec() - started
	_update_rain(delta, camera_position, focus_region)
	var frame_usec := Time.get_ticks_usec() - started
	if _dm12_water_trace and frame_usec >= 8_000:
		PerformanceTrace.emit("dm12_water_frame", {
			"poll_usec": poll_usec,
			"rain_usec": frame_usec - poll_usec,
			"total_usec": frame_usec,
			"resident_regions": _regions.size(),
			"cursor": _cursor,
		})


func get_visual_metrics() -> Dictionary:
	return {
		"resident_region_nodes": _regions.size(),
		"region_polls_total": _polls_total,
		"region_rebuilds_total": _rebuilds_total,
		"stale_hides_total": _stale_hides_total,
		"retained_refreshes_total": _retained_refreshes_total,
		"completed_visual_swaps_total": _completed_visual_swaps_total,
		"peak_retained_usec": _peak_retained_usec,
		"pending_visual_refreshes": _count_pending_visual_refreshes(),
		"unchanged_visual_skips_total": _unchanged_visual_skips_total,
		"peak_rebuild_usec": _peak_rebuild_usec,
		"rain_visible": _rain_node != null and _rain_node.visible,
		"visible_shoreline_vertices": _count_visible_shoreline_vertices(),
		"water_debug_mode": _water_debug_mode,
		"visible_coastal_halo_cells": _sum_visible_region_metric("last_halo_cells"),
		"visible_refined_coast_quads": _sum_visible_region_metric("last_refined_coast_quads"),
		"visible_ocean_sdf_tiles": _sum_visible_region_metric("last_ocean_sdf_tiles"),
		"visible_ocean_seam_edges": _sum_visible_region_metric("last_ocean_seam_edges"),
		"visible_ocean_neighbor_anchor_tiles": _sum_visible_region_metric("last_ocean_neighbor_anchor_tiles"),
		"visible_ocean_unadmitted_wet_tiles": _sum_visible_region_metric("last_ocean_unadmitted_wet_tiles"),
		"visible_ocean_unadmitted_boundary_tiles": _sum_visible_region_metric("last_ocean_unadmitted_boundary_tiles"),
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
			var physical_depth_m := float(water[index]) / (1_000_000_000.0 * cell_area)
			if physical_depth_m < MIN_RENDERABLE_FINITE_DEPTH_M:
				continue
			y = float(heights[index]) / 1000.0 + minf(physical_depth_m, MAX_VISIBLE_DEPTH_M) + WATER_EPSILON_M
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
	var detail_heights: Dictionary = shoreline.get("fine_height_mm", {})
	var detail_valid: Dictionary = shoreline.get("fine_valid", {})
	if detail_heights.size() > MAX_SPARSE_FINE_SAMPLES or detail_heights.size() != detail_valid.size():
		return false
	var row: Dictionary = _regions[id]
	row["shoreline"] = shoreline.duplicate(true)
	row["shoreline_token"] = _surface_identity(surface_record)
	row["token"] = ""
	_regions[id] = row
	return true



## Invalidate the sample provenance, but NOT the already committed GPU mesh.
## The old presentation is kept until a revision-matched new mesh is ready.
## This changes no SDF, hydrology, collision or persisted authority.
func invalidate_region_shoreline_samples(region_key: Vector2i) -> void:
	var id := _scope_id(region_key)
	if not _regions.has(id):
		return
	var row: Dictionary = _regions[id]
	_begin_pending_visual_refresh(id, row, "terrain_revision_invalidated")
	row["token"] = ""
	row["shoreline_token"] = ""
	row["shoreline"] = {}
	# Old mesh + last metrics intentionally remain committed and visible.
	_regions[id] = row


func has_region_shoreline_samples(region_key: Vector2i, surface_record: Dictionary) -> bool:
	var id := _scope_id(region_key)
	return _regions.has(id) and String(_regions[id].get("shoreline_token", "")) == _surface_identity(surface_record)


func _count_pending_visual_refreshes() -> int:
	var pending := 0
	for id in _region_ids:
		if bool(_regions[id].get("refresh_pending", false)):
			pending += 1
	return pending


## Only a source-verified next mesh can replace an already visible mesh.
## Record a pending refresh once, even if multiple terrain edits supersede it.
func _begin_pending_visual_refresh(id: String, row: Dictionary, reason: String) -> void:
	if bool(row.get("refresh_pending", false)):
		return
	var node: MeshInstance3D = row["node"]
	row["refresh_pending"] = true
	row["retained_visible"] = node.visible and node.mesh != null
	row["retained_source_token"] = String(row.get("token", ""))
	row["wait_started_usec"] = Time.get_ticks_usec()
	row["last_wait_report_usec"] = 0
	if bool(row["retained_visible"]):
		_retained_refreshes_total += 1
		if _trace_enabled:
			PerformanceTrace.emit("p5_water_visual_retained", {
				"scope": id, "reason": reason,
				"old_token": String(row["retained_source_token"]),
				"vertices": int(row.get("last_vertex_count", 0)),
			})


func _sum_visible_region_metric(key: String) -> int:
	var total := 0
	for id in _region_ids:
		var row: Dictionary = _regions[id]
		if (row["node"] as MeshInstance3D).visible:
			total += int(row.get(key, 0))
	return total


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
	shoreline: Dictionary,
	water_debug_mode: String = "normal",
	ocean_domain_enabled: bool = true,
	ocean_external_anchors: Dictionary = {}
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
	var ocean_tiles := 0
	var ocean_edges := 0
	var ocean_refined := 0
	var ocean_sources := 0
	var baseline_rejected_seeds := 0
	var ocean_neighbor_anchors := 0
	var ocean_boundary_edges: Dictionary = {}
	# In ocean-band regions, the ocean is a single clipped SDF plane,
	# not a union of coarse 2m hydro-cell rectangles or coastal halos.
	var continuous_ocean := {
		"ok": true, "vertices": PackedVector3Array(),
		"colors": PackedColorArray(), "water_tiles": 0,
		"ocean_seam_edges": 0, "refined_coast_quads": 0, "source_ocean_cells": 0
	}
	if ocean_domain_enabled:
		continuous_ocean = OceanVisual.build(
			region_key, environment, shoreline, water_debug_mode,
			ocean_external_anchors
		)
	if not continuous_ocean.get("ok", false):
		return continuous_ocean
	var ocean_vertices: PackedVector3Array = continuous_ocean["vertices"]
	var ocean_colors: PackedColorArray = continuous_ocean["colors"]
	vertices.append_array(ocean_vertices)
	colors.append_array(ocean_colors)
	ocean_tiles = int(continuous_ocean.get("water_tiles", 0))
	ocean_edges = int(continuous_ocean.get("ocean_seam_edges", 0))
	ocean_refined = int(continuous_ocean.get("refined_coast_quads", 0))
	ocean_sources = int(continuous_ocean.get("source_ocean_cells", 0))
	baseline_rejected_seeds = int(continuous_ocean.get("baseline_rejected_seeds", 0))
	ocean_neighbor_anchors = int(continuous_ocean.get("ocean_neighbor_anchor_tiles", 0))
	ocean_boundary_edges = continuous_ocean.get("ocean_boundary_edges", {})
	var water_cells := 0
	var refined_quads := 0
	var origin_x := float(region_key.x) * 16.0
	var origin_z := float(region_key.y) * 12.0
	var fine_heights: Dictionary = shoreline.get("fine_height_mm", {})
	var fine_valid: Dictionary = shoreline.get("fine_valid", {})
	if fine_heights.size() > MAX_SPARSE_FINE_SAMPLES or fine_heights.size() != fine_valid.size():
		return {"ok": false, "reason": "shoreline_sparse_samples_invalid"}
	# Retain the legacy R3 path ONLY for synthetic ocean fixtures outside
	# the real ocean band; river and finite puddles still use hydro cells.
	# The actual ocean band never invokes the one-cell halo compensator.
	var real_ocean_band := region_key.y >= OceanVisual.OCEAN_START_REGION_Z
	var render_plan: Dictionary = {"cells": base["cells"], "halo_cells": 0}
	if not real_ocean_band:
		render_plan = _coastal_render_cells(
			region_key, environment, surface_cache, heights, valid, base["cells"]
		)
	var cells: Array = render_plan["cells"]
	for cell_value in cells:
		var cell: Dictionary = cell_value
		var kind := int(cell["kind"])
		# R4: ocean-band hydro cells must never reintroduce rectangular
		# ocean quads, even when they are classified as an ocean source.
		if real_ocean_band and kind == EnvironmentStore.RESERVOIR_OCEAN:
			continue
		if water_debug_mode == "ocean-only" and kind != EnvironmentStore.RESERVOIR_OCEAN:
			continue
		# Below the global sea plane, finite water is already under the
		# R4 ocean surface; avoid two coplanar transparent surfaces.
		if real_ocean_band and kind == EnvironmentStore.RESERVOIR_FINITE and ocean_tiles > 0:
			if float((cell["position"] as Vector3).y) <= float(OceanVisual.OCEAN_LEVEL_MM) / 1000.0 + WATER_EPSILON_M:
				continue
		var color: Color = cell["color"]
		if water_debug_mode == "sources":
			if bool(cell.get("is_halo", false)):
				color = Color(1.0, 0.08, 0.78, 0.97)
			elif int(cell["kind"]) == EnvironmentStore.RESERVOIR_OCEAN:
				color = Color(0.04, 0.31, 0.76, 0.88)
			elif int(cell["kind"]) == EnvironmentStore.RESERVOIR_RIVER:
				color = Color(0.2, 0.88, 0.3, 0.9)
			else:
				color = Color(0.2, 0.94, 0.96, 0.9)
		var index := int(cell["cell_index"])
		var col := index % 8
		var row := int(index / 8)
		var y := float((cell["position"] as Vector3).y)
		var threshold := y - SHORELINE_CLEARANCE_M
		var emitted := false
		for sub_z in range(SHORELINE_SUBDIVISIONS):
			for sub_x in range(SHORELINE_SUBDIVISIONS):
				var x := col * SHORELINE_SUBDIVISIONS + sub_x
				var z := row * SHORELINE_SUBDIVISIONS + sub_z
				var a := z * SHORELINE_WIDTH + x
				var b := a + SHORELINE_WIDTH
				var c := b + 1
				var d := a + 1
				if valid[a] == 0 or valid[b] == 0 or valid[c] == 0 or valid[d] == 0:
					continue
				var wet := 0
				for sample_index in [a, b, c, d]:
					if float(heights[sample_index]) / 1000.0 <= threshold:
						wet += 1
				if wet == 0:
					continue
				# Subdivide only the mixed 1m coastal tiles to 0.5m.
				# Fully submerged interior remains a pair of 1m triangles.
				var subdivisions := 1
				if wet < 4 and refined_quads < MAX_REFINED_COAST_QUADS:
					subdivisions = 2
					refined_quads += 1
				var stride := 2 if subdivisions == 1 else 1
				for tz in range(subdivisions):
					for tx in range(subdivisions):
						var fx := x * 2 + tx * stride
						var fz := z * 2 + tz * stride
						var fine_coords: Array[Vector2i] = [
							Vector2i(fx, fz), Vector2i(fx, fz + stride),
							Vector2i(fx + stride, fz + stride), Vector2i(fx + stride, fz),
						]
						var polygon: Array[Dictionary] = []
						for point in fine_coords:
							var sampled: Dictionary = _shoreline_height_at(
								point.x, point.y, heights, valid,
								fine_heights, fine_valid
							)
							if not sampled.get("ok", false):
								polygon.clear()
								break
							polygon.append({
								"p": Vector2(origin_x + float(point.x) * 0.5,
									origin_z + float(point.y) * 0.5),
								"h": float(sampled["height_mm"]) / 1000.0,
							})
						if polygon.size() != 4:
							continue
						for triangle in [
							[polygon[0], polygon[1], polygon[2]],
							[polygon[0], polygon[2], polygon[3]],
						]:
							var clipped := _clip_under_surface(triangle, threshold)
							for vertex_index in range(1, clipped.size() - 1):
								for corner in [
									clipped[0], clipped[vertex_index], clipped[vertex_index + 1]
								]:
									var point: Vector2 = corner["p"]
									vertices.append(Vector3(point.x, y, point.y))
									colors.append(color)
								emitted = true
		if emitted:
			water_cells += 1
	if vertices.size() > MAX_SHORELINE_VERTICES:
		return {"ok": false, "reason": "shoreline_vertex_budget_exceeded"}
	return {
		"ok": true, "reason": "ok",
		"vertices": vertices, "colors": colors,
		"water_cells": water_cells, "triangles": int(vertices.size() / 3),
		"refined_coast_quads": refined_quads + ocean_refined,
		"coastal_halo_cells": int(render_plan["halo_cells"]),
		"ocean_sdf_tiles": ocean_tiles,
		"ocean_seam_edges": ocean_edges,
		"ocean_source_cells": ocean_sources,
		"ocean_baseline_rejected_seeds": baseline_rejected_seeds,
		"ocean_neighbor_anchor_tiles": ocean_neighbor_anchors,
		"ocean_unadmitted_wet_tiles": int(continuous_ocean.get("unadmitted_wet_tiles", 0)),
		"ocean_unadmitted_boundary_tiles": int(continuous_ocean.get("unadmitted_boundary_wet_tiles", 0)),
		"ocean_components_missing_source": int(continuous_ocean.get("components_missing_source", 0)),
		"ocean_components_missing_boundary": int(continuous_ocean.get("components_missing_boundary", 0)),
		"ocean_boundary_edges": ocean_boundary_edges,
	}


## Coastal visual closure: if the hydro cell center is dry but an adjacent
## authoritative ocean cell wets its subcell SDF edge, extend the *drawing*
## plane one cell. No reservoir binding, volume or simulation state changes.
static func _coastal_render_cells(
	region_key: Vector2i,
	environment: Dictionary,
	surface_cache: Dictionary,
	heights: PackedInt32Array,
	valid: PackedByteArray,
	base_cells: Array
) -> Dictionary:
	var render_cells: Array = base_cells.duplicate(true)
	var used: Dictionary = {}
	var ocean: Dictionary = {}
	for cell_value in base_cells:
		var cell: Dictionary = cell_value
		var id := int(cell["cell_index"])
		used[id] = true
		if int(cell["kind"]) == EnvironmentStore.RESERVOIR_OCEAN:
			ocean[id] = cell
	if ocean.is_empty():
		return {"cells": render_cells, "halo_cells": 0}
	var center_heights: PackedInt64Array = surface_cache["surface_height_mm"]
	var center_valid: PackedByteArray = surface_cache["surface_valid"]
	var kinds: PackedByteArray = environment["reservoir_kind"]
	var halo := 0
	for index in range(48):
		if used.has(index) or int(kinds[index]) != EnvironmentStore.RESERVOIR_FINITE:
			continue
		if center_valid[index] == 0:
			continue
		var cx := index % 8
		var cz := int(index / 8)
		var adjacent_ocean: Dictionary = {}
		for direction_value in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
			var direction: Vector2i = direction_value
			var nx: int = cx + direction.x
			var nz: int = cz + direction.y
			if nx < 0 or nx >= 8 or nz < 0 or nz >= 6:
				continue
			var nid: int = nz * 8 + nx
			if ocean.has(nid):
				adjacent_ocean = ocean[nid]
				break
		if adjacent_ocean.is_empty():
			continue
		var plane_y := float((adjacent_ocean["position"] as Vector3).y)
		var plane_mm := roundi((plane_y - WATER_EPSILON_M) * 1000.0)
		if int(center_heights[index]) <= plane_mm:
			# This is not a partial dry-centered coastal fringe; the
			# existing hydro binding will own this cell.
			continue
		var partly_submerged := false
		for sz in range(3):
			for sx in range(3):
				var sample_id := (cz * 2 + sz) * SHORELINE_WIDTH + cx * 2 + sx
				if valid[sample_id] != 0 and float(heights[sample_id]) / 1000.0 < plane_y - SHORELINE_CLEARANCE_M:
					partly_submerged = true
					break
			if partly_submerged:
				break
		if not partly_submerged:
			continue
		render_cells.append({
			"cell_index": index,
			"kind": EnvironmentStore.RESERVOIR_OCEAN,
			"position": Vector3(
				float(region_key.x) * 16.0 + (float(cx) + 0.5) * 2.0,
				plane_y,
				float(region_key.y) * 12.0 + (float(cz) + 0.5) * 2.0
			),
			"color": adjacent_ocean["color"],
			"is_halo": true,
		})
		halo += 1
	return {"cells": render_cells, "halo_cells": halo}


## Sparse 0.5m true-SDF heights take priority on the coast. If a live
## waterline does not match the worker's pinned refinement levels, use
## bounded bilinear interpolation from the authoritative R2 SDF grid.
static func _shoreline_height_at(
	fx: int, fz: int,
	heights: PackedInt32Array, valid: PackedByteArray,
	fine_heights: Dictionary, fine_valid: Dictionary
) -> Dictionary:
	if fx < 0 or fz < 0 or fx >= SHORELINE_FINE_WIDTH or fz >= (SHORELINE_HEIGHT - 1) * 2 + 1:
		return {"ok": false}
	if fx % 2 == 0 and fz % 2 == 0:
		var index := int(fz / 2) * SHORELINE_WIDTH + int(fx / 2)
		return {"ok": valid[index] != 0, "height_mm": int(heights[index])}
	var site := fz * SHORELINE_FINE_WIDTH + fx
	if fine_heights.has(site):
		return {
			"ok": int(fine_valid.get(site, 0)) != 0,
			"height_mm": int(fine_heights[site])
		}
	var x := mini(int(fx / 2), SHORELINE_WIDTH - 2)
	var z := mini(int(fz / 2), SHORELINE_HEIGHT - 2)
	var a := z * SHORELINE_WIDTH + x
	var b := a + 1
	var c := a + SHORELINE_WIDTH
	var d := c + 1
	if valid[a] == 0 or valid[b] == 0 or valid[c] == 0 or valid[d] == 0:
		return {"ok": false}
	var tx := float(fx) * 0.5 - float(x)
	var tz := float(fz) * 0.5 - float(z)
	var height_mm := lerpf(
		lerpf(float(heights[a]), float(heights[b]), tx),
		lerpf(float(heights[c]), float(heights[d]), tx), tz
	)
	return {"ok": true, "height_mm": roundi(height_mm)}

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


## Read the 48-cell visual state without using the changing logical tick as
## a mesh revision. Sub-2mm water depth changes are presentation-only.
static func _water_visual_signature(
	region_key: Vector2i, environment: Dictionary, surface: Dictionary,
	mode: String, hydrology_enabled: bool, ocean_tiles: int = 0
) -> PackedInt64Array:
	var signature := PackedInt64Array()
	var kinds: PackedByteArray = environment.get("reservoir_kind", PackedByteArray())
	var levels: PackedInt64Array = environment.get("reservoir_level_mm", PackedInt64Array())
	var water: PackedInt64Array = environment.get("surface_water_ul", PackedInt64Array())
	if kinds.size() != MAX_CELLS_PER_REGION or levels.size() != kinds.size() or water.size() != kinds.size():
		return signature
	var cell_area_mm2 := maxi(1, int(surface.get("cell_size_x_mm", 0)) * int(surface.get("cell_size_z_mm", 0)))
	var heights: PackedInt64Array = surface.get("surface_height_mm", PackedInt64Array())
	var valid: PackedByteArray = surface.get("surface_valid", PackedByteArray())
	var sea_visible := (
		region_key.y >= OceanVisual.OCEAN_START_REGION_Z
		and ocean_tiles > 0 and hydrology_enabled and mode != "off"
		and heights.size() == MAX_CELLS_PER_REGION and valid.size() == MAX_CELLS_PER_REGION
	)
	signature.append(1 if hydrology_enabled else 0)
	for index in range(MAX_CELLS_PER_REGION):
		var kind := int(kinds[index])
		if mode == "ocean-only" and kind != EnvironmentStore.RESERVOIR_OCEAN:
			signature.append(0)
			signature.append(0)
			continue
		if kind == EnvironmentStore.RESERVOIR_FINITE:
			# 1 microliter = 1 mm3. Cell area is in square millimeters.
			var depth_mm := int(water[index] / cell_area_mm2)
			if depth_mm < 10 or (
				sea_visible and valid[index] != 0
				and int(heights[index]) + mini(depth_mm, 4000) <= OceanVisual.OCEAN_LEVEL_MM
			):
				# Finite water below the rendered sea is not drawn. It must
				# not rebuild the ocean mesh every runoff tick either.
				signature.append(0)
				signature.append(0)
				continue
			signature.append(1)
			signature.append(1 + int((mini(depth_mm, 4000) - 10) / FINITE_VISUAL_DEPTH_STEP_MM))
		elif kind == EnvironmentStore.RESERVOIR_RIVER:
			signature.append(2)
			signature.append(int(levels[index]))
		elif kind == EnvironmentStore.RESERVOIR_OCEAN:
			signature.append(3)
			signature.append(int(levels[index]))
		else:
			signature.append(-1)
			signature.append(kind)
	return signature


func _water_wait(id: String, row: Dictionary, reason: String) -> void:
	var now := Time.get_ticks_usec()
	if int(row.get("wait_started_usec", 0)) == 0:
		row["wait_started_usec"] = now
		if _trace_enabled:
			PerformanceTrace.emit("p5_water_hidden", {"scope": id, "reason": reason})
	if _trace_enabled and now - int(row.get("last_wait_report_usec", 0)) >= WATER_WAIT_REPORT_INTERVAL_USEC:
		row["last_wait_report_usec"] = now
		PerformanceTrace.emit("p5_water_wait", {
			"scope": id, "reason": reason,
			"wait_usec": now - int(row["wait_started_usec"]),
			"shoreline_token": String(row.get("shoreline_token", "")),
			"retained_visible": bool(row.get("retained_visible", false)),
		})
	_regions[id] = row


## A seam is usable only when the adjacent region has a completed current
## SDF-based visual plan. Retained old meshes during edits are NOT evidence.
func _neighbor_ocean_anchors(region_key: Vector2i) -> Dictionary:
	var result := {}
	for side in ["west", "east", "north", "south"]:
		var offset := Vector2i.ZERO
		var opposite := ""
		match side:
			"west":
				offset = Vector2i(-1, 0)
				opposite = "east"
			"east":
				offset = Vector2i(1, 0)
				opposite = "west"
			"north":
				offset = Vector2i(0, -1)
				opposite = "south"
			"south":
				offset = Vector2i(0, 1)
				opposite = "north"
		var id := _scope_id(region_key + offset)
		if not _regions.has(id):
			continue
		var neighbor: Dictionary = _regions[id]
		if bool(neighbor.get("refresh_pending", false)):
			continue
		var surface: Dictionary = _runtime.get_environment_surface_cache(id)
		if surface.is_empty() or String(neighbor.get("token", "")) != _surface_identity(surface):
			continue
		if String(neighbor.get("shoreline_token", "")) != _surface_identity(surface):
			continue
		var env: Dictionary = _runtime.get_environment_scope(id)
		if env.is_empty():
			continue
		var enabled := true
		if _runtime.has_method("has_environment_hydrology"):
			enabled = bool(_runtime.call("has_environment_hydrology"))
		var signature := _water_visual_signature(
			region_key + offset, env, surface, _water_debug_mode,
			enabled, int(neighbor.get("last_ocean_sdf_tiles", 0))
		)
		if neighbor.get("water_signature", PackedInt64Array()) != signature:
			continue
		var edges: Dictionary = neighbor.get("ocean_boundary_edges", {})
		var mask: PackedByteArray = edges.get(opposite, PackedByteArray())
		if mask.size() > 0:
			result[side] = mask
	return result


static func _neighbor_ocean_signature(anchors: Dictionary) -> PackedByteArray:
	var signature := PackedByteArray()
	for side in ["west", "east", "north", "south"]:
		var mask: PackedByteArray = anchors.get(side, PackedByteArray())
		signature.append_array(mask)
		# A completely absent edge and an explicit all-zero edge must
		# remain equivalent: both are no verified ocean connection.
		if mask.is_empty():
			for _i in range(12 if side == "west" or side == "east" else 16):
				signature.append(0)
	return signature


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
			if not bool(row.get("refresh_pending", false)):
				if node.visible:
					_stale_hides_total += 1
				node.visible = false
				row["token"] = ""
			# A cached, committed mesh is not authority; keep it visible
			# only during a known editing refresh, never after unload.
			_water_wait(id, row, "missing_surface_or_environment")
			continue
		var token := _surface_identity(surface)
		var hydrology_enabled := true
		if _runtime.has_method("has_environment_hydrology"):
			hydrology_enabled = bool(_runtime.call("has_environment_hydrology"))
		var signature := _water_visual_signature(
			row["region_key"], environment, surface, _water_debug_mode,
			hydrology_enabled, int(row.get("last_ocean_sdf_tiles", 0))
		)
		var neighbor_anchors := _neighbor_ocean_anchors(row["region_key"])
		var neighbor_signature := _neighbor_ocean_signature(neighbor_anchors)
		if String(row["token"]) == token \
		and row.get("water_signature", PackedInt64Array()) == signature \
		and row.get("ocean_neighbor_signature", PackedByteArray()) == neighbor_signature:
			_unchanged_visual_skips_total += 1
			continue
		# Defer rather than bursting rebuilds on a loaded/revisited region window.
		if rebuilt >= MAX_REBUILDS_PER_FRAME:
			continue
		if row.get("shoreline_token", "") != _surface_identity(surface):
			# Never fall back to square quads or stale computation; retain
			# only the last complete rendered mesh while waiting for SDF.
			_begin_pending_visual_refresh(id, row, "missing_or_stale_shoreline_samples")
			row["token"] = ""
			_water_wait(id, row, "missing_or_stale_shoreline_samples")
			continue
		var started := Time.get_ticks_usec()
		var plan := derive_shoreline_geometry(
			row["region_key"], environment, surface, row.get("shoreline", {}),
			_water_debug_mode, hydrology_enabled, neighbor_anchors
		)
		if not plan.get("ok", false):
			_begin_pending_visual_refresh(id, row, "mesh_plan_invalid")
			row["token"] = ""
			_water_wait(id, row, "mesh_plan:" + String(plan.get("reason", "unknown")))
			continue
		var dm12_plan_usec := Time.get_ticks_usec() - started
		var vertices: PackedVector3Array = plan["vertices"]
		# Fully prepare the replacement before touching the visible mesh.
		# The one main-thread pointer assignment has no blank frame.
		var replacement: ArrayMesh
		if not vertices.is_empty():
			var arrays: Array = []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = vertices
			arrays[Mesh.ARRAY_COLOR] = plan["colors"]
			replacement = ArrayMesh.new()
			replacement.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			replacement.surface_set_material(0, _water_material)
		var dm12_mesh_creation_usec := Time.get_ticks_usec() - started - dm12_plan_usec
		var old_retained := bool(row.get("retained_visible", false))
		var old_vertices := int(row.get("last_vertex_count", 0))
		var wait_usec := 0
		if int(row.get("wait_started_usec", 0)) > 0:
			wait_usec = Time.get_ticks_usec() - int(row["wait_started_usec"])
		node.mesh = replacement
		node.visible = replacement != null
		if bool(row.get("refresh_pending", false)):
			_completed_visual_swaps_total += 1
			if old_retained:
				_peak_retained_usec = maxi(_peak_retained_usec, wait_usec)
			if _trace_enabled:
				PerformanceTrace.emit("p5_water_visual_swapped", {
					"scope": id, "wait_usec": wait_usec,
					"old_retained": old_retained,
					"old_vertices": old_vertices,
					"new_vertices": vertices.size(),
					"old_token": String(row.get("retained_source_token", "")),
					"new_token": token,
				})
		if node.visible and _trace_enabled and wait_usec > 0:
			PerformanceTrace.emit("p5_water_visible", {
				"scope": id, "wait_usec": wait_usec,
				"triangles": int(vertices.size() / 3),
			})
		row["refresh_pending"] = false
		row["retained_visible"] = false
		row["retained_source_token"] = ""
		row["wait_started_usec"] = 0
		row["last_wait_report_usec"] = 0
		row["token"] = token
		# The signature must describe the water mesh just published. On the
		# first ocean frame, row.last_ocean_sdf_tiles is still zero, so the
		# pre-build signature incorrectly includes finite water hidden under
		# the new sea plane, forcing an unnecessary follow-up rebuild.
		row["water_signature"] = _water_visual_signature(
			row["region_key"], environment, surface, _water_debug_mode,
			hydrology_enabled, int(plan.get("ocean_sdf_tiles", 0))
		)
		row["ocean_neighbor_signature"] = neighbor_signature
		row["ocean_boundary_edges"] = plan.get("ocean_boundary_edges", {})
		row["last_ocean_neighbor_anchor_tiles"] = int(plan.get("ocean_neighbor_anchor_tiles", 0))
		row["last_ocean_unadmitted_wet_tiles"] = int(plan.get("ocean_unadmitted_wet_tiles", 0))
		row["last_ocean_unadmitted_boundary_tiles"] = int(plan.get("ocean_unadmitted_boundary_tiles", 0))
		row["last_vertex_count"] = vertices.size()
		row["last_halo_cells"] = int(plan.get("coastal_halo_cells", 0))
		row["last_refined_coast_quads"] = int(plan.get("refined_coast_quads", 0))
		row["last_ocean_sdf_tiles"] = int(plan.get("ocean_sdf_tiles", 0))
		row["last_ocean_seam_edges"] = int(plan.get("ocean_seam_edges", 0))
		_regions[id] = row
		rebuilt += 1
		_rebuilds_total += 1
		var elapsed := Time.get_ticks_usec() - started
		_peak_rebuild_usec = maxi(_peak_rebuild_usec, elapsed)
		if _dm12_water_trace and elapsed >= 8_000:
			PerformanceTrace.emit("dm12_water_rebuild_breakdown", {
				"scope": id,
				"total_usec": elapsed,
				"derive_shoreline_usec": dm12_plan_usec,
				"arraymesh_creation_usec": dm12_mesh_creation_usec,
				"post_swap_bookkeeping_usec": maxi(0, elapsed - dm12_plan_usec - dm12_mesh_creation_usec),
				"triangles": int(vertices.size() / 3),
			})
		if _trace_enabled:
			PerformanceTrace.emit("p5_environment_visual_rebuild", {
				"scope": id,
				"duration_usec": elapsed,
				"vertices": vertices.size(),
				"triangles": int(vertices.size() / 3),
				"water_cells": int(plan.get("water_cells", 0)),
				"refined_coast_quads": int(plan.get("refined_coast_quads", 0)),
				"coastal_halo_cells": int(plan.get("coastal_halo_cells", 0)),
				"ocean_sdf_tiles": int(plan.get("ocean_sdf_tiles", 0)),
				"ocean_seam_edges": int(plan.get("ocean_seam_edges", 0)),
				"ocean_baseline_rejected_seeds": int(plan.get("ocean_baseline_rejected_seeds", 0)),
				"ocean_neighbor_anchor_tiles": int(plan.get("ocean_neighbor_anchor_tiles", 0)),
				"ocean_unadmitted_wet_tiles": int(plan.get("ocean_unadmitted_wet_tiles", 0)),
				"ocean_unadmitted_boundary_tiles": int(plan.get("ocean_unadmitted_boundary_tiles", 0)),
				"ocean_components_missing_source": int(plan.get("ocean_components_missing_source", 0)),
				"ocean_components_missing_boundary": int(plan.get("ocean_components_missing_boundary", 0)),
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
