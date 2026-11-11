extends RefCounted
class_name EnvironmentOceanVisualDomain

## P5.0F-R4: ocean-only, presentation-only topology on the SDF lattice.
## Hydrology remains authoritative and unchanged (8x6, fixed reservoir).
## The ocean mask is NOT truncated at hydro-cell or halo-cell boundaries.

const Hydrology := preload("res://scripts/simulation/environment_hydrology_domain.gd")
const EnvironmentStore := preload("res://scripts/simulation/environment_state_store.gd")

const WIDTH := 17
const HEIGHT := 13
const TILES_X := WIDTH - 1
const TILES_Z := HEIGHT - 1
const TILE_COUNT := TILES_X * TILES_Z
const FINE_WIDTH := TILES_X * 2 + 1
const OCEAN_THRESHOLD_OFFSET_M := 0.018
const DRAW_OFFSET_M := 0.012
const MAX_COAST_REFINEMENT_QUADS := 96
const MAX_MESH_VERTICES := 5760
const OCEAN_START_REGION_Z := int(Hydrology.OCEAN_START_GLOBAL_CELL_Z / 6)
const OCEAN_LEVEL_MM := Hydrology.OCEAN_LEVEL_MM


## The caller first verifies SDF cache provenance and the immutable 8x6
## environmental arrays. No engine node or mutable source is accessed here.
static func build(
	region_key: Vector2i,
	environment: Dictionary,
	shoreline: Dictionary,
	debug_mode: String = "normal",
	external_anchor_edges: Dictionary = {}
) -> Dictionary:
	var output := {
		"ok": true, "vertices": PackedVector3Array(),
		"colors": PackedColorArray(), "water_tiles": 0,
		"refined_coast_quads": 0, "ocean_components": 0,
		"isolated_components_skipped": 0,
		"baseline_rejected_seeds": 0,
		"ocean_seam_edges": 0, "source_ocean_cells": 0,
		"ocean_neighbor_anchor_tiles": 0,
		"unadmitted_wet_tiles": 0,
		"unadmitted_boundary_wet_tiles": 0,
		"components_missing_source": 0,
		"components_missing_boundary": 0,
		"ocean_boundary_edges": {},
	}
	if region_key.y < OCEAN_START_REGION_Z:
		return output
	var kinds: PackedByteArray = environment.get("reservoir_kind", PackedByteArray())
	var levels: PackedInt64Array = environment.get("reservoir_level_mm", PackedInt64Array())
	if kinds.size() != 48 or levels.size() != 48:
		return {"ok": false, "reason": "ocean_authority_shape_invalid"}
	var ocean_sources := PackedByteArray()
	ocean_sources.resize(48)
	for index in range(48):
		if int(kinds[index]) != EnvironmentStore.RESERVOIR_OCEAN:
			continue
		if int(levels[index]) != Hydrology.OCEAN_LEVEL_MM:
			return {"ok": false, "reason": "ocean_level_pin_mismatch"}
		ocean_sources[index] = 1
		output["source_ocean_cells"] = int(output["source_ocean_cells"]) + 1

	var heights: PackedInt32Array = shoreline.get("height_mm", PackedInt32Array())
	var valid: PackedByteArray = shoreline.get("valid", PackedByteArray())
	if heights.size() != WIDTH * HEIGHT or valid.size() != heights.size():
		return {"ok": false, "reason": "ocean_sdf_lattice_invalid"}
	var base_sea_wet: PackedByteArray = shoreline.get("base_sea_wet", PackedByteArray())
	if base_sea_wet.size() != 0 and base_sea_wet.size() != WIDTH * HEIGHT:
		return {"ok": false, "reason": "ocean_baseline_provenance_invalid"}
	var has_baseline := base_sea_wet.size() == WIDTH * HEIGHT
	# Only evidence from a currently published, source-validated adjacent
	# region may authorize a connection across the 16x12m visual boundary.
	for side in ["west", "east", "north", "south"]:
		var mask: PackedByteArray = external_anchor_edges.get(side, PackedByteArray())
		var expected := TILES_Z if side == "west" or side == "east" else TILES_X
		if mask.size() != 0 and mask.size() != expected:
			return {"ok": false, "reason": "ocean_neighbor_edge_shape_invalid"}
	var sparse_heights: Dictionary = shoreline.get("fine_height_mm", {})
	var sparse_valid: Dictionary = shoreline.get("fine_valid", {})
	if sparse_heights.size() > 512 or sparse_heights.size() != sparse_valid.size():
		return {"ok": false, "reason": "ocean_sparse_lattice_invalid"}

	var level_m := float(Hydrology.OCEAN_LEVEL_MM) / 1000.0
	var threshold := level_m - OCEAN_THRESHOLD_OFFSET_M
	var wet := PackedByteArray()
	wet.resize(TILE_COUNT)
	var seeds: Array[int] = []
	var native_seed := PackedByteArray()
	native_seed.resize(TILE_COUNT)
	for z in range(TILES_Z):
		for x in range(TILES_X):
			var id := z * TILES_X + x
			var a := z * WIDTH + x
			var b := a + 1
			var c := a + WIDTH
			var d := c + 1
			if valid[a] == 0 or valid[b] == 0 or valid[c] == 0 or valid[d] == 0:
				continue
			if mini(mini(heights[a], heights[b]), mini(heights[c], heights[d])) >= roundi(threshold * 1000.0):
				continue
			wet[id] = 1
			var hydro_id := int(z / 2) * 8 + int(x / 2)
			var from_authority := ocean_sources[hydro_id] != 0
			# Open-sea (+Z) boundary: the same world-space SDF samples
			# are shared with the neighboring region, without a region-local
			# rectangle ending at the hydro mask. The ocean band itself is
			# a core-defined infinite fixed-level reservoir.
			var seaward := z == TILES_Z - 1 and (
				heights[(z + 1) * WIDTH + x] < roundi(threshold * 1000.0)
				or heights[(z + 1) * WIDTH + x + 1] < roundi(threshold * 1000.0)
			)
			# An admitted sea component in a READY neighbor can extend through
			# the matching wet SDF edge even where this region has no native
			# sea source. This is visual connectivity, not new water authority.
			var external_source := false
			if x == 0 and _neighbor_edge_anchor(external_anchor_edges, "west", z, x, z, heights, valid, threshold):
				external_source = true
			if x == TILES_X - 1 and _neighbor_edge_anchor(external_anchor_edges, "east", z, x, z, heights, valid, threshold):
				external_source = true
			if z == 0 and _neighbor_edge_anchor(external_anchor_edges, "north", x, x, z, heights, valid, threshold):
				external_source = true
			if z == TILES_Z - 1 and _neighbor_edge_anchor(external_anchor_edges, "south", x, x, z, heights, valid, threshold):
				external_source = true
			if external_source:
				seeds.append(id)
				output["ocean_neighbor_anchor_tiles"] = int(output["ocean_neighbor_anchor_tiles"]) + 1
			if from_authority or seaward:
				# The P5.0E V1 binding classifies any newly excavated low cell
				# in the ocean band as an infinite reservoir. That classification
				# is not proof of sea connectivity. Restrict the *visual* source
				# to sites wet in the unedited canonical terrain. Excavated
				# tiles may still flood when connected through current wet SDF
				# tiles to a proven baseline sea component.
				var baseline_source := not has_baseline or (
					base_sea_wet[a] != 0 or base_sea_wet[b] != 0
					or base_sea_wet[c] != 0 or base_sea_wet[d] != 0
				)
				if baseline_source:
					seeds.append(id)
					native_seed[id] = 1
				else:
					output["baseline_rejected_seeds"] = int(
						output["baseline_rejected_seeds"]
					) + 1
	# R5: an authoritative 2m ocean binding is only a candidate seed.
	# A newly excavated landlocked depression may have become bound by
	# height alone. Render a candidate component only when it has a real
	# submerged opening to a region boundary. Global cross-region ocean
	# connectivity remains a separate qualification obligation.
	var is_seed := PackedByteArray()
	is_seed.resize(TILE_COUNT)
	for id in seeds:
		is_seed[id] = 1
	var processed := PackedByteArray()
	var admitted := PackedByteArray()
	var trusted_export := PackedByteArray()
	processed.resize(TILE_COUNT)
	admitted.resize(TILE_COUNT)
	trusted_export.resize(TILE_COUNT)
	var admitted_components := 0
	var isolated_components := 0
	for start in range(TILE_COUNT):
		if wet[start] == 0 or processed[start] != 0:
			continue
		var queue: Array[int] = [start]
		var component_tiles: Array[int] = []
		processed[start] = 1
		var seed_found := false
		var native_found := false
		var boundary_open := false
		var head := 0
		while head < queue.size():
			var id := queue[head]
			head += 1
			component_tiles.append(id)
			if is_seed[id] != 0:
				seed_found = true
			if native_seed[id] != 0:
				native_found = true
			var x := id % TILES_X
			var z := int(id / TILES_X)
			if _open_boundary_wet_edge(x, z, heights, valid, threshold):
				boundary_open = true
			for direction_value in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
				var direction: Vector2i = direction_value
				var nx: int = x + direction.x
				var nz: int = z + direction.y
				if nx < 0 or nx >= TILES_X or nz < 0 or nz >= TILES_Z:
					continue
				var nid: int = nz * TILES_X + nx
				if wet[nid] == 0 or processed[nid] != 0:
					continue
				if not _shared_wet_edge(x, z, direction, heights, valid, threshold):
					continue
				processed[nid] = 1
				queue.append(nid)
		if seed_found and boundary_open:
			admitted_components += 1
			for tile_id in component_tiles:
				admitted[tile_id] = 1
				# Export only native-source-rooted edges: no circular
				# mutual anchoring between two formerly valid neighbors.
				if native_found:
					trusted_export[tile_id] = 1
		elif seed_found:
			isolated_components += 1
			output["components_missing_boundary"] = int(output["components_missing_boundary"]) + 1
		else:
			output["components_missing_source"] = int(output["components_missing_source"]) + 1
	# Report shared-edge coverage of admitted sea. A neighbor can use these
	# only while this source region's SDF and environmental tokens remain
	# current, never while an old visual mesh is retained during an edit.
	var boundary_edges := {
		"west": _empty_edge_mask(TILES_Z),
		"east": _empty_edge_mask(TILES_Z),
		"north": _empty_edge_mask(TILES_X),
		"south": _empty_edge_mask(TILES_X),
	}
	for z in range(TILES_Z):
		for x in range(TILES_X):
			if trusted_export[z * TILES_X + x] == 0:
				continue
			if x == 0 and _shared_wet_edge(x, z, Vector2i(-1, 0), heights, valid, threshold):
				var left: PackedByteArray = boundary_edges["west"]
				left[z] = 1
				boundary_edges["west"] = left
			if x == TILES_X - 1 and _shared_wet_edge(x, z, Vector2i(1, 0), heights, valid, threshold):
				var right: PackedByteArray = boundary_edges["east"]
				right[z] = 1
				boundary_edges["east"] = right
			if z == 0 and _shared_wet_edge(x, z, Vector2i(0, -1), heights, valid, threshold):
				var up: PackedByteArray = boundary_edges["north"]
				up[x] = 1
				boundary_edges["north"] = up
			if z == TILES_Z - 1 and _shared_wet_edge(x, z, Vector2i(0, 1), heights, valid, threshold):
				var down: PackedByteArray = boundary_edges["south"]
				down[x] = 1
				boundary_edges["south"] = down
	output["ocean_boundary_edges"] = boundary_edges
	for z in range(TILES_Z):
		for x in range(TILES_X):
			var tile_id := z * TILES_X + x
			if wet[tile_id] == 0 or admitted[tile_id] != 0:
				continue
			output["unadmitted_wet_tiles"] = int(output["unadmitted_wet_tiles"]) + 1
			if (x == 0 or x == TILES_X - 1 or z == 0 or z == TILES_Z - 1) and _open_boundary_wet_edge(x, z, heights, valid, threshold):
				output["unadmitted_boundary_wet_tiles"] = int(output["unadmitted_boundary_wet_tiles"]) + 1
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	var origin_x := float(region_key.x) * float(TILES_X)
	var origin_z := float(region_key.y) * float(TILES_Z)
	var water_color := Color(0.05, 0.31, 0.60, 0.80)
	if debug_mode == "sources":
		water_color = Color(0.04, 0.31, 0.76, 0.88)
	var refines := 0
	var sea_edges := 0
	var water_tiles := 0
	for z in range(TILES_Z):
		for x in range(TILES_X):
			var tile_id := z * TILES_X + x
			if admitted[tile_id] == 0:
				continue
			var a := z * WIDTH + x
			var b := a + 1
			var c := a + WIDTH
			var d := c + 1
			var min_h: int = mini(mini(heights[a], heights[b]), mini(heights[c], heights[d]))
			var max_h: int = maxi(maxi(heights[a], heights[b]), maxi(heights[c], heights[d]))
			var subdivision := 1
			if min_h < roundi(threshold * 1000.0) and max_h > roundi(threshold * 1000.0) and refines < MAX_COAST_REFINEMENT_QUADS:
				subdivision = 2
				refines += 1
			var stride := 2 if subdivision == 1 else 1
			var emitted := false
			for local_z in range(subdivision):
				for local_x in range(subdivision):
					var fx := x * 2 + local_x * stride
					var fz := z * 2 + local_z * stride
					var points: Array[Vector2i] = [
						Vector2i(fx, fz), Vector2i(fx, fz + stride),
						Vector2i(fx + stride, fz + stride), Vector2i(fx + stride, fz),
					]
					var polygon: Array[Dictionary] = []
					for point in points:
						var sample := _height_at(point.x, point.y, heights, valid, sparse_heights, sparse_valid)
						if not sample.get("ok", false):
							polygon.clear()
							break
						polygon.append({
							"p": Vector2(origin_x + float(point.x) * 0.5, origin_z + float(point.y) * 0.5),
							"h": float(sample["height_mm"]) / 1000.0
						})
					if polygon.size() != 4:
						continue
					for triangle in [[polygon[0], polygon[1], polygon[2]], [polygon[0], polygon[2], polygon[3]]]:
						var clipped := _clip_wet_triangle(triangle, threshold)
						for i in range(1, clipped.size() - 1):
							for point_value in [clipped[0], clipped[i], clipped[i + 1]]:
								var point: Vector2 = point_value["p"]
								vertices.append(Vector3(point.x, level_m + DRAW_OFFSET_M, point.y))
								colors.append(water_color)
							emitted = true
			if emitted:
				water_tiles += 1
				if x == 0 or x == TILES_X - 1 or z == 0 or z == TILES_Z - 1:
					sea_edges += 1
	if vertices.size() > MAX_MESH_VERTICES:
		return {"ok": false, "reason": "ocean_visual_vertex_budget_exceeded"}
	output["vertices"] = vertices
	output["colors"] = colors
	output["water_tiles"] = water_tiles
	output["ocean_components"] = admitted_components
	output["isolated_components_skipped"] = isolated_components
	output["ocean_seam_edges"] = sea_edges
	output["refined_coast_quads"] = refines
	return output


static func _empty_edge_mask(length: int) -> PackedByteArray:
	var mask := PackedByteArray()
	mask.resize(length)
	return mask


static func _neighbor_edge_anchor(
	anchors: Dictionary, side: String, index: int, x: int, z: int,
	heights: PackedInt32Array, valid: PackedByteArray, threshold: float
) -> bool:
	var mask: PackedByteArray = anchors.get(side, PackedByteArray())
	if index < 0 or index >= mask.size() or mask[index] == 0:
		return false
	var direction := Vector2i.ZERO
	match side:
		"west": direction = Vector2i(-1, 0)
		"east": direction = Vector2i(1, 0)
		"north": direction = Vector2i(0, -1)
		"south": direction = Vector2i(0, 1)
	return _shared_wet_edge(x, z, direction, heights, valid, threshold)


## A component must have a wet segment on at least one of its four
## region boundaries. This is necessary, but not sufficient, for global
## ocean connectivity: neighboring unloaded regions still need qualification.
static func _open_boundary_wet_edge(
	x: int, z: int,
	heights: PackedInt32Array, valid: PackedByteArray, threshold: float
) -> bool:
	var edge_pairs: Array[Vector2i] = []
	if x == 0:
		edge_pairs.append(Vector2i(z * WIDTH, (z + 1) * WIDTH))
	if x == TILES_X - 1:
		edge_pairs.append(Vector2i(z * WIDTH + TILES_X, (z + 1) * WIDTH + TILES_X))
	if z == 0:
		edge_pairs.append(Vector2i(x, x + 1))
	if z == TILES_Z - 1:
		edge_pairs.append(Vector2i(TILES_Z * WIDTH + x, TILES_Z * WIDTH + x + 1))
	for edge in edge_pairs:
		if valid[edge.x] != 0 and valid[edge.y] != 0 and (
			float(mini(heights[edge.x], heights[edge.y])) / 1000.0 < threshold
		):
			return true
	return false


## Two neighboring wet tiles connect only if their actual shared SDF edge
## intersects the same ocean plane. No diagonal corner-only shortcuts.
static func _shared_wet_edge(
	x: int, z: int, dir: Vector2i,
	heights: PackedInt32Array, valid: PackedByteArray,
	threshold: float
) -> bool:
	var ax := x
	var az := z
	var bx := x
	var bz := z
	if dir.x == -1:
		ax = x
		az = z
		bx = x
		bz = z + 1
	elif dir.x == 1:
		ax = x + 1
		az = z
		bx = x + 1
		bz = z + 1
	elif dir.y == -1:
		ax = x
		az = z
		bx = x + 1
		bz = z
	else:
		ax = x
		az = z + 1
		bx = x + 1
		bz = z + 1
	var a := az * WIDTH + ax
	var b := bz * WIDTH + bx
	return valid[a] != 0 and valid[b] != 0 and minf(
		float(heights[a]) / 1000.0, float(heights[b]) / 1000.0
	) < threshold


static func _height_at(
	fx: int, fz: int,
	heights: PackedInt32Array, valid: PackedByteArray,
	sparse_heights: Dictionary, sparse_valid: Dictionary
) -> Dictionary:
	if fx < 0 or fz < 0 or fx > TILES_X * 2 or fz > TILES_Z * 2:
		return {"ok": false}
	if fx % 2 == 0 and fz % 2 == 0:
		var index := int(fz / 2) * WIDTH + int(fx / 2)
		return {"ok": valid[index] != 0, "height_mm": int(heights[index])}
	var site := fz * FINE_WIDTH + fx
	if sparse_heights.has(site):
		return {"ok": int(sparse_valid.get(site, 0)) != 0, "height_mm": int(sparse_heights[site])}
	var x := mini(int(fx / 2), TILES_X - 1)
	var z := mini(int(fz / 2), TILES_Z - 1)
	var a := z * WIDTH + x
	var b := a + 1
	var c := a + WIDTH
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


static func _clip_wet_triangle(triangle: Array, threshold: float) -> Array[Dictionary]:
	var clipped: Array[Dictionary] = []
	for i in range(triangle.size()):
		var current: Dictionary = triangle[i]
		var previous: Dictionary = triangle[(i + triangle.size() - 1) % triangle.size()]
		var current_wet := float(current["h"]) <= threshold
		var previous_wet := float(previous["h"]) <= threshold
		if current_wet != previous_wet:
			var amount := clampf(
				(threshold - float(previous["h"])) / (float(current["h"]) - float(previous["h"])),
				0.0, 1.0
			)
			clipped.append({
				"p": (previous["p"] as Vector2).lerp(current["p"], amount), "h": threshold
			})
		if current_wet:
			clipped.append(current)
	return clipped
