extends SceneTree

const Core := preload("res://tests/prototypes/p3_1_r9_2_diagnostic_base.gd")
const CandidateScript := preload("res://tests/prototypes/p3_1_r9_2_candidate_impl.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var manifest: Dictionary = Core.load_manifest()
	var ids: PackedStringArray = OS.get_environment("R9_SCENARIO_IDS").split(",", false)
	if not manifest.get("valid", false) or ids.is_empty():
		print("R9_3_PROBE_BLOCKED " + JSON.stringify({"manifest": manifest.get("reason", "ok"), "scenario_ids": ids}))
		quit(2)
		return
	var candidate: RefCounted = CandidateScript.new()
	var failures := 0
	for scenario_id in ids:
		var row: Dictionary = Core.case_by_id(manifest.rows, scenario_id)
		if row.is_empty():
			print("R9_3_PROBE_FAIL " + JSON.stringify({"scenario_id": scenario_id, "reason": "scenario_not_frozen"}))
			failures += 1
			continue
		var variants: Array = []
		if row.has("roi"):
			variants = [{"id": "default", "roi": row.roi}]
		else:
			variants = row.get("variants", [])
		if variants.is_empty():
			print("R9_3_PROBE_FAIL " + JSON.stringify({"scenario_id": scenario_id, "reason": "frozen_roi_missing"}))
			failures += 1
			continue
		var variant: Dictionary = variants[0]
		var roi: Dictionary = variant.get("roi", row.get("roi", {}))
		candidate.configure_roi(roi)
		var setup: Dictionary = Core.make_snapshot(row)
		if not setup.get("valid", false):
			print("R9_3_PROBE_FAIL " + JSON.stringify({"scenario_id": scenario_id, "reason": "snapshot_invalid", "detail": setup}))
			failures += 1
			continue
		var result: Dictionary = candidate.build(setup.snapshot, row, variant)
		if not result.get("valid", false):
			print("R9_3_PROBE_FAIL " + JSON.stringify({"scenario_id": scenario_id, "reason": result.get("reason", "candidate_invalid"), "detail": result}))
			failures += 1
			continue
		var lo: Vector3 = Core.world_min(roi)
		var hi: Vector3 = lo + Vector3(Core.cell_counts(roi)) * Core.step(roi)
		if OS.get_environment("R9_CANDIDATE_ID") == "C":
			lo -= Vector3.ONE * Core.step(roi) * 0.5
			hi += Vector3.ONE * Core.step(roi) * 0.5
		var topo: Dictionary = Core.topology(result.mesh, lo, hi)
		var open_details: Array[Dictionary] = _open_edge_details(result.mesh, lo, hi, 64)
		var root_identity:Dictionary={"status":"NOT_APPLICABLE"}
		if OS.get_environment("R9_CANDIDATE_ID")=="A":
			root_identity=candidate.call("canonical_root_identity_probe",setup.snapshot)
			if not root_identity.get("valid",false) or not root_identity.get("exact_sample_keys_distinct",false):
				print("R9_3_PROBE_FAIL "+JSON.stringify({"scenario_id":scenario_id,"reason":"A_root_identity_regression","detail":root_identity}))
				failures+=1
		print("R9_3_PROBE_RESULT " + JSON.stringify({"scenario_id": scenario_id, "candidate": OS.get_environment("R9_CANDIDATE_ID"),
			"source_sha": OS.get_environment("R9_SOURCE_SHA"), "manifest_sha256": Core.EXPECTED_MANIFEST_SHA,
			"mesh_sha256": result.get("mesh_sha256", ""), "metrics": result.get("metrics", {}),
			"topology": topo, "open_edge_details_first_64": open_details,"canonical_root_identity":root_identity,
			"topology_bounds_min": [lo.x,lo.y,lo.z], "topology_bounds_max": [hi.x,hi.y,hi.z]}))
	print("R9_3_PROBE_COMPLETE " + JSON.stringify({"scenario_count": ids.size(), "failures": failures}))
	quit(1 if failures > 0 else 0)

func _open_edge_details(mesh: Dictionary, lo: Vector3, hi: Vector3, limit: int) -> Array[Dictionary]:
	var positions: PackedVector3Array = mesh.get("positions", PackedVector3Array())
	var owners: Dictionary = {}
	var counts: Dictionary = {}
	for triangle_id in range(positions.size() / 3):
		var base := triangle_id * 3
		for edge in [Vector2i(0,1), Vector2i(1,2), Vector2i(2,0)]:
			var a: Vector3 = positions[base + edge.x]
			var b: Vector3 = positions[base + edge.y]
			var ka := Core._point_key(a)
			var kb := Core._point_key(b)
			var key := ka + "|" + kb if ka < kb else kb + "|" + ka
			counts[key] = int(counts.get(key, 0)) + 1
			if not owners.has(key): owners[key] = {"triangle_id": triangle_id, "a": [a.x,a.y,a.z], "b": [b.x,b.y,b.z]}
	var rows: Array[Dictionary] = []
	for key_value in counts.keys():
		if int(counts[key_value]) != 1: continue
		var owner: Dictionary = owners[key_value]
		var a: Vector3 = Vector3(owner.a[0],owner.a[1],owner.a[2])
		var b: Vector3 = Vector3(owner.b[0],owner.b[1],owner.b[2])
		rows.append({"edge_key": key_value, "triangle_id": owner.triangle_id,
			"a": owner.a, "b": owner.b, "roi_boundary": _on_boundary(a,b,lo,hi)})
		if rows.size() >= limit: break
	return rows

func _on_boundary(a: Vector3,b: Vector3,lo: Vector3,hi: Vector3) -> bool:
	for axis in range(3):
		if absf(a[axis]-lo[axis])<0.00002 and absf(b[axis]-lo[axis])<0.00002:return true
		if absf(a[axis]-hi[axis])<0.00002 and absf(b[axis]-hi[axis])<0.00002:return true
	return false
