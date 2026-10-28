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
const FACE_CORNERS: Array[Array] = [[0,1,2,3],[4,5,6,7],[0,1,5,4],[3,2,6,7],[0,3,7,4],[1,2,6,5]]
const FACE_EDGES: Array[Array] = [[0,1,2,3],[4,5,6,7],[0,9,4,8],[2,10,6,11],[3,11,7,8],[1,10,5,9]]
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
	var vertices:Dictionary={};var edge_vertices:Dictionary={};var roots:=0;var active:=0;var split_cells:=0
	for y in range(padded_cells.y):
		for z in range(padded_cells.z):
			for x in range(padded_cells.x):
				var pts:Array[Vector3]=[];var ds:Array[float]=[]
				for c in Core.GRID_CORNERS:
					pts.append(ROI_MIN+Vector3(x-1+c.x,y-1+c.y,z-1+c.z)*STEP);ds.append(float(values[_idx(x+c.x,y+c.y,z+c.z,dims)]))
				var lo:=INF;var hi:=-INF
				for d in ds:lo=minf(lo,d);hi=maxf(hi,d)
				if lo>=0.0 or hi<0.0:continue
				var cell_coord:=Vector3i(x-1,y-1,z-1)
				var component_result:Dictionary=_cell_surface_components(cell_coord,pts,ds,vertices,edge_vertices)
				if not component_result.get("valid",false):return {"valid":false,"reason":"surface_nets_component_build_failed","detail":component_result}
				roots+=int(component_result.get("crossing_edges",0));active+=1
				split_cells+=1 if int(component_result.get("component_count",0))>1 else 0
				if Time.get_ticks_usec()-begin>MAX_USEC:return {"valid":false,"reason":"time_stop_loss","active_cells":active}
	var mesh:Dictionary=Core.new_mesh();var quads:=0;var failed_quads:=0
	# X-directed primal edges on the core node lattice.
	for y in range(CELLS.y+1):
		for z in range(CELLS.z+1):
			for x in range(CELLS.x):
				var ax:=x+1;var ay:=y+1;var az:=z+1
				if _cross(float(values[_idx(ax,ay,az,dims)]),float(values[_idx(ax+1,ay,az,dims)])):
					var emitted:=_quad_for_crossing(mesh,vertices,edge_vertices,[Vector3i(x,y-1,z-1),Vector3i(x,y,z-1),Vector3i(x,y,z),Vector3i(x,y-1,z)],[6,4,0,2],Vector3.RIGHT if values[_idx(ax,ay,az,dims)]>=0.0 else Vector3.LEFT)
					if emitted<0:return {"valid":false,"reason":"surface_nets_quad_untriangulable","axis":"x","edge":Vector3i(x,y,z)}
					quads+=emitted
	# Y-directed primal edges.
	for y in range(CELLS.y):
		for z in range(CELLS.z+1):
			for x in range(CELLS.x+1):
				var ax:=x+1;var ay:=y+1;var az:=z+1
				if _cross(float(values[_idx(ax,ay,az,dims)]),float(values[_idx(ax,ay+1,az,dims)])):
					var emitted:=_quad_for_crossing(mesh,vertices,edge_vertices,[Vector3i(x-1,y,z-1),Vector3i(x-1,y,z),Vector3i(x,y,z),Vector3i(x,y,z-1)],[5,1,3,7],Vector3.UP if values[_idx(ax,ay,az,dims)]>=0.0 else Vector3.DOWN)
					if emitted<0:return {"valid":false,"reason":"surface_nets_quad_untriangulable","axis":"y","edge":Vector3i(x,y,z)}
					quads+=emitted
	# Z-directed primal edges.
	for y in range(CELLS.y+1):
		for z in range(CELLS.z):
			for x in range(CELLS.x+1):
				var ax:=x+1;var ay:=y+1;var az:=z+1
				if _cross(float(values[_idx(ax,ay,az,dims)]),float(values[_idx(ax,ay,az+1,dims)])):
					var emitted:=_quad_for_crossing(mesh,vertices,edge_vertices,[Vector3i(x-1,y-1,z),Vector3i(x,y-1,z),Vector3i(x,y,z),Vector3i(x-1,y,z)],[10,11,8,9],Vector3.BACK if values[_idx(ax,ay,az,dims)]>=0.0 else Vector3.FORWARD)
					if emitted<0:return {"valid":false,"reason":"surface_nets_quad_untriangulable","axis":"z","edge":Vector3i(x,y,z)}
					quads+=emitted
				if mesh.positions.size()/3>MAX_TRIANGLES:return {"valid":false,"reason":"triangle_stop_loss","unique_nodes":values.size()}
				if Time.get_ticks_usec()-begin>MAX_USEC:return {"valid":false,"reason":"time_stop_loss","unique_nodes":values.size()}
	return {"valid":true,"mesh":mesh,"mesh_sha256":_hash_mesh(mesh),"topology_bounds_min":ROI_MIN-Vector3.ONE*STEP*0.5,"topology_bounds_max":ROI_MIN+Vector3(CELLS)*STEP+Vector3.ONE*STEP*0.5,"metrics":{"unique_samples":values.size(),"active_cells":active,"split_component_cells":split_cells,"linear_crossing_constraints":roots,"quads":quads,"failed_quads":failed_quads,"triangles":mesh.positions.size()/3,"build_usec":Time.get_ticks_usec()-begin,"representation":"face-decided multi-component Surface Nets; one vertex per connected local contour component; one-cell scalar halo supplies all four dual cells around core-lattice primal edges"}}

func _cell_surface_components(cell:Vector3i,points:Array[Vector3],values:Array[float],vertices:Dictionary,edge_vertices:Dictionary)->Dictionary:
	var crossing:=PackedByteArray();crossing.resize(Core.GRID_EDGES.size())
	var edge_points:Dictionary={};var parent:=PackedInt32Array();parent.resize(Core.GRID_EDGES.size())
	for i in range(parent.size()):parent[i]=i
	var crossing_count:=0
	for edge_id in range(Core.GRID_EDGES.size()):
		var edge:Vector2i=Core.GRID_EDGES[edge_id];var da:float=values[edge.x];var db:float=values[edge.y]
		if (da>=0.0)==(db>=0.0):continue
		var t:float=clampf(da/(da-db),0.0,1.0);edge_points[edge_id]=points[edge.x].lerp(points[edge.y],t)
		crossing[edge_id]=1;crossing_count+=1
	if crossing_count==0:return {"valid":false,"reason":"active_cell_without_edge_crossing","cell":cell}
	for face_index in range(FACE_CORNERS.size()):
		var corners:Array=FACE_CORNERS[face_index];var edges:Array=FACE_EDGES[face_index];var crossed:Array[int]=[]
		for local_index in range(4):
			if crossing[int(edges[local_index])]!=0:crossed.append(local_index)
		if crossed.size()==2:
			_union_edges(parent,int(edges[crossed[0]]),int(edges[crossed[1]]))
		elif crossed.size()==4:
			# Shared-face bilinear asymptotic decider. Face center sign is not
			# sufficient when corner magnitudes are asymmetric; evaluate the exact
			# bilinear saddle value (a*c-b*d)/(a-b-d+c) instead.
			var pairs:Array=_checkerboard_face_edge_pairs(corners,edges,values)
			if pairs.is_empty():return {"valid":false,"reason":"checkerboard_face_decider_invalid","cell":cell,"face":face_index}
			for pair in pairs:_union_edges(parent,int(pair[0]),int(pair[1]))
	var groups:Dictionary={}
	for edge_id in range(crossing.size()):
		if crossing[edge_id]==0:continue
		var root:int=_find_root(parent,edge_id)
		if not groups.has(root):groups[root]=[]
		groups[root].append(edge_id)
	var roots:Array=groups.keys();roots.sort();var component_count:=0
	for root in roots:
		var edge_ids:Array=groups[root];edge_ids.sort();var center:=Vector3.ZERO
		for edge_id in edge_ids:center+=edge_points[int(edge_id)]
		var vertex_key:String=_key(cell.x,cell.y,cell.z)+"#"+str(int(edge_ids[0]))
		vertices[vertex_key]=center/float(edge_ids.size())
		for edge_id in edge_ids:edge_vertices[_key(cell.x,cell.y,cell.z)+"|"+str(int(edge_id))]=vertex_key
		component_count+=1
	return {"valid":component_count>0,"crossing_edges":crossing_count,"component_count":component_count}

func _checkerboard_face_edge_pairs(corners:Array,edges:Array,values:Array[float])->Array:
	if corners.size()!=4 or edges.size()!=4:return []
	var a:float=values[int(corners[0])];var b:float=values[int(corners[1])]
	var c:float=values[int(corners[2])];var d:float=values[int(corners[3])]
	var denominator:float=a-b-d+c
	if not is_finite(denominator) or denominator==0.0:return []
	var saddle:float=(a*c-b*d)/denominator
	if not is_finite(saddle):return []
	# The shared face corners use the same cyclic global order in neighboring
	# cells. A zero saddle follows the canonical nonnegative/solid ownership.
	if (saddle>=0.0)==(a>=0.0):
		return [[int(edges[0]),int(edges[1])],[int(edges[2]),int(edges[3])]]
	return [[int(edges[3]),int(edges[0])],[int(edges[1]),int(edges[2])]]

func checkerboard_decider_regression()->Dictionary:
	# Here the center average is negative, while the exact bilinear saddle is
	# positive. The previous center-sign shortcut therefore selected the other
	# contour pairing. Construct both sides of an X face using their local cube
	# edge IDs, then map the resulting pairs back to the shared physical cycle.
	var values:Array[float]=[1.0,-100.0,1.0,-0.005]
	var left_values:Array[float]=[0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0]
	var right_values:Array[float]=[0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0]
	for i in range(4):
		left_values[int(FACE_CORNERS[5][i])]=values[i]
		right_values[int(FACE_CORNERS[4][i])]=values[i]
	var left_pairs:Array=_checkerboard_face_edge_pairs(FACE_CORNERS[5],FACE_EDGES[5],left_values)
	var right_pairs:Array=_checkerboard_face_edge_pairs(FACE_CORNERS[4],FACE_EDGES[4],right_values)
	var left_slots:Array=_map_face_edge_pairs_to_slots(left_pairs,FACE_EDGES[5])
	var right_slots:Array=_map_face_edge_pairs_to_slots(right_pairs,FACE_EDGES[4])
	var center_value:float=(values[0]+values[1]+values[2]+values[3])*0.25
	var saddle:float=(values[0]*values[2]-values[1]*values[3])/(values[0]-values[1]-values[3]+values[2])
	var expected:Array=[[0,1],[2,3]]
	return {"valid":center_value<0.0 and saddle>0.0 and left_slots==expected and right_slots==expected,
		"corner_values":values,"center_value":center_value,"saddle_value":saddle,"left_face_pairs":left_slots,"right_face_pairs":right_slots,
		"expected_pairs":expected,"reason":"bilinear_saddle_not_face_center"}

func _map_face_edge_pairs_to_slots(pairs:Array,face_edges:Array)->Array:
	var mapped:Array=[]
	for pair in pairs:
		var a:int=face_edges.find(int(pair[0]));var b:int=face_edges.find(int(pair[1]))
		if a<0 or b<0:return []
		var ordered:Array=[a,b];ordered.sort();mapped.append(ordered)
	mapped.sort_custom(func(left:Array,right:Array)->bool:
		if int(left[0])!=int(right[0]):return int(left[0])<int(right[0])
		return int(left[1])<int(right[1]))
	return mapped

func _find_root(parent:PackedInt32Array,node:int)->int:
	var root:int=node
	while parent[root]!=root:root=parent[root]
	while parent[node]!=node:
		var next:int=parent[node];parent[node]=root;node=next
	return root

func _union_edges(parent:PackedInt32Array,a:int,b:int)->void:
	var root_a:int=_find_root(parent,a);var root_b:int=_find_root(parent,b)
	if root_a==root_b:return
	if root_a<root_b:parent[root_b]=root_a
	else:parent[root_a]=root_b

func _quad_for_crossing(mesh:Dictionary,vertices:Dictionary,edge_vertices:Dictionary,cells:Array,local_edges:Array,toward:Vector3)->int:
	var p:Array[Vector3]=[]
	for i in range(cells.size()):
		var c:Vector3i=cells[i];var slot:String=_key(c.x,c.y,c.z)+"|"+str(int(local_edges[i]))
		if not edge_vertices.has(slot):return -1
		var vertex_key:String=String(edge_vertices[slot])
		if not vertices.has(vertex_key):return -1
		p.append(vertices[vertex_key])
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
