extends RefCounted

## Disposable sparse adaptive approximation. A coarse 0.5 grid is authoritative
## only as a test artifact; selected macro cells hold 0.25/0.125 refinements.
## Fine boundary nodes are constrained to the shared coarse interpolant, making
## the scalar approximation C0 across macro-cell faces. It is never exact SDF.
const Brush := preload("res://scripts/terrain/sdf_brush_edit_state.gd")
const Grid := preload("res://scripts/terrain/terrain_chunk_grid.gd")
const Spatial := preload("res://scripts/terrain/terrain_spatial_ownership.gd")
const Voxel := preload("res://tests/prototypes/r4_voxel_snapshot.gd")

const COARSE_SPACING := 0.5
const MAX_REFINED_CELLS := 12000

var base: RefCounted
var refined_cells: Dictionary = {}
var subdivisions := 4
var refinement_threshold := 0.02
var region := Vector2i.ZERO
var chunk := Vector2i.ZERO
var world_seed := 0
var revision := -1
var fine_samples := 0
var build_usec := 0
var last_reason := ""


func materialize(seed: int, region_key: Vector2i, chunk_coordinate: Vector2i,
		brush_snapshot: Dictionary, target_spacing: float, error_threshold: float = 0.02) -> bool:
	last_reason = ""
	refined_cells.clear()
	fine_samples = 0
	var start := Time.get_ticks_usec()
	if target_spacing != 0.25 and target_spacing != 0.125:
		last_reason = "unsupported_refinement_spacing"
		return false
	if not is_finite(error_threshold) or error_threshold <= 0.0:
		last_reason = "refinement_threshold_invalid"
		return false
	region = region_key
	chunk = chunk_coordinate
	world_seed = seed
	revision = int(brush_snapshot.get("revision", -1))
	refinement_threshold = error_threshold
	subdivisions = roundi(COARSE_SPACING / target_spacing)
	base = Voxel.new()
	if not base.materialize(seed, region_key, chunk_coordinate, brush_snapshot, COARSE_SPACING):
		last_reason = "adaptive_base_materialization_failed"
		return false
	for y in range(base.ny - 1):
		for z in range(base.nz - 1):
			for x in range(base.nx - 1):
				if not _requires_refinement(x, y, z, brush_snapshot):
					continue
				if refined_cells.size() >= MAX_REFINED_CELLS:
					last_reason = "adaptive_refinement_cell_quota_exceeded"
					return false
				var values := PackedFloat32Array()
				values.resize((subdivisions + 1) * (subdivisions + 1) * (subdivisions + 1))
				for fy in range(subdivisions + 1):
					for fz in range(subdivisions + 1):
						for fx in range(subdivisions + 1):
							var point: Vector3 = base.world_min + Vector3(
								float(x) + float(fx) / subdivisions,
								float(y) + float(fy) / subdivisions,
								float(z) + float(fz) / subdivisions) * COARSE_SPACING
							var on_boundary := fx == 0 or fy == 0 or fz == 0 \
								or fx == subdivisions or fy == subdivisions or fz == subdivisions
							var density: float
							if on_boundary:
								density = base.sample_world(point)
							else:
								density = _canonical_sample(point, brush_snapshot)
								fine_samples += 1
							values[_fine_index(fx, fy, fz)] = density
				refined_cells[_macro_key(x, y, z)] = values
	build_usec = Time.get_ticks_usec() - start
	return true


func sample_world(point: Vector3) -> float:
	if base == null or not point.is_finite():
		return NAN
	var grid_position: Vector3 = (point - base.world_min) / COARSE_SPACING
	if grid_position.x < 0.0 or grid_position.y < 0.0 or grid_position.z < 0.0 \
		or grid_position.x > base.nx - 1 or grid_position.y > base.ny - 1 \
		or grid_position.z > base.nz - 1:
		return NAN
	var x := mini(floori(grid_position.x), base.nx - 2)
	var y := mini(floori(grid_position.y), base.ny - 2)
	var z := mini(floori(grid_position.z), base.nz - 2)
	var values: Variant = refined_cells.get(_macro_key(x, y, z), null)
	if values == null:
		return base.sample_world(point)
	return _sample_fine(values, grid_position, Vector3i(x, y, z))


func sample_world_in_macro_cell(point: Vector3, cell: Vector3i) -> float:
	var values: Variant = refined_cells.get(_macro_key(cell.x, cell.y, cell.z), null)
	if values == null:
		return base.sample_world(point)
	var grid_position: Vector3 = (point - base.world_min) / COARSE_SPACING
	return _sample_fine(values, grid_position, cell)


func statistics() -> Dictionary:
	var coarse_count := int(base.densities.size()) if base != null else 0
	return {"base_spacing": COARSE_SPACING, "fine_spacing": COARSE_SPACING / subdivisions,
		"refinement_threshold": refinement_threshold, "coarse_node_count": coarse_count,
		"refined_cell_count": refined_cells.size(), "fine_interior_samples": fine_samples,
		"refined_node_count_with_duplicates": refined_cells.size() * (subdivisions + 1) ** 3,
		"serialized_payload_bytes": var_to_bytes(_payload()).size(), "build_usec": build_usec,
		"revision": revision}


func digest() -> String:
	return _sha256(var_to_bytes(_payload()))


func save_atomic(root: String) -> Dictionary:
	DirAccess.make_dir_recursive_absolute(root)
	var payload_bytes := var_to_bytes(_payload())
	var hash := _sha256(payload_bytes)
	var envelope := var_to_bytes({"magic": "P31-R5V-ADAPTIVE-1", "payload_sha256": hash,
		"payload": payload_bytes})
	var final_path := root.path_join(hash + ".r5v")
	if FileAccess.file_exists(final_path):
		var reused_verifier: RefCounted = get_script().new()
		return {"valid": reused_verifier._load_into(final_path, hash), "path": final_path, "reused": true,
			"bytes_written": 0}
	var temp_path := final_path + ".pending-%d" % Time.get_ticks_usec()
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return {"valid": false, "reason": "adaptive_temp_open_failed"}
	file.store_buffer(envelope)
	file.flush()
	file.close()
	var error := DirAccess.rename_absolute(temp_path, final_path)
	var verifier: RefCounted = get_script().new()
	return {"valid": error == OK and verifier._load_into(final_path, hash), "path": final_path,
		"bytes_written": envelope.size(), "publish_error": error}


func load_file(path: String, expected_digest: String) -> bool:
	return _load_into(path, expected_digest)


func _load_into(path: String, expected_digest: String) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		last_reason = "adaptive_open_failed"
		return false
	var envelope: Variant = bytes_to_var(file.get_buffer(file.get_length()))
	file.close()
	if typeof(envelope) != TYPE_DICTIONARY or String(envelope.get("magic", "")) != "P31-R5V-ADAPTIVE-1":
		last_reason = "adaptive_envelope_invalid"
		return false
	var payload: Variant = envelope.get("payload", PackedByteArray())
	if typeof(payload) != TYPE_PACKED_BYTE_ARRAY or _sha256(payload) != expected_digest \
		or String(envelope.get("payload_sha256", "")) != expected_digest:
		last_reason = "adaptive_payload_hash_invalid"
		return false
	var decoded: Variant = bytes_to_var(payload)
	if typeof(decoded) != TYPE_DICTIONARY:
		last_reason = "adaptive_identity_invalid"
		return false
	var base_density_value: Variant = decoded.get("base_densities", null)
	var cells_value: Variant = decoded.get("refined_cells", null)
	var dimensions_value: Variant = decoded.get("base_dimensions", null)
	var minimum_value: Variant = decoded.get("base_world_min", null)
	var decoded_region: Variant = decoded.get("region", null)
	var decoded_chunk: Variant = decoded.get("chunk", null)
	if typeof(base_density_value) != TYPE_PACKED_FLOAT32_ARRAY or typeof(cells_value) != TYPE_DICTIONARY \
		or typeof(dimensions_value) != TYPE_VECTOR3I or typeof(minimum_value) != TYPE_VECTOR3 \
		or typeof(decoded_region) != TYPE_VECTOR2I or typeof(decoded_chunk) != TYPE_VECTOR2I \
		or int(decoded.get("version", -1)) != 1:
		last_reason = "adaptive_payload_schema_invalid"
		return false
	var decoded_base := Voxel.new()
	decoded_base.spacing = COARSE_SPACING
	decoded_base.region = decoded_region
	decoded_base.chunk = decoded_chunk
	decoded_base.world_min = minimum_value
	decoded_base.nx = dimensions_value.x
	decoded_base.ny = dimensions_value.y
	decoded_base.nz = dimensions_value.z
	decoded_base.revision = int(decoded.get("revision", -1))
	decoded_base.world_seed = int(decoded.get("world_seed", 0))
	decoded_base.generator_version = 1
	decoded_base.densities = base_density_value
	if decoded_base.nx < 2 or decoded_base.ny < 2 or decoded_base.nz < 2 \
		or decoded_base.nx * decoded_base.ny * decoded_base.nz != decoded_base.densities.size() \
		or decoded_base.densities.size() > 100000:
		last_reason = "adaptive_base_grid_invalid"
		return false
	var decoded_subdivisions := int(decoded.get("subdivisions", -1))
	if decoded_subdivisions != 2 and decoded_subdivisions != 4:
		last_reason = "adaptive_subdivision_invalid"
		return false
	var expected_values := (decoded_subdivisions + 1) ** 3
	for key in cells_value:
		var fine_value: Variant = cells_value[key]
		if typeof(key) != TYPE_INT or typeof(fine_value) != TYPE_PACKED_FLOAT32_ARRAY \
			or fine_value.size() != expected_values:
			last_reason = "adaptive_refined_cell_invalid"
			return false
		for density in fine_value:
			if not is_finite(density):
				last_reason = "adaptive_refined_density_nonfinite"
				return false
	base = decoded_base
	region = decoded_region
	chunk = decoded_chunk
	world_seed = decoded_base.world_seed
	revision = decoded_base.revision
	subdivisions = decoded_subdivisions
	refinement_threshold = float(decoded.get("threshold", 0.02))
	refined_cells = cells_value
	fine_samples = 0
	return digest() == expected_digest


func _requires_refinement(x: int, y: int, z: int, snapshot: Dictionary) -> bool:
	var minimum := INF
	var maximum := -INF
	for oy in range(2):
		for oz in range(2):
			for ox in range(2):
				var value := float(base.densities[base._index(x + ox, y + oy, z + oz)])
				minimum = minf(minimum, value)
				maximum = maxf(maximum, value)
	if minimum <= 0.0 and maximum >= 0.0:
		return true
	var center: Vector3 = base.world_min + Vector3(float(x) + 0.5, float(y) + 0.5, float(z) + 0.5) * COARSE_SPACING
	var exact := _canonical_sample(center, snapshot)
	return absf(exact - base.sample_world(center)) > refinement_threshold


func _canonical_sample(point: Vector3, snapshot: Dictionary) -> float:
	var mapped: Dictionary = Spatial.world_to_region_local(point)
	if not bool(mapped.get("valid", false)):
		return NAN
	return Brush.sample_density_snapshot(world_seed, mapped["region_key"], mapped["local_position"], false, snapshot)


func _sample_fine(values: PackedFloat32Array, grid_position: Vector3, cell: Vector3i) -> float:
	var local := (grid_position - Vector3(cell)) * subdivisions
	var x0 := clampi(floori(local.x), 0, subdivisions - 1)
	var y0 := clampi(floori(local.y), 0, subdivisions - 1)
	var z0 := clampi(floori(local.z), 0, subdivisions - 1)
	var tx := clampf(local.x - x0, 0.0, 1.0)
	var ty := clampf(local.y - y0, 0.0, 1.0)
	var tz := clampf(local.z - z0, 0.0, 1.0)
	var c000 := float(values[_fine_index(x0, y0, z0)])
	var c100 := float(values[_fine_index(x0 + 1, y0, z0)])
	var c010 := float(values[_fine_index(x0, y0 + 1, z0)])
	var c110 := float(values[_fine_index(x0 + 1, y0 + 1, z0)])
	var c001 := float(values[_fine_index(x0, y0, z0 + 1)])
	var c101 := float(values[_fine_index(x0 + 1, y0, z0 + 1)])
	var c011 := float(values[_fine_index(x0, y0 + 1, z0 + 1)])
	var c111 := float(values[_fine_index(x0 + 1, y0 + 1, z0 + 1)])
	return lerpf(lerpf(lerpf(c000, c100, tx), lerpf(c010, c110, tx), ty),
		lerpf(lerpf(c001, c101, tx), lerpf(c011, c111, tx), ty), tz)


func _payload() -> Dictionary:
	var keys := refined_cells.keys()
	keys.sort()
	var sorted_cells := {}
	for key in keys:
		sorted_cells[key] = refined_cells[key]
	return {"version": 1, "region": region, "chunk": chunk, "world_seed": world_seed,
		"revision": revision, "base_spacing": COARSE_SPACING, "subdivisions": subdivisions,
		"threshold": refinement_threshold, "base_world_min": base.world_min if base != null else Vector3.ZERO,
		"base_dimensions": Vector3i(base.nx, base.ny, base.nz) if base != null else Vector3i.ZERO,
		"base_densities": base.densities.duplicate() if base != null else PackedFloat32Array(),
		"refined_cells": sorted_cells}


func _macro_key(x: int, y: int, z: int) -> int:
	return (y * (base.nz - 1) + z) * (base.nx - 1) + x


func _fine_index(x: int, y: int, z: int) -> int:
	var side := subdivisions + 1
	return (y * side + z) * side + x


static func _sha256(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()
