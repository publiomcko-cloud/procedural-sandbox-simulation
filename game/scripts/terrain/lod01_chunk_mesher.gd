class_name Lod01ChunkMesher
extends RefCounted

## Bounded LOD1 chunk assembly from the reviewed CPU transition-cell builder.
## Every chunk boundary uses a fine-split face, so neighboring LOD assignments
## can publish independently while remaining conforming at X/Z contacts.
const Grid := preload("res://scripts/terrain/terrain_chunk_grid.gd")
const Transition := preload("res://scripts/experiments/lod01_transition_fixture.gd")
const Field := preload("res://scripts/terrain/sdf_world.gd")


static func transition_faces_for_cell(cell: Vector3i, extent: Vector3i) -> Array[int]:
	return Transition.transition_faces_for_chunk_cell(cell, extent)


static func build_chunk_cpu_data(
	world_seed: int,
	region_key: Vector2i,
	chunk_coordinate: Vector2i,
	brush_snapshot: Dictionary,
	density_override: Callable = Callable()
) -> Dictionary:
	if not Grid.is_valid_coordinate(chunk_coordinate):
		return {"valid": false, "reason": "invalid_chunk_coordinate"}
	# D8: production LOD1 geometry is assembled in the bounded source-region
	# frame. The previous global lattice overflowed Vector3i and lost Vector3
	# precision at extreme signed regions, which is why effect-bearing chunks
	# were forced to LOD0. Chunk nodes add the region/chunk world transform later.
	var chunk_origin: Vector3 = Grid.origin_for(chunk_coordinate)
	var scaled_origin := Vector3(
		chunk_origin.x, Grid.MIN_BOUND.y, chunk_origin.z
	) * 2.0
	var min_lattice := Vector3i(
		roundi(scaled_origin.x),
		roundi(scaled_origin.y),
		roundi(scaled_origin.z)
	)
	if Vector3(min_lattice).distance_squared_to(scaled_origin) > 0.000001:
		return {"valid": false, "reason": "region_local_origin_off_lod_lattice"}
	var coarse_extent := Vector3i(Grid.CELLS_PER_CHUNK_X / 2, Grid.CELL_COUNT_Y / 2, Grid.CELLS_PER_CHUNK_Z / 2)
	var cell_result: Dictionary = Transition.build_lod1_chunk(
		world_seed, min_lattice, coarse_extent, brush_snapshot, density_override
	)
	if not cell_result.get("valid", false):
		return cell_result
	var vertices: PackedVector3Array = cell_result["vertices"]
	var positions := PackedVector3Array()
	positions.resize(vertices.size())
	for index in range(vertices.size()):
		positions[index] = vertices[index] - chunk_origin
	var fixture_timings: Dictionary = cell_result.get("timings_usec", {})
	return {
		"valid": true,
		"positions": positions,
		"normals": cell_result["normals"],
		"vertex_count": positions.size(),
		"triangle_count": positions.size() / 3,
		"sample_count": int(cell_result.get("sample_count", 0)),
		"lod_level": 1,
		"ledger_revision": int(brush_snapshot.get("revision", 0)),
		"transition_cell_count": int(cell_result.get("transition_cell_count", 0)),
		"timings_usec": {
			"sdf_and_ledger": int(fixture_timings.get("sdf_ledger_sampling", 0)),
			"triangulation_and_face_normals": int(fixture_timings.get("transition_geometry", 0)) + int(fixture_timings.get("lod_mesh_triangulation", 0)),
			"shared_gradient_normals": int(fixture_timings.get("normal_computation", 0)),
			"array_mesh_build": 0,
			"lod_transition_cell_assembly": int(fixture_timings.get("transition_geometry", 0)),
		},
	}


## Slower per-cell composition retained as an independent equivalence oracle for tests.
static func build_chunk_cpu_data_per_cell_reference(
	world_seed: int,
	region_key: Vector2i,
	chunk_coordinate: Vector2i,
	brush_snapshot: Dictionary,
	density_override: Callable = Callable()
) -> Dictionary:
	if not Grid.is_valid_coordinate(chunk_coordinate):
		return {"valid": false, "reason": "invalid_chunk_coordinate"}
	var bounds: Vector4i = Grid.cell_bounds(chunk_coordinate)
	if bounds.x % 2 != 0 or bounds.y % 2 != 0 or bounds.z % 2 != 0 or bounds.w % 2 != 0:
		return {"valid": false, "reason": "chunk_bounds_not_lod1_aligned"}
	var chunk_origin: Vector3 = Grid.origin_for(chunk_coordinate)
	var mesh_origin := chunk_origin
	var positions := PackedVector3Array()
	var normals := PackedVector3Array()
	var total_samples := 0
	var transition_cell_count := 0
	var sampling_usec := 0
	var geometry_usec := 0
	var polygonization_usec := 0
	var normal_usec := 0
	var total_started_usec := Time.get_ticks_usec()
	var coarse_x_count: int = Grid.CELLS_PER_CHUNK_X / 2
	var coarse_z_count: int = Grid.CELLS_PER_CHUNK_Z / 2
	var coarse_y_count: int = Grid.CELL_COUNT_Y / 2
	for y in range(coarse_y_count):
		for z in range(coarse_z_count):
			for x in range(coarse_x_count):
				var region_local_cell_origin := chunk_origin + Vector3(
					float(x), Grid.MIN_BOUND.y + float(y), float(z)
				)
				var scaled := region_local_cell_origin * 2.0
				var lattice_origin := Vector3i(
					roundi(scaled.x), roundi(scaled.y), roundi(scaled.z)
				)
				if Vector3(lattice_origin).distance_squared_to(scaled) > 0.000001:
					return {"valid": false, "reason": "region_local_origin_off_lod_lattice"}
				var fine_faces := transition_faces_for_cell(Vector3i(x, y, z), Vector3i(coarse_x_count, coarse_y_count, coarse_z_count))
				var cell_result: Dictionary
				if fine_faces.is_empty():
					cell_result = Transition.build_uniform_reference_cell(
						world_seed, lattice_origin, 1, brush_snapshot, density_override
					)
				else:
					transition_cell_count += 1
					cell_result = Transition.build_transition_cell(
						world_seed, lattice_origin, fine_faces, brush_snapshot, density_override
					)
				if not cell_result.get("valid", false):
					return {
						"valid": false,
						"reason": String(cell_result.get("reason", "lod1_cell_build_failed")),
						"failed_lattice_origin": lattice_origin,
					}
				var cell_vertices: PackedVector3Array = cell_result["vertices"]
				var cell_normals: PackedVector3Array = cell_result["normals"]
				for vertex in cell_vertices:
					positions.append(vertex - mesh_origin)
				normals.append_array(cell_normals)
				total_samples += int(cell_result.get("sample_count", 0))
				var timings: Dictionary = cell_result.get("timings_usec", {})
				sampling_usec += int(timings.get("sdf_ledger_sampling", 0))
				geometry_usec += int(timings.get("transition_geometry", 0))
				polygonization_usec += int(timings.get("lod_mesh_triangulation", 0))
				normal_usec += int(timings.get("normal_computation", 0))
	if positions.size() != normals.size():
		return {"valid": false, "reason": "lod1_chunk_attribute_count_mismatch"}
	for vertex in positions:
		if not vertex.is_finite():
			return {"valid": false, "reason": "non_finite_lod1_chunk_vertex"}
	for normal in normals:
		if not normal.is_finite():
			return {"valid": false, "reason": "non_finite_lod1_chunk_normal"}
	return {
		"valid": true,
		"positions": positions,
		"normals": normals,
		"vertex_count": positions.size(),
		"triangle_count": positions.size() / 3,
		"sample_count": total_samples,
		"lod_level": 1,
		"ledger_revision": int(brush_snapshot.get("revision", 0)),
		"world_seed": world_seed,
		"generator_version": Field.GENERATOR_VERSION,
		"transition_cell_count": transition_cell_count,
		"elapsed_usec": Time.get_ticks_usec() - total_started_usec,
		"timings_usec": {
			"sdf_and_ledger": sampling_usec,
			"triangulation_and_face_normals": geometry_usec + polygonization_usec,
			"shared_gradient_normals": normal_usec,
			"array_mesh_build": 0,
			"lod_transition_cell_assembly": geometry_usec,
		},
	}
