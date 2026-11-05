extends SceneTree

## Architecture alternative A: feed the project's canonical edited SDF into the
## native Voxel Tools Transvoxel mesher. The script deliberately resolves
## VoxelBuffer/VoxelMesherTransvoxel through ClassDB so the base project stays
## loadable with stock Godot; this probe is executed only with a Voxel Tools build.

const Field := preload("res://scripts/terrain/sdf_world.gd")
const Brush := preload("res://scripts/terrain/sdf_brush_edit_state.gd")
const Spatial := preload("res://scripts/terrain/terrain_spatial_ownership.gd")

const SEED := 131102026
const STEP := 0.25
const FACE_Y_MIN := 1.0
const FACE_Z_MIN := 6.0
const INTERIOR_CELLS := Vector3i(8, 8, 8)
const TARGET_XPLUS := 16.0
const CHANNEL_SDF := 1
const DEPTH_32_BIT := 2
const DIR_X_POS := 1

var assertions := 0
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_check(ClassDB.class_exists("VoxelBuffer"), "Voxel Tools exposes VoxelBuffer")
	_check(ClassDB.class_exists("VoxelMesherTransvoxel"), "Voxel Tools exposes VoxelMesherTransvoxel")
	if failures > 0:
		_finish({})
		return

	var snapshot_result := _make_frozen_snapshot()
	_check(snapshot_result.get("valid", false), "exact R6 edit snapshot is accepted")
	if not snapshot_result.get("valid", false):
		_finish(snapshot_result)
		return
	var snapshot: Dictionary = snapshot_result.snapshot

	var face_changes := _count_xplus_face_sign_changes(snapshot)
	_check(face_changes > 0, "the frozen R6 field crosses the +X transition face at x=16")

	var first := _build_case(snapshot)
	var second := _build_case(snapshot)
	_check(first.get("valid", false), "Transvoxel regular and +X transition meshes build")
	_check(second.get("valid", false), "Transvoxel deterministic repeat builds")
	if not first.get("valid", false) or not second.get("valid", false):
		_finish(first)
		return

	_check(int(first.get("regular_triangle_count", 0)) > 0, "regular Transvoxel mesh is non-empty")
	_check(int(first.get("transition_triangle_count", 0)) > 0, "+X Transvoxel transition mesh is non-empty")
	_check(int(first.get("regular_degenerate_count", -1)) == 0, "regular mesh has no degenerate triangles")
	_check(int(first.get("transition_degenerate_count", -1)) == 0, "transition mesh has no degenerate triangles")
	_check(bool(first.get("regular_finite", false)), "regular mesh vertices are finite")
	_check(bool(first.get("transition_finite", false)), "transition mesh vertices are finite")
	_check(first.get("regular_signature", "") == second.get("regular_signature", ""), "regular mesh repeats deterministically")
	_check(first.get("transition_signature", "") == second.get("transition_signature", ""), "transition mesh repeats deterministically")

	first["xplus_face_sign_change_edges"] = face_changes
	first["scenario_id"] = "R9.2.SEAM.XPLUS_MIXED_LOD.v1"
	first["architecture"] = "canonical project SDF/ledger -> float32 VoxelBuffer -> VoxelMesherTransvoxel regular mesh plus +X transition mesh"
	_finish(first)


func _make_frozen_snapshot() -> Dictionary:
	var ledger := Brush.new(SEED, Field.GENERATOR_VERSION)
	if not ledger.add_sphere(Brush.Mode.FILL, Vector3(8.0, 1.17898154258728, 5.10309219360352), 0.58):
		return {"valid": false, "reason": "fill_rejected", "detail": ledger.last_rejection_reason}
	if not ledger.add_sphere(Brush.Mode.CARVE, Vector3(8.0, 1.17898154258728, 5.92309236526489), 0.58):
		return {"valid": false, "reason": "carve_rejected", "detail": ledger.last_rejection_reason}
	var snapshot: Dictionary = ledger.get_meshing_snapshot()
	if int(snapshot.get("revision", -1)) != 2:
		return {"valid": false, "reason": "snapshot_revision_mismatch"}
	return {"valid": true, "snapshot": snapshot}


func _sample_project_density(world: Vector3, snapshot: Dictionary) -> float:
	var mapped: Dictionary = Spatial.world_to_region_local(world)
	if not bool(mapped.get("valid", false)):
		return NAN
	return Brush.sample_density_snapshot(SEED, mapped.region_key, mapped.local_position, false, snapshot)


func _build_case(snapshot: Dictionary) -> Dictionary:
	var mesher: Object = ClassDB.instantiate("VoxelMesherTransvoxel")
	if mesher == null:
		return {"valid": false, "reason": "mesher_instantiation_failed"}
	var min_padding := int(mesher.call("get_minimum_padding"))
	var max_padding := int(mesher.call("get_maximum_padding"))
	if min_padding < 0 or max_padding < 0 or min_padding > 8 or max_padding > 8:
		return {"valid": false, "reason": "unexpected_padding", "minimum": min_padding, "maximum": max_padding}

	var node_extent := INTERIOR_CELLS + Vector3i.ONE
	var size := node_extent + Vector3i.ONE * (min_padding + max_padding)
	var buffer: Object = ClassDB.instantiate("VoxelBuffer")
	if buffer == null:
		return {"valid": false, "reason": "buffer_instantiation_failed"}
	buffer.call("create", size.x, size.y, size.z)
	buffer.call("set_channel_depth", CHANNEL_SDF, DEPTH_32_BIT)

	for y in range(size.y):
		for z in range(size.z):
			for x in range(size.x):
				var transition_face_buffer_x := size.x - 1 - min_padding
				var world := Vector3(
					TARGET_XPLUS + float(x - transition_face_buffer_x) * STEP,
					FACE_Y_MIN + float(y - min_padding) * STEP,
					FACE_Z_MIN + float(z - min_padding) * STEP
				)
				var project_density := _sample_project_density(world, snapshot)
				if not is_finite(project_density):
					return {"valid": false, "reason": "nonfinite_project_density", "voxel": [x, y, z]}
				# Project convention: positive is solid. Voxel Tools SDF convention:
				# negative is inside matter, so the sign must be inverted.
				buffer.call("set_voxel_f", -project_density, x, y, z, CHANNEL_SDF)

	var regular_variant: Variant = mesher.call("build_mesh", buffer, [], {})
	var transition_variant: Variant = mesher.call("build_transition_mesh", buffer, DIR_X_POS)
	if regular_variant == null:
		return {"valid": false, "reason": "regular_mesh_null", "padding": [min_padding, max_padding]}
	if transition_variant == null:
		return {"valid": false, "reason": "transition_mesh_null", "padding": [min_padding, max_padding]}
	if not regular_variant is Mesh or not transition_variant is Mesh:
		return {"valid": false, "reason": "mesher_return_type_invalid"}

	var regular := _inspect_mesh(regular_variant)
	var transition := _inspect_mesh(transition_variant)
	if not regular.valid:
		return {"valid": false, "reason": "regular_mesh_invalid", "detail": regular}
	if not transition.valid:
		return {"valid": false, "reason": "transition_mesh_invalid", "detail": transition}
	return {
		"valid": true,
		"voxel_tools_detected": true,
		"minimum_padding": min_padding,
		"maximum_padding": max_padding,
		"buffer_size": [size.x, size.y, size.z],
		"regular_grid_min_world": [
			TARGET_XPLUS - float((size.x - 1 - min_padding) - min_padding) * STEP,
			FACE_Y_MIN,
			FACE_Z_MIN
		],
		"transition_face_world_x": TARGET_XPLUS,
		"interior_cells": [INTERIOR_CELLS.x, INTERIOR_CELLS.y, INTERIOR_CELLS.z],
		"sample_step": STEP,
		"transition_direction": DIR_X_POS,
		"regular_vertex_count": regular.vertex_count,
		"regular_triangle_count": regular.triangle_count,
		"regular_degenerate_count": regular.degenerate_count,
		"regular_finite": regular.finite,
		"regular_signature": regular.signature,
		"transition_vertex_count": transition.vertex_count,
		"transition_triangle_count": transition.triangle_count,
		"transition_degenerate_count": transition.degenerate_count,
		"transition_finite": transition.finite,
		"transition_signature": transition.signature,
	}


func _inspect_mesh(mesh: Mesh) -> Dictionary:
	var vertices_total := 0
	var triangles_total := 0
	var degenerates := 0
	var finite := true
	var signature_rows: Array[String] = []
	for surface_index in range(mesh.get_surface_count()):
		var arrays: Array = mesh.surface_get_arrays(surface_index)
		if arrays.size() <= Mesh.ARRAY_VERTEX:
			continue
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		vertices_total += vertices.size()
		for v in vertices:
			if not v.is_finite():
				finite = false
			signature_rows.append("v:%d,%d,%d" % [roundi(v.x * 1000000.0), roundi(v.y * 1000000.0), roundi(v.z * 1000000.0)])
		if indices.is_empty():
			triangles_total += vertices.size() / 3
			for i in range(0, vertices.size() - 2, 3):
				if (vertices[i + 1] - vertices[i]).cross(vertices[i + 2] - vertices[i]).length_squared() <= 1.0e-14:
					degenerates += 1
		else:
			if indices.size() % 3 != 0:
				return {"valid": false, "reason": "index_count_not_triangular"}
			triangles_total += indices.size() / 3
			for i in range(0, indices.size(), 3):
				var ia := indices[i]
				var ib := indices[i + 1]
				var ic := indices[i + 2]
				if ia < 0 or ib < 0 or ic < 0 or ia >= vertices.size() or ib >= vertices.size() or ic >= vertices.size():
					return {"valid": false, "reason": "index_out_of_range"}
				if (vertices[ib] - vertices[ia]).cross(vertices[ic] - vertices[ia]).length_squared() <= 1.0e-14:
					degenerates += 1
				signature_rows.append("i:%d,%d,%d" % [ia, ib, ic])
	return {
		"valid": true,
		"vertex_count": vertices_total,
		"triangle_count": triangles_total,
		"degenerate_count": degenerates,
		"finite": finite,
		"signature": _fnv1a_64("\n".join(signature_rows)),
	}


func _count_xplus_face_sign_changes(snapshot: Dictionary) -> int:
	var changes := 0
	var x := TARGET_XPLUS
	var nodes := INTERIOR_CELLS.y + 1
	var values: Array[Array] = []
	for y in range(nodes):
		var row: Array = []
		for z in range(INTERIOR_CELLS.z + 1):
			row.append(_sample_project_density(Vector3(x, FACE_Y_MIN + y * STEP, FACE_Z_MIN + z * STEP), snapshot))
		values.append(row)
	for y in range(INTERIOR_CELLS.y + 1):
		for z in range(INTERIOR_CELLS.z):
			if _different_sign(float(values[y][z]), float(values[y][z + 1])):
				changes += 1
	for y in range(INTERIOR_CELLS.y):
		for z in range(INTERIOR_CELLS.z + 1):
			if _different_sign(float(values[y][z]), float(values[y + 1][z])):
				changes += 1
	return changes


func _different_sign(a: float, b: float) -> bool:
	return (a >= 0.0 and b < 0.0) or (a < 0.0 and b >= 0.0)


func _fnv1a_64(text_value: String) -> String:
	var hash: int = 1469598103934665603
	for byte in text_value.to_utf8_buffer():
		hash = hash ^ int(byte)
		hash = hash * 1099511628211
	return "%016x" % hash


func _check(condition: bool, message: String) -> void:
	assertions += 1
	if condition:
		print("PASS: %s" % message)
	else:
		failures += 1
		push_error("FAIL: %s" % message)


func _finish(result: Dictionary) -> void:
	var payload := {
		"status": "PASS" if failures == 0 else "FAIL",
		"assertions": assertions,
		"failures": failures,
		"result": result,
	}
	print("ARCH_ALT_TRANSVOXEL_RESULT=" + JSON.stringify(payload))
	print("ARCH_ALT_TRANSVOXEL_%s: assertions=%d failures=%d" % ["PASS" if failures == 0 else "FAIL", assertions, failures])
	quit(0 if failures == 0 else 1)
