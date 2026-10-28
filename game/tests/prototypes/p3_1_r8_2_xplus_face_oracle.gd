extends "res://tests/prototypes/p3_1_r8_2_geometry_provenance.gd"

## Focused test-only oracle for the x=16 face around the frozen X+ mismatch.
## It compares the canonical piecewise-linear face contour with the actual
## transition-cell and complete chunk meshes; production code is not changed.

func _initialize() -> void:
	call_deferred("_run_xplus_face_oracle")

func _run_xplus_face_oracle() -> void:
	_r81_evidence_dir=OS.get_environment("P31_R82_EVIDENCE_DIR")
	var pre:Dictionary=_r8_preflight()
	if not pre.get("valid",false):
		print("P3_1_R8_2_FACE_ORACLE "+JSON.stringify({"valid":false,"reason":"preflight_failed","preflight":pre}))
		quit(1);return
	var setup:Dictionary=_make_snapshot("center_fill_then_wall_carve")
	if not setup.get("valid",false):
		print("P3_1_R8_2_FACE_ORACLE "+JSON.stringify({"valid":false,"reason":"snapshot_failed"}))
		quit(1);return
	var snapshot:Dictionary=setup.snapshot
	var lattice:=Vector3i(30,4,14)
	var face_triangles:Array[Dictionary]=[]
	var fan_tetra_oracle:Array[Dictionary]=[]
	var center:Vector3=Vector3(lattice)*T.LOD0_STEP+Vector3.ONE*(T.LOD1_STEP*0.5)
	var center_density:float=T.sample_canonical(SEED,center,snapshot)
	for tri_value in T._boundary_triangles(lattice,[1]):
		var tri:Array=tri_value
		var p0:Vector3=tri[0];var p1:Vector3=tri[1];var p2:Vector3=tri[2]
		if not (absf(p0.x-16.0)<0.000001 and absf(p1.x-16.0)<0.000001 and absf(p2.x-16.0)<0.000001):
			continue
		var points:Array[Vector3]=[tri[0],tri[1],tri[2]]
		var values:Array[float]=[]
		for p in points:values.append(T.sample_canonical(SEED,p,snapshot))
		var tetra_points:Array[Vector3]=[center,points[0],points[1],points[2]]
		var tetra_values:Array[float]=[center_density,values[0],values[1],values[2]]
		var tetra_poly:Dictionary=_poly(tetra_points,tetra_values,false)
		fan_tetra_oracle.append({"tetra_points":tetra_points.map(func(v:Vector3)->Array[float]:return _vec3_array(v)),
			"tetra_densities":tetra_values,"tetra_density_f32":[_float32_bytes(center_density),_float32_bytes(values[0]),_float32_bytes(values[1]),_float32_bytes(values[2])],
			"oracle_triangles":_json_tris(tetra_poly.get("triangles",[])),"oracle_rejected_triangles":_json_tris(tetra_poly.get("pre_cutoff_triangles",[]))})
		var crossings:Array[Vector3]=[]
		for edge in [[0,1],[1,2],[2,0]]:
			var ia:int=edge[0];var ib:int=edge[1];var da:float=values[ia];var db:float=values[ib]
			if da*db<0.0:crossings.append(points[ia].lerp(points[ib],da/(da-db)))
		if crossings.size()==2:
			face_triangles.append({"points":points,"density":values,"contour_segment":[crossings[0],crossings[1]]})
	var transition_cell:Dictionary=T.build_transition_cell(SEED,lattice,[1],snapshot)
	var transition_vertices:PackedVector3Array=transition_cell.get("vertices",PackedVector3Array())
	var transition_segments:Dictionary=_contour_with_sources(transition_vertices,0,16.0)
	var transition_triangles:Array[Dictionary]=[]
	for index in range(0,transition_vertices.size(),3):
		var tri:Array[Vector3]=[transition_vertices[index],transition_vertices[index+1],transition_vertices[index+2]]
		var plane_vertices:Array[Vector3]=[]
		for point in tri:
			if absf(point.x-16.0)<=0.000001:plane_vertices.append(point)
		if not plane_vertices.is_empty():
			transition_triangles.append({"triangle_index":index/3,"vertices":tri.map(func(v:Vector3)->Array[float]:return _vec3_array(v)),
				"plane_vertex_count":plane_vertices.size(),"plane_vertices":plane_vertices.map(func(v:Vector3)->Array[float]:return _vec3_array(v))})
	var chunk_a:Dictionary=_build_r81_world_chunk(1,Vector2i(0,0),Vector2i(3,2),snapshot)
	var chunk_b0:Dictionary=_build_r81_world_chunk(0,Vector2i(1,0),Vector2i(0,2),snapshot)
	var chunk_b1:Dictionary=_build_r81_world_chunk(1,Vector2i(1,0),Vector2i(0,2),snapshot)
	var manual_face_oracle:Array[Dictionary]=_manual_face_oracle(snapshot)
	var contour_a:Dictionary=_contour_with_sources(chunk_a.get("positions",PackedVector3Array()),0,16.0)
	var contour_b0:Dictionary=_contour_with_sources(chunk_b0.get("positions",PackedVector3Array()),0,16.0)
	var contour_b1:Dictionary=_contour_with_sources(chunk_b1.get("positions",PackedVector3Array()),0,16.0)
	var manual_keys:Array[String]=_manual_contour_keys(manual_face_oracle)
	var keys_a:Dictionary={};for segment in contour_a.segments:keys_a[String(segment.key_1e_minus_5)]=true
	var keys_b0:Dictionary={};for segment in contour_b0.segments:keys_b0[String(segment.key_1e_minus_5)]=true
	var keys_b1:Dictionary={};for segment in contour_b1.segments:keys_b1[String(segment.key_1e_minus_5)]=true
	var manual_in_b0:=true;var manual_absent_a:=true;var manual_in_b1:=true
	for key in manual_keys:
		manual_in_b0=manual_in_b0 and keys_b0.has(key);manual_absent_a=manual_absent_a and not keys_a.has(key);manual_in_b1=manual_in_b1 and keys_b1.has(key)
	var all_valid:bool=transition_cell.get("valid",false) and chunk_a.get("valid",false) and chunk_b0.get("valid",false) and chunk_b1.get("valid",false)
	var result:Dictionary={"valid":all_valid,"scenario_input_sha256":INPUT_SHA_FILL_CARVE,"interface_plane_x":16.0,
		"world_lattice_origin":[lattice.x,lattice.y,lattice.z],"selected_face_ids":[1],"fine_face_triangle_count":8,
		"face_triangle_piecewise_linear_oracle":face_triangles,"manual_face_oracle_from_explicit_coordinates":manual_face_oracle,
		"center_world":_vec3_array(center),"center_density":center_density,
		"center_density_f32":_float32_bytes(center_density),"fan_tetra_piecewise_linear_oracle":fan_tetra_oracle,"transition_cell_valid":transition_cell.get("valid",false),
		"transition_cell_triangle_count":transition_cell.get("triangle_count",-1),"transition_cell_sample_count":transition_cell.get("sample_count",-1),
		"transition_cell_vertex_count":transition_vertices.size(),"transition_cell_plane_triangle_count":transition_triangles.size(),
		"transition_cell_plane_triangles":transition_triangles,"transition_cell_contour":transition_segments,
		"manual_oracle_segment_keys":manual_keys,"manual_oracle_segments_present_positive_lod0":manual_in_b0,
		"manual_oracle_segments_absent_negative_lod1":manual_absent_a,"manual_oracle_segments_present_positive_lod1":manual_in_b1,
		"chunk_contours":{"negative_lod1":contour_a,"positive_lod0":contour_b0,"positive_lod1":contour_b1},
		"interpretation":"same canonical face samples and face triangles are compared against emitted mesh intersections; no geometry tolerance or production edit"}
	print("P3_1_R8_2_FACE_ORACLE "+JSON.stringify(result))
	if not _r81_evidence_dir.is_empty():
		var path:String=_r81_evidence_dir.path_join("xplus-face-oracle.json")
		var file:=FileAccess.open(path,FileAccess.WRITE)
		if file==null:printerr("P3_1_R8_2_FACE_ORACLE_WRITE_FAILED");quit(1);return
		file.store_string(JSON.stringify(result)+"\n");file.flush();file.close()
	quit(0 if all_valid else 1)


func _manual_face_oracle(snapshot:Dictionary)->Array[Dictionary]:
	# Independent hand-specified two fine triangles that contain the frozen
	# unmatched contour. This deliberately does not call interface_triangles or
	# _boundary_triangles to construct the expected geometry.
	var triangles:Array[Array]=[
		[Vector3(16.0,2.0,7.0),Vector3(16.0,2.5,7.0),Vector3(16.0,2.5,7.5)],
		[Vector3(16.0,2.0,7.0),Vector3(16.0,2.5,7.5),Vector3(16.0,2.0,7.5)],
	]
	var result:Array[Dictionary]=[]
	for tri in triangles:
		var values:Array[float]=[]
		for point in tri:values.append(T.sample_canonical(SEED,point,snapshot))
		var hits:Array[Vector3]=[]
		for edge in [[0,1],[1,2],[2,0]]:
			var a:=int(edge[0]);var b:=int(edge[1]);var da:=values[a];var db:=values[b]
			if da*db<0.0:hits.append(tri[a].lerp(tri[b],da/(da-db)))
		result.append({"triangle_world":tri.map(func(v:Vector3)->Array[float]:return _vec3_array(v)),
			"sample_density":values,"sample_density_f32":[_float32_bytes(values[0]),_float32_bytes(values[1]),_float32_bytes(values[2])],
			"contour_world":hits.map(func(v:Vector3)->Array[float]:return _vec3_array(v)),
			"contour_vertex_f32":hits.map(func(v:Vector3)->String:return _vec3_bytes(v))})
	return result


func _manual_contour_keys(rows:Array[Dictionary])->Array[String]:
	var result:Array[String]=[]
	for row in rows:
		var hits:Array=row.contour_world
		if hits.size()==2:
			var a:Vector3=_parse_vector3(hits[0]);var b:Vector3=_parse_vector3(hits[1])
			result.append(_r8_edge_key(_r8_point_key(a),_r8_point_key(b)))
	return result
