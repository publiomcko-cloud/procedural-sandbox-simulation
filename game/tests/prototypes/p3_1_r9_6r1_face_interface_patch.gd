extends RefCounted

## Test-only shared interface authority for the bounded R9.6R1 A3/D3
## experiments. It consumes the two already-built boundary contours once and
## returns one immutable patch mesh plus identity and incidence evidence.
## The bridge is intentionally diagnostic: it is planar on the shared face and
## is not claimed to lie on the canonical SDF surface.
const Core := preload("res://tests/prototypes/p3_1_r9_2_diagnostic_base.gd")
const CUTOFF_SQUARED := 1.0e-12
const PLANE_EPSILON := 1.0e-6

func build(identity: Dictionary, left_mesh: Dictionary, right_mesh: Dictionary,
		axis: int, plane: float) -> Dictionary:
	var identity_result := _validate_identity(identity, axis, plane)
	if not identity_result.valid:
		return identity_result
	var left := _boundary_graph(left_mesh, axis, plane)
	var right := _boundary_graph(right_mesh, axis, plane)
	if not left.valid or not right.valid:
		return {"valid":false,"reason":"interface_boundary_graph_invalid","left":left,"right":right}
	var identity_text := _identity_text(identity, axis, plane)
	var patch_key := Core.sha256(identity_text.to_utf8_buffer())
	var same_contour := _same_keys(left.edge_keys, right.edge_keys)
	if same_contour:
		var direct_winding:bool=_same_directed_opposites(left.directed_edges,right.directed_edges)
		if not direct_winding:
			return {"valid":false,"reason":"identical_interface_contour_winding_conflict","patch_key_sha256":patch_key,
				"left_graph":left.summary,"right_graph":right.summary}
		return {"valid":true,"patch_key_sha256":patch_key,"identity":identity,
			"identity_text":identity_text,"mode":"shared_existing_contour",
			"mesh":Core.new_mesh(),"left_boundary_edge_count":left.edge_keys.size(),
			"right_boundary_edge_count":right.edge_keys.size(),"patch_boundary_edge_count":0,
			"left_consumes_patch_key":true,"right_consumes_patch_key":true,
			"contours_identical":true,"winding_compatible":direct_winding,
			"left_graph":left.summary,"right_graph":right.summary,"triangles":0,
			"left_boundary_vertex_keys":_component_vertex_keys(left.components),
			"right_boundary_vertex_keys":_component_vertex_keys(right.components),
			"shared_boundary_vertex_key_count":_shared_vertex_key_count(left.components,right.components),
			"correspondence_mode":"identity_shared_boundary","interface_vertex_count":_graph_vertex_count(left.summary),
			"triangle_count":0,"minimum_cross_squared":null,"cutoff_rejections":0,
			"cutoff_rejected_candidates":0,"vertex_authority":"INTERPOLATED_VOLUME"}
	if left.components.size() != right.components.size():
		return {"valid":false,"reason":"interface_component_count_mismatch","patch_key_sha256":patch_key,
			"left_graph":left.summary,"right_graph":right.summary,
			"left_boundary_vertex_keys":_component_vertex_keys(left.components),"right_boundary_vertex_keys":_component_vertex_keys(right.components),
			"shared_boundary_vertex_key_count":_shared_vertex_key_count(left.components,right.components)}
	var pairs := _pair_components(left.components, right.components)
	if not pairs.valid:
		return {"valid":false,"reason":"interface_component_pairing_failed","patch_key_sha256":patch_key,"detail":pairs,
			"left_graph":left.summary,"right_graph":right.summary,
			"left_boundary_vertex_keys":_component_vertex_keys(left.components),"right_boundary_vertex_keys":_component_vertex_keys(right.components),
			"shared_boundary_vertex_key_count":_shared_vertex_key_count(left.components,right.components)}
	var mesh := Core.new_mesh()
	var emitted_components: Array[Dictionary] = []
	var endpoint_connectors:Array[Dictionary]=[]
	for pair in pairs.pairs:
		var aligned := _align_paths(pair.left, pair.right, bool(pair.closed))
		if not aligned.valid:
			return {"valid":false,"reason":"interface_path_alignment_failed","patch_key_sha256":patch_key,"detail":aligned,
				"left_graph":left.summary,"right_graph":right.summary,
				"left_boundary_vertex_keys":_component_vertex_keys(left.components),"right_boundary_vertex_keys":_component_vertex_keys(right.components),
				"shared_boundary_vertex_key_count":_shared_vertex_key_count(left.components,right.components)}
		var strip := _zipper(mesh, aligned.left, aligned.right, bool(pair.closed), Vector3.RIGHT, axis, plane, identity)
		if not strip.valid:
			return {"valid":false,"reason":"interface_strip_generation_failed","patch_key_sha256":patch_key,"detail":strip,
				"left_graph":left.summary,"right_graph":right.summary,
				"left_boundary_vertex_keys":_component_vertex_keys(left.components),"right_boundary_vertex_keys":_component_vertex_keys(right.components),
				"shared_boundary_vertex_key_count":_shared_vertex_key_count(left.components,right.components)}
		emitted_components.append({"closed":pair.closed,"left_vertices":aligned.left.size(),
			"right_vertices":aligned.right.size(),"triangles":strip.triangles,
			"alignment_cost":aligned.cost,"correspondence_mode":strip.correspondence_mode,
			"correspondence_states":strip.correspondence_states,
			"minimum_cross_squared":strip.minimum_cross_squared,
			"cutoff_rejected_candidates":strip.cutoff_rejected_candidates,
			"endpoint_connectors":strip.endpoint_connectors})
		for connector in strip.endpoint_connectors:endpoint_connectors.append(connector)
	var patch_edges := _mesh_boundary_graph(mesh, axis, plane)
	if not patch_edges.valid:
		return {"valid":false,"reason":"interface_patch_boundary_invalid","patch_key_sha256":patch_key,"detail":patch_edges}
	var expected := _union_keys(left.edge_keys, right.edge_keys)
	for connector in endpoint_connectors:
		var connector_key:String=String(connector.get("edge_key",""))
		if not connector_key.is_empty() and not expected.has(connector_key):expected.append(connector_key)
	expected.sort()
	if not _same_keys(patch_edges.edge_keys, expected):
		return {"valid":false,"reason":"interface_patch_boundary_does_not_match_inputs","patch_key_sha256":patch_key,
			"expected_count":expected.size(),"actual_count":patch_edges.edge_keys.size(),
			"missing":_set_difference(expected,patch_edges.edge_keys),"extra":_set_difference(patch_edges.edge_keys,expected)}
	var winding := _winding_report(patch_edges.directed_edges,left.directed_edges,right.directed_edges)
	if not winding.valid:
		_flip_mesh(mesh)
		patch_edges=_mesh_boundary_graph(mesh,axis,plane)
		winding=_winding_report(patch_edges.directed_edges,left.directed_edges,right.directed_edges)
	if not winding.valid:
		return {"valid":false,"reason":"interface_patch_winding_conflict","patch_key_sha256":patch_key,
			"winding":winding,"left_graph":left.summary,"right_graph":right.summary,
			"patch_graph":patch_edges.summary}
	var triangle_count: int = int(mesh.positions.size()/3)
	return {"valid":true,"patch_key_sha256":patch_key,"identity":identity,
		"identity_text":identity_text,"mode":"single_shared_zipper_patch",
		"mesh":mesh,"mesh_sha256":_mesh_sha(mesh),"left_boundary_edge_count":left.edge_keys.size(),
		"right_boundary_edge_count":right.edge_keys.size(),"patch_boundary_edge_count":patch_edges.edge_keys.size(),
		"left_consumes_patch_key":true,"right_consumes_patch_key":true,"contours_identical":false,
		"winding_compatible":true,"left_graph":left.summary,"right_graph":right.summary,
		"left_boundary_vertex_keys":_component_vertex_keys(left.components),
		"right_boundary_vertex_keys":_component_vertex_keys(right.components),
		"shared_boundary_vertex_key_count":_shared_vertex_key_count(left.components,right.components),
		"endpoint_connectors":endpoint_connectors,
		"patch_graph":patch_edges.summary,"component_pairs":emitted_components,"triangle_count":triangle_count,
		"interface_vertex_count":_unique_vertex_count(mesh.positions),"minimum_cross_squared":_mesh_min_cross_squared(mesh.positions),
		"cutoff_rejections":0,"cutoff_rejected_candidates":_component_candidate_rejections(emitted_components),
		"correspondence_mode":"bounded_maximin_monotone_dp_with_roi_edge_connectors",
		"vertex_authority":"INTERPOLATED_VOLUME","endpoint_connector_count":endpoint_connectors.size(),
		"cutoff_squared":CUTOFF_SQUARED,"patch_geometry_claim":"topological face bridge only; canonical surface residual is diagnostic and no SDF projection is performed"}

func _validate_identity(identity: Dictionary, axis: int, plane: float) -> Dictionary:
	for key in ["left_chunk_id","right_chunk_id","lod_pair","field_revision","edit_revision","candidate","volume_payload_hashes"]:
		if not identity.has(key):
			return {"valid":false,"reason":"interface_identity_field_missing","field":key}
	if axis < 0 or axis > 2 or not is_finite(plane):
		return {"valid":false,"reason":"interface_plane_invalid"}
	if String(identity.left_chunk_id).is_empty() or String(identity.right_chunk_id).is_empty() or identity.left_chunk_id == identity.right_chunk_id:
		return {"valid":false,"reason":"interface_chunk_identity_invalid"}
	if typeof(identity.field_revision) != TYPE_INT or typeof(identity.edit_revision) != TYPE_INT:
		return {"valid":false,"reason":"interface_revision_invalid"}
	if typeof(identity.lod_pair) != TYPE_ARRAY or identity.lod_pair.size() != 2:
		return {"valid":false,"reason":"interface_lod_pair_invalid"}
	for key in ["interface_roi_min","interface_roi_max"]:
		if not identity.has(key) or typeof(identity[key])!=TYPE_ARRAY or identity[key].size()!=3:
			return {"valid":false,"reason":"interface_roi_bounds_invalid","field":key}
		for coordinate in identity[key]:
			if not is_finite(float(coordinate)):return {"valid":false,"reason":"interface_roi_bounds_nonfinite","field":key}
	var roi_min:Vector3=Vector3(float(identity.interface_roi_min[0]),float(identity.interface_roi_min[1]),float(identity.interface_roi_min[2]))
	var roi_max:Vector3=Vector3(float(identity.interface_roi_max[0]),float(identity.interface_roi_max[1]),float(identity.interface_roi_max[2]))
	if roi_min.x>=roi_max.x or roi_min.y>=roi_max.y or roi_min.z>=roi_max.z:return {"valid":false,"reason":"interface_roi_bounds_order_invalid"}
	if plane<roi_min[axis]-PLANE_EPSILON or plane>roi_max[axis]+PLANE_EPSILON:return {"valid":false,"reason":"interface_plane_outside_roi"}
	return {"valid":true}

func _identity_text(identity: Dictionary, axis: int, plane: float) -> String:
	var lod: Array = identity.lod_pair
	var hashes: Array = identity.volume_payload_hashes
	var roi_min:Array=identity.interface_roi_min;var roi_max:Array=identity.interface_roi_max
	return "candidate=%s|face_axis=%d|face_coordinate=%.9f|left=%s|right=%s|lod=%s,%s|field_revision=%d|edit_revision=%d|volume_payloads=%s,%s|roi_min=%.9f,%.9f,%.9f|roi_max=%.9f,%.9f,%.9f" % [
		String(identity.candidate),axis,plane,String(identity.left_chunk_id),String(identity.right_chunk_id),
		str(lod[0]),str(lod[1]),int(identity.field_revision),int(identity.edit_revision),
		String(hashes[0]) if hashes.size()>0 else "canonical",String(hashes[1]) if hashes.size()>1 else "canonical",
		float(roi_min[0]),float(roi_min[1]),float(roi_min[2]),float(roi_max[0]),float(roi_max[1]),float(roi_max[2])]

func _boundary_graph(mesh: Dictionary, axis: int, plane: float) -> Dictionary:
	return _mesh_boundary_graph(mesh, axis, plane)

func _mesh_boundary_graph(mesh: Dictionary, axis: int, plane: float) -> Dictionary:
	var positions: PackedVector3Array = mesh.get("positions", PackedVector3Array())
	if axis < 0 or axis > 2 or positions.size() % 3 != 0:
		return {"valid":false,"reason":"boundary_mesh_invalid"}
	var incidence: Dictionary = {}
	var directed: Dictionary = {}
	for i in range(0,positions.size(),3):
		for edge in [Vector2i(0,1),Vector2i(1,2),Vector2i(2,0)]:
			var a: Vector3 = positions[i+edge.x]
			var b: Vector3 = positions[i+edge.y]
			if absf(a[axis]-plane)>PLANE_EPSILON or absf(b[axis]-plane)>PLANE_EPSILON:
				continue
			var ka := Core._point_key(a)
			var kb := Core._point_key(b)
			var key := _edge_key(ka,kb)
			incidence[key] = int(incidence.get(key,0))+1
			if not directed.has(key):
				directed[key] = [ka,kb]
	var edge_keys: Array[String] = []
	for key_value in incidence.keys():
		var key := String(key_value)
		if int(incidence[key]) == 1:
			edge_keys.append(key)
		elif int(incidence[key]) > 2:
			return {"valid":false,"reason":"face_edge_nonmanifold","edge":key,"incidence":incidence[key]}
	edge_keys.sort()
	if edge_keys.is_empty():
		return {"valid":false,"reason":"interface_contour_has_no_boundary_edges"}
	var boundary_directed: Dictionary = {}
	for key in edge_keys:
		boundary_directed[key] = directed[key]
	return _graph_from_edges(edge_keys,boundary_directed)

func _graph_from_edges(edge_keys: Array[String], directed: Dictionary) -> Dictionary:
	var adjacency: Dictionary = {}
	for key in edge_keys:
		var ends := key.split("|")
		if ends.size()!=2:
			return {"valid":false,"reason":"face_edge_key_invalid","edge":key}
		for node in ends:
			if not adjacency.has(node): adjacency[node]=[]
			var neighbors: Array = adjacency[node]
			var other: String = String(ends[1]) if node == ends[0] else String(ends[0])
			if not neighbors.has(other): neighbors.append(other)
	for node in adjacency:
		adjacency[node].sort()
	var all_nodes: Array[String] = []
	for node in adjacency: all_nodes.append(String(node))
	all_nodes.sort()
	var visited: Dictionary = {}
	var components: Array[Dictionary] = []
	for seed in all_nodes:
		if visited.has(seed): continue
		var queue: Array[String]=[seed];visited[seed]=true;var head:=0;var nodes:Array[String]=[]
		while head<queue.size():
			var current:String=queue[head];head+=1;nodes.append(current)
			for neighbor_value in adjacency[current]:
				var neighbor:String=String(neighbor_value)
				if not visited.has(neighbor):visited[neighbor]=true;queue.append(neighbor)
		nodes.sort()
		var endpoints:Array[String]=[];var valid_degrees:=true
		var degree_histogram:Dictionary={};var invalid_degree_nodes:Array[Dictionary]=[];var degree_sum:=0
		for node in nodes:
			var degree:int=adjacency[node].size()
			degree_sum+=degree
			degree_histogram[degree]=int(degree_histogram.get(degree,0))+1
			if degree==1:endpoints.append(node)
			elif degree!=2:
				valid_degrees=false
				invalid_degree_nodes.append({"node":node,"degree":degree,"neighbors":adjacency[node].duplicate()})
		var closed:bool=endpoints.is_empty() and valid_degrees
		if not valid_degrees or (not closed and endpoints.size()!=2):
			return {"valid":false,"reason":"face_contour_branch_or_open_degree_invalid","nodes":nodes,
				"endpoint_count":endpoints.size(),"degree_histogram":degree_histogram,
				"invalid_degree_nodes":invalid_degree_nodes,"component_edge_count":int(degree_sum/2),
				"branch_diagnostic":"a boundary component may only be a simple open path or simple closed cycle"}
		var ordered := _order_component(nodes,adjacency,endpoints,closed)
		if not ordered.valid:return ordered
		components.append({"closed":closed,"points":ordered.points,"node_keys":nodes,"edge_count":nodes.size() if closed else nodes.size()-1})
	components.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return String(a.node_keys[0])<String(b.node_keys[0]))
	return {"valid":true,"edge_keys":edge_keys,"directed_edges":directed,"components":components,
		"summary":{"edge_count":edge_keys.size(),"component_count":components.size(),
		"components":components.map(func(c:Dictionary)->Dictionary:return {"closed":c.closed,"vertices":c.points.size(),"edges":c.edge_count}),
		"degree_histogram":_degree_histogram(adjacency)}}

func _order_component(nodes: Array[String], adjacency: Dictionary, endpoints: Array[String], closed: bool) -> Dictionary:
	var start: String
	if closed:start=nodes[0]
	else:
		endpoints.sort();start=endpoints[0]
	var points: Array[Vector3]=[]
	var current:String=start
	var previous:String=""
	var max_steps:int=nodes.size()+1
	for _step in range(max_steps):
		points.append(Core._key_point(current))
		var choices:Array=[]
		for next_value in adjacency[current]:
			var next:String=String(next_value)
			if next!=previous:choices.append(next)
		if choices.is_empty():break
		choices.sort()
		var next_node:String=String(choices[0])
		if closed and next_node==start:break
		previous=current;current=next_node
	if (closed and points.size()!=nodes.size()) or (not closed and points.size()!=nodes.size()):
		return {"valid":false,"reason":"face_contour_order_incomplete","expected_nodes":nodes.size(),"actual_nodes":points.size()}
	return {"valid":true,"points":points}

func _pair_components(left: Array[Dictionary], right: Array[Dictionary]) -> Dictionary:
	var remaining: Array[int]=[]
	for i in range(right.size()):remaining.append(i)
	var pairs:Array[Dictionary]=[]
	for lc in left:
		var best_index: int=-1;var best_cost:float=INF
		for ri in remaining:
			var rc:Dictionary=right[ri]
			if bool(lc.closed)!=bool(rc.closed):continue
			var cost:=_centroid(lc.points).distance_squared_to(_centroid(rc.points))
			if cost<best_cost:best_cost=cost;best_index=ri
		if best_index<0:return {"valid":false,"reason":"no_compatible_interface_component"}
		pairs.append({"left":lc.points,"right":right[best_index].points,"closed":lc.closed,"pair_cost":best_cost})
		remaining.erase(best_index)
	if not remaining.is_empty():return {"valid":false,"reason":"unpaired_right_interface_components","indices":remaining}
	return {"valid":true,"pairs":pairs}

func _align_paths(a: Array[Vector3], b: Array[Vector3], closed: bool) -> Dictionary:
	if a.size()<2 or b.size()<2:return {"valid":false,"reason":"interface_component_too_small"}
	if not closed:
		var forward:float=a[0].distance_squared_to(b[0])+a.back().distance_squared_to(b.back())
		var reverse:float=a[0].distance_squared_to(b.back())+a.back().distance_squared_to(b[0])
		var out:Array[Vector3]=b.duplicate();if reverse<forward:out.reverse()
		return {"valid":true,"left":a,"right":out,"cost":minf(forward,reverse)}
	var best:Array[Vector3]=[];var best_cost:float=INF
	for reverse_mode in [false,true]:
		var oriented:Array[Vector3]=b.duplicate()
		if reverse_mode:oriented.reverse()
		for shift in range(oriented.size()):
			var rotated:Array[Vector3]=[]
			for offset in range(oriented.size()):rotated.append(oriented[(shift+offset)%oriented.size()])
			var cost:=_path_alignment_cost(a,rotated,true)
			if cost<best_cost:best_cost=cost;best=rotated
	return {"valid":not best.is_empty(),"left":a,"right":best,"cost":best_cost}

func _path_alignment_cost(a: Array[Vector3], b: Array[Vector3], closed: bool) -> float:
	var total:=0.0
	for sample_index in range(32):
		var t:=float(sample_index)/32.0
		total+=_sample_path(a,t,closed).distance_squared_to(_sample_path(b,t,closed))
	return total

func _sample_path(points: Array[Vector3], t: float, closed: bool) -> Vector3:
	var count:int=points.size() if closed else points.size()-1
	var lengths:Array[float]=[];var total:=0.0
	for i in range(count):
		var j:=(i+1)%points.size();var length:=points[i].distance_to(points[j]);lengths.append(length);total+=length
	if total<=1.0e-15:return points[0]
	var target:=clampf(t,0.0,1.0)*total;var cumulative:=0.0
	for i in range(count):
		if target<=cumulative+lengths[i] or i==count-1:
			var j:=(i+1)%points.size();var local:float=(target-cumulative)/lengths[i] if lengths[i]>1.0e-15 else 0.0
			return points[i].lerp(points[j],clampf(local,0.0,1.0))
		cumulative+=lengths[i]
	return points.back()

func _zipper(mesh: Dictionary, left: Array[Vector3], right: Array[Vector3], closed: bool, toward: Vector3,
		axis:int,plane:float,identity:Dictionary) -> Dictionary:
	var a:Array[Vector3]=left.duplicate();var b:Array[Vector3]=right.duplicate()
	if closed:a.append(a[0]);b.append(b[0])
	var na:int=a.size()-1;var nb:int=b.size()-1
	if na<1 or nb<1:return {"valid":false,"reason":"zipper_path_empty"}
	var ca:=_normalized_cumulative(a);var cb:=_normalized_cumulative(b)
	var shared_start:bool=Core._point_key(a[0])==Core._point_key(b[0])
	var shared_end:bool=Core._point_key(a[na])==Core._point_key(b[nb])
	var endpoint_connectors:Array[Dictionary]=[]
	if not closed and not shared_start:
		var start_connector:=_make_roi_edge_connector(a[0],b[0],"start",identity,axis,plane)
		if not bool(start_connector.get("valid",false)):return {"valid":false,"reason":"open_start_roots_not_on_common_roi_edge","detail":start_connector}
		endpoint_connectors.append(start_connector)
	if not closed and not shared_end:
		var end_connector:=_make_roi_edge_connector(a[na],b[nb],"end",identity,axis,plane)
		if not bool(end_connector.get("valid",false)):return {"valid":false,"reason":"open_end_roots_not_on_common_roi_edge","detail":end_connector}
		endpoint_connectors.append(end_connector)
	var best_quality:Array=[]
	var best_alignment:Array=[]
	var back:Array=[]
	for _i in range(na+1):
		var q_row:Array=[];var alignment_row:Array=[];var back_row:Array=[]
		for _j in range(nb+1):q_row.append(-1.0);alignment_row.append(INF);back_row.append({})
		best_quality.append(q_row);best_alignment.append(alignment_row);back.append(back_row)
	best_quality[0][0]=INF;best_alignment[0][0]=0.0
	var rejected_candidates:=0
	var minimum_rejected_cross_squared:=INF
	for i in range(na+1):
		for j in range(nb+1):
			if float(best_quality[i][j])<0.0:continue
			if not closed and shared_start and i==0 and j==0:
				var start_relax:=_relax_correspondence(best_quality,best_alignment,back,a,b,ca,cb,0,0,1,1,"START")
				if not bool(start_relax.valid):rejected_candidates+=1;minimum_rejected_cross_squared=minf(minimum_rejected_cross_squared,float(start_relax.cross_squared))
				continue
			if not closed and shared_end and i==na-1 and j==nb-1:
				var end_relax:=_relax_correspondence(best_quality,best_alignment,back,a,b,ca,cb,i,j,na,nb,"END")
				if not bool(end_relax.valid):rejected_candidates+=1;minimum_rejected_cross_squared=minf(minimum_rejected_cross_squared,float(end_relax.cross_squared))
				continue
			if i<na:
				var left_relax:=_relax_correspondence(best_quality,best_alignment,back,a,b,ca,cb,i,j,i+1,j,"A")
				if not bool(left_relax.valid):rejected_candidates+=1;minimum_rejected_cross_squared=minf(minimum_rejected_cross_squared,float(left_relax.cross_squared))
			if j<nb:
				var right_relax:=_relax_correspondence(best_quality,best_alignment,back,a,b,ca,cb,i,j,i,j+1,"B")
				if not bool(right_relax.valid):rejected_candidates+=1;minimum_rejected_cross_squared=minf(minimum_rejected_cross_squared,float(right_relax.cross_squared))
	if float(best_quality[na][nb])<0.0:
		return {"valid":false,"reason":"no_cutoff_valid_monotone_correspondence",
			"correspondence_mode":"bounded_maximin_monotone_dp_with_roi_edge_connectors","cutoff_squared":CUTOFF_SQUARED,
			"cutoff_rejected_candidates":rejected_candidates,
			"minimum_rejected_cross_squared":minimum_rejected_cross_squared if is_finite(minimum_rejected_cross_squared) else null,
			"left_vertices":a.size(),"right_vertices":b.size(),"shared_start_root":shared_start,"shared_end_root":shared_end,
			"endpoint_connectors":endpoint_connectors}
	var transitions:Array[Dictionary]=[];var state_i:=na;var state_j:=nb
	while state_i!=0 or state_j!=0:
		var previous:Dictionary=back[state_i][state_j]
		if previous.is_empty():return {"valid":false,"reason":"correspondence_backtrack_incomplete","state":[state_i,state_j]}
		transitions.append(previous)
		state_i=int(previous.from_i);state_j=int(previous.from_j)
	transitions.reverse()
	var triangle_count:=0;var minimum_cross_squared:=INF
	var correspondence_states:Array=[[0,0]]
	for transition in transitions:
		var triangle:Array[Vector3]=_transition_triangle(a,b,int(transition.from_i),int(transition.from_j),String(transition.kind))
		if triangle.size()!=3:return {"valid":false,"reason":"correspondence_triangle_invalid","transition":transition}
		if not Core.add_triangle(mesh,triangle[0],triangle[1],triangle[2],toward,CUTOFF_SQUARED):
			return {"valid":false,"reason":"selected_transition_below_cutoff","transition":transition,"cross_squared":transition.cross_squared}
		triangle_count+=1;minimum_cross_squared=minf(minimum_cross_squared,float(transition.cross_squared))
		correspondence_states.append([int(transition.to_i),int(transition.to_j)])
	return {"valid":true,"triangles":triangle_count,"correspondence_mode":"bounded_maximin_monotone_dp_with_roi_edge_connectors",
		"correspondence_states":correspondence_states,"minimum_cross_squared":minimum_cross_squared,
		"minimum_triangle_quality":float(best_quality[na][nb]),"cutoff_rejections":0,
		"cutoff_rejected_candidates":rejected_candidates,
		"minimum_rejected_cross_squared":minimum_rejected_cross_squared if is_finite(minimum_rejected_cross_squared) else null,
		"shared_start_root":shared_start,"shared_end_root":shared_end,"endpoint_connectors":endpoint_connectors}

func _make_roi_edge_connector(a:Vector3,b:Vector3,label:String,identity:Dictionary,axis:int,plane:float)->Dictionary:
	var key_a:String=Core._point_key(a);var key_b:String=Core._point_key(b)
	if key_a==key_b:return {"valid":true,"needed":false,"label":label}
	if absf(a[axis]-plane)>PLANE_EPSILON or absf(b[axis]-plane)>PLANE_EPSILON:
		return {"valid":false,"reason":"connector_endpoint_off_interface_plane","label":label}
	var roi_min:Vector3=Vector3(float(identity.interface_roi_min[0]),float(identity.interface_roi_min[1]),float(identity.interface_roi_min[2]))
	var roi_max:Vector3=Vector3(float(identity.interface_roi_max[0]),float(identity.interface_roi_max[1]),float(identity.interface_roi_max[2]))
	var common_boundary_axis:=-1;var varying_axes:=0
	for coordinate_axis in range(3):
		if a[coordinate_axis]<roi_min[coordinate_axis]-PLANE_EPSILON or a[coordinate_axis]>roi_max[coordinate_axis]+PLANE_EPSILON or b[coordinate_axis]<roi_min[coordinate_axis]-PLANE_EPSILON or b[coordinate_axis]>roi_max[coordinate_axis]+PLANE_EPSILON:
			return {"valid":false,"reason":"connector_endpoint_outside_interface_roi","label":label,"axis":coordinate_axis,
				"left_coordinate":a[coordinate_axis],"right_coordinate":b[coordinate_axis],
				"roi_min":roi_min[coordinate_axis],"roi_max":roi_max[coordinate_axis]}
		if coordinate_axis==axis:continue
		if absf(a[coordinate_axis]-b[coordinate_axis])>PLANE_EPSILON:
			varying_axes+=1
			continue
		if absf(a[coordinate_axis]-roi_min[coordinate_axis])<=PLANE_EPSILON or absf(a[coordinate_axis]-roi_max[coordinate_axis])<=PLANE_EPSILON:
			common_boundary_axis=coordinate_axis
	if common_boundary_axis<0 or varying_axes!=1:
		return {"valid":false,"reason":"connector_not_on_single_outer_roi_edge","label":label,
			"left_root":key_a,"right_root":key_b,"varying_axes":varying_axes,"common_boundary_axis":common_boundary_axis}
	if absf(a[common_boundary_axis]-b[common_boundary_axis])>PLANE_EPSILON:
		return {"valid":false,"reason":"connector_endpoints_do_not_share_roi_boundary","label":label,"axis":common_boundary_axis}
	return {"valid":true,"needed":true,"label":label,"edge_key":_edge_key(key_a,key_b),
		"left_root":key_a,"right_root":key_b,"boundary_axis":common_boundary_axis,
		"boundary_coordinate":a[common_boundary_axis],"authority":"INTERPOLATED_VOLUME_ENDPOINTS"}

func _relax_correspondence(best_quality:Array,best_alignment:Array,back:Array,a:Array[Vector3],b:Array[Vector3],
		ca:Array[float],cb:Array[float],from_i:int,from_j:int,to_i:int,to_j:int,kind:String)->Dictionary:
	var triangle:Array[Vector3]=_transition_triangle(a,b,from_i,from_j,kind)
	if triangle.size()!=3:return {"valid":false,"cross_squared":0.0}
	var cross_squared:=_cross_squared(triangle[0],triangle[1],triangle[2])
	if not is_finite(cross_squared) or cross_squared<=CUTOFF_SQUARED:return {"valid":false,"cross_squared":cross_squared}
	var quality:=_triangle_quality(triangle[0],triangle[1],triangle[2],cross_squared)
	var candidate_quality:=minf(float(best_quality[from_i][from_j]),quality)
	var candidate_alignment:=float(best_alignment[from_i][from_j])+absf(float(ca[to_i])-float(cb[to_j]))
	var current_quality:=float(best_quality[to_i][to_j]);var current_alignment:=float(best_alignment[to_i][to_j])
	if _better_correspondence(candidate_quality,candidate_alignment,current_quality,current_alignment):
		best_quality[to_i][to_j]=candidate_quality;best_alignment[to_i][to_j]=candidate_alignment
		back[to_i][to_j]={"from_i":from_i,"from_j":from_j,"to_i":to_i,"to_j":to_j,"kind":kind,
			"cross_squared":cross_squared,"triangle_quality":quality}
	return {"valid":true,"cross_squared":cross_squared}

func _transition_triangle(a:Array[Vector3],b:Array[Vector3],i:int,j:int,kind:String)->Array[Vector3]:
	var triangle:Array[Vector3]=[]
	match kind:
		"A":triangle=[a[i],a[i+1],b[j]]
		"B":triangle=[a[i],b[j+1],b[j]]
		"START":triangle=[a[0],a[1],b[1]]
		"END":triangle=[a[a.size()-2],a[a.size()-1],b[b.size()-2]]
	return triangle

func _better_correspondence(candidate_quality:float,candidate_alignment:float,current_quality:float,current_alignment:float)->bool:
	if candidate_quality>current_quality+1.0e-15:return true
	if absf(candidate_quality-current_quality)<=1.0e-15 and candidate_alignment<current_alignment-1.0e-15:return true
	return false

func _triangle_quality(a:Vector3,b:Vector3,c:Vector3,cross_squared:float)->float:
	var max_edge_squared:=maxf((b-a).length_squared(),maxf((c-b).length_squared(),(a-c).length_squared()))
	if max_edge_squared<=0.0:return 0.0
	return cross_squared/(max_edge_squared*max_edge_squared)

func _normalized_cumulative(points: Array[Vector3]) -> Array[float]:
	var lengths:Array[float]=[];var total:=0.0
	for i in range(points.size()-1):var length:=points[i].distance_to(points[i+1]);lengths.append(length);total+=length
	var out:Array[float]=[0.0];var cumulative:=0.0
	for length in lengths:cumulative+=length;out.append(cumulative/total if total>0.0 else 0.0)
	return out

func _winding_report(patch: Dictionary, left: Dictionary, right: Dictionary) -> Dictionary:
	var left_ok:=true;var right_ok:=true;var left_bad:Array[String]=[];var right_bad:Array[String]=[]
	for key in left:
		if not patch.has(key) or not _opposite(patch[key],left[key]):left_ok=false;left_bad.append(String(key))
	for key in right:
		if not patch.has(key) or not _opposite(patch[key],right[key]):right_ok=false;right_bad.append(String(key))
	return {"valid":left_ok and right_ok,"left_opposite":left_ok,"right_opposite":right_ok,"left_bad":left_bad,"right_bad":right_bad}

func _opposite(a: Array, b: Array) -> bool:
	return String(a[0])==String(b[1]) and String(a[1])==String(b[0])

func _same_directed_opposites(a: Dictionary,b: Dictionary)->bool:
	if a.size()!=b.size():return false
	for key in a:
		if not b.has(key) or not _opposite(a[key],b[key]):return false
	return true

func _same_keys(a: Array[String],b:Array[String])->bool:
	if a.size()!=b.size():return false
	var right:Dictionary={};for key in b:right[key]=true
	for key in a:if not right.has(key):return false
	return true

func _union_keys(a:Array[String],b:Array[String])->Array[String]:
	var out:Dictionary={}
	for key in a:
		out[key]=true
	for key in b:
		out[key]=true
	var keys:Array[String]=[]
	for key in out:
		keys.append(String(key))
	keys.sort()
	return keys

func _set_difference(a:Array[String],b:Array[String])->Array[String]:
	var other:Dictionary={}
	for key in b:other[key]=true
	var out:Array[String]=[]
	for key in a:
		if not other.has(key):out.append(key)
	return out

func _flip_mesh(mesh:Dictionary)->void:
	var positions:PackedVector3Array=mesh.positions;var normals:PackedVector3Array=mesh.normals
	for i in range(0,positions.size(),3):
		var swap:Vector3=positions[i+1];positions[i+1]=positions[i+2];positions[i+2]=swap
		if i+2<normals.size():
			normals[i]=-normals[i];normals[i+1]=-normals[i+1];normals[i+2]=-normals[i+2]
	mesh.positions=positions;mesh.normals=normals

func _edge_key(a:String,b:String)->String:return a+"|"+b if a<b else b+"|"+a
func _centroid(points:Array[Vector3])->Vector3:
	var out:=Vector3.ZERO
	for point in points:out+=point
	return out/float(points.size()) if not points.is_empty() else out
func _cross_squared(a:Vector3,b:Vector3,c:Vector3)->float:return (b-a).cross(c-a).length_squared()
func _graph_vertex_count(summary:Dictionary)->int:
	var total:=0
	for component in summary.get("components",[]):total+=int(component.get("vertices",0))
	return total
func _component_vertex_keys(components:Array[Dictionary])->Array:
	var rows:Array=[]
	for index in range(components.size()):
		var keys:Array=[]
		for point in components[index].get("points",[]):keys.append(Core._point_key(point))
		rows.append({"component_index":index,"closed":bool(components[index].get("closed",false)),"ordered_quantized_mesh_vertex_keys":keys})
	return rows
func _shared_vertex_key_count(left:Array[Dictionary],right:Array[Dictionary])->int:
	var left_keys:Dictionary={};var shared:Dictionary={}
	for component in left:
		for point in component.get("points",[]):left_keys[Core._point_key(point)]=true
	for component in right:
		for point in component.get("points",[]):
			var key:String=Core._point_key(point)
			if left_keys.has(key):shared[key]=true
	return shared.size()
func _unique_vertex_count(positions:PackedVector3Array)->int:
	var seen:Dictionary={}
	for point in positions:seen[Core._point_key(point)]=true
	return seen.size()
func _mesh_min_cross_squared(positions:PackedVector3Array)->Variant:
	if positions.is_empty() or positions.size()%3!=0:return null
	var minimum:=INF
	for i in range(0,positions.size(),3):minimum=minf(minimum,_cross_squared(positions[i],positions[i+1],positions[i+2]))
	return minimum if is_finite(minimum) else null
func _component_candidate_rejections(components:Array[Dictionary])->int:
	var total:=0
	for component in components:total+=int(component.get("cutoff_rejected_candidates",0))
	return total
func _degree_histogram(adjacency:Dictionary)->Dictionary:
	var out:Dictionary={}
	for node in adjacency:var degree:int=adjacency[node].size();out[degree]=int(out.get(degree,0))+1
	return out
func _mesh_sha(mesh:Dictionary)->String:
	var position_bytes:PackedByteArray=mesh.positions.to_byte_array()
	var normal_bytes:PackedByteArray=mesh.normals.to_byte_array()
	var hash:=HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(("%d:%d:"%[position_bytes.size(),normal_bytes.size()]).to_utf8_buffer())
	if not position_bytes.is_empty():hash.update(position_bytes)
	if not normal_bytes.is_empty():hash.update(normal_bytes)
	return hash.finish().hex_encode()
