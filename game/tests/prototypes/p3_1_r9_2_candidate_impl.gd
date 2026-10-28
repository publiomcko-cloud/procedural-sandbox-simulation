extends RefCounted

## R9-C test-only Surface Nets prototype. One active-cell vertex is the mean
## of linearly interpolated canonical grid-edge crossings. No independent
## per-vertex noise or production mesh code is used.
const Core := preload("res://tests/prototypes/p3_1_r9_2_diagnostic_base.gd")
var ROI_MIN: Vector3 = Vector3(8.0,-2.0,3.0)
var CELLS: Vector3i = Vector3i(8,20,12)
var STEP: float = 0.5
const MAX_NODES := 10000
const MAX_TRIANGLES := 20000
const MAX_USEC := 60000000
var _started := 0
var _assertions := 0
var _failures: Array[String] = []

func configure_roi(roi: Dictionary) -> void:
	ROI_MIN = Core.world_min(roi)
	CELLS = Core.cell_counts(roi)
	STEP = Core.step(roi)

func build(snapshot: Dictionary, _row: Dictionary, _variant: Dictionary) -> Dictionary:
	return _build(snapshot)
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
	var position_bytes:PackedByteArray=m.positions.to_byte_array()
	var normal_bytes:PackedByteArray=m.normals.to_byte_array()
	var c:=HashingContext.new()
	c.start(HashingContext.HASH_SHA256)
	# Prefix lengths so empty arrays remain distinguishable and never call update with zero bytes.
	c.update(("%d:%d:" % [position_bytes.size(),normal_bytes.size()]).to_utf8_buffer())
	if not position_bytes.is_empty():c.update(position_bytes)
	if not normal_bytes.is_empty():c.update(normal_bytes)
	return c.finish().hex_encode()
