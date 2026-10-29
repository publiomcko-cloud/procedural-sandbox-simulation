extends SceneTree

const Core := preload("res://tests/prototypes/p3_1_r9_2_diagnostic_base.gd")
const CandidateScript := preload("res://tests/prototypes/p3_1_r9_2_candidate_impl.gd")
const BaselineScript := preload("res://tests/prototypes/r9_5_source_snapshots/candidate_d.gd")
const EXPECTED_MANIFEST_SHA := "1610c535f98a11e26ca1890c0d99addf4316fbcaa7ec9cdb7dfaa71cf5bb3972"
const CORNER_EDGES: Array[Array] = [[0,1],[0,2],[0,3],[1,2],[1,3],[2,3]]

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var manifest: Dictionary = Core.load_manifest()
	if not bool(manifest.get("valid", false)) or String(manifest.get("sha256", "")) != EXPECTED_MANIFEST_SHA:
		_finish({"valid":false,"reason":"frozen_manifest_invalid","detail":manifest})
		return
	var manifest_rows: Array = manifest.get("rows", [])
	var row: Dictionary = Core.case_by_id(manifest_rows, "R9.2.SEAM.NEGATIVE_REGIONS.v1")
	if row.is_empty():
		_finish({"valid":false,"reason":"x_negative_frozen_scenario_missing"})
		return
	var setup: Dictionary = Core.make_snapshot(row)
	if not bool(setup.get("valid", false)):
		_finish({"valid":false,"reason":"frozen_snapshot_invalid","detail":setup})
		return
	var variant: Dictionary = {}
	for value in row.get("variants", []):
		var candidate_variant: Dictionary = value
		if String(candidate_variant.get("id", "")) == "X_NEG":
			variant = candidate_variant
			break
	if variant.is_empty():
		_finish({"valid":false,"reason":"x_negative_variant_missing"})
		return
	var roi: Dictionary = variant.get("roi", {})
	var candidate: RefCounted = CandidateScript.new()
	var baseline: RefCounted = BaselineScript.new()
	candidate.call("configure_roi", roi)
	baseline.call("configure_roi", roi)
	var candidate_build: Dictionary = candidate.call("build", setup.snapshot, row, variant)
	var baseline_build: Dictionary = baseline.call("build", setup.snapshot, row, variant)
	if not bool(candidate_build.get("valid", false)) or not bool(baseline_build.get("valid", false)):
		_finish({"valid":false,"reason":"x_negative_build_failed","candidate_reason":candidate_build.get("reason","unknown"),"baseline_reason":baseline_build.get("reason","unknown")})
		return
	var candidate_volume: Dictionary = candidate_build.get("volume", {})
	var baseline_volume: Dictionary = baseline_build.get("volume", {})
	var values: PackedFloat32Array = candidate_volume.get("values", PackedFloat32Array())
	var dims: Vector3i = Core.cell_counts(roi) + Vector3i.ONE
	var root_diagnostic: Dictionary = _compare_crossing_roots(values, dims, Core.world_min(roi), Core.step(roi))
	var candidate_mesh: Dictionary = candidate_build.get("mesh", {})
	var baseline_mesh: Dictionary = baseline_build.get("mesh", {})
	var candidate_positions: PackedVector3Array = candidate_mesh.get("positions", PackedVector3Array())
	var baseline_positions: PackedVector3Array = baseline_mesh.get("positions", PackedVector3Array())
	var candidate_normals: PackedVector3Array = candidate_mesh.get("normals", PackedVector3Array())
	var baseline_normals: PackedVector3Array = baseline_mesh.get("normals", PackedVector3Array())
	var candidate_indices: PackedInt32Array = candidate_mesh.get("indices", PackedInt32Array())
	var baseline_indices: PackedInt32Array = baseline_mesh.get("indices", PackedInt32Array())
	var positions: Dictionary = _compare_vector3_arrays(candidate_positions, baseline_positions)
	var normals: Dictionary = _compare_vector3_arrays(candidate_normals, baseline_normals)
	var indices: Dictionary = _compare_int_arrays(candidate_indices, baseline_indices)
	var bounds_min: Vector3 = Core.world_min(roi)
	var bounds_max: Vector3 = bounds_min + Vector3(Core.cell_counts(roi)) * Core.step(roi)
	var payload: Dictionary = {
		"schema":"P3.1.R9.6R1.DXNEG.Diagnostic.v1",
		"scenario_id":String(row.get("scenario_id", "")),"variant_id":"X_NEG",
		"manifest_sha256":String(manifest.get("sha256", "")),
		"candidate_source_sha256":Core.sha256(FileAccess.get_file_as_bytes("res://tests/prototypes/p3_1_r9_2_candidate_impl.gd")),
		"baseline_source_sha256":Core.sha256(FileAccess.get_file_as_bytes("res://tests/prototypes/r9_5_source_snapshots/candidate_d.gd")),
		"roi":roi,"revision":int(setup.get("revision", -1)),"command_count":row.get("commands", []).size(),
		"volume_sha256_candidate":String(candidate_volume.get("sha256", "")),
		"volume_sha256_baseline":String(baseline_volume.get("sha256", "")),
		"volume_bytes_equal":String(candidate_volume.get("sha256", "")) == String(baseline_volume.get("sha256", "")),
		"root_arithmetic":root_diagnostic,
		"candidate_mesh_sha256":String(candidate_build.get("mesh_sha256", "")),
		"baseline_mesh_sha256":String(baseline_build.get("mesh_sha256", "")),
		"mesh_sha_equal":String(candidate_build.get("mesh_sha256", "")) == String(baseline_build.get("mesh_sha256", "")),
		"positions":positions,"normals":normals,"indices":indices,
		"candidate_topology":Core.topology(candidate_mesh, bounds_min, bounds_max),
		"baseline_topology":Core.topology(baseline_mesh, bounds_min, bounds_max),
		"candidate_mesh_hash_inputs":_mesh_hash_inputs(candidate_mesh),
		"baseline_mesh_hash_inputs":_mesh_hash_inputs(baseline_mesh),
		"attempt_classification":"D1_CONTROL_DIAGNOSTIC_ONLY; DOES_NOT_CONSUME_D2"
	}
	var valid: bool = bool(payload.get("volume_bytes_equal", false)) and bool(root_diagnostic.get("valid", false)) and bool(root_diagnostic.get("baseline_equals_numeric_global", false)) and bool(payload.get("mesh_sha_equal", false)) and bool(positions.get("exact_equal", false)) and bool(normals.get("exact_equal", false)) and bool(indices.get("exact_equal", false))
	payload["valid"] = valid
	payload["diagnosis"] = "NUMERIC_ORDERING_DRIFT_CORRECTED" if valid else "UNRESOLVED_REQUIRES_FURTHER_CONTROL_DIAGNOSIS"
	_finish(payload)

func _compare_crossing_roots(values: PackedFloat32Array, dims: Vector3i, roi_min: Vector3, step: float) -> Dictionary:
	if values.size() != dims.x * dims.y * dims.z or dims.x < 2 or dims.y < 2 or dims.z < 2:
		return {"valid":false,"reason":"materialized_values_shape_invalid","size":values.size(),"dims":dims}
	var lattice_origin := Vector3i(roundi(roi_min.x / step), roundi(roi_min.y / step), roundi(roi_min.z / step))
	var cells: Vector3i = dims - Vector3i.ONE
	var edges: Dictionary = {}
	for y in range(cells.y):
		for z in range(cells.z):
			for x in range(cells.x):
				for tet_value in Core.TETS:
					var tet: Array = tet_value
					for pair_value in CORNER_EDGES:
						var pair: Array = pair_value
						var ca: int = int(tet[int(pair[0])])
						var cb: int = int(tet[int(pair[1])])
						var node_a: Vector3i = Vector3i(x,y,z) + Core.GRID_CORNERS[ca]
						var node_b: Vector3i = Vector3i(x,y,z) + Core.GRID_CORNERS[cb]
						var value_a: float = values[_idx(node_a, dims)]
						var value_b: float = values[_idx(node_b, dims)]
						if (value_a >= 0.0) == (value_b >= 0.0):
							continue
						var id_a: String = _lattice_key(node_a)
						var id_b: String = _lattice_key(node_b)
						var unique_key: String = id_a + "|" + id_b if _int3_before(node_a, node_b) else id_b + "|" + id_a
						if edges.has(unique_key):
							continue
						edges[unique_key] = {"a":node_a,"b":node_b,"value_a":value_a,"value_b":value_b}
	var baseline_current_order_differences: int = 0
	var baseline_numeric_root_bit_differences: int = 0
	var current_numeric_root_bit_differences: int = 0
	var examples: Array[Dictionary] = []
	var sorted_edges: Array = edges.keys()
	sorted_edges.sort()
	for edge_id_value in sorted_edges:
		var edge_id: String = String(edge_id_value)
		var edge: Dictionary = edges[edge_id]
		var a: Vector3i = edge.a
		var b: Vector3i = edge.b
		var va: float = float(edge.value_a)
		var vb: float = float(edge.value_b)
		var pa: Vector3 = roi_min + Vector3(a) * step
		var pb: Vector3 = roi_min + Vector3(b) * step
		var local_a: String = _lattice_key(a)
		var local_b: String = _lattice_key(b)
		var global_a: Vector3i = lattice_origin + a
		var global_b: Vector3i = lattice_origin + b
		var global_key_a: String = _lattice_key(global_a)
		var global_key_b: String = _lattice_key(global_b)
		var old_root: Dictionary = _ordered_root(local_a > local_b, a, b, va, vb, pa, pb, lattice_origin, "baseline")
		var pre_fix_root: Dictionary = _ordered_root(global_key_a > global_key_b, a, b, va, vb, pa, pb, lattice_origin, "pre_fix_d1")
		var fixed_root: Dictionary = _ordered_root(_int3_before(global_b, global_a), a, b, va, vb, pa, pb, lattice_origin, "fixed_d1")
		var order_changed: bool = (local_a > local_b) != (global_key_a > global_key_b)
		if order_changed:
			baseline_current_order_differences += 1
		if String(old_root.point_hex) != String(fixed_root.point_hex):
			baseline_numeric_root_bit_differences += 1
		if String(pre_fix_root.point_hex) != String(fixed_root.point_hex):
			current_numeric_root_bit_differences += 1
		if order_changed or String(old_root.point_hex) != String(pre_fix_root.point_hex):
			if examples.size() < 32:
				examples.append({"baseline_edge_id":String(old_root.edge_id),"pre_fix_d1_edge_id":String(pre_fix_root.edge_id),"fixed_global_edge_id":String(fixed_root.edge_id),"baseline_root_identity":String(old_root.root_identity),"pre_fix_d1_root_identity":String(pre_fix_root.root_identity),"fixed_root_identity":String(fixed_root.root_identity),"local_endpoints":[a,b],"global_endpoints":[global_a,global_b],"original_endpoint_order":[a,b],"baseline_order":[old_root.ordered_nodes[0],old_root.ordered_nodes[1]],"pre_fix_d1_order":[pre_fix_root.ordered_nodes[0],pre_fix_root.ordered_nodes[1]],"fixed_order":[fixed_root.ordered_nodes[0],fixed_root.ordered_nodes[1]],"endpoint_float32":[va,vb],"baseline_t_float64_hex":old_root.t_hex,"pre_fix_d1_t_float64_hex":pre_fix_root.t_hex,"fixed_t_float64_hex":fixed_root.t_hex,"baseline_point_float32_hex":old_root.point_hex,"pre_fix_d1_point_float32_hex":pre_fix_root.point_hex,"fixed_point_float32_hex":fixed_root.point_hex,"baseline_vs_fixed_equal":String(old_root.point_hex)==String(fixed_root.point_hex),"pre_fix_vs_fixed_equal":String(pre_fix_root.point_hex)==String(fixed_root.point_hex)})	return {"valid":true,"unique_crossing_tetra_edges":edges.size(),"baseline_lexical_vs_pre_fix_global_lexical_order_differences":baseline_current_order_differences,"baseline_root_binary32_vs_fixed_numeric_global_mismatches":baseline_numeric_root_bit_differences,"pre_fix_root_binary32_vs_fixed_numeric_mismatches":current_numeric_root_bit_differences,"baseline_equals_numeric_global":baseline_numeric_root_bit_differences==0,"examples":examples}

func _ordered_root(reverse: bool, a: Vector3i, b: Vector3i, va: float, vb: float, pa: Vector3, pb: Vector3, lattice_origin: Vector3i, identity_mode: String) -> Dictionary:
	var first_node: Vector3i = b if reverse else a
	var second_node: Vector3i = a if reverse else b
	var first_value: float = vb if reverse else va
	var second_value: float = va if reverse else vb
	var first_point: Vector3 = pb if reverse else pa
	var second_point: Vector3 = pa if reverse else pb
	var denominator: float = first_value - second_value
	if denominator == 0.0 or not is_finite(denominator):
		return {"valid":false,"edge_id":"","point_hex":"","t_hex":"","ordered_nodes":[first_node,second_node]}
	var t: float = clampf(first_value / denominator, 0.0, 1.0)
	var point: Vector3 = first_point.lerp(second_point, t)
	if first_value == 0.0:
		point = first_point
	elif second_value == 0.0:
		point = second_point
	var first_key: String = _lattice_key(first_node) if identity_mode == "baseline" else _lattice_key(lattice_origin + first_node)
	var second_key: String = _lattice_key(second_node) if identity_mode == "baseline" else _lattice_key(lattice_origin + second_node)
	var edge_id: String = first_key + "|" + second_key
	var root_identity: String = edge_id if identity_mode == "baseline" else "edge|" + _point_key(first_point) + "|" + _point_key(second_point)
	if identity_mode != "baseline":
		var first_world_key: String = _point_key(first_point)
		var second_world_key: String = _point_key(second_point)
		if first_world_key > second_world_key:
			var key_swap: String = first_world_key
			first_world_key = second_world_key
			second_world_key = key_swap
		root_identity = "edge|" + first_world_key + "|" + second_world_key
	if first_value == 0.0:
		root_identity = "node|" + (first_key if identity_mode == "baseline" else _point_key(first_point))
	elif second_value == 0.0:
		root_identity = "node|" + (second_key if identity_mode == "baseline" else _point_key(second_point))
	return {"valid":point.is_finite(),"edge_id":edge_id,"root_identity":root_identity,"t_hex":PackedFloat64Array([t]).to_byte_array().hex_encode(),"point_hex":PackedVector3Array([point]).to_byte_array().hex_encode(),"ordered_nodes":[first_node,second_node]}

func _point_key(point: Vector3) -> String:
	return PackedVector3Array([point]).to_byte_array().hex_encode()

func _compare_vector3_arrays(left: PackedVector3Array, right: PackedVector3Array) -> Dictionary:
	if left.size() != right.size():
		return {"exact_equal":false,"left_size":left.size(),"right_size":right.size(),"first_mismatch":-1}
	for i in range(left.size()):
		if left[i] != right[i]:
			return {"exact_equal":false,"left_size":left.size(),"right_size":right.size(),"first_mismatch":i,"left_float32_hex":PackedVector3Array([left[i]]).to_byte_array().hex_encode(),"right_float32_hex":PackedVector3Array([right[i]]).to_byte_array().hex_encode()}
	return {"exact_equal":true,"left_size":left.size(),"right_size":right.size(),"first_mismatch":-1}

func _compare_int_arrays(left: PackedInt32Array, right: PackedInt32Array) -> Dictionary:
	if left.size() != right.size():
		return {"exact_equal":false,"left_size":left.size(),"right_size":right.size(),"first_mismatch":-1}
	for i in range(left.size()):
		if left[i] != right[i]:
			return {"exact_equal":false,"left_size":left.size(),"right_size":right.size(),"first_mismatch":i,"left_value":left[i],"right_value":right[i]}
	return {"exact_equal":true,"left_size":left.size(),"right_size":right.size(),"first_mismatch":-1}

func _mesh_hash_inputs(mesh: Dictionary) -> Dictionary:
	var position_values: PackedVector3Array = mesh.get("positions", PackedVector3Array())
	var normal_values: PackedVector3Array = mesh.get("normals", PackedVector3Array())
	var position_bytes: PackedByteArray = position_values.to_byte_array()
	var normal_bytes: PackedByteArray = normal_values.to_byte_array()
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(("%d:%d:" % [position_bytes.size(), normal_bytes.size()]).to_utf8_buffer())
	if not position_bytes.is_empty(): context.update(position_bytes)
	if not normal_bytes.is_empty(): context.update(normal_bytes)
	return {"position_bytes":position_bytes.size(),"normal_bytes":normal_bytes.size(),"positions_sha256":Core.sha256(position_bytes),"normals_sha256":Core.sha256(normal_bytes),"composite_sha256":context.finish().hex_encode()}

func _lattice_key(node: Vector3i) -> String:
	return "%d,%d,%d" % [node.x,node.y,node.z]

func _int3_before(a: Vector3i, b: Vector3i) -> bool:
	if a.x != b.x: return a.x < b.x
	if a.y != b.y: return a.y < b.y
	return a.z < b.z

func _idx(node: Vector3i, dims: Vector3i) -> int:
	return (node.y * dims.z + node.z) * dims.x + node.x

func _finish(payload: Dictionary) -> void:
	var artifact_root: String = OS.get_environment("R96R1_ARTIFACT_DIR")
	if artifact_root.is_empty():
		payload["valid"] = false
		payload["artifact_write_reason"] = "R96R1_ARTIFACT_DIR_missing"
	else:
		DirAccess.make_dir_recursive_absolute(artifact_root)
		var path: String = artifact_root.path_join("D_XNEG_root_order_diagnostic.json")
		var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			payload["valid"] = false
			payload["artifact_write_reason"] = "artifact_open_failed"
		else:
			file.store_string(JSON.stringify(payload, "\t") + "\n")
			file.flush()
			file.close()
	print("R96R1_D_XNEG_DIAGNOSTIC " + JSON.stringify(payload))
	quit(0 if bool(payload.get("valid", false)) else 1)
