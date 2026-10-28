extends "res://tests/prototypes/p3_1_r8_1_geometry_causality.gd"
const T := preload("res://scripts/experiments/lod01_transition_fixture.gd")
const R81_SHA := "191c37dd8d65f31b94c3a356e1e3232e8483fd037de5d4089844429c3795b9be"
var started := 0
var phases: Array[Dictionary] = []
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	started=Time.get_ticks_usec(); _r81_evidence_dir=OS.get_environment("P31_R82_EVIDENCE_DIR")
	var pre:Dictionary=_r8_preflight()
	pre["r81_script_sha256"]=_sha256(FileAccess.get_file_as_bytes("res://tests/prototypes/p3_1_r8_1_geometry_causality.gd"))
	pre["r81_script_sha256_expected"]=R81_SHA
	pre["r81_script_pin_match"]=pre.r81_script_sha256==R81_SHA
	pre["godot_version"]=Engine.get_version_info()
	_emit("preflight",pre)
	if not pre.get("valid",false) or not pre.get("r81_script_pin_match",false): _r82_finish("BLOCKED","source_or_frozen_input_preflight_failed"); return
	var normals:Dictionary=_diagnose_r81_normals(); _emit("triangle_baseline",normals)
	if not normals.get("valid",false): _r82_finish("BLOCKED","triangle_baseline_failed"); return
	var triangle:Dictionary=_triangle_trace(normals); _emit("triangle_3103_provenance",triangle)
	if not triangle.get("valid",false): _r82_finish("BLOCKED","triangle_source_reconstruction_failed"); return
	var seam:Dictionary=_diagnose_r81_xplus_seam(); _emit("xplus_baseline",seam)
	if not seam.get("valid",false): _r82_finish("BLOCKED","xplus_baseline_failed"); return
	var seam_trace:Dictionary=_xplus_trace(seam); _emit("xplus_source_provenance",seam_trace)
	if not seam_trace.get("valid",false): _r82_finish("BLOCKED","xplus_source_trace_failed"); return
	var picker:Dictionary=_diagnose_r81_xminus_picker(); _emit("xminus_baseline",picker)
	if not picker.get("valid",false): _r82_finish("BLOCKED","xminus_baseline_failed"); return
	var picker_trace:Dictionary=_xminus_trace(picker); _emit("xminus_source_provenance",picker_trace)
	if not picker_trace.get("valid",false): _r82_finish("BLOCKED","xminus_source_trace_failed"); return
	_r82_finish("DIAGNOSTIC_COMPLETE","frozen_triangles_mapped_and_reconstructed; no production change")

func _triangle_trace(normals:Dictionary)->Dictionary:
	var scenario:Dictionary=normals.scenarios.center_fill_then_wall_carve
	var triangle:Dictionary=scenario.target_triangle_before_repair
	var source:Dictionary=scenario.target_tetra_source_trace
	var matches:Array=source.matched_source_tetrahedra
	var tet:Dictionary={}
	for item in matches:
		if int(item.tetrahedron_index)==1 and item.subcell_xyz==[0,0,0]: tet=item; break
	if tet.is_empty(): return {"valid":false,"reason":"frozen_tetra_not_found"}
	var corners:Array=tet.corners; var pts:Array[Vector3]=[]; var vals:Array[float]=[]
	for item in corners:
		pts.append(_parse_vector3(item.position)); vals.append(float(item.density))
	var rebuilt:Dictionary=_poly(pts,vals,false)
	var wanted:Array[String]=_tri_keys(triangle.vertices); var matched:=0; var edge_rows:Array[Dictionary]=[]
	for tri in rebuilt.triangles:
		if _tri_keys(tri.vertices)==wanted: matched+=1
	for edge in rebuilt.edge_records:
		var a:Vector3=edge.a; var b:Vector3=edge.b; var p:Vector3=edge.position
		var root:Dictionary=_bisect_edge(a,b,_r8_fill_snapshot)
		var branch_a:Dictionary=_field_trace(a,_r8_fill_snapshot); var branch_b:Dictionary=_field_trace(b,_r8_fill_snapshot)
		var branch_mesh:Dictionary=_field_trace(p,_r8_fill_snapshot)
		var root_position:Vector3=_parse_vector3(root.position) if root.bracketed else Vector3.ZERO
		var branch_root:Dictionary=_field_trace(root_position,_r8_fill_snapshot) if root.bracketed else {}
		edge_rows.append({"corner_indices":edge.corner_indices,"a_world":_vec3_array(a),"a_bits":_vec3_bytes(a),"a_stored_density":edge.value_a,
			"a_stored_f32":_float32_bytes(edge.value_a),"a_continuous_density":T.sample_canonical(SEED,a,_r8_fill_snapshot),"a_branch":branch_a,
			"b_world":_vec3_array(b),"b_bits":_vec3_bytes(b),"b_stored_density":edge.value_b,"b_stored_f32":_float32_bytes(edge.value_b),
			"b_continuous_density":T.sample_canonical(SEED,b,_r8_fill_snapshot),"b_branch":branch_b,"linear_t":edge.t,"mesh_world":_vec3_array(p),
			"mesh_bits":_vec3_bytes(p),"mesh_continuous_density":T.sample_canonical(SEED,p,_r8_fill_snapshot),"mesh_branch":branch_mesh,
			"continuous_root":root,"root_branch":branch_root,"linear_to_root_distance":p.distance_to(root_position) if root.bracketed else -1.0,
			"winner_changes_across_edge":root.bracketed and _branch(branch_a)!=_branch(branch_root)})
	var stable:=true; var roots:=0
	for row in edge_rows:
		if row.winner_changes_across_edge: stable=false
		if row.continuous_root.bracketed: roots+=1
	var reconstructed:=matched==1
	var classification:="CAUSE_UNRESOLVED"
	if reconstructed and roots==edge_rows.size() and stable: classification="CONTINUOUS_SDF_VERSUS_TETRAHEDRAL_PIECEWISE_LINEAR_INTERPOLATION"
	return {"valid":reconstructed and edge_rows.size()>=3,"scenario":"center_fill_then_wall_carve","input_sha256":INPUT_SHA_FILL_CARVE,
		"triangle_index":int(triangle.triangle_index),"owner_cell_id":712,"cell_coordinate":source.cell_coordinate,"subcell_xyz":tet.subcell_xyz,
		"tetrahedron_index":tet.tetrahedron_index,"tetrahedron_corner_order":tet.tetrahedron_corner_indices_in_source_order,
		"source_corner_samples":corners,"recorded_triangle":triangle,"independent_reconstruction":_json_tris(rebuilt.triangles),
		"reconstructed_triangle_count":matched,"interpolation_edges":edge_rows,"piecewise_linear_gradient":rebuilt.piecewise_linear_gradient,
		"centroid_branch_trace":_field_trace(_parse_vector3(triangle.centroid),_r8_fill_snapshot),"branch_stable_on_crossed_edges":stable,
		"root_bracket_count":roots,"classification":classification,
		"first_divergence":"source corner samples to tetra edge interpolation; compare each interpolation with a root of the continuous canonical field"}

func _field_trace(p:Vector3,snapshot:Dictionary)->Dictionary:
	var mapped:Dictionary=SpatialR8.world_to_region_local(p); var region:Vector2i=mapped.region_key; var local:Vector3=mapped.local_position
	var wx:=float(region.x)*16.0+local.x; var wz:=float(region.y)*12.0+local.z; var phase:=float(posmod(SEED,100003))*0.000173
	var surface:=3.8+1.25*sin(wx*0.22+phase)+0.70*cos(wz*0.31-phase*0.7)+0.28*sin((wx+wz)*0.11+phase*0.3)
	var top:=surface-local.y; var bottom:=local.y+1.0; var bounded:=minf(top,bottom)
	var cy:=1.15+0.24*sin(wx*0.25+phase); var cz:=6.0+1.05*sin(wx*0.17+phase*0.6)
	var cave:=Vector2(local.y-cy,wz-cz).length()-0.92; var density:=minf(bounded,cave)
	var base_winner:="surface_top" if top<=bottom else "lower_bound"
	if cave<bounded: base_winner="cave_distance"
	var operations:Array[Dictionary]=[]; var winning:=-1; var winner:=base_winner
	for i in range(snapshot.centers.size()):
		var center:Vector3=snapshot.centers[i]; var radius:float=snapshot.radii[i]; var mode:=int(snapshot.modes[i])
		var dist:=center.distance_to(p); var op:=dist-radius if mode==Brush.Mode.CARVE else radius-dist; var before:=density
		var selected:=op<before if mode==Brush.Mode.CARVE else op>before; var tie:=op==before
		if mode==Brush.Mode.CARVE: density=minf(density,op)
		else: density=maxf(density,op)
		if selected or tie: winning=i; winner="operation_%d_%s"%[i,"CARVE" if mode==Brush.Mode.CARVE else "FILL"]
		operations.append({"sequence":i,"mode":"CARVE" if mode==Brush.Mode.CARVE else "FILL","center":_vec3_array(center),"radius":radius,
			"distance":dist,"operator_value":op,"before":before,"after":density,"selected":selected,"tie":tie})
	return {"world":_vec3_array(p),"world_bits":_vec3_bytes(p),"region":_vec2i_array(region),"local":_vec3_array(local),
		"base_terms":{"world_x":wx,"world_z":wz,"phase":phase,"surface_y":surface,"top":top,"bottom":bottom,"bounded_surface":bounded,
			"cave_center_y":cy,"cave_center_z":cz,"cave_distance":cave,"density":minf(bounded,cave),"winner":base_winner},
		"ordered_operations":operations,"final_density":density,"winning_sequence":winning,"winning_branch":winner,
		"matches_canonical":density==T.sample_canonical(SEED,p,snapshot)}

func _bisect_edge(a:Vector3,b:Vector3,snapshot:Dictionary)->Dictionary:
	var da:=T.sample_canonical(SEED,a,snapshot); var db:=T.sample_canonical(SEED,b,snapshot)
	if (da>=0.0)==(db>=0.0): return {"bracketed":false,"a_density":da,"b_density":db,"reason":"not_sign_bracketed"}
	var lo:=0.0; var hi:=1.0; var dlo:=da; var iterations:=0
	for i in range(48):
		var mid:float=(lo+hi)*0.5
		if mid==lo or mid==hi: break
		var dm:=T.sample_canonical(SEED,a.lerp(b,mid),snapshot); iterations+=1
		if (dm>=0.0)==(dlo>=0.0): lo=mid; dlo=dm
		else: hi=mid
	var t:float=(lo+hi)*0.5; var p:Vector3=a.lerp(b,t)
	return {"bracketed":true,"t":t,"position":_vec3_array(p),"position_bits":_vec3_bytes(p),"root_density":T.sample_canonical(SEED,p,snapshot),
		"endpoint_density_a":da,"endpoint_density_b":db,"iterations":iterations}

func _branch(trace:Dictionary)->String:
	return "%s|%d"%[trace.get("base_terms",{}).get("winner","?"),int(trace.get("winning_sequence",-1))]
func _xplus_trace(seam:Dictionary)->Dictionary:
	var setup:Dictionary=_make_snapshot("center_fill_then_wall_carve")
	if not setup.valid:return {"valid":false,"reason":"frozen_snapshot_failed"}
	var snap:Dictionary=setup.snapshot; var rows:Array[Dictionary]=[]
	for item in seam.cases:
		var c:Dictionary=item; var lod_a:=int(c.lod_a_negative_side); var lod_b:=int(c.lod_b_positive_side)
		var unmatched:Array=c.unmatched_segments_from_b
		if unmatched.is_empty():continue
		var region_b:=Vector2i(c.region_b[0],c.region_b[1]); var chunk_b:=Vector2i(c.chunk_b[0],c.chunk_b[1])
		var unique:Dictionary={}
		for seg_value in unmatched:
			var seg:Dictionary=seg_value; unique[int(seg.triangle_index)]=seg.triangle_vertices
		var b_traces:Array[Dictionary]=[]
		for idx_value in unique:
			var idx:=int(idx_value); var tr:Dictionary=_trace_chunk_triangle(lod_b,region_b,chunk_b,idx,unique[idx],snap)
			b_traces.append({"triangle_index":idx,"trace":tr})
			if not tr.valid:return {"valid":false,"reason":"positive_side_triangle_source_missing","partial":b_traces}
		var a_segments:Array=c.a_contour_with_triangle_sources.segments; var a_near:Array[Dictionary]=[]
		var anchor:=Vector3(16.0,2.0,7.0)
		for seg_value in a_segments:
			var seg:Dictionary=seg_value; var a:Vector3=_parse_vector3(seg.a); var b:Vector3=_parse_vector3(seg.b)
			var mid:Vector3=(a+b)*0.5
			if a.distance_to(anchor)<0.02 or b.distance_to(anchor)<0.02 or mid.distance_to(anchor)<0.02:a_near.append(seg)
		var region_a:=Vector2i(c.region_a[0],c.region_a[1]);var chunk_a:=Vector2i(c.chunk_a[0],c.chunk_a[1]);var a_traces:Array[Dictionary]=[];var seen:Dictionary={}
		for seg_value in a_near:
			var seg:Dictionary=seg_value;var idx:=int(seg.triangle_index)
			if seen.has(idx):continue
			seen[idx]=true;var tr:Dictionary=_trace_chunk_triangle(lod_a,region_a,chunk_a,idx,seg.triangle_vertices,snap)
			a_traces.append({"triangle_index":idx,"segment":seg,"trace":tr})
			if not tr.valid:return {"valid":false,"reason":"negative_side_counterpart_source_missing","partial":a_traces}
		rows.append({"lod_pair":[lod_a,lod_b],"contour_counts":[c.a_contour_with_triangle_sources.segment_count,c.b_contour_with_triangle_sources.segment_count],
			"unmatched_counts":[c.unmatched_segments_from_a.size(),c.unmatched_segments_from_b.size()],"shared_scalar_samples":c.shared_scalar_samples,
			"negative_side_local_counterpart":a_traces,"positive_side_unmatched_source_triangles":b_traces,"anchor_world":_vec3_array(anchor),"input_sha256":INPUT_SHA_FILL_CARVE})
	return {"valid":rows.size()>=2,"cases":rows,"disposition":"source triangles/cells/tetrahedra and full mesh reconstruction are traced; seam cause is classified only if source interface inputs and triangle rejection explain extra segments"}

func _xminus_trace(picking:Dictionary)->Dictionary:
	var setup:Dictionary=_make_snapshot("center_fill_then_wall_carve");if not setup.valid:return {"valid":false,"reason":"snapshot_failed"}
	var snap:Dictionary=setup.snapshot;var rows:Array[Dictionary]=[]
	for c_value in picking.cases:
		var c:Dictionary=c_value;var xminus:bool=String(c.boundary)=="X_NEG";var control:bool=String(c.boundary)=="X_POS" and int(c.lod_a_negative_side)==0
		if not xminus and not control:continue
		if xminus and (int(c.lod_a_negative_side)!=0 or int(c.lod_b_positive_side)!=0):continue
		for side in ["mesh_a_ray_hits","mesh_b_ray_hits"]:
			var hits:Array=c[side];if hits.is_empty():return {"valid":false,"reason":"ray_hit_missing"}
			var hit:Dictionary=hits[0];var is_a:bool=String(side)=="mesh_a_ray_hits"
			var region:=Vector2i(c.region_a[0],c.region_a[1]) if is_a else Vector2i(c.region_b[0],c.region_b[1])
			var chunk:=Vector2i(c.chunk_a[0],c.chunk_a[1]) if is_a else Vector2i(c.chunk_b[0],c.chunk_b[1])
			var lod:=int(c.lod_a_negative_side) if is_a else int(c.lod_b_positive_side)
			var tr:Dictionary=_trace_chunk_triangle(lod,region,chunk,int(hit.triangle_index),hit.triangle_vertices,snap)
			if not tr.get("valid",false):
				rows.append({"boundary":c.boundary,"lod_pair":[c.lod_a_negative_side,c.lod_b_positive_side],"side":side,
					"region":_vec2i_array(region),"chunk":_vec2i_array(chunk),"lod":lod,"ray_origin":c.world_ray_origin,
					"ray_direction":c.world_ray_direction,"picker_distance":c.picker_distance,
					"canonical_root_distance":c.independent_dense_sdf_first_root_distance,"mesh_hit":hit.position,
					"mesh_first_hit_distance":hit.distance,"mesh_hit_minus_root":float(hit.distance)-float(c.independent_dense_sdf_first_root_distance),
					"triangle_index":hit.triangle_index,"source_trace":tr,"source_trace_valid":false})
				continue
			var samples:Array[Dictionary]=[]
			for v in hit.triangle_vertices:
				var p:Vector3=_parse_vector3(v);samples.append({"world":_vec3_array(p),"bits":_vec3_bytes(p),"canonical_density":T.sample_canonical(SEED,p,snap),"branch":_field_trace(p,snap)})
			var centroid:=(_parse_vector3(hit.triangle_vertices[0])+_parse_vector3(hit.triangle_vertices[1])+_parse_vector3(hit.triangle_vertices[2]))/3.0
			rows.append({"boundary":c.boundary,"lod_pair":[c.lod_a_negative_side,c.lod_b_positive_side],"side":side,"region":_vec2i_array(region),"chunk":_vec2i_array(chunk),"lod":lod,
				"ray_origin":c.world_ray_origin,"ray_direction":c.world_ray_direction,"picker_distance":c.picker_distance,
				"canonical_root_distance":c.independent_dense_sdf_first_root_distance,"mesh_first_hit_distance":hit.distance,
				"mesh_hit_minus_root":float(hit.distance)-float(c.independent_dense_sdf_first_root_distance),"mesh_hit":hit.position,
				"mesh_hit_density":T.sample_canonical(SEED,_parse_vector3(hit.position),snap),"triangle_vertices":samples,
				"triangle_centroid":_vec3_array(centroid),"centroid_density":T.sample_canonical(SEED,centroid,snap),"source_trace":tr})
	var all_mapped:=rows.size()==4
	for row in rows:
		if not bool(row.get("source_trace_valid",row.get("source_trace",{}).get("valid",false))):all_mapped=false
	return {"valid":rows.size()==4 and all_mapped,"reason":"" if all_mapped else "one_or_more_triangle_source_maps_failed",
		"traces":rows,"control":"X_POS LOD0/LOD0 retained as same-ray root/picker/mesh control"}

func _trace_chunk_triangle(lod:int,region:Vector2i,chunk:Vector2i,target_index:int,target_values:Array,snapshot:Dictionary)->Dictionary:
	if target_values.size()!=3:return {"valid":false,"reason":"target_vertex_count"}
	var target_keys:=_tri_keys(target_values);var actual:Dictionary=_r8_build_chunk(lod,region,chunk,snapshot)
	if not actual.valid:return {"valid":false,"reason":"chunk_rebuild_failed"}
	var origin:Vector3=SpatialR8.region_origin_world(region)+GridR8.origin_for(chunk);var actual_world:PackedVector3Array=actual.positions.duplicate()
	for i in range(actual_world.size()):actual_world[i]+=origin
	if target_index<0 or target_index*3+2>=actual_world.size():return {"valid":false,"reason":"target_index_out_of_bounds","index":target_index}
	var target_at_index:Array[Vector3]=[actual_world[target_index*3],actual_world[target_index*3+1],actual_world[target_index*3+2]]
	var index_match:=_tri_keys(target_at_index)==target_keys;var rebuilt:=PackedVector3Array();var found:Dictionary={}
	var plane:=_chunk_shared_plane(region,chunk)
	if lod==0:
		var bounds:Vector4i=GridR8.cell_bounds(chunk);var region_origin:=SpatialR8.region_origin_world(region)
		var sample_origin:=GridR8.MIN_BOUND+Vector3(bounds.x,0,bounds.z)*GridR8.SAMPLE_STEP
		for y in range(GridR8.CELL_COUNT_Y):
			for z in range(bounds.z,bounds.w):
				for x in range(bounds.x,bounds.y):
					var cp:Array[Vector3]=[];var pv:=PackedFloat32Array()
					for corner_value in MesherR8.CORNERS:
						var corner:Vector3i=corner_value;var p:=region_origin+sample_origin+Vector3(x-bounds.x+corner.x,y+corner.y,z-bounds.z+corner.z)*GridR8.SAMPLE_STEP
						cp.append(p);var owner_local:Vector3=p-region_origin;pv.append(Brush.sample_density_snapshot(SEED,region,owner_local,false,snapshot))
					var cv:Array[float]=[];for raw in pv:cv.append(float(raw))
					var solid:=false;var empty:=false
					for d in cv:solid=solid or d>=0.0;empty=empty or d<0.0
					if not solid or not empty:continue
					for ti in range(MesherR8.TETRAHEDRA.size()):
						var tet:Array=MesherR8.TETRAHEDRA[ti];var pp:=PackedVector3Array();var nn:=PackedVector3Array()
						MesherR8._polygonize_tetra(tet,cp,cv,pp,nn);var points:Array[Vector3]=[];var vals:Array[float]=[];var cube_ids:Array[int]=[]
						for cv_id in tet:
							var ci:=int(cv_id);points.append(cp[ci]);vals.append(cv[ci]);cube_ids.append(ci)
						var ind:Dictionary=_poly(points,vals,false);var start:=rebuilt.size()/3
						for v in pp:rebuilt.append((v-origin)+origin)
						for j in range(pp.size()/3):
							var gi:int=start+j;var tri:Array[Vector3]=[rebuilt[gi*3],rebuilt[gi*3+1],rebuilt[gi*3+2]]
							var raw_tri:Array[Vector3]=[pp[j*3],pp[j*3+1],pp[j*3+2]]
							if gi==target_index:
								found=_source_record(lod,region,chunk,target_index,gi,Vector3i(x-bounds.x,y,z-bounds.z),ti,tet,cube_ids,points,vals,ind,tri,"marching_tetrahedra_cube",true,pv)
								found["polygonizer_world_vertices_before_chunk_transform"]=raw_tri.map(func(v:Variant)->Array[float]:return _vec3_array(v))
								found["chunk_local_vertices_after_subtract"]=raw_tri.map(func(v:Variant)->Array[float]:return _vec3_array(_parse_vector3(v)-origin))
								found["world_vertices_after_add_origin"]=tri.map(func(v:Variant)->Array[float]:return _vec3_array(v))
								found["target_index_geometry_match"]=_tri_keys(tri)==target_keys
							if _tri_keys(tri)==target_keys and found.is_empty():found=_source_record(lod,region,chunk,target_index,gi,Vector3i(x-bounds.x,y,z-bounds.z),ti,tet,cube_ids,points,vals,ind,tri,"marching_tetrahedra_cube",true,pv)
	else:
		var extent:=Vector3i(GridR8.CELLS_PER_CHUNK_X/2,GridR8.CELL_COUNT_Y/2,GridR8.CELLS_PER_CHUNK_Z/2)
		for y in range(extent.y):
			for z in range(extent.z):
				for x in range(extent.x):
					var cell:=Vector3i(x,y,z);var selected:Array[int]=T.transition_faces_for_chunk_cell(cell,extent)
					var world_cell:=origin+Vector3(float(x),GridR8.MIN_BOUND.y+float(y),float(z))
					var lattice:=Vector3i(roundi(world_cell.x*2.0),roundi(world_cell.y*2.0),roundi(world_cell.z*2.0))
					var builder:RefCounted=T.new();builder._world_seed=SEED;builder._brush_snapshot=snapshot;var origin_cell:Vector3=Vector3(lattice)*T.LOD0_STEP
					if selected.is_empty():
						var ids:Array[int]=[];var cell_points:Array[Vector3]=[];var cell_values:Array[float]=[]
						
						for corner_value in T.CUBE_CORNERS:
							var corner:Vector3i=corner_value;var p:=origin_cell+Vector3(corner)*T.LOD1_STEP;cell_points.append(p)
							var id:=int(builder._add_sample_point(p,SEED,snapshot));ids.append(id);cell_values.append(float(builder._sample_by_id(id).density))
						for ti in range(T.CUBE_TETRAHEDRA.size()):
							var cube_tet:Array=T.CUBE_TETRAHEDRA[ti];var tet_ids:Array[int]=[ids[int(cube_tet[0])],ids[int(cube_tet[1])],ids[int(cube_tet[2])],ids[int(cube_tet[3])]]
							var points:Array[Vector3]=[];var vals:Array[float]=[];var cube_ids:Array[int]=[]
							for value in cube_tet:
								var ci:=int(value);points.append(cell_points[ci]);vals.append(cell_values[ci]);cube_ids.append(ci)
							var ind:Dictionary=_poly(points,vals,true);var before:int=builder._positions.size();builder._polygonize_tetra(tet_ids)
							var added:=_builder_triangles(builder._positions,before);var base:int=rebuilt.size()/3
							for v in builder._positions.slice(before,builder._positions.size()):rebuilt.append((v-origin)+origin)
							for item in added:
								var gi:int=base+int(item.triangle_index)-int(before/3);var tri:Array[Vector3]=[rebuilt[gi*3],rebuilt[gi*3+1],rebuilt[gi*3+2]];var raw_tri:Array=item.vertices
								if gi==target_index:
									found=_source_record(lod,region,chunk,target_index,gi,cell,ti,cube_tet,cube_ids,points,vals,ind,tri,"lod1_uniform_cube",false,PackedFloat32Array())
									found["cell_lattice_origin"]=_vec3i_array(lattice);found["selected_face_ids"]=selected
									found["polygonizer_world_vertices_before_chunk_transform"]=raw_tri.map(func(v:Variant)->Array[float]:return _vec3_array(v))
									found["chunk_local_vertices_after_subtract"]=raw_tri.map(func(v:Variant)->Array[float]:return _vec3_array(_parse_vector3(v)-origin))
									found["world_vertices_after_add_origin"]=tri.map(func(v:Variant)->Array[float]:return _vec3_array(v))
									found["target_index_geometry_match"]=_tri_keys(tri)==target_keys
								elif _tri_keys(tri)==target_keys and found.is_empty():
									found=_source_record(lod,region,chunk,target_index,gi,cell,ti,cube_tet,cube_ids,points,vals,ind,tri,"lod1_uniform_cube",false,PackedFloat32Array())
					else:
						var faces:Array[Array]=T._boundary_triangles(lattice,selected);var center:Vector3=origin_cell+Vector3.ONE*0.5
						var center_id:=int(builder._add_sample_point(center,SEED,snapshot))
						for bi in range(faces.size()):
							var face:Array=faces[bi];var ids4:Array[int]=[center_id];var points4:Array[Vector3]=[center];var vals4:Array[float]=[float(builder._sample_by_id(center_id).density)]
							for value in face:
								var p:Vector3=value;var id:=int(builder._add_sample_point(p,SEED,snapshot));ids4.append(id);points4.append(p);vals4.append(float(builder._sample_by_id(id).density))
							var ind2:Dictionary=_poly(points4,vals4,true);var before2:int=builder._positions.size();builder._polygonize_tetra(ids4)
							var added2:=_builder_triangles(builder._positions,before2);var base2:int=rebuilt.size()/3
							for v in builder._positions.slice(before2,builder._positions.size()):rebuilt.append((v-origin)+origin)
							for item in added2:
								var gi2:int=base2+int(item.triangle_index)-int(before2/3);var tri2:Array[Vector3]=[rebuilt[gi2*3],rebuilt[gi2*3+1],rebuilt[gi2*3+2]];var raw_tri2:Array=item.vertices
								if gi2==target_index:
									found=_source_record(lod,region,chunk,target_index,gi2,cell,bi,[0,1,2,3],[0,1,2,3],points4,vals4,ind2,tri2,"lod1_transition_center_fan",false,PackedFloat32Array())
									found["cell_lattice_origin"]=_vec3i_array(lattice);found["selected_face_ids"]=selected;found["boundary_triangle_index"]=bi
									found["source_boundary_triangle"]=face.map(func(v:Variant)->Array[float]:return _vec3_array(v))
									found["source_boundary_triangle_face"]=_face_triangles(points4,vals4,plane)
									found["polygonizer_world_vertices_before_chunk_transform"]=raw_tri2.map(func(v:Variant)->Array[float]:return _vec3_array(v))
									found["chunk_local_vertices_after_subtract"]=raw_tri2.map(func(v:Variant)->Array[float]:return _vec3_array(_parse_vector3(v)-origin))
									found["world_vertices_after_add_origin"]=tri2.map(func(v:Variant)->Array[float]:return _vec3_array(v))
									found["target_index_geometry_match"]=_tri_keys(tri2)==target_keys
								elif _tri_keys(tri2)==target_keys and found.is_empty():
									found=_source_record(lod,region,chunk,target_index,gi2,cell,bi,[0,1,2,3],[0,1,2,3],points4,vals4,ind2,tri2,"lod1_transition_center_fan",false,PackedFloat32Array())
						# `builder` is cell-local, so append once after all face tetrahedra.
	var rebuilt_hash:=_pos_hash(rebuilt);var actual_hash:=_pos_hash(actual_world);var position_differences:Array[Dictionary]=[]
	for i in range(mini(rebuilt.size(),actual_world.size())):
		if _vec3_bytes(rebuilt[i])!=_vec3_bytes(actual_world[i]) and position_differences.size()<8:
			position_differences.append({"vertex_index":i,"rebuilt":_vec3_array(rebuilt[i]),"actual":_vec3_array(actual_world[i]),
				"rebuilt_f32":_vec3_bytes(rebuilt[i]),"actual_f32":_vec3_bytes(actual_world[i])})
	if not found.is_empty():
		found["target_index_geometry_match"]=index_match;found["target_index"]=target_index;found["target_vertices_float32_bytes"]=target_values.map(func(v:Variant)->String:return _vec3_bytes(_parse_vector3(v)))
		found["independent_reconstruction_matches_source_triangle"]=_json_triangle_contains(found.get("independent_triangles",[]),target_keys,origin)
	return {"valid":not found.is_empty() and rebuilt_hash==actual_hash,"reason":"" if not found.is_empty() and rebuilt_hash==actual_hash else "source_map_or_full_mesh_parity_failed",
		"lod":lod,"region":_vec2i_array(region),"chunk":_vec2i_array(chunk),"chunk_world_origin":_vec3_array(origin),
		"target_triangle_index":target_index,"target_index_geometry_match":index_match,"triangle_count":actual_world.size()/3,
		"actual_vertex_count":actual_world.size(),"rebuilt_vertex_count":rebuilt.size(),"first_position_differences":position_differences,
		"rebuilt_position_sha256":rebuilt_hash,"actual_position_sha256":actual_hash,"full_position_rebuild_matches":rebuilt_hash==actual_hash,
		"source_match":found,"source_face_triangle_diagnostics":found.get("source_boundary_triangle_face",found.get("cell_boundary_face_triangles",[]))}

func _source_record(lod:int,region:Vector2i,chunk:Vector2i,target_index:int,global_index:int,cell:Vector3i,tet_index:int,tet:Array,cube_ids:Array,
		points:Array,values:Array,independent:Dictionary,tri:Array,kind:String,packed:bool,packed_values:PackedFloat32Array)->Dictionary:
	var samples:Array[Dictionary]=[]
	var owner_origin:Vector3=SpatialR8.region_origin_world(region)
	for i in range(points.size()):
		var p:Vector3=points[i];var mapped:Dictionary=SpatialR8.world_to_region_local(p);var owner_local:Vector3=p-owner_origin
		var canonical:=Brush.sample_density_snapshot(SEED,region,owner_local,false,_r8_fill_snapshot)
		samples.append({"tetra_local_index":i,"source_corner_index":cube_ids[i] if i<cube_ids.size() else i,"world":_vec3_array(p),"world_bits":_vec3_bytes(p),
			"owner_region":_vec2i_array(region),"owner_region_local":_vec3_array(owner_local),"world_to_region_map":_vec2i_array(mapped.region_key),
			"world_to_region_local":_vec3_array(mapped.local_position),"ownership_mapping_differs_at_boundary":mapped.region_key!=region,
			"canonical_sample":canonical,"stored_sample":values[i],
			"stored_f32":_float32_bytes(float(values[i])),"storage":"PackedFloat32Array" if packed else "scalar transition cache","storage_value_matches_canonical":float(values[i])==canonical})
	return {"valid":true,"kind":kind,"source_cell":_vec3i_array(cell),"owner":{"region":_vec2i_array(region),"chunk":_vec2i_array(chunk)},
		"source_tetra_index":tet_index,"source_tetra_corner_order":tet,"source_global_triangle_index":global_index,"target_triangle_index":target_index,
		"global_triangle_index_matches":global_index==target_index,"source_tetra_samples":samples,"source_triangle_vertices":tri.map(func(v:Variant)->Array[float]:return _vec3_array(v)),
		"source_triangle_vertex_bits":tri.map(func(v:Variant)->String:return _vec3_bytes(v)),"independent_triangles":_json_tris(independent.get("triangles",[])),
		"independent_edge_interpolation":_json_edges(independent.get("edge_records",[])),"pre_cutoff_triangles":_json_tris(independent.get("pre_cutoff_triangles",[])),
		"piecewise_linear_gradient":independent.get("piecewise_linear_gradient",[])}

func _chunk_shared_plane(region:Vector2i,chunk:Vector2i)->float:
	if region.x<0 or (region.x==0 and chunk.x==0):return 0.0
	return 16.0

func _face_triangles(points:Array,values:Array,plane:float)->Array[Dictionary]:
	var result:Array[Dictionary]=[]
	for combo in [[0,1,2],[0,1,3],[0,2,3],[1,2,3]]:
		var a:Vector3=points[int(combo[0])];var b:Vector3=points[int(combo[1])];var c:Vector3=points[int(combo[2])]
		if absf(a.x-plane)>0.000001 or absf(b.x-plane)>0.000001 or absf(c.x-plane)>0.000001:continue
		result.append({"tetra_local_indices":combo,"points":[_vec3_array(a),_vec3_array(b),_vec3_array(c)],"bits":[_vec3_bytes(a),_vec3_bytes(b),_vec3_bytes(c)],
			"densities":[values[int(combo[0])],values[int(combo[1])],values[int(combo[2])]]})
	return result
func _poly(points:Array,values:Array,canonical_order:bool)->Dictionary:
	if points.size()!=4 or values.size()!=4:return {"valid":false,"reason":"tetra_input_size"}
	var inside:Array[int]=[];var outside:Array[int]=[];var ic:=Vector3.ZERO;var oc:=Vector3.ZERO
	for i in range(4):
		if float(values[i])>=0.0:inside.append(i);ic+=points[i]
		else:outside.append(i);oc+=points[i]
	if inside.is_empty() or outside.is_empty():return {"valid":true,"triangles":[],"pre_cutoff_triangles":[],"edge_records":[],"piecewise_linear_gradient":[]}
	ic/=float(inside.size());oc/=float(outside.size());var empty:=oc-ic;var groups:Array[Array]=[]
	if inside.size()==1 or outside.size()==1:
		var pivot:=inside[0] if inside.size()==1 else outside[0];var others:Array=outside if inside.size()==1 else inside
		groups.append([_edge(pivot,int(others[0]),points,values,canonical_order),_edge(pivot,int(others[1]),points,values,canonical_order),_edge(pivot,int(others[2]),points,values,canonical_order)])
	else:
		var a:=_edge(inside[0],outside[0],points,values,canonical_order);var b:=_edge(inside[0],outside[1],points,values,canonical_order)
		var c:=_edge(inside[1],outside[0],points,values,canonical_order);var d:=_edge(inside[1],outside[1],points,values,canonical_order)
		groups.append([a,b,d]);groups.append([a,d,c])
	var triangles:Array[Dictionary]=[];var rejected:Array[Dictionary]=[];var edges:Array[Dictionary]=[]
	for group_value in groups:
		var group:Array=group_value;var tri_edges:Array[Dictionary]=[group[0],group[1],group[2]]
		var verts:Array[Vector3]=[tri_edges[0].position,tri_edges[1].position,tri_edges[2].position]
		var cross:Vector3=(verts[1]-verts[0]).cross(verts[2]-verts[0]);var cross2:=cross.length_squared();var swapped:=cross.dot(empty)<0.0
		if swapped:
			var v:Vector3=verts[1];verts[1]=verts[2];verts[2]=v;var e:Dictionary=tri_edges[1];tri_edges[1]=tri_edges[2];tri_edges[2]=e;cross=-cross
		var row:Dictionary={"vertices":verts,"edges":tri_edges,"cross":cross,"cross_squared":cross2,"swapped_to_toward_empty":swapped,"rejected_by_unchanged_squared_cross_cutoff":cross2<=1.0e-12}
		if cross2<=1.0e-12:rejected.append(row)
		else:
			triangles.append(row)
			for edge_value in tri_edges:
				var edge:Dictionary=edge_value;var found:=false
				for existing in edges:
					if existing.key==edge.key:found=true;break
				if not found:edges.append(edge)
	return {"valid":true,"inside_local_indices":inside,"outside_local_indices":outside,"inside_center":ic,"outside_center":oc,
		"toward_empty":empty,"triangles":triangles,"pre_cutoff_triangles":rejected,"edge_records":edges,"piecewise_linear_gradient":_linear_gradient(points,values)}

func _edge(ai:int,bi:int,points:Array,values:Array,canonical_order:bool)->Dictionary:
	var ap:Vector3=points[ai];var bp:Vector3=points[bi];var av:=float(values[ai]);var bv:=float(values[bi]);var ca:=ai;var cb:=bi
	if canonical_order and T._point_precedes(bp,ap):
		var p:Vector3=ap;ap=bp;bp=p;var v:=av;av=bv;bv=v;var n:=ca;ca=cb;cb=n
	var denom:=av-bv;var t:=0.5 if is_zero_approx(denom) else clampf(av/denom,0.0,1.0);var pos:Vector3=ap.lerp(bp,t)
	return {"key":"%s|%s"%[_vec3_bytes(ap),_vec3_bytes(bp)],"corner_indices":[ca,cb],"a":ap,"b":bp,"value_a":av,"value_b":bv,"denominator":denom,"t":t,"position":pos}

func _linear_gradient(points:Array,values:Array)->Array[float]:
	var p0:Vector3=points[0];var p1:Vector3=points[1];var p2:Vector3=points[2];var p3:Vector3=points[3]
	var m:=Basis(p1-p0,p2-p0,p3-p0);var rhs:=Vector3(float(values[1])-float(values[0]),float(values[2])-float(values[0]),float(values[3])-float(values[0]))
	if absf(m.determinant())<1.0e-12:return []
	return _vec3_array(m.inverse()*rhs)

func _tri_keys(vertices:Array)->Array[String]:
	var keys:Array[String]=[]
	for value in vertices:keys.append(_vec3_bytes(_parse_vector3(value)))
	keys.sort();return keys

func _json_triangle_contains(triangles:Array,target_keys:Array[String],origin:Vector3)->bool:
	for value in triangles:
		var row:Dictionary=value
		if _tri_keys(_chunk_roundtrip_triangle(row.get("vertices",[]),origin))==target_keys:return true
	return false

func _chunk_roundtrip_triangle(vertices:Array,origin:Vector3)->Array[Vector3]:
	var local:=PackedVector3Array()
	for value in vertices:local.append(_parse_vector3(value)-origin)
	var world:=PackedVector3Array()
	for value in local:world.append(value+origin)
	var result:Array[Vector3]=[]
	for value in world:result.append(value)
	return result

func _json_tris(values:Array)->Array[Dictionary]:
	var out:Array[Dictionary]=[]
	for value in values:
		var tri:Dictionary=value;out.append({"vertices":tri.vertices.map(func(v:Variant)->Array[float]:return _vec3_array(v)),
			"vertex_bits":tri.vertices.map(func(v:Variant)->String:return _vec3_bytes(v)),"cross":_vec3_array(tri.cross),"cross_squared":tri.cross_squared,
			"swapped_to_empty":tri.swapped_to_toward_empty,"rejected_by_unchanged_cutoff":tri.rejected_by_unchanged_squared_cross_cutoff})
	return out

func _json_edges(values:Array)->Array[Dictionary]:
	var out:Array[Dictionary]=[]
	for value in values:
		var edge:Dictionary=value;out.append({"corner_indices":edge.corner_indices,"a":_vec3_array(edge.a),"b":_vec3_array(edge.b),"stored_values":[edge.value_a,edge.value_b],
			"denominator":edge.denominator,"t":edge.t,"position":_vec3_array(edge.position),"position_bits":_vec3_bytes(edge.position)})
	return out

func _builder_triangles(pos:PackedVector3Array,start:int)->Array[Dictionary]:
	var out:Array[Dictionary]=[]
	for i in range(start,pos.size(),3):out.append({"triangle_index":i/3,"vertices":[pos[i],pos[i+1],pos[i+2]]})
	return out

func _pos_hash(pos:PackedVector3Array)->String:return _sha256(pos.to_byte_array())

func _emit(name:String,record:Dictionary)->void:
	var payload:Dictionary={"phase":name,"record":record};phases.append(payload);print("P3_1_R8_2_JSON "+JSON.stringify(payload))
	if _r81_evidence_dir.is_empty():return
	var f:=FileAccess.open(_r81_evidence_dir.path_join("phase-%02d-%s.json"%[phases.size(),name]),FileAccess.WRITE)
	if f==null:failures.append("evidence_write_failed:"+error_string(FileAccess.get_open_error()));return
	f.store_string(JSON.stringify(payload)+"\n");f.flush();f.close()

func _r82_finish(status:String,reason:String)->void:
	var final_status:=status if failures.is_empty() else "BLOCKED"
	var result:Dictionary={"suite":"P3_1_R8_2_EXACT_GEOMETRY_PROVENANCE","status":final_status,"reason":reason,"elapsed_usec":Time.get_ticks_usec()-started,
		"phase_count":phases.size(),"phases":phases,"failures":failures};print("P3_1_R8_2_RESULT "+JSON.stringify(result))
	if not _r81_evidence_dir.is_empty():
		var f:=FileAccess.open(_r81_evidence_dir.path_join("result.json"),FileAccess.WRITE)
		if f==null:printerr("P3_1_R8_2_RESULT_WRITE_FAIL "+error_string(FileAccess.get_open_error()));quit(1);return
		f.store_string(JSON.stringify(result)+"\n");f.flush();f.close()
	quit(0 if final_status=="DIAGNOSTIC_COMPLETE" else 1)
