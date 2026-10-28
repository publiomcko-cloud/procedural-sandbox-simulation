extends SceneTree

## R9-C test-only Surface Nets prototype. One active-cell vertex is the mean
## of linearly interpolated canonical grid-edge crossings. No independent
## per-vertex noise or production mesh code is used.
const Core := preload("res://tests/prototypes/p3_1_r9_experiment_base.gd")
const ROI_MIN := Vector3(8.0,-2.0,3.0)
const CELLS := Vector3i(8,20,12)
const STEP := 0.5
const MAX_NODES := 10000
const MAX_TRIANGLES := 20000
const MAX_USEC := 600000000
var _started := 0
var _assertions := 0
var _failures: Array[String] = []

func _initialize() -> void:
	_started=Time.get_ticks_usec();call_deferred("_run")

func _run() -> void:
	var manifest:Dictionary=Core.load_manifest()
	_check(bool(manifest.get("valid",false)),"frozen_manifest_verified")
	if not manifest.get("valid",false):_finish("BLOCKED","manifest_preflight_failed");return
	var row:Dictionary=Core.case_by_id(manifest.rows,"R9.GEO.ZERO.v1")
	var setup:Dictionary=Core.make_snapshot(row)
	_check(bool(setup.get("valid",false)),"zero_ledger_snapshot_valid")
	if not setup.get("valid",false):_finish("BLOCKED","zero_snapshot_failed");return
	var built:Dictionary=_build(setup.snapshot)
	_check(bool(built.get("valid",false)),"zero_surface_nets_build_within_stop_loss")
	if not built.get("valid",false):_finish("BLOCKED",String(built.get("reason","zero_build_failed")),built);return
	var topo:Dictionary=Core.topology(built.mesh,ROI_MIN,ROI_MIN+Vector3(CELLS)*STEP)
	print("R9C_ZERO "+JSON.stringify({"mesh_sha256":built.mesh_sha256,"metrics":built.metrics,"topology":topo}))
	_check(int(topo.internal_open_edges)==0,"zero_surface_nets_no_internal_open_edges")
	_check(int(topo.nonmanifold_edges)==0,"zero_surface_nets_no_nonmanifold_edges")
	if int(topo.internal_open_edges)!=0 or int(topo.nonmanifold_edges)!=0:
		_finish("BLOCKED","zero_topology_gate_failed",{"topology":topo});return
	var second:Dictionary=_build(setup.snapshot)
	_check(bool(second.get("valid",false)) and String(second.get("mesh_sha256",""))==String(built.mesh_sha256),"zero_surface_nets_repeat_deterministic")
	if not _failures.is_empty():_finish("BLOCKED","determinism_gate_failed",{"topology":topo});return
	_finish("BLOCKED","frozen_seam_and_edit_cases_not_yet_implemented",{"topology":topo,"zero_metrics":built.metrics})

func _build(snapshot:Dictionary)->Dictionary:
	var begin:int=Time.get_ticks_usec();var dims:Vector3i=CELLS+Vector3i.ONE
	var values:=PackedFloat32Array();values.resize(dims.x*dims.y*dims.z)
	for y in range(dims.y):
		for z in range(dims.z):
			for x in range(dims.x):
				var p:Vector3=ROI_MIN+Vector3(x,y,z)*STEP;var d:float=Core.sample(p,snapshot)
				if not is_finite(d):return {"valid":false,"reason":"nonfinite_density"}
				values[_idx(x,y,z,dims)]=d
				if Time.get_ticks_usec()-begin>MAX_USEC:return {"valid":false,"reason":"time_stop_loss","unique_nodes":_idx(x,y,z,dims)+1}
	var vertices:Dictionary={};var roots:=0;var active:=0
	for y in range(CELLS.y):
		for z in range(CELLS.z):
			for x in range(CELLS.x):
				var pts:Array[Vector3]=[];var ds:Array[float]=[]
				for c in Core.GRID_CORNERS:
					pts.append(ROI_MIN+Vector3(x+c.x,y+c.y,z+c.z)*STEP);ds.append(float(values[_idx(x+c.x,y+c.y,z+c.z,dims)]))
				var lo:=INF;var hi:=-INF
				for d in ds:lo=minf(lo,d);hi=maxf(hi,d)
				if lo>=0.0 or hi<0.0:continue
				var crossings:Array[Vector3]=[]
				for edge in Core.GRID_EDGES:
					var a:int=edge.x;var b:int=edge.y;var da:float=ds[a];var db:float=ds[b]
					if (da>=0.0)==(db>=0.0):continue
					var t:float=clampf(da/(da-db),0.0,1.0);crossings.append(pts[a].lerp(pts[b],t));roots+=1
				if not crossings.is_empty():
					var center:=Vector3.ZERO
					for p in crossings:center+=p
					vertices[_key(x,y,z)]=center/float(crossings.size());active+=1
	var mesh:Dictionary=Core.new_mesh();var quads:=0
	for y in range(dims.y):
		for z in range(dims.z):
			for x in range(CELLS.x):
				if _cross(float(values[_idx(x,y,z,dims)]),float(values[_idx(x+1,y,z,dims)])):
					quads+=_quad(mesh,vertices,[Vector3i(x,y-1,z-1),Vector3i(x,y,z-1),Vector3i(x,y,z),Vector3i(x,y-1,z)],Vector3.RIGHT if values[_idx(x,y,z,dims)]>=0.0 else Vector3.LEFT)
	for y in range(CELLS.y):
		for z in range(dims.z):
			for x in range(dims.x):
				if _cross(float(values[_idx(x,y,z,dims)]),float(values[_idx(x,y+1,z,dims)])):
					quads+=_quad(mesh,vertices,[Vector3i(x-1,y,z-1),Vector3i(x-1,y,z),Vector3i(x,y,z),Vector3i(x,y,z-1)],Vector3.UP if values[_idx(x,y,z,dims)]>=0.0 else Vector3.DOWN)
	for y in range(dims.y):
		for z in range(CELLS.z):
			for x in range(dims.x):
				if _cross(float(values[_idx(x,y,z,dims)]),float(values[_idx(x,y,z+1,dims)])):
					quads+=_quad(mesh,vertices,[Vector3i(x-1,y-1,z),Vector3i(x,y-1,z),Vector3i(x,y,z),Vector3i(x-1,y,z)],Vector3.BACK if values[_idx(x,y,z,dims)]>=0.0 else Vector3.FORWARD)
				if mesh.positions.size()/3>MAX_TRIANGLES:return {"valid":false,"reason":"triangle_stop_loss","unique_nodes":values.size()}
	return {"valid":true,"mesh":mesh,"mesh_sha256":_hash_mesh(mesh),"metrics":{"unique_samples":values.size(),"active_cells":active,"linear_crossing_constraints":roots,"quads":quads,"triangles":mesh.positions.size()/3,"build_usec":Time.get_ticks_usec()-begin,"representation":"one Surface Nets vertex per sign-active cell; dual quads around sign-changing primal edges"}}

func _quad(mesh:Dictionary,vertices:Dictionary,keys:Array[Vector3i],toward:Vector3)->int:
	var p:Array[Vector3]=[]
	for c in keys:
		var k:=_key(c.x,c.y,c.z)
		if not vertices.has(k):return 0
		p.append(vertices[k])
	var n:=0
	if Core.add_triangle(mesh,p[0],p[1],p[2],toward,1.0e-12):n+=1
	if Core.add_triangle(mesh,p[0],p[2],p[3],toward,1.0e-12):n+=1
	return n
func _cross(a:float,b:float)->bool:return (a>=0.0)!=(b>=0.0)
func _idx(x:int,y:int,z:int,d:Vector3i)->int:return (y*d.z+z)*d.x+x
func _key(x:int,y:int,z:int)->String:return "%d,%d,%d"%[x,y,z]
func _hash_mesh(m:Dictionary)->String:
	var c:=HashingContext.new();c.start(HashingContext.HASH_SHA256);c.update(m.positions.to_byte_array());c.update(m.normals.to_byte_array());return c.finish().hex_encode()
func _check(ok:bool,label:String)->void:_assertions+=1;if not ok:_failures.append(label)
func _finish(status:String,reason:String,details:Dictionary={})->void:
	var final_status:String=status if _failures.is_empty() else "BLOCKED"
	print("P3_1_R9C_RESULT "+JSON.stringify({"candidate":"C","algorithm":"uniform Surface Nets with linearly interpolated active-cell representatives","status":final_status,"reason":reason,"details":details,"assertions":_assertions,"failures":_failures,"duration_usec":Time.get_ticks_usec()-_started,"manifest_sha256":Core.EXPECTED_MANIFEST_SHA,"product_tolerance":"NONE_APPROVED","physics_server":"NOT_RUN","gui":"NOT_RUN"}));quit(0 if final_status=="PASS" else 1)
