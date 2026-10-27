extends SceneTree

const Brush := preload("res://scripts/terrain/sdf_brush_edit_state.gd")
const Field := preload("res://scripts/terrain/sdf_world.gd")
const Spatial := preload("res://scripts/terrain/terrain_spatial_ownership.gd")
const Grid := preload("res://scripts/terrain/terrain_chunk_grid.gd")
const R5Density := preload("res://tests/prototypes/r5_exact_density.gd")
const SEED := 131102026
const FIXTURE := "res://tests/fixtures/p3_1_r4/issue131/P31.EDIT.CONCENTRATED.N8192.v1.R01.commands.json"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var fixture_bytes := FileAccess.get_file_as_bytes(FIXTURE)
	var parsed: Variant = JSON.parse_string(fixture_bytes.get_string_from_utf8())
	if typeof(parsed) != TYPE_ARRAY or (parsed as Array).size() != 8192:
		push_error("R6E frozen fixture invalid")
		quit(2)
		return
	var ledger: RefCounted = Brush.new(SEED, 1)
	for command_value in parsed as Array:
		var command: Dictionary = command_value
		var mm: Array = command.center_mm
		var center := Vector3(float(mm[0]), float(mm[1]), float(mm[2])) / 1000.0
		var mode := Brush.Mode.CARVE if String(command.mode) == "CARVE" else Brush.Mode.FILL
		if not ledger.add_sphere(mode, center, float(command.radius_mm) / 1000.0):
			push_error("R6E ledger construction failed")
			quit(3)
			return
	var full: Dictionary = ledger.get_meshing_snapshot()
	var region := Vector2i.ZERO
	var chunk := Vector2i.ZERO
	var projected: Dictionary = ledger.get_meshing_snapshot_for_chunk(region, chunk)
	var evaluator := R5Density.new()
	if not bool(projected.get("valid", false)) or not evaluator.configure(SEED, region, projected):
		push_error("R6E candidate setup failed")
		quit(4)
	var probes: Array[Dictionary] = []
	var origin: Vector3 = Spatial.region_origin_world(region) + Grid.origin_for(chunk)
	var size: Vector3 = Grid.size_for(chunk)
	for index in range(768):
		var x := origin.x + size.x * float(posmod(index * 17, 769)) / 768.0
		var y := Grid.MIN_BOUND.y + (Grid.MAX_BOUND.y - Grid.MIN_BOUND.y) * float(posmod(index * 31, 769)) / 768.0
		var z := origin.z + size.z * float(posmod(index * 43, 769)) / 768.0
		probes.append({"kind": "grid", "index": index, "point": Vector3(x, y, z)})
	for command_index in [0, 1, 31, 255, 2047, 4095, 8191]:
		var center: Vector3 = projected.centers[command_index]
		probes.append({"kind": "command_center", "index": command_index, "point": center})
		probes.append({"kind": "radius_plus_0_0000005", "index": command_index,
			"point": center + Vector3(0.5800005, 0.0, 0.0)})
		probes.append({"kind": "radius_minus_0_0000005", "index": command_index,
			"point": center + Vector3(0.5799995, 0.0, 0.0)})
	for point in [Vector3(-0.001, 2.0, 1.0), Vector3(0.0, 2.0, 1.0),
		Vector3(15.999, 2.0, 11.999), Vector3(16.0, 2.0, 12.0),
		Vector3(-16.0, -0.25, -12.0), Vector3(-31.999, 1.15, -767.999)]:
		probes.append({"kind": "region_seam", "index": probes.size(), "point": point})
	var cave_center: Vector2 = Field.cave_center(SEED, Vector2i.ZERO, 2.5)
	probes.append({"kind": "cave_center", "index": probes.size(),
		"point": Vector3(2.5, cave_center.y, cave_center.x)})
	var mismatch_count := 0
	var reproduced_old_mismatch_count := 0
	var old_coordinate_mismatch_count := 0
	var old_pruning_mismatch_count := 0
	var corrected_unpruned_mismatch_count := 0
	var corrected_pruning_mismatch_count := 0
	var records: Array[Dictionary] = []
	var full_arrays_equal := _snapshots_equal(full, projected)
	var sequence_first_difference := {"canonical_sequence_source": "implicit_array_order",
		"projected_first": projected.sequences[0] if not projected.sequences.is_empty() else -1,
		"projected_last": projected.sequences[-1] if not projected.sequences.is_empty() else -1,
		"projected_count": projected.sequences.size()}
	for probe in probes:
		var point: Vector3 = probe.point
		var mapped: Dictionary = Spatial.world_to_region_local(point)
		var reconstructed: Vector3 = Spatial.region_local_to_world(mapped.region_key, mapped.local_position)
		var canonical := Brush.sample_density_snapshot(SEED, mapped.region_key, mapped.local_position, false, full)
		var candidate := evaluator.sample_world(point)
		var optimized_remapped := R5Density.sample_world_optimized(SEED, region, projected, point, false, true)
		var optimized_region_local := R5Density.sample_world_optimized(SEED, region, projected, point, false, false)
		var requires_stepwise_replay: bool = probe.kind == "command_center" \
			or probe.kind == "radius_plus_0_0000005" or probe.kind == "radius_minus_0_0000005"
		var replay: Dictionary = {}
		var old_candidate_mismatch := false
		if requires_stepwise_replay:
			replay = _first_replay_divergence(point, reconstructed, canonical, candidate, full, projected)
			old_candidate_mismatch = not bool(replay.old_pruned_matches_reference)
			if old_candidate_mismatch: reproduced_old_mismatch_count += 1
			if not replay.first_canonical_vs_raw_unpruned.is_empty(): old_coordinate_mismatch_count += 1
			if not replay.first_raw_unpruned_vs_pruned.is_empty(): old_pruning_mismatch_count += 1
			if not replay.corrected_unpruned_matches_reference: corrected_unpruned_mismatch_count += 1
			if not replay.corrected_pruned_vs_unpruned_matches: corrected_pruning_mismatch_count += 1
		if canonical != candidate or old_candidate_mismatch:
			if canonical != candidate:
				mismatch_count += 1
			var record := {"probe": {"kind": probe.kind, "index": probe.index},
				"world_query": _vec_record(point), "mapped_region": [mapped.region_key.x, mapped.region_key.y],
				"local": _vec_record(mapped.local_position), "reconstructed_world": _vec_record(reconstructed),
				"canonical_density": _scalar_record(canonical), "candidate_density": _scalar_record(candidate),
				"old_candidate_density": replay.old_pruned_replay_final,
				"optimized_remapped": _scalar_record(optimized_remapped),
				"optimized_region_local": _scalar_record(optimized_region_local),
				"snapshot_arrays_equal": full_arrays_equal,
				"first_snapshot_sequence_difference": sequence_first_difference,
				"first_replay_divergence": replay,
				"coordinate_roundtrip_delta": _vec_record(reconstructed - point)}
			records.append(record)
			print("R6E_MISMATCH " + JSON.stringify(record))
	var minimal_regression := _minimal_roundtrip_regression()
	var result := {"status": "DIAGNOSTIC_COMPLETE", "fixture_sha256": _sha256(fixture_bytes),
		"seed": SEED, "ledger_operations": full.centers.size(), "projected_operations": projected.centers.size(),
		"probe_count": probes.size(), "mismatch_count": mismatch_count,
		"reproduced_old_candidate_mismatch_count": reproduced_old_mismatch_count,
		"old_candidate_coordinate_mismatch_count": old_coordinate_mismatch_count,
		"old_candidate_pruning_mismatch_count": old_pruning_mismatch_count,
		"corrected_unpruned_mismatch_count": corrected_unpruned_mismatch_count,
		"corrected_pruned_vs_unpruned_mismatch_count": corrected_pruning_mismatch_count,
		"canonical_candidate_array_equal": full_arrays_equal,
		"first_sequence_difference": sequence_first_difference,
		"minimal_roundtrip_regression": minimal_regression,
		"mismatches": records}
	result["status"] = "PASS" if mismatch_count == 0 and reproduced_old_mismatch_count == 16 \
		and corrected_unpruned_mismatch_count == 0 \
		and corrected_pruning_mismatch_count == 0 and full_arrays_equal and bool(minimal_regression.pass) else "FAIL"
	print("R6E_RESULT " + JSON.stringify(result))
	quit(0 if String(result.status) == "PASS" else 1)


func _first_replay_divergence(point: Vector3, canonical_world: Vector3, expected: float,
		reported_candidate: float, full: Dictionary, projected: Dictionary) -> Dictionary:
	var mapped: Dictionary = Spatial.world_to_region_local(point)
	var base: float = Field.sample_density(SEED, mapped.region_key, mapped.local_position)
	var reference_state := base
	var raw_unpruned_state := base
	var candidate_state := base
	var corrected_unpruned_state := base
	var corrected_pruned_state := base
	var centers: PackedVector3Array = full.centers
	var radii: PackedFloat64Array = full.radii
	var modes: PackedByteArray = full.modes
	var sequences: PackedInt32Array = projected.sequences
	var first_canonical_raw: Dictionary = {}
	var first_raw_pruned: Dictionary = {}
	var first_actual: Dictionary = {}
	var first_corrected_pruning: Dictionary = {}
	for index in range(centers.size()):
		var center: Vector3 = centers[index]
		var radius := float(radii[index])
		var mode := int(modes[index])
		var canonical_distance := canonical_world.distance_to(center)
		var canonical_surface := canonical_distance - radius
		var canonical_after := minf(reference_state, canonical_surface) if mode == Brush.Mode.CARVE \
			else maxf(reference_state, -canonical_surface)
		var raw_distance := point.distance_to(center)
		var raw_surface := raw_distance - radius
		var raw_after := minf(raw_unpruned_state, raw_surface) if mode == Brush.Mode.CARVE \
			else maxf(raw_unpruned_state, -raw_surface)
		var cutoff := candidate_state + radius if mode == Brush.Mode.CARVE else radius - candidate_state
		var guard := maxf(0.0000001, absf(cutoff) * R5Density.DISTANCE_GUARD_RELATIVE)
		var delta := point - center
		var skipped := cutoff <= 0.0 or absf(delta.x) > cutoff + guard \
			or absf(delta.y) > cutoff + guard or absf(delta.z) > cutoff + guard
		var candidate_after := candidate_state
		if not skipped:
			candidate_after = minf(candidate_state, raw_surface) if mode == Brush.Mode.CARVE \
				else maxf(candidate_state, -raw_surface)
		var corrected_surface := canonical_distance - radius
		var corrected_unpruned_after := minf(corrected_unpruned_state, corrected_surface) if mode == Brush.Mode.CARVE \
			else maxf(corrected_unpruned_state, -corrected_surface)
		var corrected_cutoff := corrected_pruned_state + radius if mode == Brush.Mode.CARVE \
			else radius - corrected_pruned_state
		var corrected_guard := maxf(0.0000001, absf(corrected_cutoff) * R5Density.DISTANCE_GUARD_RELATIVE)
		var corrected_delta := canonical_world - center
		var corrected_skipped := corrected_cutoff <= 0.0 \
			or absf(corrected_delta.x) > corrected_cutoff + corrected_guard \
			or absf(corrected_delta.y) > corrected_cutoff + corrected_guard \
			or absf(corrected_delta.z) > corrected_cutoff + corrected_guard
		var corrected_pruned_after := corrected_pruned_state
		if not corrected_skipped:
			corrected_pruned_after = minf(corrected_pruned_state, corrected_surface) if mode == Brush.Mode.CARVE \
				else maxf(corrected_pruned_state, -corrected_surface)
		var common := {"ledger_index": index, "global_sequence": int(sequences[index]),
			"mode": "CARVE" if mode == Brush.Mode.CARVE else "FILL",
			"brush_center": _vec_record(center), "radius": _scalar_record(radius),
			"candidate_cutoff": _scalar_record(cutoff), "candidate_guard": _scalar_record(guard),
			"candidate_skipped_operation": skipped,
			"canonical_signed_distance": _scalar_record(canonical_surface),
			"canonical_distance": _scalar_record(canonical_distance),
			"raw_candidate_distance": _scalar_record(raw_distance),
			"canonical_state_before": _scalar_record(reference_state),
			"raw_unpruned_state_before": _scalar_record(raw_unpruned_state),
			"candidate_state_before": _scalar_record(candidate_state),
			"canonical_state_after": _scalar_record(canonical_after),
			"raw_unpruned_state_after": _scalar_record(raw_after),
			"candidate_state_after": _scalar_record(candidate_after)}
		if first_canonical_raw.is_empty() and canonical_after != raw_after:
			first_canonical_raw = common.duplicate(true)
			first_canonical_raw["cause_path"] = "query_to_region_local_world_roundtrip"
		if first_raw_pruned.is_empty() and raw_after != candidate_after:
			first_raw_pruned = common.duplicate(true)
			first_raw_pruned["cause_path"] = "axis_pruning_vs_raw_unpruned_replay"
		if first_actual.is_empty() and canonical_after != candidate_after:
			first_actual = common.duplicate(true)
		if first_corrected_pruning.is_empty() and corrected_unpruned_after != corrected_pruned_after:
			first_corrected_pruning = common.duplicate(true)
			first_corrected_pruning["cause_path"] = "axis_pruning_vs_full_replay_on_canonical_mapped_world"
		reference_state = canonical_after
		raw_unpruned_state = raw_after
		candidate_state = candidate_after
		corrected_unpruned_state = corrected_unpruned_after
		corrected_pruned_state = corrected_pruned_after
	return {"first_canonical_vs_raw_unpruned": first_canonical_raw,
		"first_raw_unpruned_vs_pruned": first_raw_pruned,
		"first_canonical_vs_actual_candidate": first_actual,
		"first_corrected_pruning_divergence": first_corrected_pruning,
		"canonical_replay_final": _scalar_record(reference_state),
		"raw_unpruned_replay_final": _scalar_record(raw_unpruned_state),
		"old_pruned_replay_final": _scalar_record(candidate_state),
		"old_pruned_matches_reference": candidate_state == reference_state,
		"corrected_unpruned_replay_final": _scalar_record(corrected_unpruned_state),
		"corrected_pruned_replay_final": _scalar_record(corrected_pruned_state),
		"corrected_unpruned_matches_reference": corrected_unpruned_state == reference_state,
		"corrected_pruned_vs_unpruned_matches": corrected_pruned_state == corrected_unpruned_state,
		"reported_candidate": _scalar_record(reported_candidate),
		"reported_expected": _scalar_record(expected)}


func _minimal_roundtrip_regression() -> Dictionary:
	var bytes := FileAccess.get_file_as_bytes(FIXTURE)
	var parsed: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	if typeof(parsed) != TYPE_ARRAY or (parsed as Array).is_empty():
		return {"pass": false, "reason": "first_frozen_command_unavailable"}
	var command: Dictionary = (parsed as Array)[0]
	var mm: Array = command.center_mm
	var center := Vector3(float(mm[0]), float(mm[1]), float(mm[2])) / 1000.0
	var radius := float(command.radius_mm) / 1000.0
	var mode := Brush.Mode.CARVE if String(command.mode) == "CARVE" else Brush.Mode.FILL
	var ledger: RefCounted = Brush.new(SEED, 1)
	var added: bool = ledger.add_sphere(mode, center, radius)
	var full: Dictionary = ledger.get_meshing_snapshot()
	var mapped: Dictionary = Spatial.world_to_region_local(center)
	var reconstructed: Vector3 = Spatial.region_local_to_world(mapped.region_key, mapped.local_position)
	var canonical: float = Brush.sample_density_snapshot(SEED, mapped.region_key, mapped.local_position, false, full)
	var raw_single := center.distance_to(center) - radius
	var candidate := R5Density.new()
	var configured: bool = candidate.configure(SEED, mapped.region_key, full)
	var corrected: float = candidate.sample_world(center)
	var base := Field.sample_density(SEED, mapped.region_key, mapped.local_position)
	var expected_base := Field.sample_density(SEED, mapped.region_key, mapped.local_position)
	var pass_value: bool = added and configured and mapped.region_key == Vector2i(-1, -1) \
		and reconstructed != center and canonical != raw_single and base == expected_base \
		and corrected == canonical and full.centers.size() == 1 and full.centers[0] == center \
		and full.radii[0] == radius and full.modes[0] == mode
	return {"pass": pass_value, "frozen_sequence": 0, "mode": String(command.mode),
		"center": _vec_record(center), "radius": _scalar_record(radius),
		"region": [mapped.region_key.x, mapped.region_key.y], "local": _vec_record(mapped.local_position),
		"reconstructed_world": _vec_record(reconstructed), "raw_query_world": _vec_record(center),
		"canonical_density": _scalar_record(canonical), "old_raw_world_density": _scalar_record(raw_single),
		"corrected_candidate_density": _scalar_record(corrected), "base_density_replay_equal": base == expected_base}


func _snapshots_equal(a: Dictionary, b: Dictionary) -> bool:
	return a.centers == b.centers and a.radii == b.radii and a.modes == b.modes


func _vec_record(value: Vector3) -> Dictionary:
	return {"decimal": [value.x, value.y, value.z], "float32_le_hex": [_f32(value.x), _f32(value.y), _f32(value.z)]}


func _scalar_record(value: float) -> Dictionary:
	return {"decimal": value, "float64_le_hex": _f64(value)}


func _f32(value: float) -> String:
	var bytes := PackedByteArray()
	bytes.resize(4)
	bytes.encode_float(0, value)
	return bytes.hex_encode()


func _f64(value: float) -> String:
	var bytes := PackedByteArray()
	bytes.resize(8)
	bytes.encode_double(0, value)
	return bytes.hex_encode()


func _sha256(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()
