class_name ExperimentalDiscreteSurfaceNets
extends RefCounted

## Fixed-point SDF (Q8.8), cached local surface vertices, Surface Nets
## quads. Alternative experimental backend; no production code changes.
const Field := preload("res://scripts/terrain/sdf_world.gd")
const Grid := preload("res://scripts/terrain/terrain_chunk_grid.gd")
const BrushState := preload("res://scripts/terrain/sdf_brush_edit_state.gd")
const SCALE := 256.0
const CORNERS := [
	Vector3i(0, 0, 0), Vector3i(1, 0, 0),
	Vector3i(1, 1, 0), Vector3i(0, 1, 0),
	Vector3i(0, 0, 1), Vector3i(1, 0, 1),
	Vector3i(1, 1, 1), Vector3i(0, 1, 1)
]
const EDGES := [
	Vector2i(0, 1), Vector2i(1, 2), Vector2i(2, 3), Vector2i(3, 0),
	Vector2i(4, 5), Vector2i(5, 6), Vector2i(6, 7), Vector2i(7, 4),
	Vector2i(0, 4), Vector2i(1, 5), Vector2i(2, 6), Vector2i(3, 7)
]
var step := 0.5
var seed := 0
var region_key := Vector2i.ZERO
var dims := Vector3i.ZERO
var node_dims := Vector3i.ZERO
var cell_dims := Vector3i.ZERO
var nodes := PackedInt32Array()
var cell_active := PackedByteArray()
var cell_vertices := PackedVector3Array()
var last_changed := 0
var _chunk_mode := false
var _chunk_coordinate := Vector2i.ZERO
var _chunk_offset := Vector3i.ZERO
var last_generation_sample_count := 0
## Passive timing of isolated B4 pristine visual hotspot stages.
var last_pristine_precompute_usec := 0
var last_pristine_lattice_usec := 0
var last_pristine_rebuild_usec := 0
var last_pristine_uniform_cells := 0
var last_canonical_sample_usec := 0
var last_canonical_cell_usec := 0
var last_canonical_uniform_cells := 0
var last_canonical_fast_sdf := false




func generate(seed_value: int, region_value: Vector2i, step_value: float) -> bool:
	if step_value != 0.5 and step_value != 0.25:
		return false
	step = step_value
	seed = seed_value
	region_key = region_value
	_chunk_mode = false
	_chunk_offset = Vector3i.ZERO
	last_generation_sample_count = 0
	last_pristine_precompute_usec = 0
	last_pristine_lattice_usec = 0
	last_pristine_rebuild_usec = 0
	last_pristine_uniform_cells = 0
	dims = Vector3i(
		roundi((Grid.MAX_BOUND.x - Grid.MIN_BOUND.x) / step),
		roundi((Grid.MAX_BOUND.y - Grid.MIN_BOUND.y) / step),
		roundi((Grid.MAX_BOUND.z - Grid.MIN_BOUND.z) / step)
	)
	node_dims = dims + Vector3i(3, 3, 3)
	cell_dims = dims + Vector3i(2, 2, 2)
	nodes.resize(node_dims.x * node_dims.y * node_dims.z)
	cell_active.resize(cell_dims.x * cell_dims.y * cell_dims.z)
	cell_vertices.resize(cell_active.size())
	var lattice_started := Time.get_ticks_usec()
	for y in range(-1, dims.y + 2):
		for z in range(-1, dims.z + 2):
			for x in range(-1, dims.x + 2):
				nodes[_node_index(x, y, z)] = roundi(
					Field.sample_density(seed, region_key, _point(x, y, z)) * SCALE
				)
				last_generation_sample_count += 1
	last_pristine_lattice_usec = Time.get_ticks_usec() - lattice_started
	var rebuild_started := Time.get_ticks_usec()
	for y in range(-1, dims.y + 1):
		for z in range(-1, dims.z + 1):
			for x in range(-1, dims.x + 1):
				_rebuild_cell(x, y, z)
	last_pristine_rebuild_usec = Time.get_ticks_usec() - rebuild_started
	return true



## Experimental DM9 fast path for immutable B4 visual-only regions.
## Do not use for edited/authoritative chunks: generate_chunk() intentionally
## retains the complete brush-snapshot oracle and cave section semantics.
## SDF terms that depend only on X/Z are reused across every Y sample,
## while all Q8.8 rounding and mixed-cell vertex construction stay identical.
func generate_pristine_fast(seed_value: int, region_value: Vector2i, step_value: float) -> bool:
	if step_value != 0.5:
		return false
	step = step_value
	seed = seed_value
	region_key = region_value
	_chunk_mode = false
	_chunk_offset = Vector3i.ZERO
	last_generation_sample_count = 0
	last_pristine_precompute_usec = 0
	last_pristine_lattice_usec = 0
	last_pristine_rebuild_usec = 0
	last_pristine_uniform_cells = 0
	dims = Vector3i(
		roundi((Grid.MAX_BOUND.x - Grid.MIN_BOUND.x) / step),
		roundi((Grid.MAX_BOUND.y - Grid.MIN_BOUND.y) / step),
		roundi((Grid.MAX_BOUND.z - Grid.MIN_BOUND.z) / step)
	)
	node_dims = dims + Vector3i(3, 3, 3)
	cell_dims = dims + Vector3i(2, 2, 2)
	nodes.resize(node_dims.x * node_dims.y * node_dims.z)
	cell_active.resize(cell_dims.x * cell_dims.y * cell_dims.z)
	cell_vertices.resize(cell_active.size())
	var precompute_started := Time.get_ticks_usec()
	var x_count := node_dims.x
	var z_count := node_dims.z
	var surface_terms: Array[float] = []
	var cave_y_terms: Array[float] = []
	var cave_dz_terms: Array[float] = []
	surface_terms.resize(x_count * z_count)
	cave_y_terms.resize(x_count * z_count)
	cave_dz_terms.resize(x_count * z_count)
	var phase := float(posmod(seed, 100003)) * 0.000173
	for z in range(-1, dims.z + 2):
		var world_z := float(region_key.y) * Field.REGION_SIZE_Z + float(z) * step
		var z_surface := 0.70 * cos(world_z * 0.31 - phase * 0.7)
		for x in range(-1, dims.x + 2):
			var world_x := float(region_key.x) * Field.REGION_SIZE_X + float(x) * step
			var index := (z + 1) * x_count + x + 1
			var surface_y := 3.8 \
				+ 1.25 * sin(world_x * 0.22 + phase) \
				+ z_surface \
				+ 0.28 * sin((world_x + world_z) * 0.11 + phase * 0.3)
			surface_terms[index] = surface_y
			cave_y_terms[index] = 1.15 + 0.24 * sin(world_x * 0.25 + phase)
			var cave_z := 6.0 + 1.05 * sin(world_x * 0.17 + phase * 0.6)
			cave_dz_terms[index] = world_z - cave_z
	last_pristine_precompute_usec = Time.get_ticks_usec() - precompute_started
	var lattice_started := Time.get_ticks_usec()
	for y in range(-1, dims.y + 2):
		var local_y := Grid.MIN_BOUND.y + float(y) * step
		var row_start := (y + 1) * node_dims.z * node_dims.x
		for z in range(-1, dims.z + 2):
			var layer_start := row_start + (z + 1) * node_dims.x
			var term_start := (z + 1) * x_count
			for x in range(-1, dims.x + 2):
				var index := term_start + x + 1
				var bounded_surface: float = minf(
					surface_terms[index] - local_y, local_y - Field.MIN_Y
				)
				var cave_distance := Vector2(
					local_y - cave_y_terms[index], cave_dz_terms[index]
				).length() - 0.92
				var density: float = minf(bounded_surface, cave_distance)
				nodes[layer_start + x + 1] = roundi(density * SCALE)
				last_generation_sample_count += 1
	last_pristine_lattice_usec = Time.get_ticks_usec() - lattice_started
	var rebuild_started := Time.get_ticks_usec()
	for y in range(-1, dims.y + 1):
		for z in range(-1, dims.z + 1):
			for x in range(-1, dims.x + 1):
				_rebuild_cell_fast_uniform_gate(x, y, z)
	last_pristine_rebuild_usec = Time.get_ticks_usec() - rebuild_started
	return true


## Uniform-cell early exit: integer sign inspection, no per-cell
## PackedFloat32Array allocation. Mixed cells delegate to the unchanged
## Surface Nets oracle to preserve exactly the same Q8.8 vertex geometry.
func _rebuild_cell_fast_uniform_gate(x: int, y: int, z: int) -> void:
	var n := _node_index(x, y, z)
	var stride_y := node_dims.x * node_dims.z
	var stride_z := node_dims.x
	var positive_count := int(nodes[n] >= 0) + int(nodes[n + 1] >= 0) \
		+ int(nodes[n + stride_y] >= 0) + int(nodes[n + stride_y + 1] >= 0) \
		+ int(nodes[n + stride_z] >= 0) + int(nodes[n + stride_z + 1] >= 0) \
		+ int(nodes[n + stride_y + stride_z] >= 0) \
		+ int(nodes[n + stride_y + stride_z + 1] >= 0)
	if positive_count == 0 or positive_count == 8:
		cell_active[_cell_index(x, y, z)] = 0
		last_pristine_uniform_cells += 1
		return
	_rebuild_cell(x, y, z)



## DM2: independent per-chunk volume, including a 1-cell halo. All field
## samples come from the immutable, revision-tagged worker snapshot. No shared
## mutable cache, scene-tree reads or procedural fallback after snapshot build.
func generate_chunk(
	seed_value: int,
	region_value: Vector2i,
	coordinate_value: Vector2i,
	snapshot: Dictionary,
	cave_section_enabled: bool = false,
	canonical_fast: bool = false
) -> bool:
	if not Grid.is_valid_coordinate(coordinate_value) \
			or not bool(snapshot.get("valid", true)):
		return false
	step = Grid.SAMPLE_STEP
	seed = seed_value
	region_key = region_value
	_chunk_mode = true
	_chunk_coordinate = coordinate_value
	_chunk_offset = Vector3i(
		coordinate_value.x * Grid.CELLS_PER_CHUNK_X, 0,
		coordinate_value.y * Grid.CELLS_PER_CHUNK_Z
	)
	dims = Vector3i(
		Grid.CELLS_PER_CHUNK_X, Grid.CELL_COUNT_Y, Grid.CELLS_PER_CHUNK_Z
	)
	node_dims = dims + Vector3i(3, 3, 3)
	cell_dims = dims + Vector3i(2, 2, 2)
	nodes.resize(node_dims.x * node_dims.y * node_dims.z)
	cell_active.resize(cell_dims.x * cell_dims.y * cell_dims.z)
	cell_vertices.resize(cell_active.size())
	last_generation_sample_count = 0
	last_canonical_sample_usec = 0
	last_canonical_cell_usec = 0
	last_canonical_uniform_cells = 0
	last_canonical_fast_sdf = false
	last_pristine_uniform_cells = 0
	var sample_started := Time.get_ticks_usec()
	# Only cache the pristine base field when all overlay sources are provably
	# absent. Edited/materialized/effect/cave snapshots use the exact original
	# evaluator; no speculative replacement of authoritative semantics.
	var centers: PackedVector3Array = snapshot.get("centers", PackedVector3Array())
	var materialized: Variant = snapshot.get("materialized_tiles", [])
	var effects: Variant = snapshot.get("terrain_object_effect_frames", [])
	var pristine := canonical_fast and not cave_section_enabled \
		and centers.is_empty() \
		and materialized is Array and (materialized as Array).is_empty() \
		and effects is Array and (effects as Array).is_empty()
	if pristine:
		last_canonical_fast_sdf = true
		# Preserve exact SdfWorld expression ordering and Q8.8 roundi.
		var x_count := node_dims.x
		var surface_terms := PackedFloat64Array()
		var cave_y_terms := PackedFloat64Array()
		var cave_dz_terms := PackedFloat64Array()
		surface_terms.resize(x_count * node_dims.z)
		cave_y_terms.resize(x_count * node_dims.z)
		cave_dz_terms.resize(x_count * node_dims.z)
		var phase := float(posmod(seed, 100003)) * 0.000173
		for z in range(-1, dims.z + 2):
			var world_z := float(region_key.y) * Field.REGION_SIZE_Z \
				+ float(z + _chunk_offset.z) * step
			var z_term := 0.70 * cos(world_z * 0.31 - phase * 0.7)
			for x in range(-1, dims.x + 2):
				var world_x := float(region_key.x) * Field.REGION_SIZE_X \
					+ float(x + _chunk_offset.x) * step
				var index := (z + 1) * x_count + x + 1
				surface_terms[index] = 3.8 \
					+ 1.25 * sin(world_x * 0.22 + phase) \
					+ z_term \
					+ 0.28 * sin((world_x + world_z) * 0.11 + phase * 0.3)
				cave_y_terms[index] = 1.15 + 0.24 * sin(world_x * 0.25 + phase)
				var cave_z := 6.0 + 1.05 * sin(world_x * 0.17 + phase * 0.6)
				cave_dz_terms[index] = world_z - cave_z
		for y in range(-1, dims.y + 2):
			var local_y := Grid.MIN_BOUND.y + float(y) * step
			var y_start := (y + 1) * node_dims.z * x_count
			for z in range(-1, dims.z + 2):
				var row := y_start + (z + 1) * x_count
				for x in range(-1, dims.x + 2):
					var i := (z + 1) * x_count + x + 1
					var bounded_surface: float = minf(
						surface_terms[i] - local_y, local_y - Field.MIN_Y
					)
					var cave_distance := Vector2(
						local_y - cave_y_terms[i], cave_dz_terms[i]
					).length() - 0.92
					var density: float = minf(bounded_surface, cave_distance)
					nodes[row + x + 1] = roundi(density * SCALE)
					last_generation_sample_count += 1
	else:
		for y in range(-1, dims.y + 2):
			for z in range(-1, dims.z + 2):
				for x in range(-1, dims.x + 2):
					var density := BrushState.sample_density_snapshot(
						seed, region_key, _point(x, y, z),
						cave_section_enabled, snapshot
					)
					if not is_finite(density):
						return false
					nodes[_node_index(x, y, z)] = roundi(density * SCALE)
					last_generation_sample_count += 1
	last_canonical_sample_usec = Time.get_ticks_usec() - sample_started
	var cell_started := Time.get_ticks_usec()
	for y in range(-1, dims.y + 1):
		for z in range(-1, dims.z + 1):
			for x in range(-1, dims.x + 1):
				if canonical_fast:
					_rebuild_cell_fast_uniform_gate(x, y, z)
				else:
					_rebuild_cell(x, y, z)
	last_canonical_cell_usec = Time.get_ticks_usec() - cell_started
	last_canonical_uniform_cells = last_pristine_uniform_cells if canonical_fast else 0
	return true


func byte_count() -> int:
	return nodes.size() * 4 + cell_active.size() + cell_vertices.size() * 12


func sample_local(local: Vector3) -> int:
	var fx := local.x / step
	var fy := (local.y - Grid.MIN_BOUND.y) / step
	var fz := local.z / step
	var x := clampi(floori(fx), -1, dims.x)
	var y := clampi(floori(fy), -1, dims.y)
	var z := clampi(floori(fz), -1, dims.z)
	var tx := clampf(fx - float(x), 0.0, 1.0)
	var ty := clampf(fy - float(y), 0.0, 1.0)
	var tz := clampf(fz - float(z), 0.0, 1.0)
	var q000 := _node(x, y, z)
	var q100 := _node(x + 1, y, z)
	var q010 := _node(x, y + 1, z)
	var q110 := _node(x + 1, y + 1, z)
	var q001 := _node(x, y, z + 1)
	var q101 := _node(x + 1, y, z + 1)
	var q011 := _node(x, y + 1, z + 1)
	var q111 := _node(x + 1, y + 1, z + 1)
	var bottom := lerpf(lerpf(q000, q100, tx), lerpf(q010, q110, tx), ty)
	var top := lerpf(lerpf(q001, q101, tx), lerpf(q011, q111, tx), ty)
	return 1 if lerpf(bottom, top, tz) >= 0.0 else 0


func edit_sphere(mode: int, center_world: Vector3, radius: float) -> int:
	var local := center_world - Vector3(
		float(region_key.x) * Field.REGION_SIZE_X,
		0.0,
		float(region_key.y) * Field.REGION_SIZE_Z
	)
	var changed := 0
	var minimum := dims + Vector3i(2, 2, 2)
	var maximum := Vector3i(-2, -2, -2)
	# Intentionally full-region update for truthful initial cost.
	for y in range(-1, dims.y + 2):
		for z in range(-1, dims.z + 2):
			for x in range(-1, dims.x + 2):
				var at := _node_index(x, y, z)
				var before := float(nodes[at]) / SCALE
				var threshold := _point(x, y, z).distance_to(local) - radius
				var updated := minf(before, threshold) if mode == 0 \
					else maxf(before, -threshold)
				var fixed := roundi(updated * SCALE)
				if fixed != nodes[at]:
					nodes[at] = fixed
					changed += 1
					minimum = minimum.min(Vector3i(x, y, z))
					maximum = maximum.max(Vector3i(x, y, z))
	if changed > 0:
		for y in range(maxi(-1, minimum.y - 1), mini(dims.y, maximum.y) + 1):
			for z in range(maxi(-1, minimum.z - 1), mini(dims.z, maximum.z) + 1):
				for x in range(maxi(-1, minimum.x - 1), mini(dims.x, maximum.x) + 1):
					_rebuild_cell(x, y, z)
	last_changed = changed
	return changed


func build_chunk(chunk: Vector2i) -> Dictionary:
	if not Grid.is_valid_coordinate(chunk) or nodes.is_empty():
		return {"valid": false, "reason": "invalid_chunk_or_missing_lattice"}
	if _chunk_mode and chunk != _chunk_coordinate:
		return {"valid": false, "reason": "b4_wrong_chunk"}
	var chunk_x := dims.x if _chunk_mode else roundi(4.0 / step)
	var chunk_z := dims.z if _chunk_mode else roundi(3.0 / step)
	var x0 := 0 if _chunk_mode else chunk.x * chunk_x
	var z0 := 0 if _chunk_mode else chunk.y * chunk_z
	var mesh_origin := Grid.origin_for(chunk)
	var positions := PackedVector3Array()
	var normals := PackedVector3Array()
	var quads := 0
	var skipped := 0
	# Exactly one chunk owns each oriented lattice edge.
	for z in range(z0, z0 + chunk_z):
		for y in range(dims.y + 1):
			for x in range(x0, x0 + chunk_x):
				for axis in range(3):
					if axis == 1 and y == dims.y:
						continue
					var next := Vector3i(x, y, z)
					next[axis] += 1
					var before := _node(x, y, z)
					var after := _node(next.x, next.y, next.z)
					if (before >= 0.0) == (after >= 0.0):
						continue
					var corners := _surrounding_cells(axis, x, y, z)
					var missing := false
					for cell in corners:
						var ci := _cell_index(cell.x, cell.y, cell.z)
						if cell_active[ci] == 0:
							missing = true
							break
					if missing:
						skipped += 1
						continue
					var a: Vector3i = corners[0]
					var b: Vector3i = corners[1]
					var c: Vector3i = corners[2]
					var d: Vector3i = corners[3]
					var p0: Vector3 = cell_vertices[_cell_index(a.x, a.y, a.z)] - mesh_origin
					var p1: Vector3 = cell_vertices[_cell_index(b.x, b.y, b.z)] - mesh_origin
					var p2: Vector3 = cell_vertices[_cell_index(c.x, c.y, c.z)] - mesh_origin
					var p3: Vector3 = cell_vertices[_cell_index(d.x, d.y, d.z)] - mesh_origin
					var target := Vector3.ZERO
					target[axis] = 1.0 if before >= 0.0 else -1.0
					_append_quad(positions, normals, p0, p1, p2, p3, target)
					quads += 1
	return {
		"valid": skipped == 0,
		"skipped_faces": skipped,
		"positions": positions,
		"normals": normals,
		"triangle_count": quads * 2,
		"vertex_count": positions.size(),
		"quad_count": quads,
		"sample_count": last_generation_sample_count,
		"memory_bytes": byte_count(),
	}


## Only for immutable full-region B4 visual meshes. No chunks with edits.
## Removes the per-edge Vector3i allocation and four-element corner Array;
## the same _append_quad function determines vertex order/face normals.
func build_chunk_pristine_fast(chunk: Vector2i) -> Dictionary:
	if _chunk_mode:
		return {"valid": false, "reason": "fast_pristine_does_not_accept_edited_chunks"}
	if not Grid.is_valid_coordinate(chunk) or nodes.is_empty():
		return {"valid": false, "reason": "invalid_chunk_or_missing_lattice"}
	var chunk_x := roundi(4.0 / step)
	var chunk_z := roundi(3.0 / step)
	var x0 := chunk.x * chunk_x
	var z0 := chunk.y * chunk_z
	var mesh_origin := Grid.origin_for(chunk)
	var positions := PackedVector3Array()
	var normals := PackedVector3Array()
	var quads := 0
	var skipped := 0
	var node_y_stride := node_dims.x * node_dims.z
	var node_z_stride := node_dims.x
	var cell_y_stride := cell_dims.x * cell_dims.z
	var cell_z_stride := cell_dims.x
	for z in range(z0, z0 + chunk_z):
		for y in range(dims.y + 1):
			for x in range(x0, x0 + chunk_x):
				var n := _node_index(x, y, z)
				var positive := nodes[n] >= 0
				for axis in range(3):
					if axis == 1 and y == dims.y:
						continue
					var offset := 1 if axis == 0 else (node_y_stride if axis == 1 else node_z_stride)
					if positive == (nodes[n + offset] >= 0):
						continue
					var c0 := 0
					var c1 := 0
					var c2 := 0
					var c3 := 0
					match axis:
						0:
							c0 = _cell_index(x, y - 1, z - 1)
							c1 = c0 + cell_z_stride
							c2 = c1 + cell_y_stride
							c3 = c0 + cell_y_stride
						1:
							c0 = _cell_index(x - 1, y, z - 1)
							c1 = c0 + 1
							c2 = c1 + cell_z_stride
							c3 = c0 + cell_z_stride
						_:
							c0 = _cell_index(x - 1, y - 1, z)
							c1 = c0 + 1
							c2 = c1 + cell_y_stride
							c3 = c0 + cell_y_stride
					if cell_active[c0] == 0 or cell_active[c1] == 0 \
						or cell_active[c2] == 0 or cell_active[c3] == 0:
						skipped += 1
						continue
					var p0: Vector3 = cell_vertices[c0] - mesh_origin
					var p1: Vector3 = cell_vertices[c1] - mesh_origin
					var p2: Vector3 = cell_vertices[c2] - mesh_origin
					var p3: Vector3 = cell_vertices[c3] - mesh_origin
					var target := Vector3.ZERO
					target[axis] = 1.0 if positive else -1.0
					_append_quad(positions, normals, p0, p1, p2, p3, target)
					quads += 1
	return {
		"valid": skipped == 0,
		"skipped_faces": skipped,
		"positions": positions,
		"normals": normals,
		"triangle_count": quads * 2,
		"vertex_count": positions.size(),
		"quad_count": quads,
		"sample_count": last_generation_sample_count,
		"memory_bytes": byte_count(),
	}



## Canonical equivalent to the pristine fast edge traversal, but
## uses the local per-chunk halo/ownership offsets. Still returns the
## original chunk-relative vertex positions, normals and winding.
func build_chunk_canonical_fast(chunk: Vector2i) -> Dictionary:
	if not _chunk_mode or chunk != _chunk_coordinate:
		return {"valid": false, "reason": "canonical_chunk_mode_required"}
	if not Grid.is_valid_coordinate(chunk) or nodes.is_empty():
		return {"valid": false, "reason": "invalid_chunk_or_missing_lattice"}
	var positions := PackedVector3Array()
	var normals := PackedVector3Array()
	var mesh_origin := Grid.origin_for(chunk)
	var node_y_stride := node_dims.x * node_dims.z
	var node_z_stride := node_dims.x
	var cell_y_stride := cell_dims.x * cell_dims.z
	var cell_z_stride := cell_dims.x
	var quads := 0
	var skipped := 0
	for z in range(dims.z):
		for y in range(dims.y + 1):
			for x in range(dims.x):
				var n := _node_index(x, y, z)
				var positive := nodes[n] >= 0
				for axis in range(3):
					if axis == 1 and y == dims.y:
						continue
					var offset := 1 if axis == 0 else (node_y_stride if axis == 1 else node_z_stride)
					if positive == (nodes[n + offset] >= 0):
						continue
					var c0 := 0
					var c1 := 0
					var c2 := 0
					var c3 := 0
					match axis:
						0:
							c0 = _cell_index(x, y - 1, z - 1)
							c1 = c0 + cell_z_stride
							c2 = c1 + cell_y_stride
							c3 = c0 + cell_y_stride
						1:
							c0 = _cell_index(x - 1, y, z - 1)
							c1 = c0 + 1
							c2 = c1 + cell_z_stride
							c3 = c0 + cell_z_stride
						_:
							c0 = _cell_index(x - 1, y - 1, z)
							c1 = c0 + 1
							c2 = c1 + cell_y_stride
							c3 = c0 + cell_y_stride
					if cell_active[c0] == 0 or cell_active[c1] == 0 \
						or cell_active[c2] == 0 or cell_active[c3] == 0:
						skipped += 1
						continue
					var p0: Vector3 = cell_vertices[c0] - mesh_origin
					var p1: Vector3 = cell_vertices[c1] - mesh_origin
					var p2: Vector3 = cell_vertices[c2] - mesh_origin
					var p3: Vector3 = cell_vertices[c3] - mesh_origin
					var target := Vector3.ZERO
					target[axis] = 1.0 if positive else -1.0
					_append_quad(positions, normals, p0, p1, p2, p3, target)
					quads += 1
	return {
		"valid": skipped == 0,
		"skipped_faces": skipped,
		"positions": positions,
		"normals": normals,
		"triangle_count": quads * 2,
		"vertex_count": positions.size(),
		"quad_count": quads,
		"sample_count": last_generation_sample_count,
		"memory_bytes": byte_count(),
	}



func _rebuild_cell(x: int, y: int, z: int) -> void:
	var at := _cell_index(x, y, z)
	var density := PackedFloat32Array()
	density.resize(8)
	var mask := 0
	for i in range(8):
		var c: Vector3i = CORNERS[i]
		var d := _node(x + c.x, y + c.y, z + c.z)
		density[i] = d
		if d >= 0.0:
			mask |= 1 << i
	if mask == 0 or mask == 255:
		cell_active[at] = 0
		return
	var total := Vector3.ZERO
	var crossings := 0
	for edge in EDGES:
		var aa: int = edge.x
		var bb: int = edge.y
		var da := float(density[aa])
		var db := float(density[bb])
		if (da >= 0.0) == (db >= 0.0):
			continue
		var t := clampf(da / (da - db), 0.0, 1.0)
		var ac: Vector3i = CORNERS[aa]
		var bc: Vector3i = CORNERS[bb]
		var pa := Vector3(float(ac.x), float(ac.y), float(ac.z))
		var pb := Vector3(float(bc.x), float(bc.y), float(bc.z))
		total += pa.lerp(pb, t)
		crossings += 1
	if crossings == 0:
		cell_active[at] = 0
		return
	cell_active[at] = 1
	cell_vertices[at] = _point(x, y, z) + total * (step / float(crossings))


static func _surrounding_cells(axis: int, x: int, y: int, z: int) -> Array[Vector3i]:
	match axis:
		0:
			return [Vector3i(x, y - 1, z - 1), Vector3i(x, y - 1, z),
				Vector3i(x, y, z), Vector3i(x, y, z - 1)]
		1:
			return [Vector3i(x - 1, y, z - 1), Vector3i(x, y, z - 1),
				Vector3i(x, y, z), Vector3i(x - 1, y, z)]
		_:
			return [Vector3i(x - 1, y - 1, z), Vector3i(x, y - 1, z),
				Vector3i(x, y, z), Vector3i(x - 1, y, z)]


static func _append_quad(
	positions: PackedVector3Array,
	normals: PackedVector3Array,
	a: Vector3, b: Vector3, c: Vector3, d: Vector3, outward: Vector3
) -> void:
	var face: Vector3 = (b - a).cross(c - a)
	if face.dot(outward) < 0.0:
		var swap := b
		b = d
		d = swap
		face = (b - a).cross(c - a)
	var normal := face.normalized() if face.length_squared() > 0.000001 \
		else outward
	for vertex in [a, b, c, a, c, d]:
		positions.append(vertex)
		normals.append(normal)


func _point(x: int, y: int, z: int) -> Vector3:
	return Vector3(float(x + _chunk_offset.x) * step,
		Grid.MIN_BOUND.y + float(y) * step,
		float(z + _chunk_offset.z) * step)


func _node(x: int, y: int, z: int) -> float:
	return float(nodes[_node_index(x, y, z)]) / SCALE


func _node_index(x: int, y: int, z: int) -> int:
	return ((y + 1) * node_dims.z + z + 1) * node_dims.x + x + 1


func _cell_index(x: int, y: int, z: int) -> int:
	return ((y + 1) * cell_dims.z + z + 1) * cell_dims.x + x + 1
