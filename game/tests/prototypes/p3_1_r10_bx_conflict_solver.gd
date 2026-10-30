extends RefCounted

## Test-only R10-BX solver. It consumes only the immutable B1R candidate domain
## and never writes production data. Compatibility is precomputed once for the
## frozen root set and then used as bitset propagation during exact search.

const B1R := preload("res://tests/prototypes/p3_1_r10_b1r_direct_triangulator.gd")
const DOMAIN_SHA256 := "30c89e9ca26c5c6550b6662fc6ccb46f566cfff7eb29b9e740f8ec1b1b7c9c22"
const CANDIDATE_COUNT := 7608
const ROOT_COUNT := 73
const BOUNDARY_EDGE_COUNT := 34
const CANDIDATE_UNIQUE_EDGE_COUNT := 2239
const TARGET_FACE_COUNT := 110
const TARGET_UNIQUE_EDGE_COUNT := 182
const CATEGORY_CROSSING := 1
const CATEGORY_CONTAINMENT := 2
const CATEGORY_SAME_INTERIOR_EDGE_DIRECTION := 4
const CATEGORY_BOUNDARY_EDGE_DUPLICATE := 8
const CATEGORY_GEOMETRIC_MASK := CATEGORY_CROSSING | CATEGORY_CONTAINMENT
const INDEX_SCHEMA := "P3.1.R10BX.ConflictIndex.v1"
const RECEIPT_SCHEMA := "P3.1.R10BX.ConflictIndexReceipt.v1"
const SAFE_INTEGER_MAX := 9007199254740991
const FLOAT64_UNIT_ROUNDOFF := 2.220446049250313e-16

const EXPECTED_IDENTITY: Dictionary = {
	"b1r_realizer_sha256": "31fc01c78e273aede396a7596c3827f4520f45259d2c7e0f2ef9663d73ebcb5e",
	"candidate_d_sha256": "334db9e3e9dfe3aca4a590845ba6b792629d204c0f1d6a3fc8a3898e7cbb020a",
	"component_id": "60,8,25|tet:0",
	"cross_squared_cutoff": 1.0e-12,
	"grid_step": 0.25,
	"manifest_sha256": "1610c535f98a11e26ca1890c0d99addf4316fbcaa7ec9cdb7dfaa71cf5bb3972",
	"payload_sha256": "2ff3685296a8d035967a8c723bc42cb8320a9500dc699538a731490d089203d0",
	"revision": 2,
	"roi_cells": [8, 8, 8],
	"roi_id": "XPLUS_BOTH_SIDES",
	"roi_min": [15.0, 1.0, 6.0],
	"source_sha": "6f28273d0113f93678034b9e482140e73e765721",
	"source_topology_sha256": "4ecbb2496fb34f1cf3c05a60192f76bdce7a52ec3148d02ba041510b804a8c95",
	"volume_sha256": "ecf86bce57e82cd0949d4576e7b7ebe4d1ef8d0633ac7f6d540fd56df6573be2"
}

var _popcount: PackedInt32Array = PackedInt32Array()

func _init() -> void:
	_popcount.resize(256)
	for value in range(256):
		var n: int = value
		var count: int = 0
		while n != 0:
			count += n & 1
			n >>= 1
		_popcount[value] = count

func load_pinned_domain(bytes: PackedByteArray, expected_sha256: String) -> Dictionary:
	if _sha256(bytes) != expected_sha256 or expected_sha256 != DOMAIN_SHA256:
		return {"valid": false, "reason": "candidate_domain_physical_hash_mismatch", "observed_sha256": _sha256(bytes)}
	var parser: JSON = JSON.new()
	var parse_error: Error = parser.parse(bytes.get_string_from_utf8())
	if parse_error != OK or not parser.data is Dictionary:
		return {"valid": false, "reason": "candidate_domain_json_invalid", "line": parser.get_error_line(), "message": parser.get_error_message()}
	var domain: Dictionary = parser.data
	var validator: RefCounted = B1R.new()
	var accepted: Dictionary = validator.call("_load_solver_domain", domain, EXPECTED_IDENTITY)
	if not bool(accepted.get("valid", false)):
		return {"valid": false, "reason": "pinned_b1r_domain_revalidation_failed", "detail": accepted}
	var candidates_variant: Variant = validator.get("_candidates")
	var projected_variant: Variant = validator.get("_projected")
	var boundary_variant: Variant = validator.get("_boundary_directions")
	var edge_points_variant: Variant = validator.get("_edge_points")
	if not candidates_variant is Array or not projected_variant is Array or not boundary_variant is Dictionary or not edge_points_variant is Dictionary:
		return {"valid": false, "reason": "b1r_revalidated_index_types_invalid"}
	if candidates_variant.size() != CANDIDATE_COUNT or projected_variant.size() != ROOT_COUNT or boundary_variant.size() != BOUNDARY_EDGE_COUNT:
		return {"valid": false, "reason": "pinned_candidate_domain_counts_mismatch", "candidates": candidates_variant.size(), "roots": projected_variant.size(), "boundary_edges": boundary_variant.size()}
	return {
		"valid": true,
		"domain": domain,
		"domain_sha256": expected_sha256,
		"identity_sha256": String(validator.call("_domain_identity_sha", domain)),
		"candidates": candidates_variant,
		"projected": projected_variant,
		"boundary_directions": boundary_variant,
		"edge_points": edge_points_variant,
		"candidate_count": accepted.candidate_count,
		"root_count": accepted.root_count
	}

func build_graph(loaded: Dictionary, pair_limit: int, time_limit_ms: int) -> Dictionary:
	if not bool(loaded.get("valid", false)):
		return {"valid": false, "reason": "unvalidated_domain_supplied"}
	if pair_limit <= 0 or time_limit_ms <= 0:
		return {"valid": false, "reason": "invalid_graph_build_limits"}
	var started: int = Time.get_ticks_msec()
	var candidates: Array = loaded.candidates
	var projected: Array = loaded.projected
	var count: int = candidates.size()
	var stride: int = (count + 7) >> 3
	var matrix_bytes: int = count * count
	var mask_bytes: int = count * stride
	# Preallocation estimate includes both relation matrices, bitset rows,
	# conservative candidate/edge metadata allowances and allocator headroom.
	var estimate: int = matrix_bytes + mask_bytes + 2628 * 2628 + count * 4096 + 2628 * 2048 + 64 * 1024 * 1024
	if count != CANDIDATE_COUNT or estimate > 512 * 1024 * 1024:
		return {"valid": false, "reason": "conflict_index_memory_bound_exceeded", "estimated_bytes": estimate, "limit_bytes": 512 * 1024 * 1024}
	var boundary_directions: Dictionary = loaded.boundary_directions
	var edge_index: Dictionary = {}
	var root_index: Array[Array] = []
	root_index.resize(ROOT_COUNT)
	for root in range(ROOT_COUNT): root_index[root] = []
	var candidate_ids: Array[String] = []
	var candidate_edges: Array[Array] = []
	var candidate_directions: Array[Array] = []
	var candidate_roots: Array[Array] = []
	var boxes: Array[Array] = []
	var candidate_rows: Array[Dictionary] = []
	var edge_to_points: Dictionary = loaded.edge_points.duplicate(true)
	for candidate_index in range(count):
		var candidate: Dictionary = candidates[candidate_index]
		var roots: Array = candidate.get("root_indices", [])
		var keys: Array = candidate.get("edge_keys", [])
		var directions: Array = candidate.get("edge_directions", [])
		if roots.size() != 3 or keys.size() != 3 or directions.size() != 3:
			return {"valid": false, "reason": "candidate_index_arity_invalid", "candidate_index": candidate_index}
		candidate_ids.append(String(candidate.get("id", "")))
		candidate_roots.append(roots.duplicate())
		candidate_edges.append(keys.duplicate())
		candidate_directions.append(directions.duplicate())
		for root_value in roots:
			var root_id: int = int(root_value)
			if root_id < 0 or root_id >= ROOT_COUNT:
				return {"valid": false, "reason": "candidate_root_out_of_range", "candidate_index": candidate_index}
			root_index[root_id].append(candidate_index)
		for edge_slot in range(3):
			var edge_key: int = int(keys[edge_slot])
			if not edge_index.has(edge_key):
				edge_index[edge_key] = {"key": edge_key, "a": mini(int(roots[edge_slot]), int(roots[(edge_slot + 1) % 3])), "b": maxi(int(roots[edge_slot]), int(roots[(edge_slot + 1) % 3])), "boundary": boundary_directions.has(edge_key), "required_direction": int(boundary_directions.get(edge_key, 0)), "positive": [], "negative": []}
			var edge_row: Dictionary = edge_index[edge_key]
			if int(directions[edge_slot]) > 0: edge_row.positive.append(candidate_index)
			else: edge_row.negative.append(candidate_index)
			edge_index[edge_key] = edge_row
		var a: Vector2 = projected[int(roots[0])]
		var b: Vector2 = projected[int(roots[1])]
		var c: Vector2 = projected[int(roots[2])]
		boxes.append([minf(a.x, minf(b.x, c.x)), minf(a.y, minf(b.y, c.y)), maxf(a.x, maxf(b.x, c.x)), maxf(a.y, maxf(b.y, c.y))])
		candidate_rows.append({"id": String(candidate.get("id", "")), "roots": roots.duplicate(), "root_ids": candidate.get("root_ids", []).duplicate(), "edges": keys.duplicate(), "directions": directions.duplicate(), "owner_cell": candidate.get("owner_cell", []).duplicate(), "cross_squared": float(candidate.get("cross_squared", 0.0)), "conflict_count": 0, "category_counts": {"edge_crossing": 0, "containment": 0, "same_interior_edge_direction": 0, "boundary_duplicate": 0}})
	var edge_keys: Array[int] = []
	for raw_key in edge_index.keys(): edge_keys.append(int(raw_key))
	edge_keys.sort()
	var edge_rows: Array[Dictionary] = []
	for key in edge_keys:
		var edge_row: Dictionary = edge_index[key]
		edge_row["maximum_incidence"] = 1 if bool(edge_row.boundary) else 2
		edge_row["required_final_incidence"] = 1 if bool(edge_row.boundary) else 2
		edge_row["orientation_rule"] = "frozen_boundary_direction" if bool(edge_row.boundary) else "one_positive_and_one_negative"
		edge_rows.append(edge_row)
	var edge_matrix_result: Dictionary = _build_edge_geometry_matrix(edge_rows, projected, pair_limit, time_limit_ms, started)
	if not bool(edge_matrix_result.get("valid", false)):
		return {"valid": false, "reason": "unique_edge_conflict_build_failed", "detail": edge_matrix_result, "candidate_count": count}
	var edge_conflicts: PackedByteArray = edge_matrix_result.conflicts
	var edge_count: int = edge_rows.size()
	var edge_index_by_key: Dictionary = {}
	for edge_matrix_index in range(edge_count): edge_index_by_key[int(edge_rows[edge_matrix_index].key)] = edge_matrix_index
	var candidate_edge_indices: Array[Array] = []
	for edge_keys_row in candidate_edges:
		var edge_indices: Array[int] = []
		for raw_edge_key in edge_keys_row:
			if not edge_index_by_key.has(int(raw_edge_key)):
				return {"valid": false, "reason": "candidate_unique_edge_index_missing", "edge_key": raw_edge_key}
			edge_indices.append(int(edge_index_by_key[int(raw_edge_key)]))
		candidate_edge_indices.append(edge_indices)
	var conflicts: PackedByteArray = PackedByteArray()
	conflicts.resize(mask_bytes)
	var categories: PackedByteArray = PackedByteArray()
	categories.resize(matrix_bytes)
	var theoretical_pairs: int = (count * (count - 1)) >> 1
	var x_sweep_pairs: int = 0
	var candidate_aabb_pair_tests: int = 0
	var candidate_axis_filter_pair_tests: int = 0
	var candidate_axis_rejected_pairs: int = 0
	var candidate_pair_tests: int = 0
	var unique_conflicts: int = 0
	var category_pair_counts: Dictionary = {"edge_crossing": 0, "containment": 0, "same_interior_edge_direction": 0, "boundary_duplicate": 0}
	var witness_crossing: Array[int] = []
	var witness_containment: Array[int] = []
	var witness_legal_shared_edge: Array[int] = []
	var witness_compatible_vertex_only: Array[int] = []
	var projected_centroids: Array[Vector2] = []
	for candidate_roots_row in candidate_roots:
		projected_centroids.append((projected[int(candidate_roots_row[0])] + projected[int(candidate_roots_row[1])] + projected[int(candidate_roots_row[2])]) / 3.0)
	var graph_limit_reason: String = ""
	var incidence_pair_checks: int = 0
	var order: Array[int] = []
	for candidate_index in range(count): order.append(candidate_index)
	order.sort_custom(func(left: int, right: int) -> bool:
		if boxes[left][0] == boxes[right][0]: return left < right
		return boxes[left][0] < boxes[right][0]
	)
	for order_index in range(count):
		var i: int = order[order_index]
		var box_i: Array = boxes[i]
		for next_order in range(order_index + 1, count):
			var j: int = order[next_order]
			var box_j: Array = boxes[j]
			if float(box_j[0]) > float(box_i[2]): break
			x_sweep_pairs += 1
			if (x_sweep_pairs & 4095) == 0 and Time.get_ticks_msec() - started > time_limit_ms:
				graph_limit_reason = "graph_broadphase_wall_time_limit"
				break
			if float(box_j[1]) > float(box_i[3]) or float(box_j[3]) < float(box_i[1]): continue
			candidate_aabb_pair_tests += 1
			candidate_axis_filter_pair_tests += 1
			if not _triangle_pair_may_overlap_axis(candidate_roots[i], candidate_roots[j], projected, projected_centroids[i], projected_centroids[j]):
				candidate_axis_rejected_pairs += 1
				continue
			if int(edge_matrix_result.exact_pair_tests) + candidate_pair_tests >= pair_limit:
				graph_limit_reason = "combined_edge_and_candidate_pair_limit"
				break
			candidate_pair_tests += 1
			if (candidate_pair_tests & 4095) == 0 and Time.get_ticks_msec() - started > time_limit_ms:
				graph_limit_reason = "graph_wall_time_limit"
				break
			var flags: int = _indexed_pair_flags(candidate_edge_indices[i], candidate_edge_indices[j], candidate_roots[i], candidate_roots[j], edge_conflicts, edge_count, projected, projected_centroids[i], projected_centroids[j])
			if flags == -1:
				return {"valid": false, "reason": "nonfinite_or_invalid_geometry_predicate", "pair": [i, j]}
			var shared_edge_key: int = _shared_edge_key(candidate_edges[i], candidate_edges[j])
			if shared_edge_key != -1:
				var edge_row: Dictionary = edge_index[shared_edge_key]
				var direction_i: int = _direction_for_edge(candidate_edges[i], candidate_directions[i], shared_edge_key)
				var direction_j: int = _direction_for_edge(candidate_edges[j], candidate_directions[j], shared_edge_key)
				if bool(edge_row.boundary): flags |= CATEGORY_BOUNDARY_EDGE_DUPLICATE
				elif direction_i == direction_j: flags |= CATEGORY_SAME_INTERIOR_EDGE_DIRECTION
			if flags != 0:
				_set_conflict(i, j, flags, conflicts, categories, stride, count)
				var row_i: Dictionary = candidate_rows[i]
				var row_j: Dictionary = candidate_rows[j]
				row_i.conflict_count = int(row_i.conflict_count) + 1
				row_j.conflict_count = int(row_j.conflict_count) + 1
				for bit in [CATEGORY_CROSSING, CATEGORY_CONTAINMENT, CATEGORY_SAME_INTERIOR_EDGE_DIRECTION, CATEGORY_BOUNDARY_EDGE_DUPLICATE]:
					if (flags & int(bit)) == 0: continue
					var category_name: String = _category_name(int(bit))
					row_i.category_counts[category_name] = int(row_i.category_counts[category_name]) + 1
					row_j.category_counts[category_name] = int(row_j.category_counts[category_name]) + 1
					category_pair_counts[category_name] = int(category_pair_counts[category_name]) + 1
				if (flags & CATEGORY_CROSSING) != 0 and witness_crossing.is_empty(): witness_crossing = [i, j]
				if (flags & CATEGORY_CONTAINMENT) != 0 and witness_containment.is_empty(): witness_containment = [i, j]
				unique_conflicts += 1
				candidate_rows[i] = row_i
				candidate_rows[j] = row_j
			elif witness_compatible_vertex_only.is_empty() and _shared_root_count(candidate_roots[i], candidate_roots[j]) == 1:
				witness_compatible_vertex_only = [i, j]
			if shared_edge_key != -1 and witness_legal_shared_edge.is_empty():
				var ci: int = categories[i * count + j]
				if (ci & CATEGORY_GEOMETRIC_MASK) == 0 and (ci & (CATEGORY_SAME_INTERIOR_EDGE_DIRECTION | CATEGORY_BOUNDARY_EDGE_DUPLICATE)) == 0:
					witness_legal_shared_edge = [i, j]
		if not graph_limit_reason.is_empty(): break
	if not graph_limit_reason.is_empty():
		return {"valid": false, "reason": graph_limit_reason, "candidate_count": count, "theoretical_pair_count": theoretical_pairs, "edge_x_sweep_pair_count": edge_matrix_result.sweep_pair_count, "edge_exact_pair_tests": edge_matrix_result.exact_pair_tests, "x_sweep_pair_count": x_sweep_pairs, "candidate_aabb_pair_tests": candidate_aabb_pair_tests, "candidate_axis_filter_pair_tests": candidate_axis_filter_pair_tests, "candidate_axis_rejected_pairs": candidate_axis_rejected_pairs, "candidate_exact_pair_tests": candidate_pair_tests, "exact_pair_tests": int(edge_matrix_result.exact_pair_tests) + candidate_pair_tests, "pair_limit": pair_limit, "elapsed_ms": Time.get_ticks_msec() - started}
	for edge_row in edge_rows:
		if bool(edge_row.boundary):
			var expected: int = int(edge_row.required_direction)
			if expected == 0: return {"valid": false, "reason": "boundary_edge_required_direction_missing", "edge": edge_row.key}
			var required_side: Array = edge_row.positive if expected > 0 else edge_row.negative
			var wrong_side: Array = edge_row.negative if expected > 0 else edge_row.positive
			if required_side.is_empty() or not wrong_side.is_empty():
				return {"valid": false, "reason": "boundary_candidates_disagree_with_frozen_orientation", "edge": edge_row.key, "expected_direction": expected, "required_side_count": required_side.size(), "wrong_side_count": wrong_side.size()}
		for candidate_index in edge_row.positive:
			for other_index in edge_row.negative:
				incidence_pair_checks += 1
				if (incidence_pair_checks & 4095) == 0 and Time.get_ticks_msec() - started > time_limit_ms:
					return {"valid": false, "reason": "graph_incidence_audit_wall_time_limit", "elapsed_ms": Time.get_ticks_msec() - started, "limit_ms": time_limit_ms, "incidence_pair_checks": incidence_pair_checks}
				if witness_legal_shared_edge.is_empty() and not _has_geometric_conflict_in_matrix(candidate_index, other_index, categories, count):
					witness_legal_shared_edge = [candidate_index, other_index]
				if bool(edge_row.boundary) and not _has_conflict_category(candidate_index, other_index, CATEGORY_BOUNDARY_EDGE_DUPLICATE, categories, count):
					return {"valid": false, "reason": "boundary_edge_duplicate_not_conflicted", "edge": edge_row.key, "pair": [candidate_index, other_index]}
			if bool(edge_row.boundary):
				var same_side: Array = edge_row.positive if int(edge_row.required_direction) > 0 else edge_row.negative
				for left in range(same_side.size()):
					for right in range(left + 1, same_side.size()):
						incidence_pair_checks += 1
						if (incidence_pair_checks & 4095) == 0 and Time.get_ticks_msec() - started > time_limit_ms:
							return {"valid": false, "reason": "graph_incidence_audit_wall_time_limit", "elapsed_ms": Time.get_ticks_msec() - started, "limit_ms": time_limit_ms, "incidence_pair_checks": incidence_pair_checks}
						if not _has_conflict_category(int(same_side[left]), int(same_side[right]), CATEGORY_BOUNDARY_EDGE_DUPLICATE, categories, count):
							return {"valid": false, "reason": "boundary_same_side_pair_not_conflicted", "edge": edge_row.key}
		if not bool(edge_row.boundary):
			var positive: Array = edge_row.positive
			for left in range(positive.size()):
				for right in range(left + 1, positive.size()):
					incidence_pair_checks += 1
					if (incidence_pair_checks & 4095) == 0 and Time.get_ticks_msec() - started > time_limit_ms:
						return {"valid": false, "reason": "graph_incidence_audit_wall_time_limit", "elapsed_ms": Time.get_ticks_msec() - started, "limit_ms": time_limit_ms, "incidence_pair_checks": incidence_pair_checks}
					if not _has_conflict_category(int(positive[left]), int(positive[right]), CATEGORY_SAME_INTERIOR_EDGE_DIRECTION, categories, count):
						return {"valid": false, "reason": "same_direction_edge_pair_not_conflicted", "edge": edge_row.key}
			var negative: Array = edge_row.negative
			for left in range(negative.size()):
				for right in range(left + 1, negative.size()):
					incidence_pair_checks += 1
					if (incidence_pair_checks & 4095) == 0 and Time.get_ticks_msec() - started > time_limit_ms:
						return {"valid": false, "reason": "graph_incidence_audit_wall_time_limit", "elapsed_ms": Time.get_ticks_msec() - started, "limit_ms": time_limit_ms, "incidence_pair_checks": incidence_pair_checks}
					if not _has_conflict_category(int(negative[left]), int(negative[right]), CATEGORY_SAME_INTERIOR_EDGE_DIRECTION, categories, count):
						return {"valid": false, "reason": "same_direction_edge_pair_not_conflicted", "edge": edge_row.key}
	for candidate_index in range(count):
		var row: Dictionary = candidate_rows[candidate_index]
		var row_start: int = candidate_index * stride
		var row_bytes: PackedByteArray = conflicts.slice(row_start, row_start + stride)
		row["conflict_row_sha256"] = _sha256(row_bytes)
		candidate_rows[candidate_index] = row
	if witness_crossing.is_empty() or witness_legal_shared_edge.is_empty() or witness_compatible_vertex_only.is_empty():
		return {"valid": false, "reason": "conflict_graph_witness_missing", "crossing": witness_crossing, "legal_shared_edge": witness_legal_shared_edge, "compatible_vertex_only": witness_compatible_vertex_only}
	var audit: Dictionary = audit_graph(candidate_rows, edge_rows, root_index, conflicts, categories, stride, count, candidate_roots, projected, witness_crossing, witness_legal_shared_edge, witness_compatible_vertex_only, time_limit_ms)
	if not bool(audit.get("valid", false)): return {"valid": false, "reason": "conflict_graph_audit_failed", "detail": audit}
	var metadata: Dictionary = {
		"schema": INDEX_SCHEMA,
		"domain_sha256": loaded.domain_sha256,
		"domain_identity_sha256": loaded.identity_sha256,
		"bx_source_sha": String(loaded.get("bx_source_sha", "")),
		"bx_campaign_sha256": String(loaded.get("bx_campaign_sha256", "")),
		"bx_solver_sha256": String(loaded.get("bx_solver_sha256", "")),
		"candidate_count": count,
		"root_count": ROOT_COUNT,
		"target_face_count": TARGET_FACE_COUNT,
		"boundary_edge_count": BOUNDARY_EDGE_COUNT,
		"bit_order": "candidate_j_is_bit_(j_mod_8)_in_byte_(j_div_8); rows_are_candidate_i",
		"category_matrix_layout": "row_major_u8_category_flags; symmetric; zero_diagonal",
		"category_bits": {"edge_crossing": CATEGORY_CROSSING, "containment": CATEGORY_CONTAINMENT, "same_interior_edge_direction": CATEGORY_SAME_INTERIOR_EDGE_DIRECTION, "boundary_duplicate": CATEGORY_BOUNDARY_EDGE_DUPLICATE},
		"projection_broadphase_rule": "closed AABB followed by conservative triangle SAT; candidate pair omitted only on strictly separated expanded projection intervals; SAT uses binary64 roundoff enclosure",
		"conflict_row_hash_algorithm": "SHA-256 over each packed candidate-conflict bitset row",
		"root_requirements": _root_requirement_rows(edge_rows, root_index),
		"theoretical_pair_count": theoretical_pairs,
		"x_sweep_pair_count": x_sweep_pairs,
		"candidate_aabb_pair_tests": candidate_aabb_pair_tests,
		"candidate_axis_filter_pair_tests": candidate_axis_filter_pair_tests,
		"candidate_axis_rejected_pairs": candidate_axis_rejected_pairs,
		"edge_exact_pair_tests": edge_matrix_result.exact_pair_tests,
		"candidate_exact_pair_tests": candidate_pair_tests,
		"exact_pair_tests": int(edge_matrix_result.exact_pair_tests) + candidate_pair_tests,
		"unique_conflict_pairs": unique_conflicts,
		"category_pair_counts": category_pair_counts,
		"candidate_rows": candidate_rows,
		"edge_rows": edge_rows,
		"root_candidate_rows": root_index,
		"witnesses": {"crossing": witness_crossing, "legal_shared_edge": witness_legal_shared_edge, "compatible_vertex_only": witness_compatible_vertex_only, "containment": witness_containment},
		"audit": audit
	}
	return {"valid": true, "metadata": metadata, "conflicts": conflicts, "categories": categories, "candidate_count": count, "stride": stride, "candidate_edges": candidate_edges, "candidate_directions": candidate_directions, "candidate_roots": candidate_roots, "edge_rows": edge_rows, "root_index": root_index, "build_stats": {"candidate_count": count, "theoretical_pair_count": theoretical_pairs, "edge_x_sweep_pair_count": edge_matrix_result.sweep_pair_count, "edge_exact_pair_tests": edge_matrix_result.exact_pair_tests, "x_sweep_pair_count": x_sweep_pairs, "candidate_aabb_pair_tests": candidate_aabb_pair_tests, "candidate_axis_filter_pair_tests": candidate_axis_filter_pair_tests, "candidate_axis_rejected_pairs": candidate_axis_rejected_pairs, "candidate_exact_pair_tests": candidate_pair_tests, "exact_pair_tests": int(edge_matrix_result.exact_pair_tests) + candidate_pair_tests, "incidence_pair_checks": incidence_pair_checks, "unique_conflict_pairs": unique_conflicts, "elapsed_ms": Time.get_ticks_msec() - started, "estimated_peak_bytes": estimate}}

func audit_graph(candidate_rows: Array, edge_rows: Array, root_index: Array, conflicts: PackedByteArray, categories: PackedByteArray, stride: int, count: int, candidate_roots: Array, projected: Array, crossing_witness: Array, legal_edge_witness: Array, compatible_witness: Array, time_limit_ms: int) -> Dictionary:
	if count != CANDIDATE_COUNT or stride != (count + 7) >> 3 or conflicts.size() != count * stride or categories.size() != count * count:
		return {"valid": false, "reason": "matrix_shape_mismatch"}
	var audit_started: int = Time.get_ticks_msec()
	var conflict_pairs: int = 0
	var category_counts: Dictionary = {"edge_crossing": 0, "containment": 0, "same_interior_edge_direction": 0, "boundary_duplicate": 0}
	var per_candidate_counts: PackedInt32Array = PackedInt32Array()
	per_candidate_counts.resize(count)
	var per_candidate_categories: PackedInt32Array = PackedInt32Array()
	per_candidate_categories.resize(count * 4)
	for i in range(count):
		if (i & 63) == 0 and Time.get_ticks_msec() - audit_started > time_limit_ms:
			return {"valid": false, "reason": "conflict_graph_audit_wall_time_limit", "elapsed_ms": Time.get_ticks_msec() - audit_started, "limit_ms": time_limit_ms}
		if categories[i * count + i] != 0 or _bit_is_set(conflicts, i * stride, i):
			return {"valid": false, "reason": "self_conflict", "candidate": i}
		for j in range(i + 1, count):
			var flags: int = categories[i * count + j]
			var reverse_flags: int = categories[j * count + i]
			if flags != reverse_flags:
				return {"valid": false, "reason": "category_matrix_asymmetric", "pair": [i, j], "forward": flags, "reverse": reverse_flags}
			var forward: bool = _bit_is_set(conflicts, i * stride, j)
			var reverse: bool = _bit_is_set(conflicts, j * stride, i)
			if forward != reverse or forward != (flags != 0):
				return {"valid": false, "reason": "conflict_bitset_category_disagreement", "pair": [i, j], "forward": forward, "reverse": reverse, "flags": flags}
			if forward:
				conflict_pairs += 1
				per_candidate_counts[i] += 1
				per_candidate_counts[j] += 1
			for bit in [CATEGORY_CROSSING, CATEGORY_CONTAINMENT, CATEGORY_SAME_INTERIOR_EDGE_DIRECTION, CATEGORY_BOUNDARY_EDGE_DUPLICATE]:
				if (flags & int(bit)) != 0:
					var name: String = _category_name(int(bit))
					category_counts[name] = int(category_counts[name]) + 1
					var category_index: int = _category_index(int(bit))
					per_candidate_categories[i * 4 + category_index] += 1
					per_candidate_categories[j * 4 + category_index] += 1
	for candidate_index in range(count):
		var counted: int = int(per_candidate_counts[candidate_index])
		var row: Dictionary = candidate_rows[candidate_index]
		if counted != int(row.get("conflict_count", -1)):
			return {"valid": false, "reason": "candidate_conflict_count_mismatch", "candidate_index": candidate_index, "observed": counted, "recorded": candidate_rows[candidate_index].get("conflict_count", -1)}
		var row_categories: Dictionary = row.get("category_counts", {})
		for category_index in range(4):
			var category_bit: int = [CATEGORY_CROSSING, CATEGORY_CONTAINMENT, CATEGORY_SAME_INTERIOR_EDGE_DIRECTION, CATEGORY_BOUNDARY_EDGE_DUPLICATE][category_index]
			var category_name: String = _category_name(category_bit)
			if int(row_categories.get(category_name, -1)) != int(per_candidate_categories[candidate_index * 4 + category_index]):
				return {"valid": false, "reason": "candidate_conflict_category_count_mismatch", "candidate_index": candidate_index, "category": category_name}
		var start: int = candidate_index * stride
		var conflict_row: PackedByteArray = conflicts.slice(start, start + stride)
		if _sha256(conflict_row) != String(row.get("conflict_row_sha256", "")):
			return {"valid": false, "reason": "candidate_conflict_row_hash_mismatch", "candidate_index": candidate_index}
	for witness in [crossing_witness, legal_edge_witness, compatible_witness]:
		if witness.size() != 2: return {"valid": false, "reason": "witness_arity_invalid"}
	if not _has_conflict_category(int(crossing_witness[0]), int(crossing_witness[1]), CATEGORY_CROSSING, categories, count):
		return {"valid": false, "reason": "crossing_witness_not_in_graph"}
	if (_geometry_conflict_flags(candidate_roots[int(crossing_witness[0])], candidate_roots[int(crossing_witness[1])], projected) & CATEGORY_CROSSING) == 0:
		return {"valid": false, "reason": "crossing_witness_not_reproduced_by_exact_oracle"}
	if _geometry_conflict_flags(candidate_roots[int(legal_edge_witness[0])], candidate_roots[int(legal_edge_witness[1])], projected) != 0:
		return {"valid": false, "reason": "legal_shared_edge_witness_rejected_by_oracle"}
	if _bit_is_set(conflicts, int(legal_edge_witness[0]) * stride, int(legal_edge_witness[1])):
		return {"valid": false, "reason": "legal_shared_edge_witness_in_conflict_mask"}
	if _geometry_conflict_flags(candidate_roots[int(compatible_witness[0])], candidate_roots[int(compatible_witness[1])], projected) != 0:
		return {"valid": false, "reason": "compatible_vertex_witness_rejected_by_oracle"}
	if _bit_is_set(conflicts, int(compatible_witness[0]) * stride, int(compatible_witness[1])):
		return {"valid": false, "reason": "compatible_vertex_witness_in_conflict_mask"}
	return {"valid": true, "symmetric": true, "self_conflicts": 0, "unique_conflict_pairs": conflict_pairs, "category_pair_counts": category_counts, "witnesses": {"crossing": crossing_witness, "legal_shared_edge": legal_edge_witness, "compatible_vertex_only": compatible_witness}}

func write_graph_artifacts(graph: Dictionary, artifact_directory: String) -> Dictionary:
	if not bool(graph.get("valid", false)) or artifact_directory.is_empty():
		return {"valid": false, "reason": "graph_or_artifact_directory_invalid"}
	var index_path: String = artifact_directory.path_join("bx_conflict_index.json")
	var matrix_path: String = artifact_directory.path_join("bx_conflicts.bin")
	var receipt_path: String = artifact_directory.path_join("bx_conflict_index_receipt.json")
	for path in [index_path, matrix_path, receipt_path]:
		if FileAccess.file_exists(path): return {"valid": false, "reason": "artifact_overwrite_refused", "path": path}
	var index_bytes: PackedByteArray = JSON.stringify(graph.metadata).to_utf8_buffer()
	var matrix_bytes: PackedByteArray = graph.conflicts
	matrix_bytes.append_array(graph.categories)
	var index_write: Error = _write_new_file(index_path, index_bytes)
	if index_write != OK: return {"valid": false, "reason": "index_artifact_write_failed", "error": error_string(index_write)}
	var matrix_write: Error = _write_new_file(matrix_path, matrix_bytes)
	if matrix_write != OK: return {"valid": false, "reason": "matrix_artifact_write_failed", "error": error_string(matrix_write)}
	var graph_sha: String = graph_digest(graph)
	var receipt: Dictionary = {"schema": RECEIPT_SCHEMA, "domain_sha256": graph.metadata.domain_sha256, "index_sha256": _sha256(index_bytes), "matrix_sha256": _sha256(matrix_bytes), "candidate_matrix_bytes": graph.conflicts.size(), "category_matrix_bytes": graph.categories.size(), "graph_sha256": graph_sha, "candidate_count": graph.candidate_count, "stride": graph.stride}
	var receipt_bytes: PackedByteArray = JSON.stringify(receipt).to_utf8_buffer()
	var receipt_write: Error = _write_new_file(receipt_path, receipt_bytes)
	if receipt_write != OK: return {"valid": false, "reason": "receipt_artifact_write_failed", "error": error_string(receipt_write)}
	return {"valid": true, "index_path": index_path, "matrix_path": matrix_path, "receipt_path": receipt_path, "index_sha256": _sha256(index_bytes), "matrix_sha256": _sha256(matrix_bytes), "graph_sha256": graph_sha, "matrix_bytes": matrix_bytes.size()}

func reload_and_validate_graph(loaded: Dictionary, index_path: String, matrix_path: String, receipt_path: String, expected_graph_sha256: String = "") -> Dictionary:
	for path in [index_path, matrix_path, receipt_path]:
		if not FileAccess.file_exists(path): return {"valid": false, "reason": "serialized_graph_artifact_missing", "path": path}
	var index_bytes: PackedByteArray = FileAccess.get_file_as_bytes(index_path)
	var matrix_bytes: PackedByteArray = FileAccess.get_file_as_bytes(matrix_path)
	var receipt_parser: JSON = JSON.new()
	var receipt_error: Error = receipt_parser.parse(FileAccess.get_file_as_string(receipt_path))
	if receipt_error != OK or not receipt_parser.data is Dictionary: return {"valid": false, "reason": "graph_receipt_invalid"}
	var receipt: Dictionary = receipt_parser.data
	if String(receipt.get("schema", "")) != RECEIPT_SCHEMA or String(receipt.get("domain_sha256", "")) != loaded.domain_sha256:
		return {"valid": false, "reason": "graph_receipt_identity_mismatch"}
	if _sha256(index_bytes) != String(receipt.get("index_sha256", "")) or _sha256(matrix_bytes) != String(receipt.get("matrix_sha256", "")):
		return {"valid": false, "reason": "graph_artifact_hash_mismatch"}
	var graph_context: HashingContext = HashingContext.new()
	graph_context.start(HashingContext.HASH_SHA256)
	graph_context.update(index_bytes)
	graph_context.update(matrix_bytes)
	var graph_sha: String = graph_context.finish().hex_encode().to_lower()
	if graph_sha != String(receipt.get("graph_sha256", "")):
		return {"valid": false, "reason": "graph_identity_digest_mismatch"}
	if not expected_graph_sha256.is_empty() and graph_sha != expected_graph_sha256:
		return {"valid": false, "reason": "graph_sha256_does_not_match_launch_pin", "expected": expected_graph_sha256, "observed": graph_sha}
	var parser: JSON = JSON.new()
	var parse_error: Error = parser.parse(index_bytes.get_string_from_utf8())
	if parse_error != OK or not parser.data is Dictionary: return {"valid": false, "reason": "graph_index_json_invalid"}
	var metadata: Dictionary = parser.data
	if String(metadata.get("schema", "")) != INDEX_SCHEMA or String(metadata.get("domain_sha256", "")) != loaded.domain_sha256 or int(metadata.get("candidate_count", -1)) != CANDIDATE_COUNT or String(metadata.get("bx_source_sha", "")) != String(loaded.get("bx_source_sha", "")) or String(metadata.get("bx_campaign_sha256", "")) != String(loaded.get("bx_campaign_sha256", "")) or String(metadata.get("bx_solver_sha256", "")) != String(loaded.get("bx_solver_sha256", "")):
		return {"valid": false, "reason": "graph_index_domain_binding_invalid"}
	var domain_index_check: Dictionary = _metadata_matches_domain(loaded, metadata)
	if not bool(domain_index_check.get("valid", false)):
		return {"valid": false, "reason": "serialized_index_disagrees_with_pinned_domain", "detail": domain_index_check}
	var count: int = CANDIDATE_COUNT
	var stride: int = (count + 7) >> 3
	var expected_primary_bytes: int = count * stride
	var expected_category_bytes: int = count * count
	if matrix_bytes.size() != expected_primary_bytes + expected_category_bytes or int(receipt.get("candidate_matrix_bytes", -1)) != expected_primary_bytes or int(receipt.get("category_matrix_bytes", -1)) != expected_category_bytes:
		return {"valid": false, "reason": "serialized_matrix_shape_invalid", "observed_bytes": matrix_bytes.size()}
	var primary: PackedByteArray = matrix_bytes.slice(0, expected_primary_bytes)
	var categories: PackedByteArray = matrix_bytes.slice(expected_primary_bytes, matrix_bytes.size())
	var serialized_candidate_rows: Array = metadata.get("candidate_rows", [])
	if serialized_candidate_rows.size() != count: return {"valid": false, "reason": "serialized_candidate_conflict_rows_invalid"}
	for candidate_index in range(count):
		var row_start: int = candidate_index * stride
		var conflict_row: PackedByteArray = primary.slice(row_start, row_start + stride)
		if _sha256(conflict_row) != String(serialized_candidate_rows[candidate_index].get("conflict_row_sha256", "")):
			return {"valid": false, "reason": "serialized_candidate_conflict_row_hash_mismatch", "candidate_index": candidate_index}
	var tampered: PackedByteArray = matrix_bytes.duplicate()
	if tampered.is_empty(): return {"valid": false, "reason": "serialized_matrix_unexpectedly_empty"}
	tampered[0] = int(tampered[0]) ^ 1
	var tamper_context: HashingContext = HashingContext.new()
	tamper_context.start(HashingContext.HASH_SHA256)
	tamper_context.update(index_bytes)
	tamper_context.update(tampered)
	var tamper_sha: String = tamper_context.finish().hex_encode().to_lower()
	if tamper_sha == graph_sha: return {"valid": false, "reason": "matrix_tamper_not_detected"}
	return {"valid": true, "metadata": metadata, "conflicts": primary, "categories": categories, "candidate_count": count, "stride": stride, "graph_sha256": graph_sha, "tamper_negative": {"status": "REJECTED_DIGEST_MISMATCH", "tampered_sha256": tamper_sha}, "candidate_edges": _candidate_edge_rows(loaded.candidates), "candidate_directions": _candidate_direction_rows(loaded.candidates), "candidate_roots": _candidate_root_rows(loaded.candidates), "edge_rows": _metadata_edges(metadata), "root_index": _metadata_roots(metadata)}

func graph_digest(graph: Dictionary) -> String:
	var index_bytes: PackedByteArray = JSON.stringify(graph.metadata).to_utf8_buffer()
	var context: HashingContext = HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(index_bytes)
	context.update(graph.conflicts)
	context.update(graph.categories)
	return context.finish().hex_encode().to_lower()

func _metadata_matches_domain(loaded: Dictionary, metadata: Dictionary) -> Dictionary:
	var candidates: Array = loaded.candidates
	var rows: Array = metadata.get("candidate_rows", [])
	if rows.size() != candidates.size(): return {"valid": false, "reason": "candidate_row_count_mismatch"}
	var expected_edges: Dictionary = {}
	var expected_roots: Array[Array] = []
	expected_roots.resize(ROOT_COUNT)
	for root in range(ROOT_COUNT): expected_roots[root] = []
	for candidate_index in range(candidates.size()):
		var candidate: Dictionary = candidates[candidate_index]
		var row: Dictionary = rows[candidate_index]
		if String(row.get("id", "")) != String(candidate.id): return {"valid": false, "reason": "candidate_id_mismatch", "candidate_index": candidate_index}
		if not _deep_numeric_equal(row.get("roots", []), candidate.root_indices) or not _deep_numeric_equal(row.get("root_ids", []), candidate.root_ids) or not _deep_numeric_equal(row.get("edges", []), candidate.edge_keys) or not _deep_numeric_equal(row.get("directions", []), candidate.edge_directions) or not _deep_numeric_equal(row.get("owner_cell", []), candidate.owner_cell) or float(row.get("cross_squared", -1.0)) != float(candidate.cross_squared):
			return {"valid": false, "reason": "candidate_metadata_mismatch", "candidate_index": candidate_index}
		for root_variant in candidate.root_indices: expected_roots[int(root_variant)].append(candidate_index)
		for slot in range(3):
			var key: int = int(candidate.edge_keys[slot])
			if not expected_edges.has(key):
				var u: int = int(candidate.root_indices[slot])
				var v: int = int(candidate.root_indices[(slot + 1) % 3])
				expected_edges[key] = {"key": key, "a": mini(u, v), "b": maxi(u, v), "boundary": loaded.boundary_directions.has(key), "required_direction": int(loaded.boundary_directions.get(key, 0)), "positive": [], "negative": []}
			var edge: Dictionary = expected_edges[key]
			if int(candidate.edge_directions[slot]) > 0: edge.positive.append(candidate_index)
			else: edge.negative.append(candidate_index)
			expected_edges[key] = edge
	var edge_rows: Array = metadata.get("edge_rows", [])
	var keys: Array[int] = []
	for raw_key in expected_edges.keys(): keys.append(int(raw_key))
	keys.sort()
	if edge_rows.size() != keys.size(): return {"valid": false, "reason": "edge_row_count_mismatch"}
	for index in range(keys.size()):
		var expected: Dictionary = expected_edges[keys[index]]
		expected["maximum_incidence"] = 1 if bool(expected.boundary) else 2
		expected["required_final_incidence"] = 1 if bool(expected.boundary) else 2
		expected["orientation_rule"] = "frozen_boundary_direction" if bool(expected.boundary) else "one_positive_and_one_negative"
		var actual: Dictionary = edge_rows[index]
		for key_name in ["key", "a", "b", "boundary", "required_direction", "positive", "negative", "maximum_incidence", "required_final_incidence", "orientation_rule"]:
			if not _deep_numeric_equal(actual.get(key_name), expected.get(key_name)):
				return {"valid": false, "reason": "edge_index_mismatch", "edge_index": index, "field": key_name}
	var root_rows: Array = metadata.get("root_candidate_rows", [])
	if root_rows.size() != ROOT_COUNT: return {"valid": false, "reason": "root_row_count_mismatch"}
	for root in range(ROOT_COUNT):
		if not _deep_numeric_equal(root_rows[root], expected_roots[root]): return {"valid": false, "reason": "root_candidate_index_mismatch", "root": root}
	var root_requirements: Array = metadata.get("root_requirements", [])
	if root_requirements.size() != ROOT_COUNT: return {"valid": false, "reason": "root_requirement_row_count_mismatch"}
	var boundary_roots: PackedByteArray = PackedByteArray(); boundary_roots.resize(ROOT_COUNT)
	for raw_key in loaded.boundary_directions.keys():
		var key: int = int(raw_key)
		var low_root: int = floori(float(key) / float(ROOT_COUNT))
		boundary_roots[low_root] = 1
		boundary_roots[key % ROOT_COUNT] = 1
	for root in range(ROOT_COUNT):
		var requirement: Dictionary = root_requirements[root]
		var expected_class: String = "boundary" if boundary_roots[root] != 0 else "interior"
		if int(requirement.get("root_index", -1)) != root or not bool(requirement.get("required", false)) or String(requirement.get("classification", "")) != expected_class or not _deep_numeric_equal(requirement.get("candidate_indices", []), expected_roots[root]):
			return {"valid": false, "reason": "root_requirement_index_mismatch", "root": root}
	return {"valid": true, "candidate_rows": rows.size(), "edge_rows": edge_rows.size(), "root_rows": root_rows.size(), "root_requirements": root_requirements.size()}

func _deep_numeric_equal(left: Variant, right: Variant) -> bool:
	if left is Array and right is Array:
		if left.size() != right.size(): return false
		for index in range(left.size()):
			if not _deep_numeric_equal(left[index], right[index]): return false
		return true
	if typeof(left) in [TYPE_INT, TYPE_FLOAT] and typeof(right) in [TYPE_INT, TYPE_FLOAT]:
		var left_number: float = float(left)
		var right_number: float = float(right)
		return is_finite(left_number) and is_finite(right_number) and left_number == right_number
	if typeof(left) == TYPE_DICTIONARY and typeof(right) == TYPE_DICTIONARY:
		if left.size() != right.size(): return false
		for key in left:
			if not right.has(key) or not _deep_numeric_equal(left[key], right[key]): return false
		return true
	return typeof(left) == typeof(right) and left == right

func solve(graph: Dictionary, limits: Dictionary) -> Dictionary:
	if not bool(graph.get("valid", false)):
		return {"valid": false, "status": "BLOCKED", "reason": "unvalidated_graph_supplied"}
	var nodes_limit: int = int(limits.get("search_nodes", 0))
	var depth_limit: int = int(limits.get("recursion_depth", 0))
	var wall_limit: int = int(limits.get("wall_milliseconds", 0))
	var state_memory_limit: int = int(limits.get("estimated_state_bytes", 0))
	if nodes_limit <= 0 or depth_limit <= 0 or wall_limit <= 0 or state_memory_limit <= 0:
		return {"valid": false, "status": "BLOCKED", "reason": "solver_limits_invalid"}
	if int(graph.candidate_count) != CANDIDATE_COUNT or int(graph.metadata.get("target_face_count", -1)) != TARGET_FACE_COUNT:
		return {"valid": false, "status": "BLOCKED", "reason": "solver_graph_shape_invalid"}
	# This deterministic estimate accounts for both graph matrices, conservative
	# metadata/domain allowances, a maximum-depth stack of copied mutable state,
	# and fixed allocator headroom. The runner separately monitors process bytes.
	var state_bytes_per_level: int = int(graph.stride) + CANDIDATE_COUNT + int(graph.edge_rows.size()) * 8 + ROOT_COUNT + 4096
	var metadata_allowance: int = CANDIDATE_COUNT * 1024 + int(graph.edge_rows.size()) * 512 + int(ROOT_COUNT * CANDIDATE_COUNT / 8) + 8 * 1024 * 1024
	var estimated_state: int = int(graph.conflicts.size()) + int(graph.categories.size()) + metadata_allowance + state_bytes_per_level * (depth_limit + 1) + 64 * 1024 * 1024
	if estimated_state > state_memory_limit:
		return {"valid": false, "status": "BLOCKED", "reason": "solver_memory_bound_exceeded", "estimated_state_bytes": estimated_state, "limit_bytes": state_memory_limit}
	var initial: Dictionary = _new_state(graph)
	var context: Dictionary = {"nodes": 0, "branches": 0, "forced": 0, "conflicts": 0, "started_msec": Time.get_ticks_msec(), "limit_reason": "", "solution": PackedInt32Array(), "limits": limits.duplicate(true), "graph": graph, "max_depth": 0}
	var terminal: Dictionary = _search(initial, 0, context)
	var status: String = "INCONCLUSIVE_LIMIT"
	if bool(terminal.get("solution", false)):
		status = "SAT"
	elif String(context.limit_reason).is_empty() and bool(terminal.get("complete", false)):
		status = "INFEASIBLE_COMPLETE"
	elif not String(context.limit_reason).is_empty():
		status = "INCONCLUSIVE_LIMIT"
	else:
		status = "INCONCLUSIVE_INTERNAL"
	return {"valid": status in ["SAT", "INFEASIBLE_COMPLETE", "INCONCLUSIVE_LIMIT"], "status": status, "search_complete": status == "SAT" or status == "INFEASIBLE_COMPLETE", "search_exhaustive": status == "INFEASIBLE_COMPLETE", "stop_reason": context.limit_reason, "nodes": context.nodes, "branches": context.branches, "forced_selections": context.forced, "conflict_prunes": context.conflicts, "elapsed_ms": Time.get_ticks_msec() - int(context.started_msec), "max_depth": context.max_depth, "memory_estimate_bytes": estimated_state, "limits": limits.duplicate(true), "selected_candidate_indices": context.solution, "selected_triangles": _solution_rows(graph, context.solution) if status == "SAT" else []}

func _new_state(graph: Dictionary) -> Dictionary:
	var available: PackedByteArray = PackedByteArray()
	available.resize(graph.stride)
	for candidate in range(CANDIDATE_COUNT):
		var byte_index: int = candidate >> 3
		available[byte_index] = int(available[byte_index]) | (1 << (candidate & 7))
	var selected: PackedByteArray = PackedByteArray(); selected.resize(CANDIDATE_COUNT)
	var edge_positive: PackedInt32Array = PackedInt32Array(); edge_positive.resize(graph.edge_rows.size())
	var edge_negative: PackedInt32Array = PackedInt32Array(); edge_negative.resize(graph.edge_rows.size())
	var root_used: PackedByteArray = PackedByteArray(); root_used.resize(ROOT_COUNT)
	return {"available": available, "selected": selected, "edge_positive": edge_positive, "edge_negative": edge_negative, "root_used": root_used, "selected_count": 0, "available_count": CANDIDATE_COUNT, "unique_edge_count": 0, "graph": graph}

func _search(state: Dictionary, depth: int, context: Dictionary) -> Dictionary:
	var limits: Dictionary = context.limits
	if int(context.nodes) >= int(limits.search_nodes): context.limit_reason = "search_node_limit"; return {"complete": false}
	if depth > int(limits.recursion_depth): context.limit_reason = "recursion_depth_limit"; return {"complete": false}
	context.nodes = int(context.nodes) + 1
	context.max_depth = maxi(int(context.max_depth), depth)
	if (int(context.nodes) & 63) == 0 and Time.get_ticks_msec() - int(context.started_msec) > int(limits.wall_milliseconds): context.limit_reason = "search_wall_time_limit"; return {"complete": false}
	var propagated: Dictionary = _propagate(state, context)
	if not bool(propagated.get("valid", false)):
		context.conflicts = int(context.conflicts) + 1
		return {"complete": true}
	var current: Dictionary = propagated.state
	var choice: Dictionary = _choose_constraint(current)
	if String(choice.get("kind", "")) == "terminal":
		if not _validate_solution(current):
			context.conflicts = int(context.conflicts) + 1
			return {"complete": true}
		var selected: PackedInt32Array = PackedInt32Array()
		var flags: PackedByteArray = current.selected
		for candidate in range(CANDIDATE_COUNT):
			if flags[candidate] != 0: selected.append(candidate)
		context.solution = selected
		return {"complete": true, "solution": true}
	var choices: Array = choice.get("candidates", [])
	if choices.is_empty():
		context.conflicts = int(context.conflicts) + 1
		return {"complete": true}
	for candidate_variant in choices:
		if not String(context.limit_reason).is_empty(): return {"complete": false}
		var candidate: int = int(candidate_variant)
		if not _bit_is_set(current.available, 0, candidate): continue
		var child: Dictionary = _clone_state(current)
		if not _select_candidate(child, candidate, context):
			context.conflicts = int(context.conflicts) + 1
			continue
		context.branches = int(context.branches) + 1
		var result: Dictionary = _search(child, depth + 1, context)
		if bool(result.get("solution", false)): return result
		if not bool(result.get("complete", false)): return result
	return {"complete": true}

func _propagate(state: Dictionary, context: Dictionary) -> Dictionary:
	var changed: bool = true
	while changed:
		changed = false
		if int(state.selected_count) > TARGET_FACE_COUNT or int(state.selected_count) + int(state.available_count) < TARGET_FACE_COUNT:
			return {"valid": false, "reason": "face_count_bound"}
		var remaining_faces: int = TARGET_FACE_COUNT - int(state.selected_count)
		# For a triangulated disk, 3F = 2(E - B) + B. With frozen
		# F=110 and B=34, the complete mesh must use E=182 unique edges.
		# Used edges only grow and a remaining face can add at most three, so
		# these bounds are sound for early rejection.
		if int(state.unique_edge_count) > TARGET_UNIQUE_EDGE_COUNT or int(state.unique_edge_count) + remaining_faces * 3 < TARGET_UNIQUE_EDGE_COUNT:
			return {"valid": false, "reason": "euler_unique_edge_bound", "used_edges": state.unique_edge_count, "remaining_faces": remaining_faces}
		var edge_rows: Array = state.graph.edge_rows
		var edge_positive: PackedInt32Array = state.edge_positive
		var edge_negative: PackedInt32Array = state.edge_negative
		for edge_index in range(edge_rows.size()):
			var edge: Dictionary = edge_rows[edge_index]
			var plus_selected: int = int(edge_positive[edge_index])
			var minus_selected: int = int(edge_negative[edge_index])
			if bool(edge.boundary):
				var total_selected: int = plus_selected + minus_selected
				if total_selected > 1 or (total_selected == 1 and (plus_selected if int(edge.required_direction) > 0 else minus_selected) != 1):
					return {"valid": false, "reason": "boundary_incidence_conflict", "edge": edge.key}
				if total_selected == 1: continue
				var boundary_choices: Array = edge.positive if int(edge.required_direction) > 0 else edge.negative
				var available_boundary: Array[int] = _available_subset(state.available, boundary_choices)
				if available_boundary.is_empty(): return {"valid": false, "reason": "boundary_edge_has_no_available_candidate", "edge": edge.key}
				if available_boundary.size() == 1:
					if not _select_candidate(state, available_boundary[0], context): return {"valid": false, "reason": "forced_boundary_candidate_rejected", "edge": edge.key}
					context.forced = int(context.forced) + 1
					changed = true
					break
			else:
				if plus_selected > 1 or minus_selected > 1 or plus_selected + minus_selected > 2:
					return {"valid": false, "reason": "interior_edge_incidence_conflict", "edge": edge.key}
				if plus_selected + minus_selected == 0: continue
				if plus_selected == 1 and minus_selected == 1: continue
				var plus_available: Array[int] = _available_subset(state.available, edge.positive)
				var minus_available: Array[int] = _available_subset(state.available, edge.negative)
				if plus_selected == 1:
					if minus_available.is_empty(): return {"valid": false, "reason": "interior_edge_opposite_side_missing", "edge": edge.key}
					if minus_available.size() == 1:
						if not _select_candidate(state, minus_available[0], context): return {"valid": false, "reason": "forced_interior_candidate_rejected", "edge": edge.key}
						context.forced = int(context.forced) + 1; changed = true; break
				elif minus_selected == 1:
					if plus_available.is_empty(): return {"valid": false, "reason": "interior_edge_opposite_side_missing", "edge": edge.key}
					if plus_available.size() == 1:
						if not _select_candidate(state, plus_available[0], context): return {"valid": false, "reason": "forced_interior_candidate_rejected", "edge": edge.key}
						context.forced = int(context.forced) + 1; changed = true; break
				else:
					if plus_available.is_empty() or minus_available.is_empty(): return {"valid": false, "reason": "interior_edge_direction_has_no_candidate", "edge": edge.key}
					if plus_available.size() == 1:
						if not _select_candidate(state, plus_available[0], context): return {"valid": false, "reason": "forced_interior_candidate_rejected", "edge": edge.key}
						context.forced = int(context.forced) + 1; changed = true; break
					if minus_available.size() == 1:
						if not _select_candidate(state, minus_available[0], context): return {"valid": false, "reason": "forced_interior_candidate_rejected", "edge": edge.key}
						context.forced = int(context.forced) + 1; changed = true; break
		if changed: continue
		var roots: Array = state.graph.root_index
		for root in range(ROOT_COUNT):
			if int(state.root_used[root]) > 0: continue
			var available_root: Array[int] = _available_subset(state.available, roots[root])
			if available_root.is_empty(): return {"valid": false, "reason": "root_has_no_available_candidate", "root": root}
			if available_root.size() == 1:
				if not _select_candidate(state, available_root[0], context): return {"valid": false, "reason": "forced_root_candidate_rejected", "root": root}
				context.forced = int(context.forced) + 1
				changed = true
				break
	return {"valid": true, "state": state}

func _choose_constraint(state: Dictionary) -> Dictionary:
	var best: Array[int] = []
	var best_kind: String = ""
	var best_edge: int = -1
	var edge_rows: Array = state.graph.edge_rows
	for edge_index in range(edge_rows.size()):
		var edge: Dictionary = edge_rows[edge_index]
		var plus_selected: int = int(state.edge_positive[edge_index])
		var minus_selected: int = int(state.edge_negative[edge_index])
		var choices: Array[int] = []
		if bool(edge.boundary):
			if plus_selected + minus_selected == 1: continue
			choices = _available_subset(state.available, edge.positive if int(edge.required_direction) > 0 else edge.negative)
			if best.is_empty() or choices.size() < best.size(): best = choices; best_kind = "boundary"; best_edge = edge_index
		else:
			if plus_selected + minus_selected == 0: continue
			if plus_selected == 1 and minus_selected == 1: continue
			if plus_selected == 1: choices = _available_subset(state.available, edge.negative)
			elif minus_selected == 1: choices = _available_subset(state.available, edge.positive)
			else:
				var plus: Array[int] = _available_subset(state.available, edge.positive)
				var minus: Array[int] = _available_subset(state.available, edge.negative)
				choices = plus if plus.size() <= minus.size() else minus
			if best.is_empty() or choices.size() < best.size(): best = choices; best_kind = "interior_edge"; best_edge = edge_index
	if best.is_empty():
		for root in range(ROOT_COUNT):
			if int(state.root_used[root]) > 0: continue
			var choices: Array[int] = _available_subset(state.available, state.graph.root_index[root])
			if best.is_empty() or choices.size() < best.size(): best = choices; best_kind = "root"; best_edge = root
	if best.is_empty(): return {"kind": "terminal", "candidates": []}
	return {"kind": best_kind, "constraint_index": best_edge, "candidates": best}

func _select_candidate(state: Dictionary, candidate: int, context: Dictionary) -> bool:
	if candidate < 0 or candidate >= CANDIDATE_COUNT or not _bit_is_set(state.available, 0, candidate): return false
	var graph: Dictionary = state.graph
	var roots: Array = graph.candidate_roots[candidate]
	var edges: Array = graph.candidate_edges[candidate]
	var directions: Array = graph.candidate_directions[candidate]
	# Edge rows are sorted and the dictionary is reconstructed on load; do not
	# rely on hash-map iteration order.
	for slot in range(3):
		var e_index: int = _find_edge_index(graph.edge_rows, int(edges[slot]))
		if e_index < 0: return false
		var edge: Dictionary = graph.edge_rows[e_index]
		var plus_count: int = int(state.edge_positive[e_index])
		var minus_count: int = int(state.edge_negative[e_index])
		var direction: int = int(directions[slot])
		if bool(edge.boundary):
			if plus_count + minus_count > 0 or direction != int(edge.required_direction): return false
		elif direction > 0 and (plus_count > 0 or plus_count + minus_count >= 2): return false
		elif direction < 0 and (minus_count > 0 or plus_count + minus_count >= 2): return false
	var available: PackedByteArray = state.available
	var available_count: int = int(state.available_count)
	_remove_available(available, candidate, available_count)
	available_count -= 1
	var selected_flags: PackedByteArray = state.selected
	selected_flags[candidate] = 1
	var plus_state: PackedInt32Array = state.edge_positive
	var minus_state: PackedInt32Array = state.edge_negative
	for slot in range(3):
		var e_index: int = _find_edge_index(graph.edge_rows, int(edges[slot]))
		if int(state.edge_positive[e_index]) + int(state.edge_negative[e_index]) == 0:
			state.unique_edge_count = int(state.unique_edge_count) + 1
		if int(directions[slot]) > 0: plus_state[e_index] += 1
		else: minus_state[e_index] += 1
	var root_state: PackedByteArray = state.root_used
	for root_variant in roots:
		var root: int = int(root_variant)
		if root_state[root] < 255: root_state[root] += 1
	var conflicts: PackedByteArray = graph.conflicts
	var stride: int = int(graph.stride)
	var row_offset: int = candidate * stride
	for byte_index in range(stride):
		var blocked: int = int(conflicts[row_offset + byte_index])
		if blocked == 0: continue
		var old_bits: int = int(available[byte_index])
		var new_bits: int = old_bits & (255 ^ blocked)
		if new_bits != old_bits:
			available_count -= _popcount[old_bits ^ new_bits]
			available[byte_index] = new_bits
	state.available = available
	state.available_count = available_count
	state.selected = selected_flags
	state.edge_positive = plus_state
	state.edge_negative = minus_state
	state.root_used = root_state
	state.selected_count = int(state.selected_count) + 1
	return true

func _validate_solution(state: Dictionary) -> bool:
	if int(state.selected_count) != TARGET_FACE_COUNT: return false
	for root in range(ROOT_COUNT):
		if int(state.root_used[root]) <= 0: return false
	for edge_index in range(state.graph.edge_rows.size()):
		var edge: Dictionary = state.graph.edge_rows[edge_index]
		var plus: int = int(state.edge_positive[edge_index])
		var minus: int = int(state.edge_negative[edge_index])
		if bool(edge.boundary):
			if plus + minus != 1 or (plus if int(edge.required_direction) > 0 else minus) != 1: return false
		elif plus + minus == 0: continue
		elif plus != 1 or minus != 1: return false
	var used_edge_count: int = 0
	for edge_index in range(state.graph.edge_rows.size()):
		if int(state.edge_positive[edge_index]) + int(state.edge_negative[edge_index]) > 0: used_edge_count += 1
	if used_edge_count != TARGET_UNIQUE_EDGE_COUNT or ROOT_COUNT - used_edge_count + TARGET_FACE_COUNT != 1: return false
	var selected: PackedByteArray = state.selected
	var selected_ids: Array[int] = []
	for index in range(CANDIDATE_COUNT):
		if selected[index] != 0: selected_ids.append(index)
	if selected_ids.size() != TARGET_FACE_COUNT: return false
	return _selected_connected_and_vertex_manifold(selected_ids, state.graph)

func _selected_connected_and_vertex_manifold(selected_ids: Array[int], graph: Dictionary) -> bool:
	var edge_users: Dictionary = {}
	var vertex_triangles: Array[Array] = []
	vertex_triangles.resize(ROOT_COUNT)
	for root in range(ROOT_COUNT): vertex_triangles[root] = []
	for candidate_index in selected_ids:
		for edge_key in graph.candidate_edges[candidate_index]:
			if not edge_users.has(edge_key): edge_users[edge_key] = []
			edge_users[edge_key].append(candidate_index)
		for root in graph.candidate_roots[candidate_index]: vertex_triangles[int(root)].append(candidate_index)
	var neighbors: Dictionary = {}
	for candidate_index in selected_ids: neighbors[candidate_index] = {}
	for edge_key in edge_users:
		var users: Array = edge_users[edge_key]
		if users.size() == 2:
			neighbors[users[0]][users[1]] = true
			neighbors[users[1]][users[0]] = true
		elif users.size() != 1:
			return false
	var reached: Dictionary = {selected_ids[0]: true}
	var queue: Array[int] = [selected_ids[0]]
	var cursor: int = 0
	while cursor < queue.size():
		var current: int = queue[cursor]; cursor += 1
		for next_id in neighbors[current]:
			if reached.has(next_id): continue
			reached[next_id] = true
			queue.append(int(next_id))
	if reached.size() != selected_ids.size(): return false
	for root in range(ROOT_COUNT):
		var incident: Array = vertex_triangles[root]
		if incident.is_empty(): return false
		var graph_at_vertex: Dictionary = {}
		for candidate_index in incident: graph_at_vertex[candidate_index] = {}
		var boundary_degree: int = 0
		var boundary_edges: int = 0
		for edge in graph.edge_rows:
			if int(edge.a) != root and int(edge.b) != root: continue
			var users: Array = edge_users.get(int(edge.key), [])
			if bool(edge.boundary):
				if users.size() != 1: return false
				boundary_edges += 1
			elif users.is_empty():
				continue
			elif users.size() == 2:
				if not incident.has(users[0]) or not incident.has(users[1]): return false
				graph_at_vertex[users[0]][users[1]] = true
				graph_at_vertex[users[1]][users[0]] = true
			else:
				return false
		var on_boundary: bool = boundary_edges > 0
		if on_boundary and boundary_edges != 2: return false
		if not on_boundary and boundary_edges != 0: return false
		var degree_one: int = 0
		for candidate_index in incident:
			var degree: int = graph_at_vertex[candidate_index].size()
			if on_boundary:
				if degree > 2: return false
				if degree == 1: degree_one += 1
			else:
				if degree != 2: return false
		if on_boundary and incident.size() > 1 and degree_one != 2: return false
		var local_reached: Dictionary = {incident[0]: true}
		var local_queue: Array[int] = [incident[0]]
		var local_cursor: int = 0
		while local_cursor < local_queue.size():
			var current_triangle: int = local_queue[local_cursor]; local_cursor += 1
			for next_triangle in graph_at_vertex[current_triangle]:
				if local_reached.has(next_triangle): continue
				local_reached[next_triangle] = true
				local_queue.append(int(next_triangle))
		if local_reached.size() != incident.size(): return false
	return true

func _clone_state(state: Dictionary) -> Dictionary:
	return {"available": state.available.duplicate(), "selected": state.selected.duplicate(), "edge_positive": state.edge_positive.duplicate(), "edge_negative": state.edge_negative.duplicate(), "root_used": state.root_used.duplicate(), "selected_count": int(state.selected_count), "available_count": int(state.available_count), "unique_edge_count": int(state.unique_edge_count), "graph": state.graph}

func _available_subset(available: PackedByteArray, candidates: Array) -> Array[int]:
	var result: Array[int] = []
	for raw in candidates:
		var index: int = int(raw)
		if _bit_is_set(available, 0, index): result.append(index)
	return result

func _remove_available(available: PackedByteArray, candidate: int, _available_count: int) -> void:
	var byte_index: int = candidate >> 3
	available[byte_index] = int(available[byte_index]) & (255 ^ (1 << (candidate & 7)))

func _solution_rows(graph: Dictionary, ids: PackedInt32Array) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for candidate_index in ids:
		var candidate: Dictionary = graph.metadata.candidate_rows[candidate_index]
		rows.append({"candidate_id": candidate.id, "root_indices": candidate.roots, "root_ids": candidate.root_ids, "edge_ids": candidate.edges, "owner_cell": candidate.owner_cell, "cross_squared": candidate.cross_squared})
	return rows

func _candidate_edge_rows(candidates: Array) -> Array[Array]:
	var out: Array[Array] = []
	for candidate in candidates: out.append(candidate.edge_keys.duplicate())
	return out

func _candidate_direction_rows(candidates: Array) -> Array[Array]:
	var out: Array[Array] = []
	for candidate in candidates: out.append(candidate.edge_directions.duplicate())
	return out

func _candidate_root_rows(candidates: Array) -> Array[Array]:
	var out: Array[Array] = []
	for candidate in candidates: out.append(candidate.root_indices.duplicate())
	return out

func _metadata_edges(metadata: Dictionary) -> Array:
	var out: Array = []
	for row in metadata.get("edge_rows", []): out.append(row)
	return out

func _metadata_roots(metadata: Dictionary) -> Array:
	var out: Array = []
	for row in metadata.get("root_candidate_rows", []): out.append(row)
	return out

func _root_requirement_rows(edge_rows: Array, root_index: Array) -> Array[Dictionary]:
	var boundary_roots: PackedByteArray = PackedByteArray()
	boundary_roots.resize(ROOT_COUNT)
	for edge in edge_rows:
		if not bool(edge.get("boundary", false)): continue
		boundary_roots[int(edge.get("a", -1))] = 1
		boundary_roots[int(edge.get("b", -1))] = 1
	var rows: Array[Dictionary] = []
	for root in range(ROOT_COUNT):
		rows.append({"root_index": root, "classification": "boundary" if boundary_roots[root] != 0 else "interior", "required": true, "candidate_indices": root_index[root].duplicate()})
	return rows

func _geometry_conflict_flags(roots_a: Array, roots_b: Array, projected: Array) -> int:
	if roots_a.size() != 3 or roots_b.size() != 3: return -1
	var center_a: Vector2 = (projected[int(roots_a[0])] + projected[int(roots_a[1])] + projected[int(roots_a[2])]) / 3.0
	var center_b: Vector2 = (projected[int(roots_b[0])] + projected[int(roots_b[1])] + projected[int(roots_b[2])]) / 3.0
	return _geometry_conflict_flags_fast(roots_a, roots_b, projected, center_a, center_b)

func _triangle_pair_may_overlap_axis(roots_a: Array, roots_b: Array, projected: Array, center_a: Vector2, center_b: Vector2) -> bool:
	if roots_a.size() != 3 or roots_b.size() != 3: return true
	var axis: Vector2 = center_b - center_a
	if not is_finite(axis.x) or not is_finite(axis.y) or axis.length_squared() == 0.0: return true
	var intervals: Vector4 = _triangle_projection_enclosures(roots_a, roots_b, axis, projected)
	if intervals.x > intervals.y or intervals.z > intervals.w: return true
	return not (intervals.y < intervals.z or intervals.w < intervals.x)

func _triangle_projection_enclosures(roots_a: Array, roots_b: Array, axis: Vector2, projected: Array) -> Vector4:
	var minimum_a: float = INF
	var maximum_a: float = -INF
	var error_a: float = 0.0
	var minimum_b: float = INF
	var maximum_b: float = -INF
	var error_b: float = 0.0
	for root_index in range(3):
		var point_a: Vector2 = projected[int(roots_a[root_index])]
		var point_b: Vector2 = projected[int(roots_b[root_index])]
		var ax: float = point_a.x * axis.x
		var ay: float = point_a.y * axis.y
		var bx: float = point_b.x * axis.x
		var by: float = point_b.y * axis.y
		var projection_a: float = ax + ay
		var projection_b: float = bx + by
		if not is_finite(projection_a) or not is_finite(projection_b): return Vector4(-INF, INF, -INF, INF)
		minimum_a = minf(minimum_a, projection_a)
		maximum_a = maxf(maximum_a, projection_a)
		minimum_b = minf(minimum_b, projection_b)
		maximum_b = maxf(maximum_b, projection_b)
		error_a = maxf(error_a, 32.0 * FLOAT64_UNIT_ROUNDOFF * (1.0 + absf(ax) + absf(ay) + absf(projection_a)))
		error_b = maxf(error_b, 32.0 * FLOAT64_UNIT_ROUNDOFF * (1.0 + absf(bx) + absf(by) + absf(projection_b)))
	var bound_error_a: float = 32.0 * FLOAT64_UNIT_ROUNDOFF * (1.0 + absf(minimum_a) + absf(maximum_a) + error_a)
	var bound_error_b: float = 32.0 * FLOAT64_UNIT_ROUNDOFF * (1.0 + absf(minimum_b) + absf(maximum_b) + error_b)
	return Vector4(minimum_a - error_a - bound_error_a, maximum_a + error_a + bound_error_a, minimum_b - error_b - bound_error_b, maximum_b + error_b + bound_error_b)

func _build_edge_geometry_matrix(edge_rows: Array, projected: Array, pair_limit: int, time_limit_ms: int, graph_started: int) -> Dictionary:
	var count: int = edge_rows.size()
	if count != CANDIDATE_UNIQUE_EDGE_COUNT or pair_limit <= 0 or time_limit_ms <= 0:
		return {"valid": false, "reason": "unique_edge_matrix_input_invalid", "edge_count": count}
	var conflicts: PackedByteArray = PackedByteArray()
	conflicts.resize(count * count)
	var boxes: Array[Array] = []
	for edge in edge_rows:
		var a: Vector2 = projected[int(edge.a)]
		var b: Vector2 = projected[int(edge.b)]
		boxes.append([minf(a.x, b.x), minf(a.y, b.y), maxf(a.x, b.x), maxf(a.y, b.y)])
	var order: Array[int] = []
	for edge_index in range(count): order.append(edge_index)
	order.sort_custom(func(left: int, right: int) -> bool:
		if boxes[left][0] == boxes[right][0]: return left < right
		return boxes[left][0] < boxes[right][0]
	)
	var sweep_pairs: int = 0
	var exact_pair_tests: int = 0
	for order_index in range(count):
		var i: int = order[order_index]
		var box_i: Array = boxes[i]
		for next_order in range(order_index + 1, count):
			var j: int = order[next_order]
			var box_j: Array = boxes[j]
			if float(box_j[0]) > float(box_i[2]): break
			sweep_pairs += 1
			if (sweep_pairs & 4095) == 0 and Time.get_ticks_msec() - graph_started > time_limit_ms:
				return {"valid": false, "reason": "unique_edge_broadphase_wall_time_limit", "edge_count": count, "sweep_pair_count": sweep_pairs, "exact_pair_tests": exact_pair_tests}
			if float(box_j[1]) > float(box_i[3]) or float(box_j[3]) < float(box_i[1]): continue
			if exact_pair_tests >= pair_limit:
				return {"valid": false, "reason": "combined_edge_and_candidate_pair_limit", "edge_count": count, "sweep_pair_count": sweep_pairs, "exact_pair_tests": exact_pair_tests, "pair_limit": pair_limit}
			exact_pair_tests += 1
			if (exact_pair_tests & 4095) == 0 and Time.get_ticks_msec() - graph_started > time_limit_ms:
				return {"valid": false, "reason": "unique_edge_graph_wall_time_limit", "edge_count": count, "sweep_pair_count": sweep_pairs, "exact_pair_tests": exact_pair_tests}
			var left: Dictionary = edge_rows[i]
			var right: Dictionary = edge_rows[j]
			if _edge_geometry_conflict(int(left.a), int(left.b), int(right.a), int(right.b), projected):
				conflicts[i * count + j] = 1
				conflicts[j * count + i] = 1
	return {"valid": true, "edge_count": count, "sweep_pair_count": sweep_pairs, "exact_pair_tests": exact_pair_tests, "conflicts": conflicts}

func _edge_geometry_conflict(a0: int, a1: int, b0: int, b1: int, projected: Array) -> bool:
	var shared_root: int = -1
	if a0 == b0 or a0 == b1: shared_root = a0
	if a1 == b0 or a1 == b1:
		if shared_root != -1: return false
		shared_root = a1
	if shared_root != -1:
		var shared: Vector2 = projected[shared_root]
		var other_a: Vector2 = projected[a1] if a0 == shared_root else projected[a0]
		var other_b: Vector2 = projected[b1] if b0 == shared_root else projected[b0]
		return _cross2(shared, other_a, other_b) == 0.0 and (other_a - shared).dot(other_b - shared) > 0.0
	return _segments_intersect(projected[a0], projected[a1], projected[b0], projected[b1])

func _indexed_pair_flags(edge_indices_a: Array, edge_indices_b: Array, roots_a: Array, roots_b: Array, edge_conflicts: PackedByteArray, edge_count: int, projected: Array, center_a: Vector2, center_b: Vector2) -> int:
	if edge_indices_a.size() != 3 or edge_indices_b.size() != 3 or roots_a.size() != 3 or roots_b.size() != 3 or edge_count <= 0 or edge_conflicts.size() != edge_count * edge_count:
		return -1
	var flags: int = 0
	var crossing: bool = false
	for edge_a in edge_indices_a:
		var row: int = int(edge_a) * edge_count
		for edge_b in edge_indices_b:
			if edge_conflicts[row + int(edge_b)] != 0:
				crossing = true
				break
		if crossing: break
	if crossing: flags |= CATEGORY_CROSSING
	if _point_in_triangle_strict(center_a, projected[int(roots_b[0])], projected[int(roots_b[1])], projected[int(roots_b[2])]) or _point_in_triangle_strict(center_b, projected[int(roots_a[0])], projected[int(roots_a[1])], projected[int(roots_a[2])]): flags |= CATEGORY_CONTAINMENT
	return flags

func _geometry_conflict_flags_fast(roots_a: Array, roots_b: Array, projected: Array, center_a: Vector2, center_b: Vector2) -> int:
	if roots_a.size() != 3 or roots_b.size() != 3: return -1
	var flags: int = 0
	for edge_a in range(3):
		var a0: int = int(roots_a[edge_a])
		var a1: int = int(roots_a[(edge_a + 1) % 3])
		for edge_b in range(3):
			var b0: int = int(roots_b[edge_b])
			var b1: int = int(roots_b[(edge_b + 1) % 3])
			var shared_a0: bool = a0 == b0 or a0 == b1
			var shared_a1: bool = a1 == b0 or a1 == b1
			if shared_a0 and shared_a1: continue
			if shared_a0 or shared_a1:
				var shared_root: int = a0 if shared_a0 else a1
				var shared: Vector2 = projected[shared_root]
				var other_a: Vector2 = projected[a1] if a0 == shared_root else projected[a0]
				var other_b: Vector2 = projected[b1] if b0 == shared_root else projected[b0]
				var direction_a: Vector2 = other_a - shared
				var direction_b: Vector2 = other_b - shared
				# A shared root is legal only when these edges meet at that point.
				# Positive-length collinear overlap is a geometric T-junction even
				# though the root indices match, and must not be hidden by ownership.
				if _cross2(shared, other_a, other_b) == 0.0 and direction_a.dot(direction_b) > 0.0:
					flags |= CATEGORY_CROSSING
				continue
			if _segments_intersect(projected[a0], projected[a1], projected[b0], projected[b1]): flags |= CATEGORY_CROSSING
	if _point_in_triangle_strict(center_a, projected[int(roots_b[0])], projected[int(roots_b[1])], projected[int(roots_b[2])]) or _point_in_triangle_strict(center_b, projected[int(roots_a[0])], projected[int(roots_a[1])], projected[int(roots_a[2])]): flags |= CATEGORY_CONTAINMENT
	return flags

func _find_edge_index(edge_rows: Array, key: int) -> int:
	var low: int = 0
	var high: int = edge_rows.size() - 1
	while low <= high:
		var middle: int = (low + high) >> 1
		var observed: int = int(edge_rows[middle].get("key", -1))
		if observed == key: return middle
		if observed < key: low = middle + 1
		else: high = middle - 1
	return -1

func _set_conflict(a: int, b: int, flags: int, conflicts: PackedByteArray, categories: PackedByteArray, stride: int, count: int) -> void:
	if flags == 0: return
	var a_byte: int = a * stride + (b >> 3)
	var b_byte: int = b * stride + (a >> 3)
	conflicts[a_byte] = int(conflicts[a_byte]) | (1 << (b & 7))
	conflicts[b_byte] = int(conflicts[b_byte]) | (1 << (a & 7))
	categories[a * count + b] = int(categories[a * count + b]) | flags
	categories[b * count + a] = int(categories[b * count + a]) | flags

func _shared_edge_key(left: Array, right: Array) -> int:
	for raw_left in left:
		for raw_right in right:
			if int(raw_left) == int(raw_right): return int(raw_left)
	return -1

func _direction_for_edge(edges: Array, directions: Array, key: int) -> int:
	for index in range(edges.size()):
		if int(edges[index]) == key: return int(directions[index])
	return 0

func _shared_root_count(left: Array, right: Array) -> int:
	var count: int = 0
	for a in left:
		if right.has(a): count += 1
	return count

func _category_name(bit: int) -> String:
	if bit == CATEGORY_CROSSING: return "edge_crossing"
	if bit == CATEGORY_CONTAINMENT: return "containment"
	if bit == CATEGORY_SAME_INTERIOR_EDGE_DIRECTION: return "same_interior_edge_direction"
	if bit == CATEGORY_BOUNDARY_EDGE_DUPLICATE: return "boundary_duplicate"
	return "unknown"

func _category_index(bit: int) -> int:
	if bit == CATEGORY_CROSSING: return 0
	if bit == CATEGORY_CONTAINMENT: return 1
	if bit == CATEGORY_SAME_INTERIOR_EDGE_DIRECTION: return 2
	if bit == CATEGORY_BOUNDARY_EDGE_DUPLICATE: return 3
	return -1

func _has_conflict_category(a: int, b: int, category: int, categories: PackedByteArray, count: int) -> bool:
	return (int(categories[a * count + b]) & category) != 0

func _has_geometric_conflict_in_matrix(a: int, b: int, categories: PackedByteArray, count: int) -> bool:
	return (int(categories[a * count + b]) & CATEGORY_GEOMETRIC_MASK) != 0

func _bit_is_set(bits: PackedByteArray, base: int, bit: int) -> bool:
	if bit < 0 or (base + (bit >> 3)) >= bits.size(): return false
	return (int(bits[base + (bit >> 3)]) & (1 << (bit & 7))) != 0

func _write_new_file(path: String, bytes: PackedByteArray) -> Error:
	if FileAccess.file_exists(path): return ERR_ALREADY_EXISTS
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null: return FileAccess.get_open_error()
	file.store_buffer(bytes)
	var error: Error = file.get_error()
	file.close()
	return error

func _sha256(bytes: PackedByteArray) -> String:
	var context: HashingContext = HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode().to_lower()

func _segments_intersect(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> bool:
	var ab_c: float = _cross2(a, b, c)
	var ab_d: float = _cross2(a, b, d)
	var cd_a: float = _cross2(c, d, a)
	var cd_b: float = _cross2(c, d, b)
	if ((ab_c > 0.0 and ab_d < 0.0) or (ab_c < 0.0 and ab_d > 0.0)) and ((cd_a > 0.0 and cd_b < 0.0) or (cd_a < 0.0 and cd_b > 0.0)): return true
	return (ab_c == 0.0 and _point_on_segment(c, a, b)) or (ab_d == 0.0 and _point_on_segment(d, a, b)) or (cd_a == 0.0 and _point_on_segment(a, c, d)) or (cd_b == 0.0 and _point_on_segment(b, c, d))

func _point_on_segment(p: Vector2, a: Vector2, b: Vector2) -> bool:
	if _cross2(a, b, p) != 0.0: return false
	return p.x >= minf(a.x, b.x) and p.x <= maxf(a.x, b.x) and p.y >= minf(a.y, b.y) and p.y <= maxf(a.y, b.y)

func _point_in_triangle_strict(p: Vector2, a: Vector2, b: Vector2, c: Vector2) -> bool:
	var ab: float = _cross2(a, b, p)
	var bc: float = _cross2(b, c, p)
	var ca: float = _cross2(c, a, p)
	return (ab > 0.0 and bc > 0.0 and ca > 0.0) or (ab < 0.0 and bc < 0.0 and ca < 0.0)

func _cross2(a: Vector2, b: Vector2, c: Vector2) -> float:
	return (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
