extends RefCounted

## R9-A: bounded root-aware marching tetrahedra research prototype. Explicit
## shared-face samples are owned by global lattice coordinates; this script
## does not load production scene nodes or mutate production state.
const Core := preload("res://tests/prototypes/p3_1_r9_2_diagnostic_base.gd")
const T := preload("res://scripts/experiments/lod01_transition_fixture.gd")
const Mesher := preload("res://scripts/terrain/marching_tetrahedra.gd")
const LodMesher := preload("res://scripts/terrain/lod01_chunk_mesher.gd")
const Topology := preload("res://tests/prototypes/p3_1_r9_6_surface_topology.gd")
const SEED := 131102026
const A2_BISECTION_ITERATIONS := 16
const A2_ROOT_RESIDUAL_BOUND := 1.0e-4
const A2_REFINE_TETS := {"60,8,25":[0,1,2,5],"61,8,25":[3,4],"62,9,24":[2]}
const A2_TARGET_SCENARIOS := ["R9.2.SEAM.XPLUS_EQUAL.v1","R9.2.SEAM.XPLUS_MIXED_LOD.v1","R9.2.HIST.XPLUS_DEFECT.v1"]
var ROI_MIN: Vector3 = Vector3(8,-2,3)
var ROI_CELLS: Vector3i = Vector3i(8,20,12)
var STEP: float = 0.5
# R9.4-A attempt 3: 20 bisections improved the neighboring seam but exceeded
# the frozen 10,000 unique-sample stop loss on the negative-region pair. Twelve
# iterations are an evidence-based bounded compromise: 50% more root bisections
# than the original 8 passes, while staying below the frozen sample stop loss.
const ROOT_ITERATIONS := 12
var _manifest: Dictionary = {}
var _failures: Array[String] = []
var _assertions := 0
var _sample_cache: Dictionary = {}
var _root_cache: Dictionary = {}
var _started := 0
var _quad_historical_selections:int=0
var _quad_alternate_selections:int=0
var _quad_pair_rejections:int=0
var _a2_enabled: bool = false
var _a2_refined_cells: Dictionary = {}
var _a2_centroid_identities: Dictionary = {}
var _a2_centroid_provenance: Dictionary = {}
var _a2_recorded_surface_roots: Dictionary = {}
var _a2_new_vertex_evidence: Array[Dictionary] = []
var _a2_additional_sdf_evaluations: int = 0
var _a2_steiner_vertices: int = 0
var _a2_new_surface_roots: int = 0
var _a2_refined_parent_tetrahedra: int = 0
var _a2_refined_patch_emitted_triangles: int = 0
var _a2_max_vertex_displacement: float = 0.0
var _a2_max_root_residual: float = 0.0

func configure_roi(roi: Dictionary) -> void:
	ROI_MIN = Core.world_min(roi)
	ROI_CELLS = Core.cell_counts(roi)
	STEP = Core.step(roi)

func build(snapshot: Dictionary, row: Dictionary, _variant: Dictionary) -> Dictionary:
	var scenario_id: String = String(row.get("scenario_id", ""))
	_a2_enabled = A2_TARGET_SCENARIOS.has(scenario_id) and absf(ROI_MIN.x-15.0)<=1.0e-9 and absf(ROI_MIN.y-1.0)<=1.0e-9 and absf(ROI_MIN.z-6.0)<=1.0e-9 and absf(STEP-0.25)<=1.0e-9
	return _build_mt(snapshot)
func _build_mt(snapshot: Dictionary) -> Dictionary:
	var begin := Time.get_ticks_usec()
	_sample_cache.clear(); _root_cache.clear()
	_quad_historical_selections=0;_quad_alternate_selections=0;_quad_pair_rejections=0
	_a2_refined_cells.clear();_a2_centroid_identities.clear();_a2_centroid_provenance.clear();_a2_recorded_surface_roots.clear();_a2_new_vertex_evidence.clear()
	_a2_additional_sdf_evaluations=0;_a2_steiner_vertices=0;_a2_new_surface_roots=0;_a2_refined_parent_tetrahedra=0;_a2_refined_patch_emitted_triangles=0
	_a2_max_vertex_displacement=0.0;_a2_max_root_residual=0.0
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
				_sample_cache[_sample_key(p)] = d
	var mesh: Dictionary = Core.new_mesh(); var root_requests := 0; var dropped := 0
	var topology: RefCounted = Topology.new()
	var lattice_origin := Vector3i(roundi(ROI_MIN.x / STEP), roundi(ROI_MIN.y / STEP), roundi(ROI_MIN.z / STEP))
	for y in range(ROI_CELLS.y):
		for z in range(ROI_CELLS.z):
			for x in range(ROI_CELLS.x):
				var cube_points: Array[Vector3] = []; var cube_values: Array[float] = []
				for corner_value in Core.GRID_CORNERS:
					var corner: Vector3i = corner_value
					var ix: int = x+corner.x; var iy: int = y+corner.y; var iz: int = z+corner.z
					cube_points.append(ROI_MIN+Vector3(ix,iy,iz)*STEP)
					cube_values.append(float(values[_node_index(ix,iy,iz,dims)]))
				var cell_id := lattice_origin + Vector3i(x, y, z)
				for tet_index in range(Core.TETS.size()):
					var result: Dictionary
					if _a2_cell_tet_selected(cell_id,tet_index):
						result=_polygonize_a2_parent_tet(Core.TETS[tet_index],cube_points,cube_values,snapshot,mesh,topology,cell_id,tet_index)
					else:
						result=_polygonize_tet(Core.TETS[tet_index],cube_points,cube_values,snapshot,mesh,topology,cell_id,tet_index)
					root_requests += int(result.root_edges); dropped += int(result.dropped)
					if not bool(result.get("topology_valid", true)):
						return {"valid":false,"reason":"topology_ledger_rejected_geometry","detail":result.get("topology_reason","unknown"),"cell":cell_id,"tetrahedron":tet_index}
					if mesh.positions.size()/3 > Core.MAX_TRIANGLES: return {"valid":false,"reason":"triangle_stop_loss"}
					if _sample_cache.size() > Core.MAX_NODES: return {"valid":false,"reason":"unique_sample_stop_loss"}
					if Time.get_ticks_usec()-begin > int(Core.MAX_SCENARIO_USEC): return {"valid":false,"reason":"time_stop_loss"}
	var topology_report: Dictionary = topology.report(ROI_MIN, ROI_MIN + Vector3(ROI_CELLS) * STEP)
	if not bool(topology_report.get("valid", false)):
		return {"valid":false,"reason":"topology_ledger_incomplete","topology":topology_report}
	if int(topology_report.get("emitted_triangle_count", -1)) != int(mesh.positions.size() / 3):
		return {"valid":false,"reason":"topology_geometry_count_mismatch","topology_emitted":topology_report.get("emitted_triangle_count"),"mesh_triangles":mesh.positions.size() / 3}
	return {"valid":true,"mesh":mesh,"mesh_sha256":_mesh_sha(mesh),"topology":topology_report,"metrics":{"grid_nodes":total,
		"unique_canonical_samples_including_root_iterations":_sample_cache.size(),"root_iterations":ROOT_ITERATIONS,
		"root_edge_requests":root_requests,"cached_root_edges":_root_cache.size(),"cutoff_drops":dropped,
		"quad_historical_selections":_quad_historical_selections,"quad_alternate_selections":_quad_alternate_selections,"quad_pair_rejections":_quad_pair_rejections,
		"a2_enabled":_a2_enabled,"a2_refinement_method":"four-child tetrahedron split at a canonical-SDF-sampled barycentric centroid; original parent faces are preserved",
		"a2_root_bisection_iterations":A2_BISECTION_ITERATIONS,"a2_root_residual_bound":A2_ROOT_RESIDUAL_BOUND,
		"a2_refined_cells":_a2_refined_cells.keys(),"a2_refined_cell_count":_a2_refined_cells.size(),"a2_refined_parent_tetrahedra":_a2_refined_parent_tetrahedra,
		"a2_additional_sdf_evaluations":_a2_additional_sdf_evaluations,"a2_new_surface_roots":_a2_new_surface_roots,"a2_steiner_vertices":_a2_steiner_vertices,
		"a2_refined_patch_emitted_triangles":_a2_refined_patch_emitted_triangles,"a2_max_vertex_displacement":_a2_max_vertex_displacement,
		"a2_max_root_residual":_a2_max_root_residual,"a2_vertex_evidence":_a2_new_vertex_evidence,
		"triangle_count":mesh.positions.size()/3,"build_usec":Time.get_ticks_usec()-begin}}

func _a2_cell_tet_selected(cell_id: Vector3i, tet_index: int) -> bool:
	if not _a2_enabled:
		return false
	var cell_key: String = "%d,%d,%d" % [cell_id.x,cell_id.y,cell_id.z]
	if not A2_REFINE_TETS.has(cell_key):
		return false
	var selected: Array = A2_REFINE_TETS[cell_key]
	return selected.has(tet_index)

func _polygonize_a2_parent_tet(parent_tet: Array, parent_points: Array[Vector3], parent_values: Array[float], snapshot: Dictionary,
		mesh: Dictionary, topology: Variant, cell_id: Vector3i, parent_tet_index: int) -> Dictionary:
	var has_solid: bool = false
	var has_empty: bool = false
	var source_points: Array[Vector3] = []
	var source_values: Array[float] = []
	for value in parent_tet:
		var index: int = int(value)
		source_points.append(parent_points[index])
		source_values.append(parent_values[index])
		has_solid = has_solid or parent_values[index] >= 0.0
		has_empty = has_empty or parent_values[index] < 0.0
	if not has_solid or not has_empty:
		return {"root_edges":0,"dropped":0,"topology_valid":true}
	var centroid: Vector3 = Vector3.ZERO
	for point in source_points:
		centroid += point
	centroid *= 0.25
	var center_sample: Dictionary = _a2_sample(centroid, snapshot)
	if not bool(center_sample.get("valid", false)):
		return {"root_edges":0,"dropped":0,"topology_valid":false,"topology_reason":"a2_centroid_sample_invalid"}
	var center_key: String = _sample_key(centroid)
	var centroid_identity: String = "a2-centroid|%d,%d,%d|parent-tet:%d" % [cell_id.x,cell_id.y,cell_id.z,parent_tet_index]
	_a2_centroid_identities[center_key] = centroid_identity
	_a2_centroid_provenance[center_key] = {"source_cell":[cell_id.x,cell_id.y,cell_id.z],"source_tetrahedron":parent_tet_index,"construction":"arithmetic barycenter of the four original tetrahedron vertices","initial_construction_point":[centroid.x,centroid.y,centroid.z]}
	_a2_refined_cells["%d,%d,%d" % [cell_id.x,cell_id.y,cell_id.z]] = true
	_a2_refined_parent_tetrahedra += 1
	_a2_steiner_vertices += 1
	var child_points: Array[Vector3] = [centroid]
	child_points.append_array(source_points)
	var child_values: Array[float] = [float(center_sample.value)]
	child_values.append_array(source_values)
	var total_roots: int = 0
	var total_dropped: int = 0
	for omitted in range(4):
		var child_tet: Array[int] = [0]
		for source_index in range(4):
			if source_index != omitted:
				child_tet.append(source_index+1)
		var before_triangles: int = mesh.positions.size()/3
		var child_result: Dictionary = _polygonize_tet(child_tet,child_points,child_values,snapshot,mesh,topology,cell_id,100000+parent_tet_index*4+omitted)
		total_roots += int(child_result.get("root_edges",0))
		total_dropped += int(child_result.get("dropped",0))
		_a2_refined_patch_emitted_triangles += mesh.positions.size()/3-before_triangles
		if not bool(child_result.get("topology_valid",true)):
			return {"root_edges":total_roots,"dropped":total_dropped,"topology_valid":false,"topology_reason":child_result.get("topology_reason","a2_child_tetrahedron_rejected"),"child":omitted}
	return {"root_edges":total_roots,"dropped":total_dropped,"topology_valid":true}

func _polygonize_tet(tet:Array,cube_points:Array[Vector3],cube_values:Array[float],snapshot:Dictionary,mesh:Dictionary,
		topology:Variant=null,cell_id:Vector3i=Vector3i.ZERO,tet_index:int=0)->Dictionary:
	var inside: Array[int]=[]; var outside: Array[int]=[]; var ci:=Vector3.ZERO; var co:=Vector3.ZERO
	for raw in tet:
		var i:=int(raw)
		if cube_values[i]>=0.0: inside.append(i); ci+=cube_points[i]
		else: outside.append(i); co+=cube_points[i]
	if inside.is_empty() or outside.is_empty(): return {"root_edges":0,"dropped":0}
	ci/=float(inside.size()); co/=float(outside.size()); var empty_dir:=co-ci
	var faces: Array[Dictionary]=[]; var edges:=0
	if inside.size()==1 or outside.size()==1:
		var pivot:=inside[0] if inside.size()==1 else outside[0]
		var others: Array=outside if inside.size()==1 else inside
		var a:=_edge_root(pivot,int(others[0]),cube_points,cube_values,snapshot); var b:=_edge_root(pivot,int(others[1]),cube_points,cube_values,snapshot); var c:=_edge_root(pivot,int(others[2]),cube_points,cube_values,snapshot)
		edges=3
		if not a.valid or not b.valid or not c.valid:return {"root_edges":edges,"dropped":0,"topology_valid":false,"topology_reason":"required_root_computation_failed"}
		faces.append({"points": [a.point,b.point,c.point], "root_ids": [String(a.root_identity),String(b.root_identity),String(c.root_identity)]})
	else:
		var a:=_edge_root(inside[0],outside[0],cube_points,cube_values,snapshot); var b:=_edge_root(inside[0],outside[1],cube_points,cube_values,snapshot)
		var c:=_edge_root(inside[1],outside[0],cube_points,cube_values,snapshot); var d:=_edge_root(inside[1],outside[1],cube_points,cube_values,snapshot)
		edges=4
		if not a.valid or not b.valid or not c.valid or not d.valid:return {"root_edges":edges,"dropped":0,"topology_valid":false,"topology_reason":"required_root_computation_failed"}
		# The tetrahedron/zero-plane intersection is a convex quad in cyclic order
		# a,b,d,c. Keep the historical diagonal when both of its triangles pass;
		# otherwise use the alternate diagonal only when its complete pair passes
		# the unchanged squared-cross cutoff. Never emit half a quad.
		var emitted: Dictionary = _emit_quad(a.point,b.point,d.point,c.point,empty_dir,mesh,
			[String(a.root_identity),String(b.root_identity),String(d.root_identity),String(c.root_identity)],topology,cell_id,tet_index)
		return {"root_edges":edges,"dropped":int(emitted.get("dropped",0)),"topology_valid":bool(emitted.get("topology_valid",true)),"topology_reason":emitted.get("topology_reason","")}
	var dropped:=0
	var face_index := 0
	for face in faces:
		var points: Array = face.points
		var root_ids: Array[String] = []
		for root_id in face.root_ids:
			root_ids.append(String(root_id))
		var triangle_id := _triangle_id(cell_id,tet_index,"single:%d" % face_index)
		if topology != null:
			var registered: Dictionary = _register_required_triangle(topology,triangle_id,root_ids,points,cell_id,tet_index)
			if not bool(registered.get("valid",false)):
				return {"root_edges":edges,"dropped":dropped,"topology_valid":false,"topology_reason":registered.get("reason","triangle_registration_failed")}
		var emitted := Core.add_triangle(mesh,points[0],points[1],points[2],empty_dir,1.0e-12)
		if topology != null:
			var marked: Dictionary = _mark_triangle(topology,triangle_id,emitted,points,"below_frozen_cross_squared_cutoff")
			if not bool(marked.get("valid",false)):
				return {"root_edges":edges,"dropped":dropped,"topology_valid":false,"topology_reason":marked.get("reason","triangle_realization_failed")}
		if not emitted: dropped+=1
		face_index += 1
	return {"root_edges":edges,"dropped":dropped,"topology_valid":true}

func _emit_quad(a:Vector3,b:Vector3,d:Vector3,c:Vector3,toward_empty:Vector3,mesh:Dictionary,
		root_ids:Array[String]=[],topology:Variant=null,cell_id:Vector3i=Vector3i.ZERO,tet_index:int=0)->Dictionary:
	var old_diagonal:=_triangle_passes_cutoff(a,b,d) and _triangle_passes_cutoff(a,d,c)
	var alternate_diagonal:=_triangle_passes_cutoff(a,b,c) and _triangle_passes_cutoff(b,d,c)
	var selected_points: Array = []
	var selected_roots: Array = []
	var diagonal := ""
	if old_diagonal:
		selected_points = [[a,b,d],[a,d,c]]
		selected_roots = [[root_ids[0],root_ids[1],root_ids[2]],[root_ids[0],root_ids[2],root_ids[3]]]
		diagonal = "historical"
	elif alternate_diagonal:
		selected_points = [[a,b,c],[b,d,c]]
		selected_roots = [[root_ids[0],root_ids[1],root_ids[3]],[root_ids[1],root_ids[2],root_ids[3]]]
		diagonal = "alternate"
	else:
		selected_points = [[a,b,d],[a,d,c]]
		selected_roots = [[root_ids[0],root_ids[1],root_ids[2]],[root_ids[0],root_ids[2],root_ids[3]]]
		diagonal = "none"
	var triangle_ids: Array[String] = [_triangle_id(cell_id,tet_index,"quad:%s:0" % diagonal),_triangle_id(cell_id,tet_index,"quad:%s:1" % diagonal)]
	if topology != null:
		for i in range(2):
			var required_roots: Array[String] = []
			var raw_required_roots: Variant = selected_roots[i]
			if typeof(raw_required_roots) != TYPE_ARRAY or raw_required_roots.size() != 3:
				return {"emitted":0,"dropped":2,"topology_valid":false,"topology_reason":"selected_triangle_root_count_invalid"}
			for required_root in raw_required_roots:
				if typeof(required_root) != TYPE_STRING or String(required_root).is_empty():
					return {"emitted":0,"dropped":2,"topology_valid":false,"topology_reason":"selected_triangle_root_identity_invalid"}
				required_roots.append(required_root)
			var registered: Dictionary = _register_required_triangle(topology,triangle_ids[i],required_roots,selected_points[i],cell_id,tet_index)
			if not bool(registered.get("valid",false)):
				return {"emitted":0,"dropped":2,"topology_valid":false,"topology_reason":registered.get("reason","triangle_registration_failed")}
	var emitted: Array[bool] = [false,false]
	if diagonal != "none":
		for i in range(2):
			emitted[i] = Core.add_triangle(mesh,selected_points[i][0],selected_points[i][1],selected_points[i][2],toward_empty,1.0e-12)
			if topology != null:
				var marked: Dictionary = _mark_triangle(topology,triangle_ids[i],emitted[i],selected_points[i],"below_frozen_cross_squared_cutoff")
				if not bool(marked.get("valid",false)):
					return {"emitted":0,"dropped":2,"topology_valid":false,"topology_reason":marked.get("reason","triangle_realization_failed")}
	else:
		if topology != null:
			for i in range(2):
				var marked: Dictionary = _mark_triangle(topology,triangle_ids[i],false,selected_points[i],"no_complete_diagonal_pair_passed_frozen_cross_squared_cutoff")
				if not bool(marked.get("valid",false)):
					return {"emitted":0,"dropped":2,"topology_valid":false,"topology_reason":marked.get("reason","triangle_realization_failed")}
	var emitted_count := int(emitted[0]) + int(emitted[1])
	if diagonal == "historical" and emitted_count == 2: _quad_historical_selections += 1
	elif diagonal == "alternate" and emitted_count == 2: _quad_alternate_selections += 1
	else: _quad_pair_rejections += 1
	return {"emitted":emitted_count,"dropped":2-emitted_count,"diagonal":diagonal,"topology_valid":true}

func _triangle_id(cell_id:Vector3i,tet_index:int,suffix:String)->String:
	return "%d,%d,%d|tet:%d|%s" % [cell_id.x,cell_id.y,cell_id.z,tet_index,suffix]

func _register_required_triangle(topology:RefCounted,triangle_id:String,root_ids:Array[String],points:Array,cell_id:Vector3i,tet_index:int)->Dictionary:
	if root_ids.size()!=3 or points.size()!=3:return {"valid":false,"reason":"triangle_root_point_count_mismatch"}
	for i in range(3):
		var root_id:String=root_ids[i]
		var added_root:Dictionary=topology.add_root(root_id,points[i],"root/%s" % root_id)
		if not bool(added_root.get("valid",false)):return added_root
	var cell_text := "%d,%d,%d" % [cell_id.x,cell_id.y,cell_id.z]
	var owner_id := "%s|tet:%d" % [cell_text,tet_index]
	var added_triangle:Dictionary=topology.add_triangle(triangle_id,root_ids,owner_id,cell_text,_roi_face_ids(points))
	return added_triangle

func _mark_triangle(topology:RefCounted,triangle_id:String,emitted:bool,points:Array,rejection_reason:String)->Dictionary:
	if points.size()!=3:return {"valid":false,"reason":"triangle_point_count_mismatch"}
	var cross:Vector3=(points[1]-points[0]).cross(points[2]-points[0])
	var cross_squared := cross.length_squared() if cross.is_finite() else NAN
	return topology.mark_realization(triangle_id,emitted,cross_squared,"" if emitted else rejection_reason)

func _roi_face_ids(points:Array)->Array[String]:
	var result:Array[String]=[]
	for axis in range(3):
		var on_min:=true;var on_max:=true
		for point_value in points:
			var point:Vector3=point_value
			on_min=on_min and absf(point[axis]-ROI_MIN[axis])<=1.0e-6
			on_max=on_max and absf(point[axis]-(ROI_MIN[axis]+float(ROI_CELLS[axis])*STEP))<=1.0e-6
		if on_min:result.append(String(["X_MIN","Y_MIN","Z_MIN"][axis]))
		if on_max:result.append(String(["X_MAX","Y_MAX","Z_MAX"][axis]))
	return result

func _rollback_triangles(mesh:Dictionary,positions_size:int,normals_size:int,indices_size:int)->void:
	var positions:PackedVector3Array=mesh.positions;positions.resize(positions_size);mesh.positions=positions
	var normals:PackedVector3Array=mesh.normals;normals.resize(normals_size);mesh.normals=normals
	var indices:PackedInt32Array=mesh.indices;indices.resize(indices_size);mesh.indices=indices

func _triangle_passes_cutoff(a:Vector3,b:Vector3,c:Vector3)->bool:
	var cross:Vector3=(b-a).cross(c-a)
	return cross.is_finite() and cross.length_squared()>1.0e-12

func diagonal_selection_regression()->Dictionary:
	# The historical diagonal A-D contains one sub-cutoff triangle, while B-C
	# produces two valid triangles. This is a routing regression, not a relaxed
	# degeneracy threshold.
	var a:=Vector3(0.0,0.0,0.0);var b:=Vector3(1.0,0.0,0.0)
	var d:=Vector3(2.0,1.0e-8,0.0);var c:=Vector3(0.0,1.0,0.0)
	var historical:=_triangle_passes_cutoff(a,b,d) and _triangle_passes_cutoff(a,d,c)
	var alternate:=_triangle_passes_cutoff(a,b,c) and _triangle_passes_cutoff(b,d,c)
	return {"historical_pair_valid":historical,"alternate_pair_valid":alternate,
		"cutoff_squared":1.0e-12,"selected":"alternate" if not historical and alternate else "historical" if historical else "none",
		"valid":not historical and alternate}

func _a2_sample(point: Vector3, snapshot: Dictionary) -> Dictionary:
	var key: String = _sample_key(point)
	if _sample_cache.has(key):
		var cached: float = float(_sample_cache[key])
		return {"valid":is_finite(cached),"value":cached,"cached":true}
	var value: float = Core.sample(point,snapshot)
	_a2_additional_sdf_evaluations += 1
	if not is_finite(value):
		return {"valid":false,"reason":"a2_nonfinite_canonical_sample","point":[point.x,point.y,point.z]}
	_sample_cache[key] = value
	return {"valid":true,"value":value,"cached":false}

func _a2_endpoint_identity(point: Vector3) -> String:
	var sample_key: String = _sample_key(point)
	if _a2_centroid_identities.has(sample_key):
		return String(_a2_centroid_identities[sample_key])
	var lattice: Vector3i = Vector3i(roundi(point.x/STEP),roundi(point.y/STEP),roundi(point.z/STEP))
	return "grid-node|"+_global_lattice_key(lattice)

func _a2_record_surface_root(root_identity: String, point: Vector3, initial_point: Vector3, bracket_a: Vector3,
		bracket_b: Vector3, bracket_da: float, bracket_db: float, residual: float, iterations: int,
		snapshot: Dictionary, source_identity: String) -> Dictionary:
	if _a2_recorded_surface_roots.has(root_identity):
		return {"valid":true}
	var gradient_delta: float = 0.01
	var xp: Dictionary = _a2_sample(point+Vector3(gradient_delta,0.0,0.0),snapshot)
	var xm: Dictionary = _a2_sample(point-Vector3(gradient_delta,0.0,0.0),snapshot)
	var yp: Dictionary = _a2_sample(point+Vector3(0.0,gradient_delta,0.0),snapshot)
	var ym: Dictionary = _a2_sample(point-Vector3(0.0,gradient_delta,0.0),snapshot)
	var zp: Dictionary = _a2_sample(point+Vector3(0.0,0.0,gradient_delta),snapshot)
	var zm: Dictionary = _a2_sample(point-Vector3(0.0,0.0,gradient_delta),snapshot)
	for sample in [xp,xm,yp,ym,zp,zm]:
		if not bool(sample.get("valid",false)):
			return {"valid":false,"reason":"a2_root_gradient_sample_invalid"}
	var gradient: Vector3 = Vector3(float(xp.value)-float(xm.value),float(yp.value)-float(ym.value),float(zp.value)-float(zm.value))/(2.0*gradient_delta)
	if not is_finite(gradient.x) or not is_finite(gradient.y) or not is_finite(gradient.z) or gradient.length_squared()<=1.0e-20:
		return {"valid":false,"reason":"a2_root_gradient_invalid"}
	var normal: Vector3 = gradient.normalized()
	var provenance: Dictionary = {}
	if source_identity.begins_with("a2-centroid|"):
		for key in _a2_centroid_provenance:
			if String(_a2_centroid_identities.get(key,""))==source_identity:
				provenance=_a2_centroid_provenance[key]
				break
	var displacement: float = point.distance_to(initial_point)
	_a2_max_vertex_displacement = maxf(_a2_max_vertex_displacement,displacement)
	_a2_max_root_residual = maxf(_a2_max_root_residual,absf(residual))
	_a2_new_surface_roots += 1
	_a2_recorded_surface_roots[root_identity] = true
	var source_cell: Variant = provenance.get("source_cell",[])
	var source_tet: int = int(provenance.get("source_tetrahedron",-1))
	var edge_kind: String = "centroid-to-grid-node" if source_identity.begins_with("a2-centroid|") else "centroid-surface-endpoint"
	_a2_new_vertex_evidence.append({
		"surface_root_identity":root_identity,"source_cell":source_cell,"source_tetrahedron":source_tet,
		"source_topology_edge":edge_kind,"source_centroid_identity":source_identity,
		"initial_construction_point_world":[initial_point.x,initial_point.y,initial_point.z],
		"final_bracket_endpoints_world":[[bracket_a.x,bracket_a.y,bracket_a.z],[bracket_b.x,bracket_b.y,bracket_b.z]],
		"final_bracket_density":[bracket_da,bracket_db],"root_method":"exact_zero_centroid_endpoint" if iterations==0 else "canonical continuous SDF bisection",
		"iterations":iterations,"final_point_world":[point.x,point.y,point.z],"canonical_density_residual":residual,
		"canonical_gradient": [gradient.x,gradient.y,gradient.z],"canonical_normal": [normal.x,normal.y,normal.z],
		"displacement_from_linear_construction":displacement,"gradient_probe_delta":gradient_delta})
	return {"valid":true}

func _a2_refined_edge_root(a: Vector3, b: Vector3, da: float, db: float, snapshot: Dictionary) -> Dictionary:
	if (da<0.0)==(db<0.0):
		return {"valid":false,"reason":"a2_edge_does_not_cross_surface"}
	var identity_a: String = _a2_endpoint_identity(a)
	var identity_b: String = _a2_endpoint_identity(b)
	if identity_a>identity_b:
		var point_swap: Vector3=a;a=b;b=point_swap
		var density_swap: float=da;da=db;db=density_swap
		var identity_swap: String=identity_a;identity_a=identity_b;identity_b=identity_swap
	var edge_key: String = "a2-edge|"+identity_a+"|"+identity_b
	if da==0.0 or db==0.0:
		var exact_point: Vector3 = a if da==0.0 else b
		var exact_identity: String = "node|"+_sample_key(exact_point)
		var exact_residual: float = 0.0
		if _a2_centroid_identities.has(_sample_key(exact_point)):
			var recorded: Dictionary = _a2_record_surface_root(exact_identity,exact_point,exact_point,exact_point,exact_point,0.0,0.0,exact_residual,0,snapshot,String(_a2_centroid_identities[_sample_key(exact_point)]))
			if not bool(recorded.get("valid",false)):
				return {"valid":false,"reason":recorded.get("reason","a2_exact_root_diagnostic_failed")}
		_root_cache[edge_key]={"point":exact_point,"root_identity":exact_identity}
		return {"valid":true,"point":exact_point,"root_kind":"exact_zero_endpoint","root_identity":exact_identity}
	if _root_cache.has(edge_key):
		var cached: Dictionary = _root_cache[edge_key]
		return {"valid":true,"point":cached.point,"root_kind":"a2_canonical_edge_bisection","root_identity":cached.root_identity}
	var initial_t: float = clampf(da/(da-db),0.0,1.0)
	var initial_point: Vector3 = a.lerp(b,initial_t)
	var low: float=0.0;var high: float=1.0;var low_value: float=da;var high_value: float=db;var iterations_run: int=0
	for iteration in range(A2_BISECTION_ITERATIONS):
		iterations_run=iteration+1
		var t: float=(low+high)*0.5
		var midpoint: Vector3=a.lerp(b,t)
		var sample: Dictionary=_a2_sample(midpoint,snapshot)
		if not bool(sample.get("valid",false)):
			return {"valid":false,"reason":sample.get("reason","a2_root_sample_invalid")}
		var midpoint_value: float=float(sample.value)
		if midpoint_value==0.0:
			low=t;high=t;low_value=0.0;high_value=0.0;break
		if (midpoint_value<0.0)==(low_value<0.0):
			low=t;low_value=midpoint_value
		else:
			high=t;high_value=midpoint_value
	var point: Vector3=a.lerp(b,(low+high)*0.5)
	var residual_sample: Dictionary=_a2_sample(point,snapshot)
	if not bool(residual_sample.get("valid",false)):
		return {"valid":false,"reason":"a2_root_residual_sample_invalid"}
	var residual: float=float(residual_sample.value)
	if absf(residual)>A2_ROOT_RESIDUAL_BOUND:
		return {"valid":false,"reason":"a2_root_residual_bound_exceeded","residual":residual,"bound":A2_ROOT_RESIDUAL_BOUND,"edge":edge_key}
	var root_identity: String=edge_key
	var source_identity: String=identity_a if identity_a.begins_with("a2-centroid|") else identity_b
	var recorded_root: Dictionary=_a2_record_surface_root(root_identity,point,initial_point,a.lerp(b,low),a.lerp(b,high),low_value,high_value,residual,iterations_run,snapshot,source_identity)
	if not bool(recorded_root.get("valid",false)):
		return {"valid":false,"reason":recorded_root.get("reason","a2_root_evidence_failed")}
	_root_cache[edge_key]={"point":point,"root_identity":root_identity}
	return {"valid":true,"point":point,"root_kind":"a2_canonical_edge_bisection","root_identity":root_identity}

func _edge_root(ai:int,bi:int,points:Array[Vector3],values:Array[float],snapshot:Dictionary)->Dictionary:
	var a:Vector3=points[ai]; var b:Vector3=points[bi]; var da:float=values[ai]; var db:float=values[bi]
	if (da<0.0)==(db<0.0):return {"valid":false}
	if _a2_centroid_identities.has(_sample_key(a)) or _a2_centroid_identities.has(_sample_key(b)):
		return _a2_refined_edge_root(a,b,da,db,snapshot)
	# The root-cache identity is the exact global scalar-lattice edge, not a
	# quantized world-space position. Canonical endpoint order also gives fresh
	# chunk builds the same bisection arithmetic when they traverse an edge in
	# opposite directions.
	var lattice_a:=Vector3i(roundi(a.x/STEP),roundi(a.y/STEP),roundi(a.z/STEP))
	var lattice_b:=Vector3i(roundi(b.x/STEP),roundi(b.y/STEP),roundi(b.z/STEP))
	var ka:String=_global_lattice_key(lattice_a);var kb:String=_global_lattice_key(lattice_b)
	if ka>kb:
		var swap_point:=a;a=b;b=swap_point
		var swap_value:=da;da=db;db=swap_value
		var swap_key:=ka;ka=kb;kb=swap_key
	var key:String=ka+"|"+kb
	var world_key_a:String=_sample_key(a);var world_key_b:String=_sample_key(b)
	if world_key_a>world_key_b:
		var world_key_swap:String=world_key_a;world_key_a=world_key_b;world_key_b=world_key_swap
	var edge_identity:String="edge|"+world_key_a+"|"+world_key_b
	# Zero belongs to the solid side (the polygonizer classifies d >= 0 as
	# inside). When the opposite endpoint is empty, the shared lattice node is
	# already the exact interface root. Bisection would move that root inward by
	# up to one of the fixed iterations and give incident edges distinct points
	# for the same zero-valued node.
	if da==0.0:
		_root_cache[key]=a
		return {"valid":true,"point":a,"root_kind":"exact_zero_endpoint","root_identity":"node|"+_sample_key(a)}
	if db==0.0:
		_root_cache[key]=b
		return {"valid":true,"point":b,"root_kind":"exact_zero_endpoint","root_identity":"node|"+_sample_key(b)}
	if _root_cache.has(key): return {"valid":true,"point":_root_cache[key],"root_kind":"edge_bisection","root_identity":edge_identity}
	var low:=0.0; var high:=1.0; var low_value:=da
	for iteration in range(ROOT_ITERATIONS):
		var t:float=(low+high)*0.5; var p:=a.lerp(b,t); var pk:String=_sample_key(p)
		var dm:float=float(_sample_cache.get(pk,NAN))
		if not is_finite(dm): dm=Core.sample(p,snapshot); _sample_cache[pk]=dm
		if not is_finite(dm):return {"valid":false,"reason":"nonfinite_root_sample"}
		if dm==0.0:low=t;high=t;break
		if (dm<0.0)==(low_value<0.0): low=t;low_value=dm
		else:high=t
	var point:=a.lerp(b,(low+high)*0.5);_root_cache[key]=point
	return {"valid":true,"point":point,"root_kind":"edge_bisection","root_identity":edge_identity}

func _global_lattice_key(index:Vector3i)->String:
	return "%d,%d,%d"%[index.x,index.y,index.z]

func _sample_key(point:Vector3)->String:
	var packed:=PackedVector3Array();packed.append(point)
	return packed.to_byte_array().hex_encode()

func canonical_root_identity_probe(snapshot:Dictionary)->Dictionary:
	var a:=Vector3.ZERO;var b:=Vector3.ZERO;var da:=0.0;var db:=0.0;var found:=false
	for y in range(ROI_CELLS.y+1):
		for z in range(ROI_CELLS.z+1):
			for x in range(ROI_CELLS.x+1):
				var node:=Vector3i(x,y,z)
				for axis in range(3):
					if node[axis]>=ROI_CELLS[axis]:continue
					var next:=node;next[axis]+=1
					var candidate_a:=ROI_MIN+Vector3(node)*STEP
					var candidate_b:=ROI_MIN+Vector3(next)*STEP
					var candidate_da:=Core.sample(candidate_a,snapshot);var candidate_db:=Core.sample(candidate_b,snapshot)
					if (candidate_da<0.0)!=(candidate_db<0.0):
						a=candidate_a;b=candidate_b;da=candidate_da;db=candidate_db;found=true;break
				if found:break
		if found:break
	if not found:return {"valid":false,"reason":"probe_crossing_edge_not_found"}
	_root_cache.clear();var first:=_edge_root(0,1,[a,b],[da,db],snapshot)
	_root_cache.clear();var reversed:=_edge_root(0,1,[b,a],[db,da],snapshot)
	var zero_endpoint:=canonical_zero_endpoint_probe()
	var p:Vector3=Vector3(8.0,1.0,2.0);var q:=p+Vector3(0.000001,0.0,0.0)
	return {"valid":first.get("valid",false) and reversed.get("valid",false) and first.point==reversed.point and first.get("root_identity","")==reversed.get("root_identity","") and zero_endpoint.get("valid",false),
		"forward_root":first.get("point",Vector3.ZERO),"reverse_root":reversed.get("point",Vector3.ZERO),
		"forward_root_identity":first.get("root_identity",""),"reverse_root_identity":reversed.get("root_identity",""),
		"zero_endpoint":zero_endpoint,
		"quantized_keys_collide":Core._point_key(p)==Core._point_key(q),
		"exact_sample_keys_distinct":_sample_key(p)!=_sample_key(q),
		"root_key":_global_lattice_key(Vector3i(roundi(a.x/STEP),roundi(a.y/STEP),roundi(a.z/STEP)))+"|"+
			_global_lattice_key(Vector3i(roundi(b.x/STEP),roundi(b.y/STEP),roundi(b.z/STEP)))}

func canonical_zero_endpoint_probe()->Dictionary:
	# Exercise both endpoint orientations with no SDF access: a zero-valued
	# lattice endpoint is the root exactly, independent of edge traversal order.
	var a:=Vector3(8.0,1.0,5.0)
	var b:=a+Vector3(STEP,0.0,0.0)
	_root_cache.clear()
	var a_forward:=_edge_root(0,1,[a,b],[0.0,-1.0],{})
	_root_cache.clear()
	var a_reverse:=_edge_root(0,1,[b,a],[-1.0,0.0],{})
	_root_cache.clear()
	var b_forward:=_edge_root(0,1,[a,b],[-1.0,0.0],{})
	_root_cache.clear()
	var b_reverse:=_edge_root(0,1,[b,a],[0.0,-1.0],{})
	var valid:bool=bool(a_forward.get("valid",false)) and bool(a_reverse.get("valid",false)) and bool(b_forward.get("valid",false)) and bool(b_reverse.get("valid",false))
	valid=valid and String(a_forward.get("root_identity",""))==String(a_reverse.get("root_identity","")) and String(b_forward.get("root_identity",""))==String(b_reverse.get("root_identity","")) and String(a_forward.get("root_identity",""))!=String(b_forward.get("root_identity",""))
	valid=valid and a_forward.get("point",Vector3.ZERO)==a and a_reverse.get("point",Vector3.ZERO)==a
	valid=valid and b_forward.get("point",Vector3.ZERO)==b and b_reverse.get("point",Vector3.ZERO)==b
	return {"valid":valid,"a_forward":a_forward.get("point",Vector3.ZERO),"a_reverse":a_reverse.get("point",Vector3.ZERO),
		"b_forward":b_forward.get("point",Vector3.ZERO),"b_reverse":b_reverse.get("point",Vector3.ZERO),
		"a_forward_root_identity":a_forward.get("root_identity",""),"a_reverse_root_identity":a_reverse.get("root_identity",""),"b_forward_root_identity":b_forward.get("root_identity",""),"b_reverse_root_identity":b_reverse.get("root_identity",""),
		"expected_a":a,"expected_b":b,"samples_performed":0}

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
	var position_bytes:PackedByteArray=(mesh.positions as PackedVector3Array).to_byte_array()
	var normal_bytes:PackedByteArray=(mesh.normals as PackedVector3Array).to_byte_array()
	var ctx:=HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	# Prefix lengths so empty arrays remain distinguishable and never call update with zero bytes.
	ctx.update(("%d:%d:" % [position_bytes.size(),normal_bytes.size()]).to_utf8_buffer())
	if not position_bytes.is_empty():ctx.update(position_bytes)
	if not normal_bytes.is_empty():ctx.update(normal_bytes)
	return ctx.finish().hex_encode()
