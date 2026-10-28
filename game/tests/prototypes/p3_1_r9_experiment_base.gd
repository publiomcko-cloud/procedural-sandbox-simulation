class_name P31R9ExperimentBase
extends RefCounted

## Shared test-only input verifier and geometry oracle support for R9 candidates.
## It is not referenced by any production script.
const Brush := preload("res://scripts/terrain/sdf_brush_edit_state.gd")
const Field := preload("res://scripts/terrain/sdf_world.gd")
const Transition := preload("res://scripts/experiments/lod01_transition_fixture.gd")
const MANIFEST_PATH := "res://tests/prototypes/p3_1_r9_frozen_inputs.jsonl"
const SIDECAR_PATH := "res://tests/prototypes/p3_1_r9_frozen_inputs.sha256"
const EXPECTED_MANIFEST_SHA := "2b44cb52ef091c2527fa2f8b06859752cc7cfaa14bcafe94d4a4c55b0cdd908f"
const MAX_NODES := 10000
const MAX_TRIANGLES := 20000
const MAX_SECONDS := 600.0
const GRID_CORNERS: Array[Vector3i] = [
	Vector3i(0,0,0), Vector3i(1,0,0), Vector3i(1,1,0), Vector3i(0,1,0),
	Vector3i(0,0,1), Vector3i(1,0,1), Vector3i(1,1,1), Vector3i(0,1,1)]
const GRID_EDGES: Array[Vector2i] = [
	Vector2i(0,1),Vector2i(1,2),Vector2i(2,3),Vector2i(3,0),
	Vector2i(4,5),Vector2i(5,6),Vector2i(6,7),Vector2i(7,4),
	Vector2i(0,4),Vector2i(1,5),Vector2i(2,6),Vector2i(3,7)]
const TETS: Array[Array] = [
	[0,5,1,6],[0,1,2,6],[0,2,3,6],[0,3,7,6],[0,7,4,6],[0,4,5,6]]

static func sha256(bytes: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	if ctx.start(HashingContext.HASH_SHA256) != OK: return "HASH_START_FAILED"
	ctx.update(bytes)
	return ctx.finish().hex_encode()

static func load_manifest() -> Dictionary:
	var bytes := FileAccess.get_file_as_bytes(MANIFEST_PATH)
	if bytes.is_empty(): return {"valid": false, "reason": "manifest_unreadable"}
	if sha256(bytes) != EXPECTED_MANIFEST_SHA: return {"valid": false, "reason": "manifest_sha_mismatch"}
	var text := bytes.get_string_from_utf8()
	if text.contains("\r") or not text.ends_with("\n"):
		return {"valid": false, "reason": "manifest_line_ending_invalid"}
	var rows: Array[Dictionary] = []
	for line in text.trim_suffix("\n").split("\n"):
		var parsed: Variant = JSON.parse_string(line)
		if typeof(parsed) != TYPE_DICTIONARY or parsed.get("schema", "") != "P3.1.R9.Input.v1":
			return {"valid": false, "reason": "manifest_row_invalid"}
		rows.append(parsed)
	if rows.size() != 9: return {"valid": false, "reason": "manifest_case_count_invalid"}
	var sidecar := FileAccess.get_file_as_string(SIDECAR_PATH).strip_edges()
	if not sidecar.begins_with(EXPECTED_MANIFEST_SHA): return {"valid": false, "reason": "manifest_sidecar_mismatch"}
	return {"valid": true, "sha256": sha256(bytes), "rows": rows}

static func case_by_id(rows: Array, case_id: String) -> Dictionary:
	for value in rows:
		var row: Dictionary = value
		if String(row.get("id", "")) == case_id: return row
	return {}

static func make_snapshot(case_row: Dictionary) -> Dictionary:
	var seed := int(case_row.get("seed", -1))
	if seed < 0 or int(case_row.get("generator_version", -1)) != Field.GENERATOR_VERSION:
		return {"valid": false, "reason": "world_identity_invalid"}
	var ledger: RefCounted = Brush.new(seed, Field.GENERATOR_VERSION)
	var edit_id := String(case_row.get("edit_case", case_row.get("id", "")))
	var edit_row := case_row
	if not case_row.has("commands"):
		var manifest := load_manifest()
		if not manifest.valid: return manifest
		edit_row = case_by_id(manifest.rows, edit_id)
	if typeof(edit_row.get("commands", null)) != TYPE_ARRAY:
		return {"valid": false, "reason": "commands_missing"}
	for value in edit_row.commands:
		var command: Dictionary = value
		var mode_text := String(command.get("mode", ""))
		var mode := Brush.Mode.CARVE if mode_text == "CARVE" else (Brush.Mode.FILL if mode_text == "FILL" else -1)
		var c: Array = command.get("center", [])
		if c.size() != 3 or not ledger.add_sphere(mode, Vector3(float(c[0]),float(c[1]),float(c[2])), float(command.get("radius", -1.0))):
			return {"valid": false, "reason": "frozen_command_rejected", "rejection": ledger.last_rejection_reason}
	var snapshot: Dictionary = ledger.get_meshing_snapshot()
	if int(snapshot.get("revision", -1)) != edit_row.get("commands", []).size():
		return {"valid": false, "reason": "snapshot_revision_mismatch"}
	return {"valid": true, "snapshot": snapshot, "revision": ledger.revision,
		"edit_count": ledger.get_edit_count(), "last_sequence": ledger.get_last_sequence()}

static func sample(world: Vector3, snapshot: Dictionary) -> float:
	return Transition.sample_canonical(131102026, world, snapshot)

static func root(a: Vector3, b: Vector3, da: float, db: float, snapshot: Dictionary, iterations: int = 40) -> Dictionary:
	if not is_finite(da) or not is_finite(db) or da == 0.0 or db == 0.0 or (da < 0.0) == (db < 0.0):
		return {"valid": false, "reason": "edge_not_sign_bracketed"}
	var low := 0.0
	var high := 1.0
	var low_value := da
	for i in range(iterations):
		var mid := (low + high) * 0.5
		var dm := sample(a.lerp(b, mid), snapshot)
		if not is_finite(dm): return {"valid": false, "reason": "nonfinite_root_sample"}
		if dm == 0.0:
			low = mid; high = mid; break
		if (dm < 0.0) == (low_value < 0.0): low = mid; low_value = dm
		else: high = mid
	var t := (low + high) * 0.5
	return {"valid": true, "t": t, "point": a.lerp(b,t), "bracket": [low,high]}

static func new_mesh() -> Dictionary:
	return {"positions": PackedVector3Array(), "normals": PackedVector3Array(), "indices": PackedInt32Array()}

static func add_triangle(mesh: Dictionary, a: Vector3, b: Vector3, c: Vector3, toward_empty: Vector3, cutoff: float = 1.0e-12) -> bool:
	var cross := (b-a).cross(c-a)
	if not cross.is_finite() or cross.length_squared() <= cutoff: return false
	if cross.dot(toward_empty) < 0.0:
		var swap := b; b = c; c = swap; cross = -cross
	var n := cross.normalized()
	var p: PackedVector3Array = mesh.positions
	var ns: PackedVector3Array = mesh.normals
	var ids: PackedInt32Array = mesh.indices
	var start := p.size()
	p.append_array(PackedVector3Array([a,b,c])); ns.append_array(PackedVector3Array([n,n,n]))
	ids.append_array(PackedInt32Array([start,start+1,start+2]))
	mesh.positions = p; mesh.normals = ns; mesh.indices = ids
	return true

static func topology(mesh: Dictionary, bounds_min: Vector3, bounds_max: Vector3) -> Dictionary:
	var positions: PackedVector3Array = mesh.positions
	var edge_counts: Dictionary = {}
	var degenerate := 0
	var bad_winding := 0
	for i in range(0, positions.size(), 3):
		var a: Vector3 = positions[i]; var b: Vector3 = positions[i+1]; var c: Vector3 = positions[i+2]
		var cross := (b-a).cross(c-a)
		if not cross.is_finite() or cross.length_squared() <= 1.0e-12: degenerate += 1
		if mesh.normals.size() > i and cross.dot(mesh.normals[i]) <= 0.0: bad_winding += 1
		for pair in [Vector2i(i,i+1), Vector2i(i+1,i+2), Vector2i(i+2,i)]:
			var p: Vector3 = positions[pair.x]; var q: Vector3 = positions[pair.y]
			var kp := _point_key(p); var kq := _point_key(q)
			var key := kp + "|" + kq if kp < kq else kq + "|" + kp
			edge_counts[key] = int(edge_counts.get(key,0))+1
	var opens := 0; var nonmanifold := 0; var boundary_opens := 0
	for key_value in edge_counts:
		var count := int(edge_counts[key_value])
		if count > 2: nonmanifold += 1
		elif count == 1:
			var parts := String(key_value).split("|")
			var a := _key_point(parts[0]); var b := _key_point(parts[1])
			if _on_roi_boundary(a,b,bounds_min,bounds_max): boundary_opens += 1
			else: opens += 1
	return {"triangle_count": positions.size()/3, "internal_open_edges": opens,
		"roi_boundary_open_edges": boundary_opens,"nonmanifold_edges":nonmanifold,"degenerate_triangles":degenerate,"winding_inconsistencies":bad_winding}

static func _point_key(p: Vector3) -> String:
	return "%d,%d,%d" % [roundi(p.x*100000.0),roundi(p.y*100000.0),roundi(p.z*100000.0)]

static func _key_point(key: String) -> Vector3:
	var c := key.split(",")
	return Vector3(float(c[0]),float(c[1]),float(c[2]))/100000.0

static func _on_roi_boundary(a: Vector3,b: Vector3,lo: Vector3,hi: Vector3)->bool:
	for axis in range(3):
		if absf(a[axis]-lo[axis])<0.00002 and absf(b[axis]-lo[axis])<0.00002:return true
		if absf(a[axis]-hi[axis])<0.00002 and absf(b[axis]-hi[axis])<0.00002:return true
	return false

static func ray_mesh(origin: Vector3, direction: Vector3, max_distance: float, mesh: Dictionary) -> Dictionary:
	var best := INF; var hits := 0
	var p: PackedVector3Array = mesh.positions
	for i in range(0,p.size(),3):
		var result := _ray_triangle(origin,direction,p[i],p[i+1],p[i+2])
		if result >= 0.0 and result <= max_distance:
			hits += 1; best = minf(best,result)
	return {"hit": hits>0, "hit_count": hits, "distance": best if hits>0 else INF,
		"position": origin+direction*best if hits>0 else origin}

static func _ray_triangle(o:Vector3,d:Vector3,a:Vector3,b:Vector3,c:Vector3)->float:
	var e1:=b-a; var e2:=c-a; var h:=d.cross(e2); var det:=e1.dot(h)
	if absf(det)<1.0e-10:return -1.0
	var inv:=1.0/det; var s:=o-a; var u:=inv*s.dot(h)
	if u<0.0 or u>1.0:return -1.0
	var q:=s.cross(e1); var v:=inv*d.dot(q)
	if v<0.0 or u+v>1.0:return -1.0
	var t:=inv*e2.dot(q)
	return t if t>=0.0 else -1.0
