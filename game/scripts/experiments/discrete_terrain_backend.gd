class_name ExperimentalDiscreteTerrainBackend
extends RefCounted

## Isolated experimental alternative: a dense byte occupancy lattice with
## deterministic 3D greedy quad meshing. NOT authoritative gameplay terrain.
## This is intentionally a radical block/occupancy alternative to smooth SDF.
const Field := preload("res://scripts/terrain/sdf_world.gd")
const Grid := preload("res://scripts/terrain/terrain_chunk_grid.gd")

var step := 0.5
var seed := 0
var region_key := Vector2i.ZERO
var dims := Vector3i.ZERO
var padded := Vector3i.ZERO
var cells := PackedByteArray()
var solid_count := 0
var last_changed := 0


func generate(seed_value: int, region_value: Vector2i, step_value: float) -> bool:
	if step_value != 0.5 and step_value != 0.25 and step_value != 0.125:
		return false
	seed = seed_value
	region_key = region_value
	step = step_value
	dims = Vector3i(
		roundi((Grid.MAX_BOUND.x - Grid.MIN_BOUND.x) / step),
		roundi((Grid.MAX_BOUND.y - Grid.MIN_BOUND.y) / step),
		roundi((Grid.MAX_BOUND.z - Grid.MIN_BOUND.z) / step)
	)
	padded = dims + Vector3i(2, 2, 2)
	cells.resize(padded.x * padded.y * padded.z)
	solid_count = 0
	# One-cell halo prevents false walls on chunk and region boundaries.
	for y in range(-1, dims.y + 1):
		for z in range(-1, dims.z + 1):
			for x in range(-1, dims.x + 1):
				var local := Vector3(
					(float(x) + 0.5) * step,
					Grid.MIN_BOUND.y + (float(y) + 0.5) * step,
					(float(z) + 0.5) * step
				)
				var value := 1 if Field.sample_density(seed, region_key, local) >= 0.0 else 0
				cells[_index(x, y, z)] = value
				if x >= 0 and x < dims.x and y >= 0 and y < dims.y \
						and z >= 0 and z < dims.z and value == 1:
					solid_count += 1
	return true


func byte_count() -> int:
	return cells.size()


func occupancy(x: int, y: int, z: int) -> int:
	if x < -1 or x > dims.x or y < -1 or y > dims.y \
			or z < -1 or z > dims.z:
		return 0
	return cells[_index(x, y, z)]


func sample_local(local: Vector3) -> int:
	var x := floori(local.x / step)
	var y := floori((local.y - Grid.MIN_BOUND.y) / step)
	var z := floori(local.z / step)
	return occupancy(x, y, z)


func edit_sphere(mode: int, center_world: Vector3, radius: float) -> int:
	var local := center_world - Vector3(
		float(region_key.x) * Field.REGION_SIZE_X,
		0.0,
		float(region_key.y) * Field.REGION_SIZE_Z
	)
	var min_cell := Vector3i(
		maxi(-1, floori((local.x - radius) / step) - 1),
		maxi(-1, floori((local.y - radius - Grid.MIN_BOUND.y) / step) - 1),
		maxi(-1, floori((local.z - radius) / step) - 1)
	)
	var max_cell := Vector3i(
		mini(dims.x, ceili((local.x + radius) / step) + 1),
		mini(dims.y, ceili((local.y + radius - Grid.MIN_BOUND.y) / step) + 1),
		mini(dims.z, ceili((local.z + radius) / step) + 1)
	)
	var new_value := 0 if mode == 0 else 1
	var changed := 0
	for y in range(min_cell.y, max_cell.y + 1):
		for z in range(min_cell.z, max_cell.z + 1):
			for x in range(min_cell.x, max_cell.x + 1):
				var point := Vector3(
					(float(x) + 0.5) * step,
					Grid.MIN_BOUND.y + (float(y) + 0.5) * step,
					(float(z) + 0.5) * step
				)
				if point.distance_squared_to(local) > radius * radius:
					continue
				var at := _index(x, y, z)
				if cells[at] != new_value:
					cells[at] = new_value
					changed += 1
					if x >= 0 and x < dims.x and y >= 0 and y < dims.y \
							and z >= 0 and z < dims.z:
						solid_count += 1 if new_value == 1 else -1
	last_changed = changed
	return changed


func build_chunk(chunk: Vector2i) -> Dictionary:
	if not Grid.is_valid_coordinate(chunk) or cells.is_empty():
		return {"valid": false, "reason": "uninitialized_or_invalid_chunk"}
	var chunk_dims := Vector3i(
		roundi(4.0 / step), dims.y, roundi(3.0 / step)
	)
	var origin := Vector3i(
		chunk.x * chunk_dims.x, 0, chunk.y * chunk_dims.z
	)
	var positions := PackedVector3Array()
	var normals := PackedVector3Array()
	var quad_count := 0
	var exposed_face_count := 0
	# For each direction, scan each integer plane, create the +/- exposed-face
	# mask, then merge same-oriented rectangles. Six face directions are implicit.
	for axis in range(3):
		var u := (axis + 1) % 3
		var v := (axis + 2) % 3
		var mask := PackedInt32Array()
		mask.resize(chunk_dims[u] * chunk_dims[v])
		for plane in range(chunk_dims[axis] + 1):
			for j in range(chunk_dims[v]):
				for i in range(chunk_dims[u]):
					var a := origin
					var b := origin
					a[axis] += plane - 1
					b[axis] += plane
					a[u] += i
					a[v] += j
					b[u] += i
					b[v] += j
					var a_solid := occupancy(a.x, a.y, a.z)
					var b_solid := occupancy(b.x, b.y, b.z)
					var code := 0
					if a_solid != b_solid:
						if a_solid == 1 and plane > 0:
							code = 1
						elif b_solid == 1 and plane < chunk_dims[axis]:
							code = -1
					mask[j * chunk_dims[u] + i] = code
					if code != 0:
						exposed_face_count += 1
			for j in range(chunk_dims[v]):
				var i := 0
				while i < chunk_dims[u]:
					var code := mask[j * chunk_dims[u] + i]
					if code == 0:
						i += 1
						continue
					var width := 1
					while i + width < chunk_dims[u] \
							and mask[j * chunk_dims[u] + i + width] == code:
						width += 1
					var height := 1
					var can_extend := true
					while j + height < chunk_dims[v] and can_extend:
						for check_i in range(i, i + width):
							if mask[(j + height) * chunk_dims[u] + check_i] != code:
								can_extend = false
								break
						if can_extend:
							height += 1
					var p := Vector3.ZERO
					p[axis] = float(plane) * step
					p[u] = float(i) * step
					p[v] = float(j) * step
					p.y += Grid.MIN_BOUND.y
					var du := Vector3.ZERO
					var dv := Vector3.ZERO
					du[u] = float(width) * step
					dv[v] = float(height) * step
					var n := Vector3.ZERO
					n[axis] = float(code)
					if code == 1:
						_add_quad(positions, normals, p, p + du, p + du + dv, p + dv, n)
					else:
						_add_quad(positions, normals, p, p + dv, p + du + dv, p + du, n)
					quad_count += 1
					for clear_j in range(j, j + height):
						for clear_i in range(i, i + width):
							mask[clear_j * chunk_dims[u] + clear_i] = 0
					i += width
	return {
		"valid": true,
		"positions": positions,
		"normals": normals,
		"quad_count": quad_count,
		"exposed_face_count": exposed_face_count,
		"triangle_count": quad_count * 2,
		"vertex_count": positions.size(),
		"memory_bytes": byte_count(),
	}


static func _add_quad(
	positions: PackedVector3Array,
	normals: PackedVector3Array,
	a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3
) -> void:
	positions.append(a)
	positions.append(b)
	positions.append(c)
	positions.append(a)
	positions.append(c)
	positions.append(d)
	for _i in range(6):
		normals.append(normal)


func _index(x: int, y: int, z: int) -> int:
	return ((y + 1) * padded.z + (z + 1)) * padded.x + x + 1
