extends SceneTree

## R9-B test-only bounded adaptive Hermite/QEF dual-contouring prototype.
## The uniform 0.5 lattice owns topology; only sign-active cells receive one
## 0.25 Hermite refinement level. This deliberately bounded prototype does
## not change the production mesher or claim a product tolerance.
const Core := preload("res://tests/prototypes/p3_1_r9_experiment_base.gd")
const SEED := 131102026
const ROI_MIN := Vector3(8.0, -2.0, 3.0)
const ROI_CELLS := Vector3i(8, 20, 12)
const STEP := 0.5
const MAX_NODES := 10000
const MAX_TRIANGLES := 20000
const MAX_USEC := 600000000
const TETRA_CUTOFF := 1.0e-12
var _started := 0
var _assertions := 0
var _failures: Array[String] = []

func _initialize() -> void:
	_started = Time.get_ticks_usec()
	call_deferred("_run")

func _run() -> void:
	var manifest: Dictionary = Core.load_manifest()
	_check(bool(manifest.get("valid", false)), "frozen_manifest_verified")
	if not manifest.get("valid", false):
		_finish("BLOCKED", "manifest_preflight_failed")
		return
	var zero: Dictionary = Core.case_by_id(manifest.rows, "R9.GEO.ZERO.v1")
	var setup: Dictionary = Core.make_snapshot(zero)
	_check(bool(setup.get("valid", false)), "zero_ledger_snapshot_valid")
	if not setup.get("valid", false):
		_finish("BLOCKED", "zero_snapshot_failed")
		return
	var built: Dictionary = _build_adaptive(setup.snapshot)
	_check(bool(built.get("valid", false)), "zero_adaptive_dc_build_within_stop_loss")
	if not built.get("valid", false):
		_finish("BLOCKED", String(built.get("reason", "zero_build_failed")), built)
		return
	var topo: Dictionary = Core.topology(built.mesh, ROI_MIN, ROI_MIN + Vector3(ROI_CELLS) * STEP)
	print("R9B_ZERO " + JSON.stringify({"mesh_sha256": built.mesh_sha256, "metrics": built.metrics, "topology": topo}))
	_check(int(topo.internal_open_edges) == 0, "zero_dc_mesh_has_no_internal_open_edges")
	_check(int(topo.nonmanifold_edges) == 0, "zero_dc_mesh_has_no_nonmanifold_edges")
	if int(topo.internal_open_edges) != 0 or int(topo.nonmanifold_edges) != 0:
		_finish("BLOCKED", "zero_topology_gate_failed", {"topology": topo})
		return
	_finish("BLOCKED", "bounded_candidate_does_not_yet_emit_frozen_chunk_transition_oracles", {"topology": topo})

func _build_adaptive(snapshot: Dictionary) -> Dictionary:
	var begin: int = Time.get_ticks_usec()
	var cells: Vector3i = ROI_CELLS
	var dims: Vector3i = cells + Vector3i.ONE
	var coarse := PackedFloat32Array()
	coarse.resize(dims.x * dims.y * dims.z)
	var samples: Dictionary = {}
	for y in range(dims.y):
		for z in range(dims.z):
			for x in range(dims.x):
				var p: Vector3 = ROI_MIN + Vector3(x, y, z) * STEP
				var d: float = Core.sample(p, snapshot)
				if not is_finite(d): return {"valid": false, "reason": "nonfinite_coarse_density"}
				coarse[_index(x,y,z,dims)] = d
				samples[_fine_key(Vector3i(x*2,y*2,z*2))] = d
				if samples.size() > MAX_NODES: return _stop("unique_sample_stop_loss", samples.size(), begin)
	var vertices: Dictionary = {}
	var active_cells := 0
	var refined_cells := 0
	for y in range(cells.y):
		for z in range(cells.z):
			for x in range(cells.x):
				var corners: Array[float] = []
				for c in Core.GRID_CORNERS:
					corners.append(float(coarse[_index(x+c.x,y+c.y,z+c.z,dims)]))
				if not _has_crossing(corners): continue
				active_cells += 1
				# One local refinement level only for sign-active cells.
				for fy in range(3):
					for fz in range(3):
						for fx in range(3):
							var coord := Vector3i(x*2+fx,y*2+fy,z*2+fz)
							var key: String = _fine_key(coord)
							if samples.has(key): continue
							if samples.size() >= MAX_NODES: return _stop("unique_sample_stop_loss", samples.size(), begin)
							var p: Vector3 = ROI_MIN + Vector3(coord) * (STEP*0.5)
							var d: float = Core.sample(p, snapshot)
							if not is_finite(d): return {"valid": false, "reason": "nonfinite_refined_density"}
							samples[key] = d
					refined_cells += 1
				var qef: Dictionary = _cell_qef(x,y,z,samples)
				if not qef.get("valid", false): return {"valid": false, "reason": "qef_has_no_constraints"}
				vertices[_cell_key(x,y,z)] = qef.position
				if Time.get_ticks_usec()-begin > MAX_USEC: return _stop("time_stop_loss", samples.size(), begin)
	var mesh: Dictionary = Core.new_mesh()
	var quad_count := 0
	for y in range(dims.y):
		for z in range(dims.z):
			for x in range(cells.x):
				if _cross(float(coarse[_index(x,y,z,dims)]),float(coarse[_index(x+1,y,z,dims)])):
					quad_count += _emit_quad(mesh,vertices,[Vector3i(x,y-1,z-1),Vector3i(x,y,z-1),Vector3i(x,y,z),Vector3i(x,y-1,z)],Vector3.RIGHT if coarse[_index(x,y,z,dims)]>=0.0 else Vector3.LEFT)
	for y in range(cells.y):
		for z in range(dims.z):
			for x in range(dims.x):
				if _cross(float(coarse[_index(x,y,z,dims)]),float(coarse[_index(x,y+1,z,dims)])):
					quad_count += _emit_quad(mesh,vertices,[Vector3i(x-1,y,z-1),Vector3i(x-1,y,z),Vector3i(x,y,z),Vector3i(x,y,z-1)],Vector3.UP if coarse[_index(x,y,z,dims)]>=0.0 else Vector3.DOWN)
	for y in range(dims.y):
		for z in range(cells.z):
			for x in range(dims.x):
				if _cross(float(coarse[_index(x,y,z,dims)]),float(coarse[_index(x,y,z+1,dims)])):
					quad_count += _emit_quad(mesh,vertices,[Vector3i(x-1,y-1,z),Vector3i(x,y-1,z),Vector3i(x,y,z),Vector3i(x-1,y,z)],Vector3.BACK if coarse[_index(x,y,z,dims)]>=0.0 else Vector3.FORWARD)
				if mesh.positions.size()/3 > MAX_TRIANGLES: return _stop("triangle_stop_loss", samples.size(), begin)
	return {"valid": true, "mesh": mesh, "mesh_sha256": _mesh_sha(mesh), "metrics": {"coarse_nodes": dims.x*dims.y*dims.z, "unique_samples": samples.size(), "active_parent_cells": active_cells, "refined_parent_cells": refined_cells, "dc_vertices": vertices.size(), "quads": quad_count, "triangles": mesh.positions.size()/3, "sample_usec": Time.get_ticks_usec()-begin, "total_usec": Time.get_ticks_usec()-begin, "extraction": "one-level adaptive Hermite constraints; parent-cell QEF and dual connectivity"}}

func _cell_qef(x: int,y: int,z: int,samples: Dictionary) -> Dictionary:
	var ata: Array = [[0.0,0.0,0.0],[0.0,0.0,0.0],[0.0,0.0,0.0]]
	var atb := Vector3.ZERO
	var point_sum := Vector3.ZERO
	var count := 0
	for cy in range(2):
		for cz in range(2):
			for cx in range(2):
				var values: Array[float] = []
				for c in Core.GRID_CORNERS:
					var fc := Vector3i(x*2+cx+c.x,y*2+cy+c.y,z*2+cz+c.z)
					values.append(float(samples[_fine_key(fc)]))
				var origin := Vector3(x+cx*0.5,y+cy*0.5,z+cz*0.5)
				for edge in Core.GRID_EDGES:
					var ia: int = edge.x; var ib: int = edge.y
					var da: float = values[ia]; var db: float = values[ib]
					if not _cross(da,db): continue
					var t: float = clampf(da/(da-db),0.0,1.0)
					var ca: Vector3i = Core.GRID_CORNERS[ia]; var cb: Vector3i = Core.GRID_CORNERS[ib]
					var uvw: Vector3 = Vector3(ca).lerp(Vector3(cb),t)
					var local_p: Vector3 = origin + uvw*0.5
					var normal: Vector3 = _trilinear_gradient(values,uvw,STEP*0.5).normalized()
					if normal.length_squared() < 0.5: continue
					var world_p: Vector3 = ROI_MIN + local_p*STEP
					var dplane: float = normal.dot(world_p)
					for i in range(3):
						atb[i] += normal[i]*dplane
						for j in range(3): ata[i][j] += normal[i]*normal[j]
					point_sum += world_p; count += 1
	if count == 0: return {"valid": false}
	var center: Vector3 = ROI_MIN + (Vector3(x,y,z)+Vector3.ONE*0.5)*STEP
	var lambda := 1.0e-8
	for i in range(3): ata[i][i] += lambda; atb[i] += lambda*center[i]
	var pos: Vector3 = _solve3(ata,atb,point_sum/float(count))
	pos.x=clampf(pos.x,ROI_MIN.x+x*STEP,ROI_MIN.x+(x+1)*STEP)
	pos.y=clampf(pos.y,ROI_MIN.y+y*STEP,ROI_MIN.y+(y+1)*STEP)
	pos.z=clampf(pos.z,ROI_MIN.z+z*STEP,ROI_MIN.z+(z+1)*STEP)
	return {"valid": pos.is_finite(), "position": pos}

func _trilinear_gradient(v:Array[float],p:Vector3,h:float)->Vector3:
	var u=p.x;var w=p.y;var q=p.z
	var gx=(1.0-w)*(1.0-q)*(v[1]-v[0])+w*(1.0-q)*(v[2]-v[3])+(1.0-w)*q*(v[5]-v[4])+w*q*(v[6]-v[7])
	var gy=(1.0-u)*(1.0-q)*(v[3]-v[0])+u*(1.0-q)*(v[2]-v[1])+(1.0-u)*q*(v[7]-v[4])+u*q*(v[6]-v[5])
	var gz=(1.0-u)*(1.0-w)*(v[4]-v[0])+u*(1.0-w)*(v[5]-v[1])+u*w*(v[6]-v[2])+(1.0-u)*w*(v[7]-v[3])
	return Vector3(gx,gy,gz)/h

func _solve3(a:Array,b:Vector3,fallback:Vector3)->Vector3:
	var m:Array=[]
	for i in range(3):m.append([float(a[i][0]),float(a[i][1]),float(a[i][2]),b[i]])
	for col in range(3):
		var pivot:=col
		for row in range(col+1,3):
			if absf(float(m[row][col]))>absf(float(m[pivot][col])):pivot=row
		if absf(float(m[pivot][col]))<1.0e-14:return fallback
		var tmp=m[col];m[col]=m[pivot];m[pivot]=tmp
		var scale:float=float(m[col][col]);for j in range(col,4):m[col][j]=float(m[col][j])/scale
		for row in range(3):
			if row==col:continue
			var f:float=float(m[row][col]);for j in range(col,4):m[row][j]=float(m[row][j])-f*float(m[col][j])
	return Vector3(float(m[0][3]),float(m[1][3]),float(m[2][3]))

func _emit_quad(mesh:Dictionary,vertices:Dictionary,keys:Array[Vector3i],toward:Vector3)->int:
	var points:Array[Vector3]=[]
	for k in keys:
		var key:=_cell_key(k.x,k.y,k.z)
		if not vertices.has(key):return 0
		points.append(vertices[key])
	var emitted:=0
	if Core.add_triangle(mesh,points[0],points[1],points[2],toward,TETRA_CUTOFF):emitted+=1
	if Core.add_triangle(mesh,points[0],points[2],points[3],toward,TETRA_CUTOFF):emitted+=1
	return emitted

func _cross(a:float,b:float)->bool:return (a>=0.0)!=(b>=0.0)
func _has_crossing(v:Array[float])->bool:
	var pos:=false;var neg:=false
	for d in v:if d>=0.0:pos=true
	else:neg=true
	return pos and neg
func _index(x:int,y:int,z:int,d:Vector3i)->int:return (y*d.z+z)*d.x+x
func _fine_key(v:Vector3i)->String:return "%d,%d,%d" % [v.x,v.y,v.z]
func _cell_key(x:int,y:int,z:int)->String:return "%d,%d,%d" % [x,y,z]
func _stop(reason:String,nodes:int,begin:int)->Dictionary:return {"valid":false,"reason":reason,"observed_unique_nodes":nodes,"elapsed_usec":Time.get_ticks_usec()-begin}
func _mesh_sha(mesh:Dictionary)->String:
	var ctx:=HashingContext.new();ctx.start(HashingContext.HASH_SHA256);ctx.update(mesh.positions.to_byte_array());ctx.update(mesh.normals.to_byte_array());return ctx.finish().hex_encode()
func _check(ok:bool,label:String)->void:
	_assertions+=1
	if not ok:_failures.append(label)
func _finish(status:String,reason:String,details:Dictionary={}) -> void:
	var final_status: String = status if _failures.is_empty() else "BLOCKED"
	print("P3_1_R9B_RESULT "+JSON.stringify({"candidate":"B","algorithm":"one-level adaptive Hermite/QEF dual contouring with parent-cell dual connectivity","status":final_status,"reason":reason,"details":details,"assertions":_assertions,"failures":_failures,"duration_usec":Time.get_ticks_usec()-_started,"manifest_sha256":Core.EXPECTED_MANIFEST_SHA,"product_tolerance":"NONE_APPROVED","physics_server":"NOT_RUN","gui":"NOT_RUN"}))
	quit(0 if final_status=="PASS" else 1)
