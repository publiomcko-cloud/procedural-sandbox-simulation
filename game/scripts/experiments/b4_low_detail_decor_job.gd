extends RefCounted

## DM5: low-detail presentation of the SAME deterministic population and
## hydrology constants as the authoritative world. No persistence, mutation,
## scene tree, material creation, or authoritative region admission here.
const ObjectWorld := preload("res://scripts/objects/procedural_object_world.gd")
const Field := preload("res://scripts/terrain/sdf_world.gd")
const Hydro := preload("res://scripts/simulation/environment_hydrology_domain.gd")

const GRID_X := 16
const GRID_Z := 12
const HYDRO_CELL_METERS := 2.0
const MAX_ROCKS := 64
const MAX_WATER_TRIANGLES := 2000
const OCEAN_COLOR := Color(0.05, 0.31, 0.60, 0.80)
const RIVER_COLOR := Color(0.08, 0.41, 0.73, 0.78)

var world_seed := 0
var world_id := ""
var region_key := Vector2i.ZERO
var registry: RefCounted
var result: Dictionary = {}
var worker_started_usec := 0
var worker_finished_usec := 0

func _init(seed: int, id: String, key: Vector2i, content_registry: RefCounted) -> void:
	world_seed = seed
	world_id = id
	region_key = key
	registry = content_registry


func run() -> void:
	worker_started_usec = Time.get_ticks_usec()
	result = build_data(world_seed, world_id, region_key, registry)
	worker_finished_usec = Time.get_ticks_usec()
	result["worker_usec"] = worker_finished_usec - worker_started_usec


static func build_data(
	seed: int, id: String, key: Vector2i, content_registry: RefCounted
) -> Dictionary:
	var rocks: Array[Dictionary] = []
	var rock_status := "population_registry_not_available"
	if content_registry != null and not id.is_empty():
		var generated: Dictionary = ObjectWorld.build_region_instances(
			seed, id, key, content_registry
		)
		if not generated.get("ok", false):
			rock_status = String(generated.get("reason", "population_failure"))
		else:
			rock_status = "source_matched"
			for value in generated.get("instances", []):
				var instance: Dictionary = value
				if rocks.size() >= MAX_ROCKS:
					break
				var geometry: Dictionary = instance.get("geometry", {})
				var extents := Vector3(
					float(geometry.get("half_extent_x_mm", 0)) / 1000.0,
					float(geometry.get("half_extent_y_mm", 0)) / 1000.0,
					float(geometry.get("half_extent_z_mm", 0)) / 1000.0
				)
				if extents.x <= 0.0 or extents.y <= 0.0 or extents.z <= 0.0:
					continue
				var scaled: Vector3i = instance.get(
					"default_scale_milli", Vector3i(1000, 1000, 1000)
				)
				rocks.append({
					"position": Vector3(instance["position_mm"]) / 1000.0,
					"scale": extents * Vector3(scaled) / 1000.0,
					"yaw": float(instance.get("default_yaw_mdeg", 0)) * PI / 180000.0,
					"instance_id": String(instance.get("instance_id", "")),
				})
	var water := _build_low_water(seed, key)
	return {
		"valid": bool(water.get("valid", false)),
		"region_key": key,
		"rocks": rocks,
		"rock_status": rock_status,
		"rock_count": rocks.size(),
		"water_positions": water.get("positions", PackedVector3Array()),
		"water_colors": water.get("colors", PackedColorArray()),
		"water_triangles": int(water.get("triangle_count", 0)),
		"ocean_triangles": int(water.get("ocean_triangles", 0)),
		"river_triangles": int(water.get("river_triangles", 0)),
		"visual_only": true,
	}


static func _build_low_water(seed: int, key: Vector2i) -> Dictionary:
	var heights := PackedFloat32Array()
	heights.resize((GRID_X + 1) * (GRID_Z + 1))
	for z in range(GRID_Z + 1):
		for x in range(GRID_X + 1):
			heights[z * (GRID_X + 1) + x] = _top_y(
				seed, key, float(x), float(z)
			)
	var positions := PackedVector3Array()
	var colors := PackedColorArray()
	var oceans := 0
	var rivers := 0
	if key.y * 6 >= Hydro.OCEAN_START_GLOBAL_CELL_Z:
		var level := float(Hydro.OCEAN_LEVEL_MM) / 1000.0
		for z in range(GRID_Z):
			for x in range(GRID_X):
				var i := z * (GRID_X + 1) + x
				var vertices: Array[Vector3] = [
					Vector3(x, heights[i], z),
					Vector3(x+1, heights[i+1], z),
					Vector3(x, heights[i+GRID_X+1], z+1),
					Vector3(x+1, heights[i+GRID_X+2], z+1)
				]
				oceans += _append_wet_triangle(
					positions, colors, vertices[0], vertices[2], vertices[1],
					level, OCEAN_COLOR
				)
				oceans += _append_wet_triangle(
					positions, colors, vertices[1], vertices[2], vertices[3],
					level, OCEAN_COLOR
				)
	# Generated river reservoirs are 2x2m environmental cells. This follows
	# Hydrology._river_center_global_x's v1 deterministic triangular meander,
	# but does not render mutable finite water or assert reservoir authority.
	for z_cell in range(6):
		var global_z := key.y * 6 + z_cell
		var river_x := river_center_global_x(seed, global_z)
		var x_cell := river_x - key.x * 8
		if x_cell < 0 or x_cell >= 8:
			continue
		var cx := float(x_cell) * HYDRO_CELL_METERS + 1.0
		var cz := float(z_cell) * HYDRO_CELL_METERS + 1.0
		var center_height := _top_y(seed, key, cx, cz)
		if not is_finite(center_height) or center_height * 1000.0 > Hydro.RIVER_MAX_TERRAIN_MM:
			continue
		if key.y * 6 >= Hydro.OCEAN_START_GLOBAL_CELL_Z \
				and center_height < float(Hydro.OCEAN_LEVEL_MM) / 1000.0:
			continue
		var level := center_height + float(Hydro.RIVER_LEVEL_OFFSET_MM) / 1000.0
		var x0 := x_cell * 2
		var z0 := z_cell * 2
		for zz in range(z0, z0 + 2):
			for xx in range(x0, x0 + 2):
				var i := zz * (GRID_X + 1) + xx
				var a := Vector3(xx, heights[i], zz)
				var b := Vector3(xx+1, heights[i+1], zz)
				var c := Vector3(xx, heights[i+GRID_X+1], zz+1)
				var d := Vector3(xx+1, heights[i+GRID_X+2], zz+1)
				rivers += _append_wet_triangle(positions, colors, a, c, b, level, RIVER_COLOR)
				rivers += _append_wet_triangle(positions, colors, b, c, d, level, RIVER_COLOR)
	if positions.size() / 3 > MAX_WATER_TRIANGLES:
		return {"valid": false, "reason": "water_preview_triangle_budget_exceeded"}
	return {
		"valid": true,
		"positions": positions,
		"colors": colors,
		"triangle_count": positions.size() / 3,
		"ocean_triangles": oceans,
		"river_triangles": rivers,
	}


static func river_center_global_x(seed: int, global_z: int) -> int:
	var seed_base := posmod(seed, 17) - 8
	var phase := posmod(global_z + posmod(seed, Hydro.RIVER_PERIOD_CELLS),
		Hydro.RIVER_PERIOD_CELLS)
	var triangle := phase if phase < Hydro.RIVER_HALF_PERIOD_CELLS \
		else Hydro.RIVER_PERIOD_CELLS - 1 - phase
	var meander := (triangle - (Hydro.RIVER_HALF_PERIOD_CELLS / 2)) \
		/ Hydro.RIVER_MEANDER_DIVISOR
	return seed_base + meander


static func _top_y(seed: int, key: Vector2i, x: float, z: float) -> float:
	# Surface-only samples, from air downward, exclude internal caves; they
	# are never passed to the authoritative terrain or hydro runtime.
	var above := 8.0
	var below := above
	for n in range(1, 19):
		below = 8.0 - float(n) * 0.5
		if Field.sample_density(seed, key, Vector3(x, below, z)) >= 0.0:
			for _b in range(7):
				var middle := (above + below) * 0.5
				if Field.sample_density(seed, key, Vector3(x, middle, z)) >= 0.0:
					below = middle
				else:
					above = middle
			return (above + below) * 0.5
		above = below
	return NAN


static func _append_wet_triangle(
	positions: PackedVector3Array, colors: PackedColorArray,
	a: Vector3, b: Vector3, c: Vector3, level: float, tint: Color
) -> int:
	if not (is_finite(a.y) and is_finite(b.y) and is_finite(c.y)):
		return 0
	var vertices: Array[Vector3] = [a, b, c]
	var clipped: Array[Vector3] = []
	var previous := vertices[-1]
	var previous_inside := previous.y < level - 0.018
	for current in vertices:
		var inside := current.y < level - 0.018
		if inside != previous_inside:
			var dy := current.y - previous.y
			if absf(dy) > 0.000001:
				clipped.append(previous.lerp(current, clampf(
					(level - 0.018 - previous.y) / dy, 0.0, 1.0
				)))
		if inside:
			clipped.append(current)
		previous = current
		previous_inside = inside
	if clipped.size() < 3:
		return 0
	var count := 0
	for i in range(1, clipped.size() - 1):
		var points := [
			Vector3(clipped[0].x, level + 0.012, clipped[0].z),
			Vector3(clipped[i].x, level + 0.012, clipped[i].z),
			Vector3(clipped[i+1].x, level + 0.012, clipped[i+1].z),
		]
		if (points[1] - points[0]).cross(points[2] - points[0]).length_squared() < 0.000001:
			continue
		for p in points:
			positions.append(p)
			colors.append(tint)
		count += 1
	return count
