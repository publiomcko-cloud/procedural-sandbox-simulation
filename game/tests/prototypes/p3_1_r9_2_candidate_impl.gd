extends RefCounted

## R9-A: bounded root-aware marching tetrahedra research prototype. Explicit
## shared-face samples are owned by global lattice coordinates; this script
## does not load production scene nodes or mutate production state.
const Core := preload("res://tests/prototypes/p3_1_r9_2_diagnostic_base.gd")
const T := preload("res://scripts/experiments/lod01_transition_fixture.gd")
const Mesher := preload("res://scripts/terrain/marching_tetrahedra.gd")
const LodMesher := preload("res://scripts/terrain/lod01_chunk_mesher.gd")
const SEED := 131102026
var ROI_MIN: Vector3 = Vector3(8,-2,3)
var ROI_CELLS: Vector3i = Vector3i(8,20,12)
var STEP: float = 0.5
const ROOT_ITERATIONS := 8
var _manifest: Dictionary = {}
var _failures: Array[String] = []
var _assertions := 0
var _sample_cache: Dictionary = {}
var _root_cache: Dictionary = {}
var _started := 0

func configure_roi(roi: Dictionary) -> void:
	ROI_MIN = Core.world_min(roi)
	ROI_CELLS = Core.cell_counts(roi)
	STEP = Core.step(roi)

func build(snapshot: Dictionary, _row: Dictionary, _variant: Dictionary) -> Dictionary:
	return _build_mt(snapshot)
func _build_mt(snapshot: Dictionary) -> Dictionary:
	var begin := Time.get_ticks_usec()
	_sample_cache.clear(); _root_cache.clear()
	var dims := ROI_CELLS+Vector3i.ONE
	var total := dims.x*dims.y*dims.z
	if total > Core.MAX_NODES: return {"valid":false,"reason":"sample_node_stop_loss"}
	var values := PackedFloat32Array(); values.resize(total)
	for y in range(dims.y):
		for z in range(dims.z):
			for x in range(dims.x):
				var p := ROI_MIN+Vector3(x,y,z)*STEP
				var d := Core.sample(p,snapshot)
				if not is_finite(d): return {"valid":false,"reason":"nonfinite_grid_sample"}
				values[_node_index(x,y,z,dims)] = d
				_sample_cache[Core._point_key(p)] = d
	var mesh: Dictionary = Core.new_mesh(); var root_requests := 0; var dropped := 0
	for y in range(ROI_CELLS.y):
		for z in range(ROI_CELLS.z):
			for x in range(ROI_CELLS.x):
				var cube_points: Array[Vector3] = []; var cube_values: Array[float] = []
				for corner_value in Core.GRID_CORNERS:
					var corner: Vector3i = corner_value
					var ix: int = x+corner.x; var iy: int = y+corner.y; var iz: int = z+corner.z
					cube_points.append(ROI_MIN+Vector3(ix,iy,iz)*STEP)
					cube_values.append(float(values[_node_index(ix,iy,iz,dims)]))
				for tet in Core.TETS:
					var result := _polygonize_tet(tet,cube_points,cube_values,snapshot,mesh)
					root_requests += int(result.root_edges); dropped += int(result.dropped)
					if mesh.positions.size()/3 > Core.MAX_TRIANGLES: return {"valid":false,"reason":"triangle_stop_loss"}
					if _sample_cache.size() > Core.MAX_NODES: return {"valid":false,"reason":"unique_sample_stop_loss"}
					if Time.get_ticks_usec()-begin > int(Core.MAX_SCENARIO_USEC): return {"valid":false,"reason":"time_stop_loss"}
	return {"valid":true,"mesh":mesh,"mesh_sha256":_mesh_sha(mesh),"metrics":{"grid_nodes":total,
		"unique_canonical_samples_including_root_iterations":_sample_cache.size(),"root_iterations":ROOT_ITERATIONS,
		"root_edge_requests":root_requests,"cached_root_edges":_root_cache.size(),"cutoff_drops":dropped,
		"triangle_count":mesh.positions.size()/3,"build_usec":Time.get_ticks_usec()-begin}}

func _polygonize_tet(tet:Array,cube_points:Array[Vector3],cube_values:Array[float],snapshot:Dictionary,mesh:Dictionary)->Dictionary:
	var inside: Array[int]=[]; var outside: Array[int]=[]; var ci:=Vector3.ZERO; var co:=Vector3.ZERO
	for raw in tet:
		var i:=int(raw)
		if cube_values[i]>=0.0: inside.append(i); ci+=cube_points[i]
		else: outside.append(i); co+=cube_points[i]
	if inside.is_empty() or outside.is_empty(): return {"root_edges":0,"dropped":0}
	ci/=float(inside.size()); co/=float(outside.size()); var empty_dir:=co-ci
	var faces: Array[Array]=[]; var edges:=0
	if inside.size()==1 or outside.size()==1:
		var pivot:=inside[0] if inside.size()==1 else outside[0]
		var others: Array=outside if inside.size()==1 else inside
		var a:=_edge_root(pivot,int(others[0]),cube_points,cube_values,snapshot); var b:=_edge_root(pivot,int(others[1]),cube_points,cube_values,snapshot); var c:=_edge_root(pivot,int(others[2]),cube_points,cube_values,snapshot)
		edges=3
		if not a.valid or not b.valid or not c.valid:return {"root_edges":edges,"dropped":0}
		faces.append([a.point,b.point,c.point])
	else:
		var a:=_edge_root(inside[0],outside[0],cube_points,cube_values,snapshot); var b:=_edge_root(inside[0],outside[1],cube_points,cube_values,snapshot)
		var c:=_edge_root(inside[1],outside[0],cube_points,cube_values,snapshot); var d:=_edge_root(inside[1],outside[1],cube_points,cube_values,snapshot)
		edges=4
		if not a.valid or not b.valid or not c.valid or not d.valid:return {"root_edges":edges,"dropped":0}
		faces.append([a.point,b.point,d.point]); faces.append([a.point,d.point,c.point])
	var dropped:=0
	for tri in faces:
		if not Core.add_triangle(mesh,tri[0],tri[1],tri[2],empty_dir,1.0e-12): dropped+=1
	return {"root_edges":edges,"dropped":dropped}

func _edge_root(ai:int,bi:int,points:Array[Vector3],values:Array[float],snapshot:Dictionary)->Dictionary:
	var a:Vector3=points[ai]; var b:Vector3=points[bi]; var da:float=values[ai]; var db:float=values[bi]
	if (da<0.0)==(db<0.0):return {"valid":false}
	var ka: String=Core._point_key(a); var kb: String=Core._point_key(b); var key: String=ka+"|"+kb if ka<kb else kb+"|"+ka
	if _root_cache.has(key): return {"valid":true,"point":_root_cache[key]}
	var low:=0.0; var high:=1.0; var low_value:=da
	for iteration in range(ROOT_ITERATIONS):
		var t:float=(low+high)*0.5; var p:=a.lerp(b,t); var pk: String=Core._point_key(p)
		var dm:float=float(_sample_cache.get(pk,NAN))
		if not is_finite(dm): dm=Core.sample(p,snapshot); _sample_cache[pk]=dm
		if not is_finite(dm):return {"valid":false,"reason":"nonfinite_root_sample"}
		if dm==0.0:low=t;high=t;break
		if (dm<0.0)==(low_value<0.0): low=t;low_value=dm
		else:high=t
	var point:=a.lerp(b,(low+high)*0.5);_root_cache[key]=point
	return {"valid":true,"point":point}

func _xplus_shared_face_probe(snapshot:Dictionary)->Dictionary:
	var lattice:=Vector3i(30,4,14);var origin:=Vector3(lattice)*0.5;var center:=origin+Vector3.ONE*0.5
	var selected:Array[int]=[T.FACE_X_POS];var face_tris: Array = T._boundary_triangles(lattice,selected)
	var builder:RefCounted=T.new();var cache:Dictionary={};var mesh: Dictionary = Core.new_mesh();var dropped:=0;var generated:=0
	for face in face_tris:
		var points:Array[Vector3]=[center];points.append_array(face)
		var vals:Array[float]=[]
		for p in points:vals.append(Core.sample(p,snapshot))
		var result:=_polygonize_tet([0,1,2,3],points,vals,snapshot,mesh)
		generated+=1; dropped+=int(result.dropped)
	var actual: Dictionary = _plane_segments(mesh,0,16.0)
	var expected: Dictionary = _independent_fine_face_oracle(snapshot)
	var missing:Array[String]=[];var extra:Array[String]=[]
	for key in expected:
		if not actual.has(key):missing.append(key)
	for key in actual:
		if not expected.has(key):extra.append(key)
	return {"valid":missing.is_empty() and extra.is_empty() and expected.size()>0,"origin_lattice":lattice,
		"face_triangle_count":face_tris.size(),"tetrahedra_generated":generated,"cutoff_drops":dropped,
		"expected_segment_count":expected.size(),"actual_segment_count":actual.size(),"missing":missing,"extra":extra,
		"metrics":{"unique_samples":_sample_cache.size(),"root_iterations":ROOT_ITERATIONS},
		"oracle":"independently enumerated 0.5-unit face grid triangles and canonical sign-bracket roots; does not use candidate mesh for expectation"}

func _independent_fine_face_oracle(snapshot:Dictionary)->Dictionary:
	var segments:Dictionary={};var x:=16.0
	# X+ face spans y=[2,3], z=[7,8] at 0.5 spacing. Each square uses the
	# globally fixed lower-left to upper-right diagonal.
	for iy in range(2):
		for iz in range(2):
			var y:=2.0+float(iy)*0.5;var z:=7.0+float(iz)*0.5
			var p:= [Vector3(x,y,z),Vector3(x,y+0.5,z),Vector3(x,y+0.5,z+0.5),Vector3(x,y,z+0.5)]
			for tri in [[0,1,2],[0,2,3]]:
				var points:Array[Vector3]=[p[int(tri[0])],p[int(tri[1])],p[int(tri[2])]];var hits:Array[Vector3]=[]
				for edge in [[0,1],[1,2],[2,0]]:
					var a:Vector3=points[int(edge[0])];var b:Vector3=points[int(edge[1])];var da:float=Core.sample(a,snapshot);var db:float=Core.sample(b,snapshot)
					if da==0.0:hits.append(a)
					elif db==0.0:hits.append(b)
					elif (da<0.0)!=(db<0.0):
						var root:=_edge_root_for_oracle(a,b,da,db,snapshot)
						if root.valid:hits.append(root.point)
				var unique:Array[Vector3]=[]
				for h in hits:
					var duplicate:=false
					for q in unique:
						if h.distance_squared_to(q)<1.0e-12:duplicate=true;break
					if not duplicate:unique.append(h)
				if unique.size()==2:
					var akey: String=Core._point_key(unique[0]);var bkey: String=Core._point_key(unique[1]);var key: String=akey+"|"+bkey if akey<bkey else bkey+"|"+akey
					segments[key]=true
	return segments

func _edge_root_for_oracle(a:Vector3,b:Vector3,da:float,db:float,snapshot:Dictionary)->Dictionary:
	var low:=0.0;var high:=1.0;var lv:=da
	for i in range(ROOT_ITERATIONS):
		var mid:float=(low+high)*0.5;var dm:float=Core.sample(a.lerp(b,mid),snapshot)
		if (dm<0.0)==(lv<0.0):low=mid;lv=dm
		else:high=mid
	return {"valid":true,"point":a.lerp(b,(low+high)*0.5)}

func _plane_segments(mesh:Dictionary,axis:int,plane:float)->Dictionary:
	var out:Dictionary={};var pos:PackedVector3Array=mesh.positions
	for i in range(0,pos.size(),3):
		var tri:Array[Vector3]=[pos[i],pos[i+1],pos[i+2]];var hits:Array[Vector3]=[]
		for edge in [[0,1],[1,2],[2,0]]:
			var a:Vector3=tri[int(edge[0])];var b:Vector3=tri[int(edge[1])];var da:=a[axis]-plane;var db:=b[axis]-plane
			if absf(da)<1.0e-6:hits.append(a)
			if da*db < -1.0e-12:hits.append(a.lerp(b,da/(da-db)))
		var u:Array[Vector3]=[]
		for h in hits:
			var dupe:=false
			for q in u:
				if h.distance_squared_to(q)<1.0e-10:dupe=true;break
			if not dupe:u.append(h)
		if u.size()>=2 and u[0].distance_squared_to(u[1])>1.0e-12:
			var ka: String=Core._point_key(u[0]);var kb: String=Core._point_key(u[1]);out[ka+"|"+kb if ka<kb else kb+"|"+ka]=true
	return out

func _build_xplus_chunk_pair(snapshot:Dictionary)->Dictionary:
	var a:Dictionary=LodMesher.build_chunk_cpu_data(SEED,Vector2i.ZERO,Vector2i(3,2),snapshot)
	var b:Dictionary=Mesher.build_chunk_cpu_data(SEED,Vector2i(1,0),Vector2i(0,2),false,snapshot)
	if not a.get("valid",false) or not b.get("valid",false):return {"valid":false,"reason":"reference_chunk_build_failed"}
	return {"valid":false,"reason":"candidate_transition_cell_not_yet_integrated_into_complete_chunk_tessellation",
		"a_lod1_triangles":a.get("triangle_count",-1),"b_lod0_triangles":b.get("triangle_count",-1),
		"candidate_face_probe_passed":true,"scope":"local face-template proof only; no full chunk mesh candidate emitted"}

func _node_index(x:int,y:int,z:int,dims:Vector3i)->int:return (y*dims.z+z)*dims.x+x
func _mesh_sha(mesh:Dictionary)->String:
	var ctx:=HashingContext.new();ctx.start(HashingContext.HASH_SHA256);ctx.update((mesh.positions as PackedVector3Array).to_byte_array());ctx.update((mesh.normals as PackedVector3Array).to_byte_array());return ctx.finish().hex_encode()
