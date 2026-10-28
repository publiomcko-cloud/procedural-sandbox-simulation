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
	var begin:int=Time.get_ticks_usec()
	# Surface Nets quads around a primal edge need all four incident dual cells.
	# Sample a one-cell halo but only create quads for primal edges on the frozen
	# core lattice. This closes the artificial interior holes at the ROI boundary
	# without changing the canonical scalar field or its classification.
	var padded_cells:Vector3i=CELLS+Vector3i(2,2,2)
	var dims:Vector3i=padded_cells+Vector3i.ONE
	var node_count:int=dims.x*dims.y*dims.z
	if node_count>MAX_NODES:return {"valid":false,"reason":"sample_node_stop_loss","nodes":node_count}
	var values:=PackedFloat32Array();values.resize(dims.x*dims.y*dims.z)
	for y in range(dims.y):
		for z in range(dims.z):
			for x in range(dims.x):
				var p:Vector3=ROI_MIN+Vector3(x-1,y-1,z-1)*STEP;var d:float=Core.sample(p,snapshot)
				if not is_finite(d):return {"valid":false,"reason":"nonfinite_density"}
				values[_idx(x,y,z,dims)]=d
				if Time.get_ticks_usec()-begin>MAX_USEC:return {"valid":false,"reason":"time_stop_loss","unique_nodes":_idx(x,y,z,dims)+1}
	var vertices:Dictionary={};var roots:=0;var active:=0
	for y in range(padded_cells.y):
		for z in range(padded_cells.z):
			for x in range(padded_cells.x):
				var pts:Array[Vector3]=[];var ds:Array[float]=[]
				for c in Core.GRID_CORNERS:
					pts.append(ROI_MIN+Vector3(x-1+c.x,y-1+c.y,z-1+c.z)*STEP);ds.append(float(values[_idx(x+c.x,y+c.y,z+c.z,dims)]))
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
					vertices[_key(x-1,y-1,z-1)]=center/float(crossings.size());active+=1
				if Time.get_ticks_usec()-begin>MAX_USEC:return {"valid":false,"reason":"time_stop_loss","active_cells":active}
	var mesh:Dictionary=Core.new_mesh();var quads:=0;var failed_quads:=0
	# X-directed primal edges on the core node lattice.
	for y in range(CELLS.y+1):
		for z in range(CELLS.z+1):
			for x in range(CELLS.x):
				var ax:=x+1;var ay:=y+1;var az:=z+1
				if _cross(float(values[_idx(ax,ay,az,dims)]),float(values[_idx(ax+1,ay,az,dims)])):
					var emitted:=_quad(mesh,vertices,[Vector3i(x,y-1,z-1),Vector3i(x,y,z-1),Vector3i(x,y,z),Vector3i(x,y-1,z)],Vector3.RIGHT if values[_idx(ax,ay,az,dims)]>=0.0 else Vector3.LEFT)
					if emitted<0:return {"valid":false,"reason":"surface_nets_quad_untriangulable","axis":"x","edge":Vector3i(x,y,z)}
					quads+=emitted
	# Y-directed primal edges.
	for y in range(CELLS.y):
		for z in range(CELLS.z+1):
			for x in range(CELLS.x+1):
				var ax:=x+1;var ay:=y+1;var az:=z+1
				if _cross(float(values[_idx(ax,ay,az,dims)]),float(values[_idx(ax,ay+1,az,dims)])):
					var emitted:=_quad(mesh,vertices,[Vector3i(x-1,y,z-1),Vector3i(x-1,y,z),Vector3i(x,y,z),Vector3i(x,y,z-1)],Vector3.UP if values[_idx(ax,ay,az,dims)]>=0.0 else Vector3.DOWN)
					if emitted<0:return {"valid":false,"reason":"surface_nets_quad_untriangulable","axis":"y","edge":Vector3i(x,y,z)}
					quads+=emitted
	# Z-directed primal edges.
	for y in range(CELLS.y+1):
		for z in range(CELLS.z):
			for x in range(CELLS.x+1):
				var ax:=x+1;var ay:=y+1;var az:=z+1
				if _cross(float(values[_idx(ax,ay,az,dims)]),float(values[_idx(ax,ay,az+1,dims)])):
					var emitted:=_quad(mesh,vertices,[Vector3i(x-1,y-1,z),Vector3i(x,y-1,z),Vector3i(x,y,z),Vector3i(x-1,y,z)],Vector3.BACK if values[_idx(ax,ay,az,dims)]>=0.0 else Vector3.FORWARD)
					if emitted<0:return {"valid":false,"reason":"surface_nets_quad_untriangulable","axis":"z","edge":Vector3i(x,y,z)}
					quads+=emitted
				if mesh.positions.size()/3>MAX_TRIANGLES:return {"valid":false,"reason":"triangle_stop_loss","unique_nodes":values.size()}
				if Time.get_ticks_usec()-begin>MAX_USEC:return {"valid":false,"reason":"time_stop_loss","unique_nodes":values.size()}
	return {"valid":true,"mesh":mesh,"mesh_sha256":_hash_mesh(mesh),"topology_bounds_min":ROI_MIN-Vector3.ONE*STEP*0.5,"topology_bounds_max":ROI_MIN+Vector3(CELLS)*STEP+Vector3.ONE*STEP*0.5,"metrics":{"unique_samples":values.size(),"active_cells":active,"linear_crossing_constraints":roots,"quads":quads,"failed_quads":failed_quads,"triangles":mesh.positions.size()/3,"build_usec":Time.get_ticks_usec()-begin,"representation":"one Surface Nets vertex per sign-active cell; one-cell scalar halo supplies all four dual cells around core-lattice primal edges"}}

func _quad(mesh:Dictionary,vertices:Dictionary,keys:Array[Vector3i],toward:Vector3)->int:
	var p:Array[Vector3]=[]
	for c in keys:
		var k:=_key(c.x,c.y,c.z)
		if not vertices.has(k):return -1
		p.append(vertices[k])
	var diagonal_a:=_triangle_area_ok(p[0],p[1],p[2]) and _triangle_area_ok(p[0],p[2],p[3])
	var diagonal_b:=_triangle_area_ok(p[0],p[1],p[3]) and _triangle_area_ok(p[1],p[2],p[3])
	if not diagonal_a and not diagonal_b:return -1
	if diagonal_a:
		if not Core.add_triangle(mesh,p[0],p[1],p[2],toward,1.0e-12):return -1
		if not Core.add_triangle(mesh,p[0],p[2],p[3],toward,1.0e-12):return -1
	else:
		if not Core.add_triangle(mesh,p[0],p[1],p[3],toward,1.0e-12):return -1
		if not Core.add_triangle(mesh,p[1],p[2],p[3],toward,1.0e-12):return -1
	return 2

func _triangle_area_ok(a:Vector3,b:Vector3,c:Vector3)->bool:
	var cross:Vector3=(b-a).cross(c-a)
	return cross.is_finite() and cross.length_squared()>1.0e-12
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
