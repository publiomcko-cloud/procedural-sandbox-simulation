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
			"left_graph":left.summary,"right_graph":right.summary,"triangles":0}
	if left.components.size() != right.components.size():
		return {"valid":false,"reason":"interface_component_count_mismatch","patch_key_sha256":patch_key,
			"left_graph":left.summary,"right_graph":right.summary}
	var pairs := _pair_components(left.components, right.components)
	if not pairs.valid:
		return {"valid":false,"reason":"interface_component_pairing_failed","patch_key_sha256":patch_key,"detail":pairs}
	var mesh := Core.new_mesh()
	var emitted_components: Array[Dictionary] = []
	for pair in pairs.pairs:
		var aligned := _align_paths(pair.left, pair.right, bool(pair.closed))
		if not aligned.valid:
			return {"valid":false,"reason":"interface_path_alignment_failed","patch_key_sha256":patch_key,"detail":aligned}
		var strip := _zipper(mesh, aligned.left, aligned.right, bool(pair.closed), Vector3.RIGHT)
		if not strip.valid:
			return {"valid":false,"reason":"interface_strip_generation_failed","patch_key_sha256":patch_key,"detail":strip}
		emitted_components.append({"closed":pair.closed,"left_vertices":aligned.left.size(),
			"right_vertices":aligned.right.size(),"triangles":strip.triangles,
			"alignment_cost":aligned.cost})
	var patch_edges := _mesh_boundary_graph(mesh, axis, plane)
	if not patch_edges.valid:
		return {"valid":false,"reason":"interface_patch_boundary_invalid","patch_key_sha256":patch_key,"detail":patch_edges}
	var expected := _union_keys(left.edge_keys, right.edge_keys)
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
		"patch_graph":patch_edges.summary,"component_pairs":emitted_components,"triangle_count":triangle_count,
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
	return {"valid":true}

func _identity_text(identity: Dictionary, axis: int, plane: float) -> String:
	var lod: Array = identity.lod_pair
	var hashes: Array = identity.volume_payload_hashes
	return "candidate=%s|face_axis=%d|face_coordinate=%.9f|left=%s|right=%s|lod=%s,%s|field_revision=%d|edit_revision=%d|volume_payloads=%s,%s" % [
		String(identity.candidate),axis,plane,String(identity.left_chunk_id),String(identity.right_chunk_id),
		str(lod[0]),str(lod[1]),int(identity.field_revision),int(identity.edit_revision),
		String(hashes[0]) if hashes.size()>0 else "canonical",String(hashes[1]) if hashes.size()>1 else "canonical"]

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
		for node in nodes:
			var degree:int=adjacency[node].size()
			if degree==1:endpoints.append(node)
			elif degree!=2:valid_degrees=false
		var closed:bool=endpoints.is_empty() and valid_degrees
		if not valid_degrees or (not closed and endpoints.size()!=2):
			return {"valid":false,"reason":"face_contour_branch_or_open_degree_invalid","nodes":nodes,"endpoint_count":endpoints.size()}
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

func _zipper(mesh: Dictionary, left: Array[Vector3], right: Array[Vector3], closed: bool, toward: Vector3) -> Dictionary:
	var a:Array[Vector3]=left.duplicate();var b:Array[Vector3]=right.duplicate()
	if closed:a.append(a[0]);b.append(b[0])
	var na:int=a.size()-1;var nb:int=b.size()-1
	if na<1 or nb<1:return {"valid":false,"reason":"zipper_path_empty"}
	var ca:=_normalized_cumulative(a);var cb:=_normalized_cumulative(b)
	var i:=0;var j:=0;var triangle_count:=0
	while i<na or j<nb:
		var next_a:float=float(ca[i+1]) if i<na else INF
		var next_b:float=float(cb[j+1]) if j<nb else INF
		if i<na and j<nb and absf(next_a-next_b)<=1.0e-12:
			if not Core.add_triangle(mesh,a[i],a[i+1],b[j],toward,CUTOFF_SQUARED):return {"valid":false,"reason":"interface_triangle_below_cutoff","side":"both","i":i,"j":j,"cross_squared":_cross_squared(a[i],a[i+1],b[j])}
			if not Core.add_triangle(mesh,a[i+1],b[j+1],b[j],toward,CUTOFF_SQUARED):return {"valid":false,"reason":"interface_triangle_below_cutoff","side":"both","i":i,"j":j,"cross_squared":_cross_squared(a[i+1],b[j+1],b[j])}
			i+=1;j+=1;triangle_count+=2
		elif next_a<next_b:
			if not Core.add_triangle(mesh,a[i],a[i+1],b[j],toward,CUTOFF_SQUARED):return {"valid":false,"reason":"interface_triangle_below_cutoff","side":"left","i":i,"j":j,"cross_squared":_cross_squared(a[i],a[i+1],b[j])}
			i+=1;triangle_count+=1
		else:
			if not Core.add_triangle(mesh,a[i],b[j+1],b[j],toward,CUTOFF_SQUARED):return {"valid":false,"reason":"interface_triangle_below_cutoff","side":"right","i":i,"j":j,"cross_squared":_cross_squared(a[i],b[j+1],b[j])}
			j+=1;triangle_count+=1
	return {"valid":true,"triangles":triangle_count}

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
	var out:Dictionary={};for key in a:out[key]=true
	for key in b:out[key]=true
	var keys:Array[String]=[];for key in out:keys.append(String(key));keys.sort();return keys

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
func _degree_histogram(adjacency:Dictionary)->Dictionary:
	var out:Dictionary={}
	for node in adjacency:var degree:int=adjacency[node].size();out[degree]=int(out.get(degree,0))+1
	return out
func _mesh_sha(mesh:Dictionary)->String:
	var position_bytes:PackedByteArray=mesh.positions.to_byte_array();var normal_bytes:PackedByteArray=mesh.normals.to_byte_array();var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(("%d:%d:"%[position_bytes.size(),normal_bytes.size()]).to_utf8_buffer());if not position_bytes.is_empty():hash.update(position_bytes);if not normal_bytes.is_empty():hash.update(normal_bytes);return hash.finish().hex_encode()
